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
