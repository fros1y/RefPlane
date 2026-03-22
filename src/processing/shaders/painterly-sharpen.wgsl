struct SharpenParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  sharpenAmount: f32,
  edgeThresholdLow: f32,
  edgeThresholdHigh: f32,
  detailSigma: f32,
};

@group(0) @binding(0) var<storage, read> akf: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> tensorTex: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> dst: array<vec4<f32>>;
@group(0) @binding(3) var<uniform> params: SharpenParams;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let w = i32(params.width);
  let h = i32(params.height);
  let px = i32(idx % params.width);
  let py = i32(idx / params.width);

  let center = akf[idx].xyz;
  let radius = max(1, i32(ceil(params.detailSigma * 2.0)));
  let sigma2 = max(params.detailSigma * params.detailSigma, 0.01);

  var blurred = vec3<f32>(0.0, 0.0, 0.0);
  var wSum = 0.0;
  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    let ny = clamp(py + dy, 0, h - 1);
    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let nx = clamp(px + dx, 0, w - 1);
      let gw = exp(-f32(dx * dx + dy * dy) / (2.0 * sigma2));
      blurred = blurred + gw * akf[u32(ny * w + nx)].xyz;
      wSum = wSum + gw;
    }
  }
  blurred = blurred / wSum;

  let detail = center - blurred;
  let t = tensorTex[idx];
  let gradMag = t.w;
  let aniso = t.z;
  let edgeMask = smoothstep(params.edgeThresholdLow, params.edgeThresholdHigh, gradMag) * mix(0.5, 1.0, aniso);

  let sharpened = max(vec3<f32>(0.0, 0.0, 0.0), center + params.sharpenAmount * edgeMask * detail);
  dst[idx] = vec4<f32>(sharpened, akf[idx].w);
}
