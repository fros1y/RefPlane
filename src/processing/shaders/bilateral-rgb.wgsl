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
  let center = unpack_rgba(src[idx]);
  let cR = center.x / 255.0;
  let cG = center.y / 255.0;
  let cB = center.z / 255.0;

  var sumR = 0.0;
  var sumG = 0.0;
  var sumB = 0.0;
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

      let sample = unpack_rgba(src[u32(ny * width + nx)]);
      let nR = sample.x / 255.0;
      let nG = sample.y / 255.0;
      let nB = sample.z / 255.0;
      let spatialDist = f32(dx * dx + dy * dy);
      let dR = cR - nR;
      let dG = cG - nG;
      let dB = cB - nB;
      let colorDist = dR * dR + dG * dG + dB * dB;
      let weight = exp(-spatialDist / params.sigmaS2 - colorDist / params.sigmaR2);

      sumR = sumR + weight * sample.x;
      sumG = sumG + weight * sample.y;
      sumB = sumB + weight * sample.z;
      weightSum = weightSum + weight;
    }
  }

  let r = u32(clamp(round(sumR / weightSum), 0.0, 255.0));
  let g = u32(clamp(round(sumG / weightSum), 0.0, 255.0));
  let b = u32(clamp(round(sumB / weightSum), 0.0, 255.0));
  let a = u32(center.w);
  dst[idx] = r | (g << 8u) | (b << 16u) | (a << 24u);
}
