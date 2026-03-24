import type { PlaneGuidance } from '../types';
import type { PlaneSegmentation } from './planes';

/**
 * Cleanup plane labels by merging small isolated fragments into their largest neighbors.
 * Uses 4-connected flood fill to identify connected components.
 */
export function buildPlaneGuidance(segmentation: PlaneSegmentation, minArea = 100): PlaneGuidance {
  const { labels, width, height, centroids } = segmentation;
  const numPixels = width * height;
  const visited = new Uint8Array(numPixels);
  const newLabels = new Uint8Array(labels);

  for (let i = 0; i < numPixels; i++) {
    if (visited[i]) continue;

    const targetLabel = labels[i];
    const component: number[] = [];
    const stack = [i];
    visited[i] = 1;

    // Flood fill
    while (stack.length > 0) {
      const idx = stack.pop()!;
      component.push(idx);

      const x = idx % width;
      const y = Math.floor(idx / width);

      const neighbors = [
        x > 0 ? idx - 1 : -1,
        x < width - 1 ? idx + 1 : -1,
        y > 0 ? idx - width : -1,
        y < height - 1 ? idx + width : -1,
      ];

      for (const next of neighbors) {
        if (next !== -1 && !visited[next] && labels[next] === targetLabel) {
          visited[next] = 1;
          stack.push(next);
        }
      }
    }

    // Small region merge
    if (component.length < minArea) {
      // Find largest neighbor label
      const neighborCounts = new Map<number, number>();
      for (const idx of component) {
        const x = idx % width;
        const y = Math.floor(idx / width);
        const check = [
          x > 0 ? idx - 1 : -1,
          x < width - 1 ? idx + 1 : -1,
          y > 0 ? idx - width : -1,
          y < height - 1 ? idx + width : -1,
        ];
        for (const nIdx of check) {
          if (nIdx !== -1) {
            const nLabel = newLabels[nIdx];
            if (nLabel !== targetLabel) {
              neighborCounts.set(nLabel, (neighborCounts.get(nLabel) || 0) + 1);
            }
          }
        }
      }

      if (neighborCounts.size > 0) {
        let bestLabel = targetLabel;
        let maxCount = -1;
        for (const [l, count] of neighborCounts.entries()) {
          if (count > maxCount) {
            maxCount = count;
            bestLabel = l;
          }
        }
        for (const idx of component) {
          newLabels[idx] = bestLabel;
        }
      }
    }
  }

  return {
    width,
    height,
    labels: newLabels,
    planeCount: centroids.length / 3,
  };
}
