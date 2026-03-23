struct Params {
  numPixels: u32,
  k: u32,
  _pad0: u32,
  _pad1: u32,
};

@group(0) @binding(0) var<storage, read> normals: array<f32>;
@group(0) @binding(1) var<storage, read> centroids: array<f32>;
@group(0) @binding(2) var<storage, read_write> labels: array<u32>;
@group(0) @binding(3) var<uniform> params: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let base = idx * 3u;
  let nx = normals[base];
  let ny = normals[base + 1u];
  let nz = normals[base + 2u];

  var bestDist: f32 = 1e20;
  var bestC: u32 = 0u;
  for (var ci: u32 = 0u; ci < params.k; ci = ci + 1u) {
    let cBase = ci * 3u;
    let dx = nx - centroids[cBase];
    let dy = ny - centroids[cBase + 1u];
    let dz = nz - centroids[cBase + 2u];
    let dist = dx * dx + dy * dy + dz * dz;
    if (dist < bestDist) {
      bestDist = dist;
      bestC = ci;
    }
  }

  labels[idx] = bestC;
}
