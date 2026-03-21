import { rgbToOklab, oklabToRgb } from '../color/oklab';

export { rgbToOklab, oklabToRgb };

export interface Centroid { L: number; a: number; b: number; }

function initCentroids(pixels: Float32Array, k: number, numPixels: number): Centroid[] {
  const centroids: Centroid[] = [];
  const first = Math.floor(Math.random() * numPixels);
  centroids.push({ L: pixels[first * 3], a: pixels[first * 3 + 1], b: pixels[first * 3 + 2] });

  for (let ci = 1; ci < k; ci++) {
    const distances = new Float32Array(numPixels);
    for (let i = 0; i < numPixels; i++) {
      let minDist = Infinity;
      for (const c of centroids) {
        const dL = pixels[i * 3] - c.L;
        const da = pixels[i * 3 + 1] - c.a;
        const db = pixels[i * 3 + 2] - c.b;
        const dist = dL * dL + da * da + db * db;
        if (dist < minDist) minDist = dist;
      }
      distances[i] = minDist;
    }
    let total = 0;
    for (let i = 0; i < numPixels; i++) total += distances[i];
    let rand = Math.random() * total;
    let chosen = 0;
    for (let i = 0; i < numPixels; i++) {
      rand -= distances[i];
      if (rand <= 0) { chosen = i; break; }
    }
    centroids.push({ L: pixels[chosen * 3], a: pixels[chosen * 3 + 1], b: pixels[chosen * 3 + 2] });
  }
  return centroids;
}

export function kMeans(pixels: Float32Array, numPixels: number, k: number): { centroids: Centroid[]; assignments: Int32Array } {
  if (numPixels === 0 || k === 0) return { centroids: [], assignments: new Int32Array(0) };
  k = Math.min(k, numPixels);

  let centroids = initCentroids(pixels, k, numPixels);
  const assignments = new Int32Array(numPixels).fill(0);

  for (let iter = 0; iter < 20; iter++) {
    for (let i = 0; i < numPixels; i++) {
      let bestDist = Infinity, bestC = 0;
      for (let ci = 0; ci < centroids.length; ci++) {
        const dL = pixels[i * 3] - centroids[ci].L;
        const da = pixels[i * 3 + 1] - centroids[ci].a;
        const db = pixels[i * 3 + 2] - centroids[ci].b;
        const dist = dL * dL + da * da + db * db;
        if (dist < bestDist) { bestDist = dist; bestC = ci; }
      }
      assignments[i] = bestC;
    }

    const newCentroids: Centroid[] = Array.from({ length: k }, () => ({ L: 0, a: 0, b: 0 }));
    const counts = new Int32Array(k);
    for (let i = 0; i < numPixels; i++) {
      const c = assignments[i];
      newCentroids[c].L += pixels[i * 3];
      newCentroids[c].a += pixels[i * 3 + 1];
      newCentroids[c].b += pixels[i * 3 + 2];
      counts[c]++;
    }

    let maxShift = 0;
    for (let ci = 0; ci < k; ci++) {
      if (counts[ci] === 0) continue;
      const nL = newCentroids[ci].L / counts[ci];
      const na = newCentroids[ci].a / counts[ci];
      const nb = newCentroids[ci].b / counts[ci];
      const shift = Math.abs(nL - centroids[ci].L) + Math.abs(na - centroids[ci].a) + Math.abs(nb - centroids[ci].b);
      if (shift > maxShift) maxShift = shift;
      centroids[ci] = { L: nL, a: na, b: nb };
    }

    if (maxShift < 0.001) break;
  }

  return { centroids, assignments };
}
