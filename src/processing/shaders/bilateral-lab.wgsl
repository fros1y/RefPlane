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

@group(0) @binding(0) var<storage, read> src: array<f32>;
@group(0) @binding(1) var<storage, read_write> dst: array<f32>;
@group(0) @binding(2) var<uniform> params: BilateralParams;

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
  let base = idx * 3u;

  let cL = src[base];
  let cA = src[base + 1u];
  let cB = src[base + 2u];

  var sumL = 0.0;
  var sumA = 0.0;
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

      let sampleIndex = u32(ny * width + nx) * 3u;
      let nL = src[sampleIndex];
      let nA = src[sampleIndex + 1u];
      let nB = src[sampleIndex + 2u];
      let dL = cL - nL;
      let dA = cA - nA;
      let dB = cB - nB;
      let spatialDist = f32(dx * dx + dy * dy);
      let valueDiff2 = dL * dL + dA * dA + dB * dB;
      let weight = exp(-spatialDist / params.sigmaS2 - valueDiff2 / params.sigmaR2);
      sumL = sumL + weight * nL;
      sumA = sumA + weight * nA;
      sumB = sumB + weight * nB;
      weightSum = weightSum + weight;
    }
  }

  dst[base] = sumL / weightSum;
  dst[base + 1u] = sumA / weightSum;
  dst[base + 2u] = sumB / weightSum;
}
