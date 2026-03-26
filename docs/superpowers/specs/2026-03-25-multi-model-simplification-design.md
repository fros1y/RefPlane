# Multi-Model Image Simplification

## Problem

The current iOS simplification pipeline uses a single RealESRGAN_x4 model in a downsample-then-upscale cycle. The previous TypeScript version used APISR GRL_GAN and produced better results — preserving edges and large structural forms while smoothing away fine texture. RealESRGAN is trained to hallucinate realistic texture detail, which is nearly the opposite of what simplification needs.

We want to explore multiple models and approaches to find the best simplification method, with a simple UI picker to switch between them at runtime.

## Candidate Models

Six approaches, spanning three paradigms:

### Super-Resolution Upscalers (downsample → tile → 4x model → stitch → upscale)

| Model | Source | Size | Conversion Path |
|-------|--------|------|-----------------|
| RealESRGAN_x4 | Already bundled | ~17 MB | None needed |
| APISR GRL_GAN 4x | [Kiteretsu77/APISR](https://github.com/Kiteretsu77/APISR) | ~40 MB | spandrel → trace@256×256 → coremltools |
| SwinIR-S Lightweight 4x | [JingyunLiang/SwinIR](https://github.com/JingyunLiang/SwinIR) | ~17 MB | spandrel → trace@256×256 → coremltools |

### Style Transfer (downsample → full-image model → upscale)

| Model | Source | Size | Conversion Path |
|-------|--------|------|-----------------|
| White-box Cartoonization | [PINTO_model_zoo/019](https://github.com/PINTO0309/PINTO_model_zoo/tree/main/019_White-box-Cartoonization) | ~5 MB | ONNX → coremltools |
| AnimeGANv3 | [TachibanaYoshino/AnimeGANv3](https://github.com/TachibanaYoshino/AnimeGANv3) | ~2.4 MB | ONNX → coremltools |

### GPU Shader (downsample → Metal compute → upscale)

| Model | Source | Size | Conversion Path |
|-------|--------|------|-----------------|
| Anisotropic Kuwahara | Kyprianidis & Semmo 2010 | 0 MB | 2-pass Metal compute shader |

## Architecture

### Unified Pipeline

All six methods share the same outer pipeline shape:

```
source image (max 1600px)
    → downsample by strength factor (2–12x)
    → process (method-specific)
    → bilinear upscale to original dimensions
```

The strength slider always controls the downsample factor. More downsampling = more simplification regardless of method.

### Method-Specific Processing

After downsampling, the pipeline branches based on method type:

**SR models (RealESRGAN, APISR, SwinIR):**
Tile the downsampled image into 256×256 patches with overlap → run each tile through the 4x CoreML model → stitch tiles → result is 4x the downsampled size. This reuses the existing `processInTiles` infrastructure unchanged.

**Style transfer models (White-box Cartoonization, AnimeGANv3):**
Run the CoreML model on the full downsampled image without tiling. These are fully convolutional generators that accept arbitrary input sizes. Tiling would create visible style-seam artifacts at tile boundaries.

**Kuwahara shader:**
Run the 2-pass anisotropic Kuwahara Metal compute shader directly on the downsampled image. No CoreML model involved.

## Data Model

### SimplificationMethod Enum (AppModels.swift)

```swift
enum SimplificationMethod: String, CaseIterable, Identifiable {
    case realESRGAN   = "RealESRGAN"
    case apisr        = "APISR"
    case swinIR       = "SwinIR"
    case kuwahara     = "Kuwahara"
    case whitebox     = "Cartoonize"
    case animeGAN     = "AnimeGAN"

    var id: String { rawValue }
    var label: String { rawValue }

    var isMLModel: Bool {
        switch self {
        case .kuwahara: return false
        default: return true
        }
    }

    /// CoreML model bundle name (nil for shader-only methods)
    var modelBundleName: String? {
        switch self {
        case .realESRGAN: return "RealESRGAN_x4"
        case .apisr:      return "APISR_GRL_x4"
        case .swinIR:     return "SwinIR_Lightweight_x4"
        case .whitebox:   return "WhiteBoxCartoonization"
        case .animeGAN:   return "AnimeGANv3"
        case .kuwahara:   return nil
        }
    }

    /// Whether this method uses the tile-based 4x upscale pipeline
    var isSuperResolution: Bool {
        switch self {
        case .realESRGAN, .apisr, .swinIR: return true
        default: return false
        }
    }
}
```

### AppState Changes

One new published property:

```swift
@Published var simplificationMethod: SimplificationMethod = .realESRGAN
```

`applySimplify()` passes the method through:

```swift
func applySimplify() {
    guard let source = sourceImage else { return }
    let downscale = CGFloat(2.0 + simplifyStrength * 10.0)
    let method = simplificationMethod
    Task {
        await MainActor.run { self.isProcessing = true }
        let simplified = await ImageSimplifier.simplify(
            image: source, downscale: downscale, method: method
        )
        await MainActor.run {
            self.simplifiedImage = simplified
            self.isProcessing = false
            self.triggerProcessing()
        }
    }
}
```

## ImageSimplifier Refactor

### Model Cache

Replace the single cached model with a dictionary:

```swift
private static var cachedModels: [SimplificationMethod: MLModel] = [:]
```

### Model Loading

Generalize `loadModel()` to take a method, look up its `modelBundleName`, and try the same 3-format cascade (`.mlmodelc`, `.mlpackage`, `.mlmodel`):

```swift
private static func loadModel(for method: SimplificationMethod) -> MLModel?
```

### Public API

```swift
static func simplify(
    image: UIImage,
    downscale: CGFloat = 4.0,
    method: SimplificationMethod = .realESRGAN
) async -> UIImage
```

### Pipeline Routing

After downsampling, the method determines the processing path:

```swift
// After downsampling to `small`:
switch method {
case .realESRGAN, .apisr, .swinIR:
    // Tile-based 4x SR — existing processInTiles logic
    guard let model = loadModel(for: method),
          let smallCG = small.cgImage,
          let upscaled = processInTiles(smallCG, model: model) else { return image }
    return resizeToPixels(upscaled, width: origW, height: origH)

case .whitebox, .animeGAN:
    // Full-image style transfer — no tiling
    guard let model = loadModel(for: method),
          let smallCG = small.cgImage,
          let result = runModel(model, input: smallCG) else { return image }
    return resizeToPixels(result, width: origW, height: origH)

case .kuwahara:
    // Metal shader — no CoreML model
    guard let smallCG = small.cgImage,
          let ctx = MetalContext.shared,
          let result = ctx.anisotropicKuwahara(smallCG) else { return image }
    return resizeToPixels(result, width: origW, height: origH)
}
```

All existing helper methods (`reflectPad`, `runModel`, `resizeToPixels`, format converters) remain unchanged.

## Anisotropic Kuwahara Metal Shader

Two new compute kernels in `Shaders.metal`.

### Pass 1: Structure Tensor (`kuwahara_structure_tensor`)

- Input: source RGBA texture
- Computes Sobel gradients (dx, dy) at each pixel
- Builds structure tensor components: `(dx*dx, dx*dy, dy*dy)`
- Applies small Gaussian blur (radius ~2) to smooth the tensor
- Output: `float4` texture containing `(E, F, G, anisotropy)` — E=dx², F=dxdy, G=dy²

### Pass 2: Anisotropic Kuwahara Filter (`kuwahara_filter`)

- Inputs: source RGBA texture + structure tensor texture from Pass 1
- For each pixel:
  1. Read structure tensor → compute eigenvalues and dominant eigenvector (orientation angle)
  2. Compute anisotropy `A = (λ₁ - λ₂) / (λ₁ + λ₂)` → controls ellipse eccentricity
  3. Construct rotated elliptical coordinate transform
  4. Evaluate 8 overlapping sectors with polynomial weights: `w(x,y) = [(x + ζ) - η·y²]²`
  5. Per sector: accumulate weighted mean color and weighted variance
  6. Output: weighted blend of sector means, weighted by inverse variance
- Output: filtered RGBA texture

### MetalContext Additions

New method and two new pipeline states:

```swift
private let kuwaharaStructurePipeline: MTLComputePipelineState
private let kuwaharaFilterPipeline: MTLComputePipelineState

func anisotropicKuwahara(_ image: CGImage, radius: Int = 6) -> UIImage?
```

The method:
1. Creates input texture from CGImage
2. Allocates structure tensor intermediate texture (`.rgba32Float`)
3. Dispatches Pass 1
4. Allocates output texture
5. Dispatches Pass 2
6. Reads result back to UIImage

### Reference Implementations

- Kyprianidis GPU Pro chapter: polynomial weighting formulation
- Godot shader: [godotshaders.com/shader/anisotropic-kuwahara-filter/](https://godotshaders.com/shader/anisotropic-kuwahara-filter/)
- LYGIA shader library: [lygia.xyz/filter/kuwahara](https://lygia.xyz/filter/kuwahara)
- Nuke C++ implementation: [github.com/sharktacos/VFX-software-prefs](https://github.com/sharktacos/VFX-software-prefs/blob/main/Nuke/Kuwahara/df_kuwaharaAnisotropic.cpp)

## CoreML Model Conversion

A Python script `scripts/convert_models.py` handles conversion for all models.

### Per-Model Conversion

**APISR GRL_GAN 4x:**
- Load PyTorch weights via spandrel
- `torch.jit.trace` at fixed 256×256 input
- `coremltools.convert()` → `.mlpackage`
- Input: `[1, 3, 256, 256]` → Output: `[1, 3, 1024, 1024]`

**SwinIR-S Lightweight 4x:**
- Load via spandrel (handles architecture reconstruction automatically)
- `torch.jit.trace` at fixed 256×256 (critical — window attention uses `torch.roll` which breaks on dynamic shapes)
- `coremltools.convert()` → `.mlpackage`
- Input: `[1, 3, 256, 256]` → Output: `[1, 3, 1024, 1024]`
- Reference: [spandrel-to-CoreML guide](https://rockyshikoku.medium.com/converting-models-such-as-super-resolution-and-brightness-correction-from-spandrel-to-coreml-8bcfbb04a8fc)

**White-box Cartoonization:**
- Download ONNX from [PINTO_model_zoo/019](https://github.com/PINTO0309/PINTO_model_zoo/tree/main/019_White-box-Cartoonization) (pre-converted available)
- `coremltools.convert()` from ONNX → `.mlpackage`
- Input: `[1, 3, H, W]` (fully convolutional) → Output: same dimensions

**AnimeGANv3:**
- Download ONNX from repo (e.g., `AnimeGANv3_Hayao_36.onnx`)
- `coremltools.convert()` from ONNX → `.mlpackage`
- Start with a style that produces the flattest output (USA cartoon or Shinkai)
- Input: `[1, 3, H, W]` → Output: same dimensions

### Script Interface

```
python scripts/convert_models.py --model apisr
python scripts/convert_models.py --model swinir
python scripts/convert_models.py --model whitebox
python scripts/convert_models.py --model animegan
python scripts/convert_models.py --all
```

Each invocation downloads weights if not cached, converts, validates with a 256×256 test inference, and outputs `.mlpackage` to `ios/RefPlane/`.

All models use `compute_units=ALL` and float32 precision (no quantization during exploration).

## UI Changes

### ControlPanelView.swift

A `Picker` is added to the Simplify panel section, between the toggle and the strength slider:

```swift
PanelSection(title: "Simplify") {
    Toggle("Enabled", isOn: /* existing binding */)

    if state.simplifyEnabled {
        // Model picker
        VStack(alignment: .leading, spacing: 4) {
            Text("Method")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Picker("Method", selection: Binding(
                get: { state.simplificationMethod },
                set: { method in
                    state.simplificationMethod = method
                    state.applySimplify()
                }
            )) {
                ForEach(SimplificationMethod.allCases) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }

        // Existing strength slider (unchanged)
    }
}
```

The toggle label changes from "UltraSharp" to "Enabled" since the method name is now shown in the picker.

No other UI changes. Compare view, export, mode processing all work unchanged on top of whatever the selected method produces.

## File Changes Summary

| File | Change |
|------|--------|
| `AppModels.swift` | Add `SimplificationMethod` enum |
| `AppState.swift` | Add `simplificationMethod` property, update `applySimplify()` |
| `ImageSimplifier.swift` | Dictionary model cache, generic `loadModel(for:)`, pipeline routing by method type |
| `Shaders.metal` | Add `kuwahara_structure_tensor` and `kuwahara_filter` compute kernels |
| `MetalContext.swift` | Add `anisotropicKuwahara()` method, compile 2 new pipeline states |
| `ControlPanelView.swift` | Add method picker, rename toggle label |
| `scripts/convert_models.py` | New — model download and CoreML conversion script |
| Bundle | Add 4 new `.mlpackage` files (APISR, SwinIR, WhiteBox, AnimeGAN) |
