struct KuwaharaParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  radius: u32,
  sharpness: f32,
  sectors: u32,
  _pad0: u32,
  _pad1: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: KuwaharaParams;
@group(0) @binding(3) var<storage, read> planeLabels: array<u32>;

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318530;

fn unpack_rgb(pixel: u32) -> vec3<f32> {
  return vec3<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu)
  );
}

fn pack_rgba(c: vec3<f32>, a: u32) -> u32 {
  return u32(clamp(round(c.x), 0.0, 255.0))
       | (u32(clamp(round(c.y), 0.0, 255.0)) << 8u)
       | (u32(clamp(round(c.z), 0.0, 255.0)) << 16u)
       | (a << 24u);
}

// Classic 4-quadrant stats with plane-label barrier
fn accumulate_q_guided(x0: i32, x1: i32, y0: i32, y1: i32, w: i32, h: i32, centerLabel: u32) -> vec4<f32> {
  var sum = vec3<f32>(0.0);
  var sum2 = vec3<f32>(0.0);
  var count = 0.0;
  for (var yy = y0; yy <= y1; yy = yy + 1) {
    if (yy < 0 || yy >= h) { continue; }
    for (var xx = x0; xx <= x1; xx = xx + 1) {
      if (xx < 0 || xx >= w) { continue; }
      let nIdx = u32(yy * w + xx);
      if (planeLabels[nIdx] != centerLabel) { continue; }
      let c = unpack_rgb(src[nIdx]);
      sum = sum + c;
      sum2 = sum2 + c * c;
      count = count + 1.0;
    }
  }
  if (count <= 0.0) {
    return vec4<f32>(0.0, 0.0, 0.0, 1e12);
  }
  let mean = sum / count;
  let v = sum2 / count - mean * mean;
  return vec4<f32>(mean, v.x + v.y + v.z);
}

// Blend 4 quadrant results using sharpness-weighted or hard-select
fn blend4(q0: vec4<f32>, q1: vec4<f32>, q2: vec4<f32>, q3: vec4<f32>, alpha: u32) -> u32 {
  let hardSelect = params.sharpness >= 20.0;
  if (hardSelect) {
    var best = q0;
    if (q1.w < best.w) { best = q1; }
    if (q2.w < best.w) { best = q2; }
    if (q3.w < best.w) { best = q3; }
    return pack_rgba(best.xyz, alpha);
  }
  let q = params.sharpness * 0.5;
  let w0 = 1.0 / pow(1.0 + q0.w, q);
  let w1 = 1.0 / pow(1.0 + q1.w, q);
  let w2 = 1.0 / pow(1.0 + q2.w, q);
  let w3 = 1.0 / pow(1.0 + q3.w, q);
  let wt = w0 + w1 + w2 + w3;
  let c = (w0 * q0.xyz + w1 * q1.xyz + w2 * q2.xyz + w3 * q3.xyz) / wt;
  return pack_rgba(c, alpha);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let w = i32(params.width);
  let h = i32(params.height);
  let radius = i32(params.radius);
  let px = i32(idx % params.width);
  let py = i32(idx / params.width);
  let alpha = (src[idx] >> 24u) & 0xffu;
  let centerLabel = planeLabels[idx];

  // ── Classic 4-quadrant path ──
  if (params.sectors == 4u) {
    let q0 = accumulate_q_guided(px - radius, px, py - radius, py, w, h, centerLabel);
    let q1 = accumulate_q_guided(px, px + radius, py - radius, py, w, h, centerLabel);
    let q2 = accumulate_q_guided(px - radius, px, py, py + radius, w, h, centerLabel);
    let q3 = accumulate_q_guided(px, px + radius, py, py + radius, w, h, centerLabel);
    dst[idx] = blend4(q0, q1, q2, q3, alpha);
    return;
  }

  // ── Generalized 8-sector Kuwahara with plane-label barrier ──
  let sectorAngle = TAU / 8.0;
  let sigma = f32(radius) * 0.5;
  let invS2 = 1.0 / (2.0 * sigma * sigma);

  // Per-sector weighted accumulators
  var sR: array<f32, 8>;
  var sG: array<f32, 8>;
  var sB: array<f32, 8>;
  var sR2: array<f32, 8>;
  var sG2: array<f32, 8>;
  var sB2: array<f32, 8>;
  var sW: array<f32, 8>;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    let ny = py + dy;
    if (ny < 0 || ny >= h) { continue; }
    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let nx = px + dx;
      if (nx < 0 || nx >= w) { continue; }

      let nIdx = u32(ny * w + nx);
      if (planeLabels[nIdx] != centerLabel) { continue; }

      let dxf = f32(dx);
      let dyf = f32(dy);
      let distSq = dxf * dxf + dyf * dyf;
      let gaussW = exp(-distSq * invS2);
      let color = unpack_rgb(src[nIdx]);
      let isCenter = (dx == 0 && dy == 0);

      if (isCenter) {
        // Center pixel belongs equally to all sectors
        let cw = gaussW * 0.125; // 1/8
        for (var k = 0u; k < 8u; k = k + 1u) {
          sR[k] += cw * color.x;
          sG[k] += cw * color.y;
          sB[k] += cw * color.z;
          sR2[k] += cw * color.x * color.x;
          sG2[k] += cw * color.y * color.y;
          sB2[k] += cw * color.z * color.z;
          sW[k] += cw;
        }
      } else {
        let angle = atan2(dyf, dxf);
        for (var k = 0u; k < 8u; k = k + 1u) {
          let center = f32(k) * sectorAngle;
          var diff = angle - center;
          if (diff > PI) { diff -= TAU; }
          if (diff < -PI) { diff += TAU; }
          let ad = abs(diff);
          if (ad < sectorAngle) {
            let angW = 0.5 * (1.0 + cos(PI * ad / sectorAngle));
            let wt = gaussW * angW;
            sR[k] += wt * color.x;
            sG[k] += wt * color.y;
            sB[k] += wt * color.z;
            sR2[k] += wt * color.x * color.x;
            sG2[k] += wt * color.y * color.y;
            sB2[k] += wt * color.z * color.z;
            sW[k] += wt;
          }
        }
      }
    }
  }

  // Blending
  let hardSelect = params.sharpness >= 20.0;
  if (hardSelect) {
    var bestC = vec3<f32>(0.0);
    var bestVar = 1e12;
    for (var k = 0u; k < 8u; k = k + 1u) {
      if (sW[k] > 0.0) {
        let m = vec3<f32>(sR[k], sG[k], sB[k]) / sW[k];
        let m2 = vec3<f32>(sR2[k], sG2[k], sB2[k]) / sW[k];
        let v = m2 - m * m;
        let variance = v.x + v.y + v.z;
        if (variance < bestVar) {
          bestVar = variance;
          bestC = m;
        }
      }
    }
    dst[idx] = pack_rgba(bestC, alpha);
  } else {
    var totalC = vec3<f32>(0.0);
    var totalW = 0.0;
    let q = params.sharpness * 0.5;
    for (var k = 0u; k < 8u; k = k + 1u) {
      if (sW[k] > 0.0) {
        let m = vec3<f32>(sR[k], sG[k], sB[k]) / sW[k];
        let m2 = vec3<f32>(sR2[k], sG2[k], sB2[k]) / sW[k];
        let v = m2 - m * m;
        let variance = max(0.0, v.x + v.y + v.z);
        let wk = 1.0 / pow(1.0 + variance, q);
        totalC += wk * m;
        totalW += wk;
      }
    }
    if (totalW > 0.0) {
      dst[idx] = pack_rgba(totalC / totalW, alpha);
    } else {
      dst[idx] = src[idx];
    }
  }
}
