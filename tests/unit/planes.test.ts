import { describe, it, expect } from 'vitest';
import { computeNormals, clusterNormals, shadePlanes, processPlanes } from '../../src/processing/planes';

describe('computeNormals', () => {
  it('returns normals pointing up for a flat surface', () => {
    // Flat depth map (all same value) → normals should point straight out (0, 0, 1)
    const depth = new Float32Array([1, 1, 1, 1, 1, 1, 1, 1, 1]);
    const normals = computeNormals(depth, 3, 3);
    // Check center pixel (avoids edge effects)
    const cx = 1, cy = 1, idx = (cy * 3 + cx) * 3;
    expect(normals[idx]).toBeCloseTo(0, 4);     // nx
    expect(normals[idx + 1]).toBeCloseTo(0, 4); // ny
    expect(normals[idx + 2]).toBeCloseTo(1, 4); // nz
  });

  it('detects a surface tilting right (depth increases with x)', () => {
    // 3x3 depth map: depth = x
    const depth = new Float32Array([0, 1, 2, 0, 1, 2, 0, 1, 2]);
    const normals = computeNormals(depth, 3, 3);
    const cx = 1, cy = 1, idx = (cy * 3 + cx) * 3;
    // Normal should tilt toward negative X (away from increasing depth)
    expect(normals[idx]).toBeLessThan(0);        // nx < 0
    expect(normals[idx + 1]).toBeCloseTo(0, 4);  // ny ≈ 0
    expect(normals[idx + 2]).toBeGreaterThan(0);  // nz > 0
  });

  it('returns normalized vectors', () => {
    const depth = new Float32Array([0, 0.5, 1, 0.3, 0.8, 1.2, 0.6, 1.1, 1.5]);
    const normals = computeNormals(depth, 3, 3);
    for (let i = 0; i < 9; i++) {
      const b = i * 3;
      const len = Math.sqrt(normals[b] ** 2 + normals[b + 1] ** 2 + normals[b + 2] ** 2);
      expect(len).toBeCloseTo(1, 4);
    }
  });
});

describe('clusterNormals', () => {
  it('assigns two distinct normal groups to two clusters', () => {
    // Create normals directly: first half pointing left, second half pointing right
    const width = 4, height = 2;
    const numPixels = width * height;
    const normals = new Float32Array(numPixels * 3);
    for (let i = 0; i < numPixels; i++) {
      const b = i * 3;
      if (i < numPixels / 2) {
        // Group A: pointing left-up
        normals[b] = -0.7071; normals[b + 1] = 0; normals[b + 2] = 0.7071;
      } else {
        // Group B: pointing right-up
        normals[b] = 0.7071; normals[b + 1] = 0; normals[b + 2] = 0.7071;
      }
    }
    const { labels, centroids } = clusterNormals(normals, width, height, 2);

    expect(labels.length).toBe(numPixels);
    expect(centroids.length).toBe(2 * 3);
    // First and second halves should get different labels
    expect(labels[0]).not.toBe(labels[numPixels - 1]);
  });

  it('returns k centroids that are unit vectors', () => {
    const normals = new Float32Array(30 * 3);
    for (let i = 0; i < 30; i++) {
      normals[i * 3 + 2] = 1; // all pointing Z
    }
    const { centroids } = clusterNormals(normals, 10, 3, 3);
    for (let c = 0; c < 3; c++) {
      const b = c * 3;
      const len = Math.sqrt(centroids[b] ** 2 + centroids[b + 1] ** 2 + centroids[b + 2] ** 2);
      expect(len).toBeCloseTo(1, 3);
    }
  });
});

describe('shadePlanes', () => {
  it('produces brighter output for planes facing the light', () => {
    // 2 planes: one facing up (0,0,1), one facing right (1,0,0)
    const labels = new Uint8Array([0, 0, 1, 1]);
    const centroids = new Float32Array([0, 0, 1, 1, 0, 0]); // plane0=up, plane1=right

    // Light from directly above: elevation=90 → light=(0,0,1)
    const result = shadePlanes(labels, centroids, 2, 2, 0, 90);

    // Plane 0 faces the light → bright; Plane 1 perpendicular → dark
    const p0shade = result.data[0]; // R of pixel 0 (plane 0)
    const p1shade = result.data[8]; // R of pixel 2 (plane 1)
    expect(p0shade).toBeGreaterThan(p1shade);
  });

  it('returns valid ImageData dimensions', () => {
    const labels = new Uint8Array([0, 0, 0, 0, 0, 0]);
    const centroids = new Float32Array([0, 0, 1]);
    const result = shadePlanes(labels, centroids, 3, 2, 225, 45);
    expect(result.width).toBe(3);
    expect(result.height).toBe(2);
    expect(result.data.length).toBe(3 * 2 * 4);
  });
});

describe('processPlanes', () => {
  it('produces an ImageData from a synthetic depth map', () => {
    const width = 10, height = 10;
    // Depth ramp: increases left to right
    const depth = new Float32Array(width * height);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        depth[y * width + x] = x / (width - 1);
      }
    }
    const config = { planeCount: 3, lightAzimuth: 225, lightElevation: 45, minRegionSize: 'off' as const };
    const result = processPlanes(depth, width, height, config);
    expect(result.width).toBe(width);
    expect(result.height).toBe(height);
    expect(result.data.length).toBe(width * height * 4);
  });
});
