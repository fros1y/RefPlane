struct SobelParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  threshold: f32,
  _pad1: f32,
  _pad2: f32,
  _pad3: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: SobelParams;

fn gray01(p: u32) -> f32 {
  return f32(p & 0xffu) / 255.0;
}

fn at(x: i32, y: i32, width: i32) -> f32 {
  return gray01(src[u32(y * width + x)]);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let width = i32(params.width);
  let height = i32(params.height);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  if (x <= 0 || y <= 0 || x >= width - 1 || y >= height - 1) {
    let a = (src[idx] >> 24u) & 0xffu;
    dst[idx] = a << 24u;
    return;
  }

  let gx = -at(x - 1, y - 1, width) - 2.0 * at(x - 1, y, width) - at(x - 1, y + 1, width)
    + at(x + 1, y - 1, width) + 2.0 * at(x + 1, y, width) + at(x + 1, y + 1, width);
  let gy = -at(x - 1, y - 1, width) - 2.0 * at(x, y - 1, width) - at(x + 1, y - 1, width)
    + at(x - 1, y + 1, width) + 2.0 * at(x, y + 1, width) + at(x + 1, y + 1, width);

  let mag = sqrt(gx * gx + gy * gy) / 4.0;
  var v = 0u;
  if (mag > params.threshold) {
    v = u32(clamp(round(mag * 255.0), 0.0, 255.0));
  }
  dst[idx] = v | (v << 8u) | (v << 16u) | (0xffu << 24u);
}
