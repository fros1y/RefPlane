struct GrayParams {
  pixelCount: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: GrayParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let rgba = unpack_rgba(src[idx]);
  let gray = u32(clamp(round(0.2126 * rgba.x + 0.7152 * rgba.y + 0.0722 * rgba.z), 0.0, 255.0));
  let alpha = u32(rgba.w);
  dst[idx] = gray | (gray << 8u) | (gray << 16u) | (alpha << 24u);
}
