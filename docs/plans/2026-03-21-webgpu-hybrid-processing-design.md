# WebGPU Hybrid Processing Design

## Goal

Reduce processing latency in RefPlane by moving the largest image-wide kernels to WebGPU while preserving the current CPU worker pipeline as a fallback.

## Scope

- Add a WebGPU processing module that can run inside the existing worker context.
- Accelerate grayscale conversion and bilateral filtering on the GPU.
- Route `value-study` and the bilateral stage of `color-regions` through WebGPU when available.
- Keep CPU implementations for fallback and for operations not yet ported.

## Design

- The worker remains the orchestration boundary for all processing requests.
- A lazy WebGPU device is initialized once and cached.
- GPU kernels operate on packed RGBA buffers or Lab float buffers.
- Results are read back into `ImageData` or `Float32Array` so the current downstream code can remain unchanged.
- Requests stay serialized in the worker so async GPU execution does not reorder results relative to the existing app logic.

## Initial Tradeoffs

- This phase focuses on the heaviest shared filters first instead of a full end-to-end GPU rewrite.
- `canny`, `sobel`, `kMeans`, and region cleanup remain on CPU for now to limit behavioral risk.
- Readback overhead remains, but the expensive per-pixel neighborhood work moves off the CPU.

## Verification

- `npm run build` must pass.
- Existing processing modes must still return valid images when WebGPU is unavailable.
- On WebGPU-capable browsers, `value-study`, `color-regions`, and grayscale mode should use the GPU path without changing the external UI contract.
