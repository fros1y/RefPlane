struct MeanShiftParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  maxIter: u32,
  spatialRadius: f32,
  colorRadius2: f32,
  convergenceThreshold: f32,
  _pad0: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: MeanShiftParams;

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
  if (idx >= params.pixelCount) { return; }

  let width = i32(params.width);
  let height = i32(params.height);
  var cx = f32(i32(idx % params.width));
  var cy = f32(i32(idx / params.width));

  let center = unpack_rgba(src[idx]);
  var cR = center.x;
  var cG = center.y;
  var cB = center.z;
  let alpha = u32(center.w);

  let sr = i32(ceil(params.spatialRadius));
  let spatialR2 = params.spatialRadius * params.spatialRadius;

  for (var iter = 0u; iter < params.maxIter; iter = iter + 1u) {
    let ix = i32(round(cx));
    let iy = i32(round(cy));
    let y0 = max(0, iy - sr);
    let y1 = min(height - 1, iy + sr);
    let x0 = max(0, ix - sr);
    let x1 = min(width - 1, ix + sr);

    var sumX = 0.0;
    var sumY = 0.0;
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    var count = 0.0;

    for (var ny = y0; ny <= y1; ny = ny + 1) {
      for (var nx = x0; nx <= x1; nx = nx + 1) {
        let dx = f32(nx) - cx;
        let dy = f32(ny) - cy;
        if (dx * dx + dy * dy > spatialR2) { continue; }

        let s = unpack_rgba(src[u32(ny * width + nx)]);
        let dR = s.x - cR;
        let dG = s.y - cG;
        let dB = s.z - cB;
        if (dR * dR + dG * dG + dB * dB > params.colorRadius2) { continue; }

        sumX = sumX + f32(nx);
        sumY = sumY + f32(ny);
        sumR = sumR + s.x;
        sumG = sumG + s.y;
        sumB = sumB + s.z;
        count = count + 1.0;
      }
    }

    if (count <= 0.0) { break; }

    let newX = sumX / count;
    let newY = sumY / count;
    let newR = sumR / count;
    let newG = sumG / count;
    let newB = sumB / count;

    let shift = sqrt((newR - cR) * (newR - cR) + (newG - cG) * (newG - cG) + (newB - cB) * (newB - cB));

    cx = newX;
    cy = newY;
    cR = newR;
    cG = newG;
    cB = newB;

    if (shift < params.convergenceThreshold) { break; }
  }

  let r = u32(clamp(round(cR), 0.0, 255.0));
  let g = u32(clamp(round(cG), 0.0, 255.0));
  let b = u32(clamp(round(cB), 0.0, 255.0));
  dst[idx] = r | (g << 8u) | (b << 16u) | (alpha << 24u);
}
