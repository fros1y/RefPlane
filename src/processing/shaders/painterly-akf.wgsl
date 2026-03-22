struct AkfParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  radius: f32,
  q: f32,
  alpha: f32,
  zeta: f32,
};

@group(0) @binding(0) var<storage, read> src: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> tensorTex: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> dst: array<vec4<f32>>;
@group(0) @binding(3) var<uniform> params: AkfParams;

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318530;

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn angular_dist(a: f32, b: f32) -> f32 {
  var d = a - b;
  if (d > PI) { d = d - TAU; }
  if (d < -PI) { d = d + TAU; }
  return abs(d);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let w = i32(params.width);
  let h = i32(params.height);
  let px = i32(idx % params.width);
  let py = i32(idx / params.width);

  let t = tensorTex[idx];
  let dir = vec2<f32>(t.x, t.y);
  let perp = vec2<f32>(-t.y, t.x);
  let A = t.z;

  let major = params.radius * (1.0 + params.alpha * A);
  let minor = max(params.radius / (1.0 + params.alpha * A), 1.0);
  let scanR = i32(ceil(major));

  var sR: array<f32, 8>;
  var sG: array<f32, 8>;
  var sB: array<f32, 8>;
  var sL: array<f32, 8>;
  var sL2: array<f32, 8>;
  var sW: array<f32, 8>;

  for (var dy = -scanR; dy <= scanR; dy = dy + 1) {
    let ny = py + dy;
    if (ny < 0 || ny >= h) { continue; }
    for (var dx = -scanR; dx <= scanR; dx = dx + 1) {
      let nx = px + dx;
      if (nx < 0 || nx >= w) { continue; }

      let offset = vec2<f32>(f32(dx), f32(dy));
      let u = dot(offset, dir) / major;
      let v = dot(offset, perp) / minor;
      let r2 = u * u + v * v;
      if (r2 > 1.0) { continue; }

      let si = u32(ny * w + nx);
      let color = src[si].xyz;
      let l = luma(color);

      let radialBase = max(0.0, 1.0 - r2);
      let radialW = radialBase * radialBase;
      let theta = atan2(v, u);

      for (var k = 0u; k < 8u; k = k + 1u) {
        let center = -PI + (f32(k) + 0.5) * TAU / 8.0;
        let phi = angular_dist(theta, center);
        let angBase = max(0.0, 1.0 - phi / params.zeta);
        let angW = angBase * angBase;
        let weight = radialW * angW;
        if (weight > 0.0) {
          sR[k] = sR[k] + weight * color.x;
          sG[k] = sG[k] + weight * color.y;
          sB[k] = sB[k] + weight * color.z;
          sL[k] = sL[k] + weight * l;
          sL2[k] = sL2[k] + weight * l * l;
          sW[k] = sW[k] + weight;
        }
      }
    }
  }

  var totalR = 0.0;
  var totalG = 0.0;
  var totalB = 0.0;
  var totalW = 0.0;
  for (var k = 0u; k < 8u; k = k + 1u) {
    if (sW[k] > 0.0) {
      let mR = sR[k] / sW[k];
      let mG = sG[k] / sW[k];
      let mB = sB[k] / sW[k];
      let mL = sL[k] / sW[k];
      let variance = max(0.0, sL2[k] / sW[k] - mL * mL);
      let wk = 1.0 / pow(1e-6 + variance, params.q * 0.5);
      totalR = totalR + wk * mR;
      totalG = totalG + wk * mG;
      totalB = totalB + wk * mB;
      totalW = totalW + wk;
    }
  }

  if (totalW > 0.0) {
    dst[idx] = vec4<f32>(totalR / totalW, totalG / totalW, totalB / totalW, src[idx].w);
  } else {
    dst[idx] = src[idx];
  }
}
