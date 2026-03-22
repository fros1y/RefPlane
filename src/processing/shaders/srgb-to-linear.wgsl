struct LinearParams {
  pixelCount: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<vec4<f32>>;
@group(0) @binding(2) var<uniform> params: LinearParams;

fn srgb_to_linear(c: f32) -> f32 {
  if (c <= 0.04045) {
    return c / 12.92;
  }
  return pow((c + 0.055) / 1.055, 2.4);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }
  let pixel = src[idx];
  let r = f32(pixel & 0xffu) / 255.0;
  let g = f32((pixel >> 8u) & 0xffu) / 255.0;
  let b = f32((pixel >> 16u) & 0xffu) / 255.0;
  let a = f32((pixel >> 24u) & 0xffu) / 255.0;
  dst[idx] = vec4<f32>(srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), a);
}
