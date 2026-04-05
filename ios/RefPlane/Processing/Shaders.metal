#include <metal_stdlib>
using namespace metal;

// ──────────────────────────────────────────────────────────────
// MARK: - Common helpers
// ──────────────────────────────────────────────────────────────

/// Unpack a 32-bit RGBA pixel (little-endian) into float4 [0..255].
inline float4 unpack_rgba(uint pixel) {
    return float4(
        float(pixel & 0xFFu),
        float((pixel >> 8u) & 0xFFu),
        float((pixel >> 16u) & 0xFFu),
        float((pixel >> 24u) & 0xFFu)
    );
}

/// Pack float4 RGBA [0..255] back to a 32-bit pixel.
inline uint pack_rgba(float4 c) {
    uint r = uint(clamp(c.x, 0.0f, 255.0f));
    uint g = uint(clamp(c.y, 0.0f, 255.0f));
    uint b = uint(clamp(c.z, 0.0f, 255.0f));
    uint a = uint(clamp(c.w, 0.0f, 255.0f));
    return r | (g << 8u) | (b << 16u) | (a << 24u);
}

/// sRGB → linear channel
inline float linearize_srgb(float c) {
    return (c <= 0.04045f) ? (c / 12.92f) : powr((c + 0.055f) / 1.055f, 2.4f);
}

/// linear → sRGB channel
inline float delinearize_srgb(float c) {
    return (c <= 0.0031308f) ? (c * 12.92f) : (1.055f * powr(c, 1.0f / 2.4f) - 0.055f);
}

/// RGB (0-1 linear) → Oklab
inline float3 linear_rgb_to_oklab(float3 rgb) {
    float l = 0.4122214708f * rgb.x + 0.5363325363f * rgb.y + 0.0514459929f * rgb.z;
    float m = 0.2119034982f * rgb.x + 0.6806995451f * rgb.y + 0.1073969566f * rgb.z;
    float s = 0.0883024619f * rgb.x + 0.2817188376f * rgb.y + 0.6299787005f * rgb.z;

    float l_ = pow(l, 1.0f / 3.0f);
    float m_ = pow(m, 1.0f / 3.0f);
    float s_ = pow(s, 1.0f / 3.0f);

    return float3(
        0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_,
        1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_,
        0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_
    );
}

/// Oklab → linear RGB (0-1, unclamped)
inline float3 oklab_to_linear_rgb(float3 lab) {
    float l_ = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m_ = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s_ = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;

    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;

    return float3(
         4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
        -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
        -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s
    );
}

/// Decode one packed RGBA pixel to Oklab (float3 Lab)
inline float3 pixel_to_oklab(uint pixel) {
    float4 rgba = unpack_rgba(pixel);
    float3 srgb = rgba.xyz / 255.0f;
    float3 lin = float3(linearize_srgb(srgb.x),
                        linearize_srgb(srgb.y),
                        linearize_srgb(srgb.z));
    return linear_rgb_to_oklab(lin);
}

/// Encode Oklab → packed RGBA (preserving given alpha byte)
inline uint oklab_to_pixel(float3 lab, uint alpha) {
    float3 lin = oklab_to_linear_rgb(lab);
    float3 srgb = float3(delinearize_srgb(lin.x),
                         delinearize_srgb(lin.y),
                         delinearize_srgb(lin.z));
    float3 bytes = round(clamp(srgb * 255.0f, 0.0f, 255.0f));
    return uint(bytes.x) | (uint(bytes.y) << 8u) | (uint(bytes.z) << 16u) | (alpha << 24u);
}


// ──────────────────────────────────────────────────────────────
// MARK: - Grayscale (Rec 709 linearized luminance)
// ──────────────────────────────────────────────────────────────

struct GrayscaleParams {
    uint pixelCount;
};

kernel void grayscale(
    device const uint*   src    [[buffer(0)]],
    device uint*         dst    [[buffer(1)]],
    constant GrayscaleParams& p [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    float4 rgba = unpack_rgba(src[gid]);
    float3 srgb = rgba.xyz / 255.0f;
    float3 lin  = float3(linearize_srgb(srgb.x),
                         linearize_srgb(srgb.y),
                         linearize_srgb(srgb.z));
    float lum   = 0.2126f * lin.x + 0.7152f * lin.y + 0.0722f * lin.z;
    float enc   = delinearize_srgb(lum);
    uint gray   = uint(clamp(round(enc * 255.0f), 0.0f, 255.0f));
    uint alpha  = uint(rgba.w);
    dst[gid]    = gray | (gray << 8u) | (gray << 16u) | (alpha << 24u);
}


// ──────────────────────────────────────────────────────────────
// MARK: - RGB → Oklab bulk conversion
// ──────────────────────────────────────────────────────────────

struct RGBToOklabParams {
    uint pixelCount;
};

/// Convert packed RGBA pixels to planar float3 Oklab (L,a,b per pixel).
kernel void rgb_to_oklab(
    device const uint*      src    [[buffer(0)]],
    device float*           lab    [[buffer(1)]],  // interleaved L,a,b
    constant RGBToOklabParams& p   [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    float3 ok = pixel_to_oklab(src[gid]);
    uint base = gid * 3u;
    lab[base]     = ok.x;
    lab[base + 1] = ok.y;
    lab[base + 2] = ok.z;
}


// ──────────────────────────────────────────────────────────────
// MARK: - Band assignment (threshold on Oklab L)
// ──────────────────────────────────────────────────────────────

struct BandAssignParams {
    uint pixelCount;
    uint thresholdCount;
    uint totalBands;
};

struct ColorLabelParams {
    uint pixelCount;
    uint familyCount;
    uint thresholdCount;
    uint valuesPerFamily;
};

struct ColorHistogramParams {
    uint pixelCount;
    uint lBins;
    uint aBins;
    uint bBins;
    float aMin;
    float aMax;
    float bMin;
    float bMax;
};

/// Assign each pixel to a luminance band based on its Oklab L value.
kernel void band_assign(
    device const float*         lab        [[buffer(0)]],  // interleaved L,a,b
    device int*                 bandMap    [[buffer(1)]],   // output: band per pixel
    constant BandAssignParams&  p          [[buffer(2)]],
    constant float*             thresholds [[buffer(3)]],   // sorted ascending
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    float L = lab[gid * 3u];
    int bnd = 0;
    for (uint t = 0u; t < p.thresholdCount; t++) {
        if (L >= thresholds[t]) bnd++;
    }
    bandMap[gid] = min(bnd, int(p.totalBands) - 1);
}

/// Combine per-pixel family assignment with Oklab-L value buckets into a global label.
kernel void color_build_labels(
    device const float*         lab               [[buffer(0)]],
    device const uint*          familyAssignments [[buffer(1)]],
    device int*                 labelMap          [[buffer(2)]],
    constant ColorLabelParams&  p                 [[buffer(3)]],
    constant float*             thresholds        [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    uint family = familyAssignments[gid];
    if (family >= p.familyCount) {
        family = (p.familyCount == 0u) ? 0u : (p.familyCount - 1u);
    }

    float L = lab[gid * 3u];
    uint value = 0u;
    for (uint t = 0u; t < p.thresholdCount; t++) {
        if (L >= thresholds[t]) value++;
    }
    if (value >= p.valuesPerFamily) {
        value = (p.valuesPerFamily == 0u) ? 0u : (p.valuesPerFamily - 1u);
    }

    labelMap[gid] = int(family * p.valuesPerFamily + value);
}

/// Accumulate a coarse Oklab histogram using integer atomics.
kernel void color_histogram(
    device const float*              lab     [[buffer(0)]],
    device atomic_uint*              counts  [[buffer(1)]],
    device atomic_uint*              sumL    [[buffer(2)]],
    device atomic_uint*              sumA    [[buffer(3)]],
    device atomic_uint*              sumB    [[buffer(4)]],
    constant ColorHistogramParams&   p       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    uint base = gid * 3u;
    float L = clamp(lab[base], 0.0f, 1.0f);
    float A = clamp(lab[base + 1u], p.aMin, p.aMax);
    float B = clamp(lab[base + 2u], p.bMin, p.bMax);

    uint lIndex = min(uint(L * float(p.lBins)), p.lBins - 1u);
    float aNorm = (A - p.aMin) / max(p.aMax - p.aMin, 1e-6f);
    float bNorm = (B - p.bMin) / max(p.bMax - p.bMin, 1e-6f);
    uint aIndex = min(uint(aNorm * float(p.aBins)), p.aBins - 1u);
    uint bIndex = min(uint(bNorm * float(p.bBins)), p.bBins - 1u);
    uint histogramIndex = (lIndex * p.aBins + aIndex) * p.bBins + bIndex;

    atomic_fetch_add_explicit(&counts[histogramIndex], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&sumL[histogramIndex], uint(round(L * 255.0f)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumA[histogramIndex], uint(round(aNorm * 255.0f)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumB[histogramIndex], uint(round(bNorm * 255.0f)), memory_order_relaxed);
}


// ──────────────────────────────────────────────────────────────
// MARK: - K-Means assignment step (nearest centroid per pixel)
// ──────────────────────────────────────────────────────────────

struct KMeansAssignParams {
    uint numPixels;
    uint k;
    float lWeight;
};

/// For each pixel, find the nearest centroid (in Oklab, with L de-weighted).
kernel void kmeans_assign(
    device const float*         pixels      [[buffer(0)]],  // interleaved L,a,b
    device const float*         centroids   [[buffer(1)]],  // k × 3 floats
    device uint*                assignments [[buffer(2)]],
    constant KMeansAssignParams& p          [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.numPixels) return;

    uint base = gid * 3u;
    float pL = pixels[base];
    float pA = pixels[base + 1u];
    float pB = pixels[base + 2u];

    float bestDist = 1e20f;
    uint bestC = 0u;
    for (uint ci = 0u; ci < p.k; ci++) {
        uint cBase = ci * 3u;
        float dL = pL - centroids[cBase];
        float dA = pA - centroids[cBase + 1u];
        float dB = pB - centroids[cBase + 2u];
        float dist = p.lWeight * dL * dL + dA * dA + dB * dB;
        if (dist < bestDist) {
            bestDist = dist;
            bestC = ci;
        }
    }

    assignments[gid] = bestC;
}


// ──────────────────────────────────────────────────────────────
// MARK: - Quantize grayscale to value-study levels
// ──────────────────────────────────────────────────────────────

struct QuantizeParams {
    uint pixelCount;
    uint thresholdCount;
    uint totalLevels;
};

/// Quantize: decode pixel to gray, compare against thresholds, output banded gray.
kernel void quantize(
    device const uint*        src        [[buffer(0)]],
    device uint*              dst        [[buffer(1)]],
    constant QuantizeParams&  p          [[buffer(2)]],
    constant float*           thresholds [[buffer(3)]],  // in 0-1, sorted ascending
    device int*               labelMap   [[buffer(4)]],  // output level index per pixel
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    float4 rgba = unpack_rgba(src[gid]);
    float3 srgb = rgba.xyz / 255.0f;
    float3 lin  = float3(linearize_srgb(srgb.x),
                         linearize_srgb(srgb.y),
                         linearize_srgb(srgb.z));
    float lum   = 0.2126f * lin.x + 0.7152f * lin.y + 0.0722f * lin.z;
    float enc   = delinearize_srgb(lum);

    // Match the CPU logic: count how many thresholdBytes the gray exceeds
    uint gray = uint(clamp(round(enc * 255.0f), 0.0f, 255.0f));
    int level = 0;
    for (uint t = 0u; t < p.thresholdCount; t++) {
        uint tb = uint(clamp(round(thresholds[t] * 255.0f), 0.0f, 255.0f));
        if (gray >= tb) level++;
    }
    level = min(level, int(p.totalLevels) - 1);
    labelMap[gid] = level;

    // Map level to evenly-spaced gray output
    uint outGray = 128u;
    if (p.totalLevels > 1u) {
        outGray = uint(clamp(round(float(level) / float(p.totalLevels - 1u) * 255.0f), 0.0f, 255.0f));
    }
    uint alpha = uint(rgba.w);
    dst[gid] = outGray | (outGray << 8u) | (outGray << 16u) | (alpha << 24u);
}


// ──────────────────────────────────────────────────────────────
// MARK: - Remap pixels by label → centroid color
// ──────────────────────────────────────────────────────────────

struct RemapParams {
    uint pixelCount;
    uint centroidCount;
};

/// Replace each pixel with the sRGB color of its assigned centroid (Oklab).
kernel void remap_by_label(
    device const uint*      src        [[buffer(0)]],  // original RGBA (for alpha)
    device const int*       labels     [[buffer(1)]],  // per-pixel label index
    device const float*     centroids  [[buffer(2)]],  // centroidCount × 3 floats (Oklab)
    device uint*            dst        [[buffer(3)]],
    constant RemapParams&   p          [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    int lbl = labels[gid];
    if (lbl < 0 || uint(lbl) >= p.centroidCount) lbl = 0;

    uint cBase = uint(lbl) * 3u;
    float3 lab = float3(centroids[cBase], centroids[cBase + 1u], centroids[cBase + 2u]);
    uint alpha = (src[gid] >> 24u) & 0xFFu;
    dst[gid] = oklab_to_pixel(lab, alpha);
}


// ──────────────────────────────────────────────────────────────
// MARK: - Remap value-study labels to evenly-spaced grays
// ──────────────────────────────────────────────────────────────

struct ValueRemapParams {
    uint pixelCount;
    uint totalLevels;
};

/// After region cleanup, re-render the label map to gray output pixels.
kernel void value_remap(
    device const uint*          src      [[buffer(0)]],
    device const int*           labels   [[buffer(1)]],
    device uint*                dst      [[buffer(2)]],
    constant ValueRemapParams&  p        [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= p.pixelCount) return;

    int level = labels[gid];
    if (level < 0) level = 0;
    if (uint(level) >= p.totalLevels) level = int(p.totalLevels) - 1;

    uint outGray = 128u;
    if (p.totalLevels > 1u) {
        outGray = uint(clamp(round(float(level) / float(p.totalLevels - 1u) * 255.0f), 0.0f, 255.0f));
    }
    uint alpha = (src[gid] >> 24u) & 0xFFu;
    dst[gid] = outGray | (outGray << 8u) | (outGray << 16u) | (alpha << 24u);
}


// ──────────────────────────────────────────────────────────────
// MARK: - Anisotropic Kuwahara: structure tensor pass
// ──────────────────────────────────────────────────────────────
//
// Pass 1: For each pixel, compute the smoothed structure tensor from a
// small Sobel gradient neighbourhood (3×3 Sobel + 5×5 Gaussian smooth).
// Output is a float4 texture storing (Jxx, Jxy, Jyy, 0).
//
// The structure tensor J encodes local orientation:
//   Jxx = E[Gx²]   Jxy = E[Gx·Gy]   Jyy = E[Gy²]
// where E[] denotes Gaussian-weighted expectation over a small window.

struct KuwaharaParams {
    uint width;
    uint height;
    int  radius;
};

kernel void kuwahara_structure_tensor(
    texture2d<float, access::sample>  src    [[texture(0)]],
    texture2d<float, access::write>   dst    [[texture(1)]],
    constant KuwaharaParams&          p      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);

    // Gaussian weights for a 5×5 window centred at (0,0)
    // σ = 1 approximation: kernel = [1,4,6,4,1]/16 separable
    const float gk[5] = { 1.0f/16.0f, 4.0f/16.0f, 6.0f/16.0f, 4.0f/16.0f, 1.0f/16.0f };

    float Jxx = 0.0f, Jxy = 0.0f, Jyy = 0.0f;

    for (int wy = -2; wy <= 2; wy++) {
        for (int wx = -2; wx <= 2; wx++) {
            float2 coord = float2(gid) + float2(wx, wy);

            // Sobel 3×3 gradient at this neighbour
            float gx = 0.0f, gy = 0.0f;
            for (int ky = -1; ky <= 1; ky++) {
                for (int kx = -1; kx <= 1; kx++) {
                    float3 col = src.sample(s, coord + float2(kx, ky)).rgb;
                    float lum  = dot(col, float3(0.2126f, 0.7152f, 0.0722f));

                    // Sobel x kernel:  -1 0 1 / -2 0 2 / -1 0 1  (column factor)
                    float sx = (kx == -1) ? -1.0f : (kx == 1 ? 1.0f : 0.0f);
                    sx *= (ky == 0) ? 2.0f : 1.0f;
                    // Sobel y kernel:  -1 -2 -1 / 0 0 0 / 1 2 1  (row factor)
                    float sy = (ky == -1) ? -1.0f : (ky == 1 ? 1.0f : 0.0f);
                    sy *= (kx == 0) ? 2.0f : 1.0f;

                    gx += sx * lum;
                    gy += sy * lum;
                }
            }

            float w = gk[wy + 2] * gk[wx + 2];
            Jxx += w * gx * gx;
            Jxy += w * gx * gy;
            Jyy += w * gy * gy;
        }
    }

    dst.write(float4(Jxx, Jxy, Jyy, 0.0f), gid);
}


// ──────────────────────────────────────────────────────────────
// MARK: - Anisotropic Kuwahara: filter pass
// ──────────────────────────────────────────────────────────────
//
// Pass 2: For each pixel, read the structure tensor, compute local
// orientation (θ) and anisotropy (A), then sweep 8 equally-spaced sectors
// in an anisotropy-scaled elliptical neighbourhood.  Output the weighted
// mean colour of the sector with the lowest weighted variance.
//
// Based on the formulation from Kyprianidis et al. (2009).

kernel void kuwahara_filter(
    texture2d<float, access::sample>  src    [[texture(0)]],
    texture2d<float, access::sample>  tensor [[texture(1)]],
    texture2d<float, access::write>   dst    [[texture(2)]],
    constant KuwaharaParams&          p      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);
    constexpr sampler ts(coord::pixel, filter::nearest, address::clamp_to_edge);

    // Read structure tensor at this pixel
    float4 J = tensor.sample(ts, float2(gid));
    float Jxx = J.x, Jxy = J.y, Jyy = J.z;

    // Eigenvalues of the 2×2 symmetric tensor
    float trace   = Jxx + Jyy;
    float det     = Jxx * Jyy - Jxy * Jxy;
    float disc    = sqrt(max(0.0f, trace * trace * 0.25f - det));
    float lambda1 = trace * 0.5f + disc;  // largest eigenvalue
    float lambda2 = trace * 0.5f - disc;  // smallest eigenvalue

    // Orientation: angle of the dominant eigenvector
    float theta = 0.5f * atan2(2.0f * Jxy, Jxx - Jyy);

    // Anisotropy ∈ [0, 1]: 0 = isotropic, 1 = fully anisotropic
    float denom   = lambda1 + lambda2 + 1e-6f;
    float A       = (lambda1 - lambda2) / denom;

    // Ellipse axes scaled by anisotropy
    float R       = float(p.radius);
    float rx      = R * (1.0f + A);      // semi-axis along dominant direction
    float ry      = R * (1.0f - A + 0.1f); // semi-axis perpendicular, keep >0

    float cosT = cos(theta);
    float sinT = sin(theta);

    const int N = 8;   // number of sectors
    const float sectorAngle = 2.0f * M_PI_F / float(N);

    float3 bestMean  = float3(0.0f);
    float  bestVar   = 1e20f;

    for (int sec = 0; sec < N; sec++) {
        // Mid-angle of this sector
        float sAngle = float(sec) * sectorAngle;

        float3 sumCol  = float3(0.0f);
        float3 sumCol2 = float3(0.0f);
        float  weight  = 0.0f;

        // Sample pixels within the sector's elliptical patch
        int iR = int(ceil(max(rx, ry)));
        for (int dy = -iR; dy <= iR; dy++) {
            for (int dx = -iR; dx <= iR; dx++) {
                if (dx == 0 && dy == 0) {
                    // Always include centre pixel in every sector
                    float3 centreCol = src.sample(s, float2(gid)).rgb;
                    sumCol  += centreCol;
                    sumCol2 += centreCol * centreCol;
                    weight  += 1.0f;
                    continue;
                }

                // Rotate offset to tensor eigenvector frame
                float u =  cosT * float(dx) + sinT * float(dy);
                float v = -sinT * float(dx) + cosT * float(dy);

                // Ellipse test
                if ((u * u) / (rx * rx) + (v * v) / (ry * ry) > 1.0f) continue;

                // Check this sample falls within the current sector
                float pixAngle = atan2(v, u);
                // Wrap difference into [-π, π]
                float diff = pixAngle - sAngle;
                diff = diff - 2.0f * M_PI_F * round(diff / (2.0f * M_PI_F));
                if (abs(diff) > sectorAngle * 0.5f) continue;

                // Gaussian weight based on distance
                float dist2 = float(dx * dx + dy * dy);
                float w     = exp(-dist2 / (2.0f * R * R));

                float3 col = src.sample(s, float2(gid) + float2(dx, dy)).rgb;
                sumCol  += w * col;
                sumCol2 += w * col * col;
                weight  += w;
            }
        }

        if (weight < 1e-6f) continue;

        float3 mean     = sumCol  / weight;
        float3 variance = sumCol2 / weight - mean * mean;
        float  totalVar = variance.x + variance.y + variance.z;

        if (totalVar < bestVar) {
            bestVar  = totalVar;
            bestMean = mean;
        }
    }

    dst.write(float4(bestMean, 1.0f), gid);
}


// ──────────────────────────────────────────────────────────────
// MARK: - Depth-based painterly effects
// ──────────────────────────────────────────────────────────────

struct DepthEffectParams {
    uint width;
    uint height;
    float foregroundCutoff;
    float backgroundCutoff;
    float intensity;
    uint backgroundMode; // 0=effects, 1=blur, 2=remove
};

struct DepthThresholdPreviewParams {
    uint width;
    uint height;
    float backgroundCutoff;
};

/// Main depth painterly effects kernel.
/// Applies atmospheric perspective: foreground gets boosted contrast/saturation/warmth,
/// background gets reduced contrast/saturation with cool shift.
/// Operates in Oklab perceptual space for natural-looking results.
kernel void depth_painterly_effects(
    texture2d<float, access::sample>  src       [[texture(0)]],
    texture2d<float, access::sample>  depthTex  [[texture(1)]],
    texture2d<float, access::write>   dst       [[texture(2)]],
    constant DepthEffectParams&       p         [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);

    float4 srcColor = src.sample(s, float2(gid));
    float depth = depthTex.sample(s, float2(gid)).r;  // 0=near, 1=far

    float fg = p.foregroundCutoff;
    float bg = p.backgroundCutoff;
    float intensity = p.intensity;

    // Convert to linear RGB then Oklab
    float3 srgb = srcColor.rgb;
    float3 lin = float3(linearize_srgb(srgb.x),
                        linearize_srgb(srgb.y),
                        linearize_srgb(srgb.z));
    float3 lab = linear_rgb_to_oklab(lin);

    float L = lab.x;  // luminance 0-1
    float a = lab.y;  // green-red
    float b = lab.z;  // blue-yellow

    // Zone classification with smooth transitions
    // fgBlend: 1 at depth=0, 0 at depth=fg
    float fgBlend = 1.0f - smoothstep(0.0f, fg, depth);
    // bgBlend: 0 at depth=bg, 1 at depth=1
    float bgBlend = smoothstep(bg, 1.0f, depth);

    // Foreground effects: boost contrast, increase chroma, warm shift
    if (fgBlend > 0.0f) {
        float strength = fgBlend * intensity;

        // Boost contrast: expand L around 0.5
        float contrastL = 0.5f + (L - 0.5f) * (1.0f + 0.4f * strength);
        L = mix(L, contrastL, fgBlend);

        // Increase chroma (scale a, b away from 0)
        float chromaScale = 1.0f + 0.3f * strength;
        a *= mix(1.0f, chromaScale, fgBlend);
        b *= mix(1.0f, chromaScale, fgBlend);

        // Warm shift: push b positive (yellow), slight a positive (red)
        b += 0.015f * strength;
        a += 0.005f * strength;
    }

    // Background effects: reduce contrast, decrease chroma, cool shift
    if (p.backgroundMode != 2 && bgBlend > 0.0f) {
        float strength = bgBlend * intensity;

        // Reduce contrast: compress L toward 0.5
        float compressL = 0.5f + (L - 0.5f) * (1.0f - 0.5f * strength);
        L = mix(L, compressL, bgBlend);

        // Decrease chroma
        float chromaScale = 1.0f - 0.5f * strength;
        a *= mix(1.0f, chromaScale, bgBlend);
        b *= mix(1.0f, chromaScale, bgBlend);

        // Cool shift: push b negative (blue), slight a positive (violet/atmospheric)
        b -= 0.02f * strength;
        a += 0.003f * strength;

        // Desaturate further into background
        float desat = 0.3f * strength;
        a *= (1.0f - desat);
        b *= (1.0f - desat);
    }

    // Clamp L
    L = clamp(L, 0.0f, 1.0f);

    float3 resultLab = float3(L, a, b);
    float3 resultLin = oklab_to_linear_rgb(resultLab);
    float3 resultSRGB = float3(delinearize_srgb(clamp(resultLin.x, 0.0f, 1.0f)),
                               delinearize_srgb(clamp(resultLin.y, 0.0f, 1.0f)),
                               delinearize_srgb(clamp(resultLin.z, 0.0f, 1.0f)));

    dst.write(float4(resultSRGB, srcColor.a), gid);
}

/// Depth-weighted Gaussian blur (horizontal pass).
/// Blur radius scales with normalized depth beyond backgroundCutoff.
/// Only affects pixels in the background zone.
kernel void depth_gaussian_blur_h(
    texture2d<float, access::sample>  src       [[texture(0)]],
    texture2d<float, access::sample>  depthTex  [[texture(1)]],
    texture2d<float, access::write>   dst       [[texture(2)]],
    constant DepthEffectParams&       p         [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);

    float depth = depthTex.sample(s, float2(gid)).r;
    float bg = p.backgroundCutoff;

    if (depth <= bg) {
        dst.write(src.sample(s, float2(gid)), gid);
        return;
    }

    // Scale blur radius based on how far into background
    float t = clamp((depth - bg) / (1.0f - bg + 1e-6f), 0.0f, 1.0f);
    float maxRadius = 12.0f * p.intensity;
    int radius = int(t * maxRadius);
    if (radius < 1) {
        dst.write(src.sample(s, float2(gid)), gid);
        return;
    }

    float sigma = float(radius) * 0.5f;
    float invSigma2 = 1.0f / (2.0f * sigma * sigma);

    float4 sum = float4(0.0f);
    float weightSum = 0.0f;

    for (int dx = -radius; dx <= radius; dx++) {
        float w = exp(-float(dx * dx) * invSigma2);
        sum += w * src.sample(s, float2(int2(gid) + int2(dx, 0)));
        weightSum += w;
    }

    dst.write(sum / weightSum, gid);
}

/// Depth-weighted Gaussian blur (vertical pass).
kernel void depth_gaussian_blur_v(
    texture2d<float, access::sample>  src       [[texture(0)]],
    texture2d<float, access::sample>  depthTex  [[texture(1)]],
    texture2d<float, access::write>   dst       [[texture(2)]],
    constant DepthEffectParams&       p         [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);

    float depth = depthTex.sample(s, float2(gid)).r;
    float bg = p.backgroundCutoff;

    if (depth <= bg) {
        dst.write(src.sample(s, float2(gid)), gid);
        return;
    }

    float t = clamp((depth - bg) / (1.0f - bg + 1e-6f), 0.0f, 1.0f);
    float maxRadius = 12.0f * p.intensity;
    int radius = int(t * maxRadius);
    if (radius < 1) {
        dst.write(src.sample(s, float2(gid)), gid);
        return;
    }

    float sigma = float(radius) * 0.5f;
    float invSigma2 = 1.0f / (2.0f * sigma * sigma);

    float4 sum = float4(0.0f);
    float weightSum = 0.0f;

    for (int dy = -radius; dy <= radius; dy++) {
        float w = exp(-float(dy * dy) * invSigma2);
        sum += w * src.sample(s, float2(int2(gid) + int2(0, dy)));
        weightSum += w;
    }

    dst.write(sum / weightSum, gid);
}

/// Remove background pixels (replace with white) based on depth.
/// Uses smoothstep at the boundary for soft edges.
kernel void depth_remove_background(
    texture2d<float, access::sample>  src       [[texture(0)]],
    texture2d<float, access::sample>  depthTex  [[texture(1)]],
    texture2d<float, access::write>   dst       [[texture(2)]],
    constant DepthEffectParams&       p         [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);

    float4 color = src.sample(s, float2(gid));
    float depth = depthTex.sample(s, float2(gid)).r;

    // Smooth transition zone around backgroundCutoff
    float edgeWidth = 0.03f;
    float bg = p.backgroundCutoff;
    float blend = smoothstep(bg - edgeWidth, bg + edgeWidth, depth) * p.intensity;

    float4 white = float4(1.0f, 1.0f, 1.0f, 1.0f);
    dst.write(mix(color, white, blend), gid);
}

kernel void depth_threshold_preview(
    texture2d<float, access::sample>  src       [[texture(0)]],
    texture2d<float, access::sample>  depthTex  [[texture(1)]],
    texture2d<float, access::write>   dst       [[texture(2)]],
    constant DepthThresholdPreviewParams& p      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;

    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);

    float2 uv = (float2(gid) + 0.5f) / float2(p.width, p.height);
    float3 sourceColor = src.sample(s, uv).rgb;
    float depth = depthTex.sample(s, uv).r;

    float edgeWidth = 0.01f;
    float backgroundBlend = smoothstep(
        p.backgroundCutoff - edgeWidth,
        p.backgroundCutoff + edgeWidth,
        depth
    );

    float3 grayscale = float3(depth);
    float3 color = mix(sourceColor, grayscale, backgroundBlend);

    dst.write(float4(color, 1.0f), gid);
}
