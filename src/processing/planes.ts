import { rgbToOklab, oklabToRgb } from '../color/oklab';
import { throwIfAborted, yieldToEventLoop } from './simplify/cancel';
import type { PlanesConfig } from '../types';
import type { ProgressCallback } from './progress';

export interface PlanesResult {
  imageData: ImageData;
  palette: string[];
  paletteBands: number[];
}

/* ── Detail → merge-threshold mapping ─────────────────────────── */

function detailToMergeThreshold(detail: number): number {
  // detail 0 → aggressive merge (low threshold in OkLab distance)
  // detail 1 → conservative merge (high threshold)
  // Interpolate logarithmically for perceptual linearity.
  const lo = 0.02;
  const hi = 0.15;
  return lo * Math.pow(hi / lo, detail);
}

/* ── Compactness → spatial weight mapping ─────────────────────── */

function compactnessToSpatialWeight(compactness: number): number {
  // compactness 0 → m=5 (loose, follows color)
  // compactness 1 → m=40 (very regular)
  return 5 + compactness * 35;
}

/* ── SLIC superpixels ─────────────────────────────────────────── */

interface Superpixel {
  L: number; a: number; b: number;
  x: number; y: number;
  count: number;
}

function initSuperpixels(
  labData: Float32Array,
  width: number,
  height: number,
  gridStep: number,
): Superpixel[] {
  const centers: Superpixel[] = [];
  const halfStep = gridStep / 2;
  for (let y = halfStep; y < height; y += gridStep) {
    for (let x = halfStep; x < width; x += gridStep) {
      const ix = Math.min(Math.round(x), width - 1);
      const iy = Math.min(Math.round(y), height - 1);
      const idx = iy * width + ix;
      centers.push({
        L: labData[idx * 3],
        a: labData[idx * 3 + 1],
        b: labData[idx * 3 + 2],
        x: ix,
        y: iy,
        count: 0,
      });
    }
  }
  return centers;
}

async function slicIterate(
  labData: Float32Array,
  width: number,
  height: number,
  centers: Superpixel[],
  labels: Int32Array,
  distances: Float32Array,
  gridStep: number,
  spatialWeight: number,
  iterations: number,
  onProgress: ProgressCallback | undefined,
  signal: AbortSignal | undefined,
): Promise<void> {
  const numPixels = width * height;
  const mOverS = spatialWeight / gridStep;
  const mOverS2 = mOverS * mOverS;

  for (let iter = 0; iter < iterations; iter++) {
    throwIfAborted(signal);

    // Reset distances
    distances.fill(Infinity);

    // Assignment step: for each center, search its 2S×2S neighbourhood
    for (let k = 0; k < centers.length; k++) {
      const c = centers[k];
      const xMin = Math.max(0, Math.floor(c.x - gridStep));
      const xMax = Math.min(width - 1, Math.ceil(c.x + gridStep));
      const yMin = Math.max(0, Math.floor(c.y - gridStep));
      const yMax = Math.min(height - 1, Math.ceil(c.y + gridStep));

      for (let py = yMin; py <= yMax; py++) {
        for (let px = xMin; px <= xMax; px++) {
          const idx = py * width + px;
          const dL = labData[idx * 3] - c.L;
          const da = labData[idx * 3 + 1] - c.a;
          const db = labData[idx * 3 + 2] - c.b;
          const colorDist2 = dL * dL + da * da + db * db;

          const dx = px - c.x;
          const dy = py - c.y;
          const spatialDist2 = dx * dx + dy * dy;

          const D = colorDist2 + mOverS2 * spatialDist2;

          if (D < distances[idx]) {
            distances[idx] = D;
            labels[idx] = k;
          }
        }
      }
    }

    // Update step: recompute centers
    for (let k = 0; k < centers.length; k++) {
      centers[k].L = 0; centers[k].a = 0; centers[k].b = 0;
      centers[k].x = 0; centers[k].y = 0; centers[k].count = 0;
    }

    for (let i = 0; i < numPixels; i++) {
      const k = labels[i];
      if (k < 0) continue;
      const c = centers[k];
      c.L += labData[i * 3];
      c.a += labData[i * 3 + 1];
      c.b += labData[i * 3 + 2];
      c.x += i % width;
      c.y += Math.floor(i / width);
      c.count++;
    }

    for (let k = 0; k < centers.length; k++) {
      const c = centers[k];
      if (c.count > 0) {
        c.L /= c.count; c.a /= c.count; c.b /= c.count;
        c.x /= c.count; c.y /= c.count;
      }
    }

    if (onProgress) {
      // Phase 1 is 0–70%
      onProgress('Superpixels', Math.round((iter + 1) / iterations * 70));
    }

    // Yield every 2 iterations to keep worker responsive
    if (iter % 2 === 1) {
      await yieldToEventLoop();
    }
  }

  // Assign any orphan pixels (label -1) to nearest center
  for (let i = 0; i < numPixels; i++) {
    if (labels[i] >= 0) continue;
    const px = i % width;
    const py = Math.floor(i / width);
    let bestK = 0, bestD = Infinity;
    for (let k = 0; k < centers.length; k++) {
      const c = centers[k];
      const dx = px - c.x, dy = py - c.y;
      const D = dx * dx + dy * dy;
      if (D < bestD) { bestD = D; bestK = k; }
    }
    labels[i] = bestK;
  }
}

/* ── RAG merging ──────────────────────────────────────────────── */

interface RAGNode {
  L: number; a: number; b: number;
  area: number;
  parent: number; // union-find parent (self = root)
}

function findRoot(nodes: RAGNode[], i: number): number {
  while (nodes[i].parent !== i) {
    nodes[i].parent = nodes[nodes[i].parent].parent; // path compression
    i = nodes[i].parent;
  }
  return i;
}

interface RAGEdge {
  i: number;
  j: number;
  dist: number;
}

function buildRAG(
  labels: Int32Array,
  width: number,
  height: number,
  nodes: RAGNode[],
): RAGEdge[] {
  const edgeSet = new Map<string, RAGEdge>();
  const numPixels = width * height;

  for (let idx = 0; idx < numPixels; idx++) {
    const x = idx % width;
    const y = Math.floor(idx / width);
    const li = labels[idx];

    // Check right and down neighbours
    if (x + 1 < width) {
      const lj = labels[idx + 1];
      if (li !== lj) {
        const key = li < lj ? `${li}-${lj}` : `${lj}-${li}`;
        if (!edgeSet.has(key)) {
          const ni = nodes[li], nj = nodes[lj];
          const dL = ni.L - nj.L, da = ni.a - nj.a, db = ni.b - nj.b;
          edgeSet.set(key, { i: li, j: lj, dist: Math.sqrt(dL * dL + da * da + db * db) });
        }
      }
    }
    if (y + 1 < height) {
      const lj = labels[idx + width];
      if (li !== lj) {
        const key = li < lj ? `${li}-${lj}` : `${lj}-${li}`;
        if (!edgeSet.has(key)) {
          const ni = nodes[li], nj = nodes[lj];
          const dL = ni.L - nj.L, da = ni.a - nj.a, db = ni.b - nj.b;
          edgeSet.set(key, { i: li, j: lj, dist: Math.sqrt(dL * dL + da * da + db * db) });
        }
      }
    }
  }

  return Array.from(edgeSet.values());
}

function mergeRAG(
  nodes: RAGNode[],
  edges: RAGEdge[],
  mergeThreshold: number,
  onProgress: ProgressCallback | undefined,
  signal: AbortSignal | undefined,
): void {
  // Sort edges by distance (ascending)
  edges.sort((a, b) => a.dist - b.dist);

  const totalEdges = edges.length;
  let processed = 0;

  for (const edge of edges) {
    throwIfAborted(signal);

    const ri = findRoot(nodes, edge.i);
    const rj = findRoot(nodes, edge.j);
    if (ri === rj) { processed++; continue; }

    // Recompute distance between current root colors
    const ni = nodes[ri], nj = nodes[rj];
    const dL = ni.L - nj.L, da = ni.a - nj.a, db = ni.b - nj.b;
    const dist = Math.sqrt(dL * dL + da * da + db * db);

    if (dist > mergeThreshold) break; // all remaining edges are farther

    // Merge j into i (area-weighted average)
    const totalArea = ni.area + nj.area;
    ni.L = (ni.L * ni.area + nj.L * nj.area) / totalArea;
    ni.a = (ni.a * ni.area + nj.a * nj.area) / totalArea;
    ni.b = (ni.b * ni.area + nj.b * nj.area) / totalArea;
    ni.area = totalArea;
    nj.parent = ri;

    processed++;
    if (onProgress && processed % 200 === 0) {
      onProgress('Merging', 70 + Math.round(processed / totalEdges * 30));
    }
  }
}

/* ── Public API ────────────────────────────────────────────────── */

export async function computePlanes(
  imageData: ImageData,
  config: PlanesConfig,
  onProgress?: ProgressCallback,
  signal?: AbortSignal,
): Promise<PlanesResult> {
  const { data, width, height } = imageData;
  const numPixels = width * height;

  // Convert to OkLab
  const labData = new Float32Array(numPixels * 3);
  for (let i = 0; i < numPixels; i++) {
    const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
    const lab = rgbToOklab(r, g, b);
    labData[i * 3] = lab.L;
    labData[i * 3 + 1] = lab.a;
    labData[i * 3 + 2] = lab.b;
  }

  throwIfAborted(signal);

  // Determine grid step for ~500 superpixels, clamped to sensible range
  const targetCount = Math.max(50, Math.min(2000, Math.round(numPixels / 400)));
  const gridStep = Math.max(4, Math.sqrt(numPixels / targetCount));

  const spatialWeight = compactnessToSpatialWeight(config.compactness);
  const mergeThreshold = detailToMergeThreshold(config.detail);

  // Phase 1: SLIC
  const centers = initSuperpixels(labData, width, height, gridStep);
  const labels = new Int32Array(numPixels).fill(-1);
  const distances = new Float32Array(numPixels);

  await slicIterate(
    labData, width, height,
    centers, labels, distances,
    gridStep, spatialWeight,
    8, // iterations
    onProgress, signal,
  );

  throwIfAborted(signal);

  // Build RAG nodes from superpixel centers
  const ragNodes: RAGNode[] = centers.map(c => ({
    L: c.L, a: c.a, b: c.b,
    area: c.count,
    parent: 0,
  }));
  for (let i = 0; i < ragNodes.length; i++) ragNodes[i].parent = i;

  // Phase 2: RAG merge
  const edges = buildRAG(labels, width, height, ragNodes);
  mergeRAG(ragNodes, edges, mergeThreshold, onProgress, signal);

  if (onProgress) onProgress('Rendering', 95);

  // Build final label map: remap each superpixel to its merged root
  const rootMap = new Map<number, number>(); // root index → final plane index
  let planeIdx = 0;
  const finalLabels = new Int32Array(numPixels);

  for (let i = 0; i < numPixels; i++) {
    const sp = labels[i];
    const root = findRoot(ragNodes, sp);
    let plane = rootMap.get(root);
    if (plane === undefined) {
      plane = planeIdx++;
      rootMap.set(root, plane);
    }
    finalLabels[i] = plane;
  }

  // Build palette and band assignments from merged roots
  const palette: string[] = [];
  const paletteBands: number[] = [];
  const planeColors: Array<{ L: number; a: number; b: number }> = [];

  for (const [root, idx] of rootMap) {
    const n = ragNodes[root];
    planeColors[idx] = { L: n.L, a: n.a, b: n.b };
    const [r, g, b] = oklabToRgb(n.L, n.a, n.b);
    palette[idx] = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    // Classify into light families by luminance for band isolation
    let band: number;
    if (n.L > 0.7) band = 0;       // Light
    else if (n.L > 0.3) band = 1;  // Halftone
    else band = 2;                  // Shadow
    paletteBands[idx] = band;
  }

  // Render output: each pixel gets its plane's average color
  const out = new ImageData(width, height);
  const outData = out.data;
  for (let i = 0; i < numPixels; i++) {
    const c = planeColors[finalLabels[i]];
    const [r, g, b] = oklabToRgb(c.L, c.a, c.b);
    outData[i * 4] = r;
    outData[i * 4 + 1] = g;
    outData[i * 4 + 2] = b;
    outData[i * 4 + 3] = 255;
  }

  if (onProgress) onProgress('Complete', 100);

  return { imageData: out, palette, paletteBands };
}
