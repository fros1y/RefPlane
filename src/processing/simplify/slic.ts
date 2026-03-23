import { rgbToOklab, oklabToRgb } from '../../color/oklab';
import { throwIfAborted, yieldToEventLoop } from './cancel';

/* ── Parameter mapping helpers ────────────────────────────────── */

/** Maps detail 0→aggressive merge (few planes), 1→conservative (many planes). */
function detailToMergeThreshold(detail: number): number {
  const hi = 0.25; // aggressive at strength=0
  const lo = 0.02; // conservative at strength=1
  return hi * Math.pow(lo / hi, detail);
}

/** Maps compactness 0→organic (follows color), 1→regular (grid-like). */
function compactnessToSpatialWeight(compactness: number): number {
  return 1 + compactness * 39;
}

/* ── SLIC superpixels ─────────────────────────────────────────── */

interface Superpixel {
  L: number; a: number; b: number;
  x: number; y: number;
  count: number;
  planeLabel: number;
}

function initSuperpixels(
  labData: Float32Array,
  width: number,
  height: number,
  gridStep: number,
  planeLabels?: Uint8Array,
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
        planeLabel: planeLabels ? planeLabels[idx] : -1,
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
  onProgress: ((percent: number) => void) | undefined,
  signal: AbortSignal | undefined,
  planeLabels?: Uint8Array,
): Promise<void> {
  const numPixels = width * height;
  const mOverS = spatialWeight / gridStep;
  const mOverS2 = mOverS * mOverS;
  // OkLab values are 0-1 while spatial distances are 0-S pixels.
  // Scale color to CIELAB-like range so both terms are comparable.
  const COLOR_SCALE2 = 100 * 100;

  for (let iter = 0; iter < iterations; iter++) {
    throwIfAborted(signal);

    distances.fill(Infinity);

    for (let k = 0; k < centers.length; k++) {
      const c = centers[k];
      const xMin = Math.max(0, Math.floor(c.x - gridStep));
      const xMax = Math.min(width - 1, Math.ceil(c.x + gridStep));
      const yMin = Math.max(0, Math.floor(c.y - gridStep));
      const yMax = Math.min(height - 1, Math.ceil(c.y + gridStep));

      for (let py = yMin; py <= yMax; py++) {
        for (let px = xMin; px <= xMax; px++) {
          const idx = py * width + px;
          // Skip pixels belonging to a different plane
          if (planeLabels && planeLabels[idx] !== c.planeLabel) continue;
          const dL = labData[idx * 3] - c.L;
          const da = labData[idx * 3 + 1] - c.a;
          const db = labData[idx * 3 + 2] - c.b;
          const colorDist2 = (dL * dL + da * da + db * db) * COLOR_SCALE2;

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
      onProgress(Math.round((iter + 1) / iterations * 70));
    }

    if (iter % 2 === 1) {
      await yieldToEventLoop();
    }
  }

  // Assign orphan pixels to nearest center (respecting plane boundaries)
  for (let i = 0; i < numPixels; i++) {
    if (labels[i] >= 0) continue;
    const px = i % width;
    const py = Math.floor(i / width);
    const pixelPlane = planeLabels ? planeLabels[i] : -1;
    let bestK = 0, bestD = Infinity;
    for (let k = 0; k < centers.length; k++) {
      const c = centers[k];
      if (planeLabels && c.planeLabel !== pixelPlane) continue;
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
  parent: number;
  planeLabel: number;
}

function findRoot(nodes: RAGNode[], i: number): number {
  while (nodes[i].parent !== i) {
    nodes[i].parent = nodes[nodes[i].parent].parent;
    i = nodes[i].parent;
  }
  return i;
}

interface RAGEdge { i: number; j: number; dist: number; }

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
    const li = labels[idx];

    if (x + 1 < width) {
      const lj = labels[idx + 1];
      if (li !== lj) {
        // Don't create edges across plane boundaries
        if (nodes[li].planeLabel !== -1 && nodes[li].planeLabel !== nodes[lj].planeLabel) continue;
        const key = li < lj ? `${li}-${lj}` : `${lj}-${li}`;
        if (!edgeSet.has(key)) {
          const ni = nodes[li], nj = nodes[lj];
          const dL = ni.L - nj.L, da = ni.a - nj.a, db = ni.b - nj.b;
          edgeSet.set(key, { i: li, j: lj, dist: Math.sqrt(dL * dL + da * da + db * db) });
        }
      }
    }
    if (idx + width < numPixels) {
      const lj = labels[idx + width];
      if (li !== lj) {
        // Don't create edges across plane boundaries
        if (nodes[li].planeLabel !== -1 && nodes[li].planeLabel !== nodes[lj].planeLabel) continue;
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
  signal: AbortSignal | undefined,
): void {
  edges.sort((a, b) => a.dist - b.dist);

  for (const edge of edges) {
    throwIfAborted(signal);

    const ri = findRoot(nodes, edge.i);
    const rj = findRoot(nodes, edge.j);
    if (ri === rj) continue;

    const ni = nodes[ri], nj = nodes[rj];
    const dL = ni.L - nj.L, da = ni.a - nj.a, db = ni.b - nj.b;
    const dist = Math.sqrt(dL * dL + da * da + db * db);

    if (dist > mergeThreshold) continue;

    const totalArea = ni.area + nj.area;
    ni.L = (ni.L * ni.area + nj.L * nj.area) / totalArea;
    ni.a = (ni.a * ni.area + nj.a * nj.area) / totalArea;
    ni.b = (ni.b * ni.area + nj.b * nj.area) / totalArea;
    ni.area = totalArea;
    nj.parent = ri;
  }
}

/* ── Public API ────────────────────────────────────────────────── */

/**
 * SLIC superpixel segmentation with RAG merge.
 * Returns a simplified ImageData where each region is filled with its
 * average color — suitable as a simplification preprocessing step.
 */
export async function slicFilter(
  imageData: ImageData,
  detail: number,
  compactness: number,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
  planeLabels?: Uint8Array,
): Promise<ImageData> {
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

  throwIfAborted(abortSignal);

  const targetCount = Math.max(50, Math.min(2000, Math.round(numPixels / 400)));
  const gridStep = Math.max(4, Math.sqrt(numPixels / targetCount));

  const spatialWeight = compactnessToSpatialWeight(compactness);
  const mergeThreshold = detailToMergeThreshold(detail);

  const centers = initSuperpixels(labData, width, height, gridStep, planeLabels);
  const labels = new Int32Array(numPixels).fill(-1);
  const distances = new Float32Array(numPixels);

  await slicIterate(
    labData, width, height,
    centers, labels, distances,
    gridStep, spatialWeight,
    8, onProgress, abortSignal,
    planeLabels,
  );

  throwIfAborted(abortSignal);

  // Build RAG nodes
  const ragNodes: RAGNode[] = centers.map(c => ({
    L: c.L, a: c.a, b: c.b,
    area: c.count,
    parent: 0,
    planeLabel: c.planeLabel,
  }));
  for (let i = 0; i < ragNodes.length; i++) ragNodes[i].parent = i;

  const edges = buildRAG(labels, width, height, ragNodes);
  mergeRAG(ragNodes, edges, mergeThreshold, abortSignal);

  if (onProgress) onProgress(90);

  // Render: each pixel gets its merged region's average color
  const out = new ImageData(width, height);
  const outData = out.data;
  for (let i = 0; i < numPixels; i++) {
    const root = findRoot(ragNodes, labels[i]);
    const n = ragNodes[root];
    const [r, g, b] = oklabToRgb(n.L, n.a, n.b);
    outData[i * 4] = r;
    outData[i * 4 + 1] = g;
    outData[i * 4 + 2] = b;
    outData[i * 4 + 3] = 255;
  }

  if (onProgress) onProgress(100);
  return out;
}
