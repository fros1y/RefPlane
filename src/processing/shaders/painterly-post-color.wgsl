struct PostParams {
  pixelCount: u32,
};

@group(0) @binding(0) var<storage, read> src: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: PostParams;

fn linear_to_srgb(c: f32) -> f32 {
  if (c <= 0.0031308) {
    return c * 12.92;
  }
  return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let rgb = clamp(src[idx].xyz, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0));
  let alpha = src[idx].w;

  let sR = u32(clamp(round(linear_to_srgb(rgb.x) * 255.0), 0.0, 255.0));
  let sG = u32(clamp(round(linear_to_srgb(rgb.y) * 255.0), 0.0, 255.0));
  let sB = u32(clamp(round(linear_to_srgb(rgb.z) * 255.0), 0.0, 255.0));
  let a = u32(clamp(round(alpha * 255.0), 0.0, 255.0));
  dst[idx] = sR | (sG << 8u) | (sB << 16u) | (a << 24u);
}
