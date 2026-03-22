struct BilateralParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  radius: u32,
  sigmaS2: f32,
  sigmaR2: f32,
  _pad0: f32,
  _pad1: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: BilateralParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

fn luminance(pixel: u32) -> f32 {
  let rgba = unpack_rgba(pixel);
  return (0.2126 * rgba.x + 0.7152 * rgba.y + 0.0722 * rgba.z) / 255.0;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let width = i32(params.width);
  let height = i32(params.height);
  let radius = i32(params.radius);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  let center = src[idx];
  let centerValue = luminance(center);

  var sum = 0.0;
  var weightSum = 0.0;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    let ny = y + dy;
    if (ny < 0 || ny >= height) {
      continue;
    }

    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let nx = x + dx;
      if (nx < 0 || nx >= width) {
        continue;
      }

      let sampleIndex = u32(ny * width + nx);
      let sampleValue = luminance(src[sampleIndex]);
      let spatialDist = f32(dx * dx + dy * dy);
      let valueDiff = centerValue - sampleValue;
      let weight = exp(-spatialDist / params.sigmaS2 - (valueDiff * valueDiff) / params.sigmaR2);
      sum = sum + weight * sampleValue;
      weightSum = weightSum + weight;
    }
  }

  let result = u32(clamp(round((sum / weightSum) * 255.0), 0.0, 255.0));
  let alpha = u32((center >> 24u) & 0xffu);
  dst[idx] = result | (result << 8u) | (result << 16u) | (alpha << 24u);
}
