struct TensorParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  tensorSigma: f32,
  _pad1: f32,
  _pad2: f32,
  _pad3: f32,
};

@group(0) @binding(0) var<storage, read> src: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> dst: array<vec4<f32>>;
@group(0) @binding(2) var<uniform> params: TensorParams;

fn fetch_luma(x: i32, y: i32, w: i32, h: i32) -> f32 {
  let cx = clamp(x, 0, w - 1);
  let cy = clamp(y, 0, h - 1);
  let c = src[u32(cy * w + cx)].xyz;
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let w = i32(params.width);
  let h = i32(params.height);
  let px = i32(idx % params.width);
  let py = i32(idx / params.width);

  let radius = max(1, i32(ceil(params.tensorSigma * 2.0)));
  let sigma2 = max(params.tensorSigma * params.tensorSigma, 0.01);

  var j11 = 0.0;
  var j12 = 0.0;
  var j22 = 0.0;
  var gradSum = 0.0;
  var wSum = 0.0;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let dist2 = f32(dx * dx + dy * dy);
      let gw = exp(-dist2 / (2.0 * sigma2));
      let nx = px + dx;
      let ny = py + dy;
      let gx = fetch_luma(nx + 1, ny, w, h) - fetch_luma(nx - 1, ny, w, h);
      let gy = fetch_luma(nx, ny + 1, w, h) - fetch_luma(nx, ny - 1, w, h);
      j11 = j11 + gw * gx * gx;
      j12 = j12 + gw * gx * gy;
      j22 = j22 + gw * gy * gy;
      gradSum = gradSum + gw * sqrt(gx * gx + gy * gy);
      wSum = wSum + gw;
    }
  }

  j11 = j11 / wSum;
  j12 = j12 / wSum;
  j22 = j22 / wSum;
  gradSum = gradSum / wSum;

  let trace = j11 + j22;
  let det = j11 * j22 - j12 * j12;
  let disc = sqrt(max(0.0, trace * trace / 4.0 - det));
  let lambda1 = trace / 2.0 + disc;
  let lambda2 = trace / 2.0 - disc;

  var dir: vec2<f32>;
  if (abs(j12) > 1e-6) {
    dir = normalize(vec2<f32>(lambda1 - j22, j12));
  } else {
    if (j11 > j22) {
      dir = vec2<f32>(1.0, 0.0);
    } else {
      dir = vec2<f32>(0.0, 1.0);
    }
  }

  let anisotropy = (lambda1 - lambda2) / (lambda1 + lambda2 + 1e-6);
  dst[idx] = vec4<f32>(dir.x, dir.y, anisotropy, gradSum);
}
