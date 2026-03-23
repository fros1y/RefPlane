struct Params {
  numPixels: u32,
  k: u32,
  _pad0: u32,
  _pad1: u32,
  lightX: f32,
  lightY: f32,
  lightZ: f32,
  ambient: f32,
};

@group(0) @binding(0) var<storage, read> labels: array<u32>;
@group(0) @binding(1) var<storage, read> centroids: array<f32>;
@group(0) @binding(2) var<storage, read_write> output: array<u32>;
@group(0) @binding(3) var<uniform> params: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let c = labels[idx];
  let cBase = c * 3u;
  let nx = centroids[cBase];
  let ny = centroids[cBase + 1u];
  let nz = centroids[cBase + 2u];

  let dot_val = nx * params.lightX + ny * params.lightY + nz * params.lightZ;
  let shade = clamp(dot_val * (1.0 - params.ambient) + params.ambient, 0.0, 1.0);
  let v = u32(shade * 255.0);

  output[idx] = v | (v << 8u) | (v << 16u) | (255u << 24u);
}
