struct QuantizeParams {
  pixelCount: u32,
  thresholdCount: u32,
  totalLevels: u32,
  _pad0: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: QuantizeParams;
@group(0) @binding(3) var<storage, read> thresholds: array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let pixel = src[idx];
  let value = f32(pixel & 0xffu) / 255.0;
  var level = params.thresholdCount;
  for (var i = 0u; i < params.thresholdCount; i = i + 1u) {
    if (value < thresholds[i]) {
      level = i;
      break;
    }
  }

  var gray = 128u;
  if (params.totalLevels > 1u) {
    gray = u32(clamp(round((f32(level) / f32(params.totalLevels - 1u)) * 255.0), 0.0, 255.0));
  }

  let alpha = (pixel >> 24u) & 0xffu;
  dst[idx] = gray | (gray << 8u) | (gray << 16u) | (alpha << 24u);
}
