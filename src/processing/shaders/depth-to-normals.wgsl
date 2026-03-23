struct Params {
  width: u32,
  height: u32,
  numPixels: u32,
  _pad: u32,
  depthScale: f32,
};

@group(0) @binding(0) var<storage, read> depth: array<f32>;
@group(0) @binding(1) var<storage, read_write> normals: array<f32>;
@group(0) @binding(2) var<uniform> params: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let x = idx % params.width;
  let y = idx / params.width;

  let left  = select(depth[idx - 1u], depth[idx], x == 0u);
  let right = select(depth[idx + 1u], depth[idx], x >= params.width - 1u);
  let up    = select(depth[idx - params.width], depth[idx], y == 0u);
  let down  = select(depth[idx + params.width], depth[idx], y >= params.height - 1u);

  let dx = (right - left) * 0.5 * params.depthScale;
  let dy = (down - up) * 0.5 * params.depthScale;

  let n = normalize(vec3<f32>(-dx, -dy, 1.0));

  let base = idx * 3u;
  normals[base]      = n.x;
  normals[base + 1u] = n.y;
  normals[base + 2u] = n.z;
}
