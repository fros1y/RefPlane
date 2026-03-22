struct KMeansParams {
  numPixels: u32,
  k: u32,
  _pad0: u32,
  _pad1: u32,
  lWeight: f32,
  _pad2: f32,
  _pad3: f32,
  _pad4: f32,
};

@group(0) @binding(0) var<storage, read> pixels: array<f32>;
@group(0) @binding(1) var<storage, read> centroids: array<f32>;
@group(0) @binding(2) var<storage, read_write> assignments: array<u32>;
@group(0) @binding(3) var<uniform> params: KMeansParams;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let base = idx * 3u;
  let pL = pixels[base];
  let pA = pixels[base + 1u];
  let pB = pixels[base + 2u];

  var bestDist = 1e20;
  var bestC = 0u;
  for (var ci = 0u; ci < params.k; ci = ci + 1u) {
    let cBase = ci * 3u;
    let dL = pL - centroids[cBase];
    let dA = pA - centroids[cBase + 1u];
    let dB = pB - centroids[cBase + 2u];
    let dist = params.lWeight * dL * dL + dA * dA + dB * dB;
    if (dist < bestDist) {
      bestDist = dist;
      bestC = ci;
    }
  }

  assignments[idx] = bestC;
}
