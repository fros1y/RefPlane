struct AnisoParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  kappa2: f32,
  lambda: f32,
  _pad1: f32,
  _pad2: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: AnisoParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

fn get_rgb(x: i32, y: i32, width: i32) -> vec3<f32> {
  let p = unpack_rgba(src[u32(y * width + x)]);
  return p.xyz;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let width = i32(params.width);
  let height = i32(params.height);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  let centerPixel = unpack_rgba(src[idx]);
  let center = centerPixel.xyz;
  let alpha = u32(centerPixel.w);

  var delta = vec3<f32>(0.0);

  if (y > 0) {
    let n = get_rgb(x, y - 1, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }
  if (y < height - 1) {
    let n = get_rgb(x, y + 1, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }
  if (x > 0) {
    let n = get_rgb(x - 1, y, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }
  if (x < width - 1) {
    let n = get_rgb(x + 1, y, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }

  let out = center + params.lambda * delta;
  let r = u32(clamp(round(out.x), 0.0, 255.0));
  let g = u32(clamp(round(out.y), 0.0, 255.0));
  let b = u32(clamp(round(out.z), 0.0, 255.0));
  dst[idx] = r | (g << 8u) | (b << 16u) | (alpha << 24u);
}
