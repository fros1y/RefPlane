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

## Scope

**What IS being built:** A model-switching infrastructure for the simplification pipeline, 4 new CoreML models, 1 Metal shader, a conversion script, and a minimal picker UI. This is an exploration tool for comparing approaches.

**What is NOT being built:** Cross-model comparison UI, model download-on-demand, quantization, performance optimization, or any changes to the downstream mode processing (tonal/value/color).

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

The entire `simplify()` body remains wrapped in `Task.detached(priority: .userInitiated)` as it is today, keeping model loading and inference off the main actor.

### Model Cache and Memory

Models are loaded lazily — only when first selected by the user. The dictionary cache avoids reloading on repeated switches. Under memory pressure, the cache should be cleared in response to `UIApplication.didReceiveMemoryWarningNotification`:

```swift
private static func registerMemoryWarning() {
    NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil, queue: nil
    ) { _ in cachedModels.removeAll() }
}
```

With all 5 models loaded (~81 MB of weights), memory pressure is possible on older devices. Lazy loading means typical usage (trying 1-2 models) keeps only 1-2 models resident.

### Error Handling for Missing Models

If `loadModel(for:)` returns nil (model not bundled, corrupt, etc.), `simplify()` returns the original image unchanged. The UI does not disable picker options — all methods are always shown. A console log is printed identifying which model failed to load. This is sufficient for the exploration phase; a production version would surface errors to the user.

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
1. Creates input `MTLTexture` from CGImage pixels (`.rgba8Unorm`, `usage: [.shaderRead]`)
2. Allocates structure tensor intermediate texture (`.rgba32Float`, `usage: [.shaderRead, .shaderWrite]`)
3. Dispatches Pass 1 with 2D threadgroups: `MTLSize(width: ceil(w/16), height: ceil(h/16), depth: 1)`, threads per group `MTLSize(width: 16, height: 16, depth: 1)`
4. Allocates output texture (`.rgba8Unorm`, `usage: [.shaderRead, .shaderWrite]`)
5. Dispatches Pass 2 with same 2D threadgroup layout
6. Reads result back via `getBytes()` into pixel array, constructs UIImage via `UIImage.fromPixelData()`

This uses **texture-based dispatch** rather than the existing buffer-based 1D `dispatch()` helper. The `anisotropicKuwahara()` method manages its own command buffer and compute encoder directly, similar to how `CIContext` operates, rather than extending the existing `dispatch()` helper which is designed for flat buffer operations.

### Kuwahara Shader Parameters

The following parameters are **hardcoded as constants in the shader** for the exploration phase:
- Number of sectors: 8
- Polynomial weight constants: ζ = 1.0, η = 1.0 (Kyprianidis defaults)
- Structure tensor Gaussian blur radius: 2
- Filter kernel radius: passed as a buffer constant, defaults to 6

Only the kernel radius is exposed to Swift via the `radius` parameter. Other parameters can be promoted to buffer constants later if tuning is needed.

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
- Input shape must use `ct.RangeDim` for H and W to allow arbitrary sizes at runtime:
  ```python
  ct.convert(model, inputs=[ct.ImageType(shape=(1, 3, ct.RangeDim(64, 1024), ct.RangeDim(64, 1024)))])
  ```
- If flexible shapes cause conversion issues, fall back to a fixed size matching the downsampled image's typical dimensions (e.g., 256×256) and resize before/after inference
- Output type: image (RGB pixel buffer) — the existing `runModel()` handles this via its `.image` branch

**AnimeGANv3:**
- Download ONNX from repo (e.g., `AnimeGANv3_Hayao_36.onnx`)
- `coremltools.convert()` from ONNX → `.mlpackage`
- Same flexible shape approach as White-box Cartoonization above
- Start with a style that produces the flattest output (USA cartoon or Shinkai)
- Output type: image (RGB pixel buffer)

### Script Interface

```
python scripts/convert_models.py --model apisr
python scripts/convert_models.py --model swinir
python scripts/convert_models.py --model whitebox
python scripts/convert_models.py --model animegan
python scripts/convert_models.py --all
```

Each invocation downloads weights if not cached, converts, validates with a 256×256 test inference, and outputs `.mlpackage` to `ios/RefPlane/` (alongside the existing `RealESRGAN_x4.mlpackage`).

All models use `compute_units=ALL` and float32 precision (no quantization during exploration).

Adding the `.mlpackage` files to the Xcode project's bundle resources is a manual step after conversion — drag into Xcode and ensure "Copy items if needed" and target membership are set. The conversion script does not modify the `.xcodeproj`.

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

## Housekeeping

Fix the stale doc comment in `AppState.swift` line 29: change "downscale factor 2–8" to "downscale factor 2–12" to match the actual implementation (`2.0 + simplifyStrength * 10.0`).

Update the MetalContext pipeline count log message from "7 compute pipelines" to "9 compute pipelines" after adding the two Kuwahara kernels.

## Verification

This is an exploration project — success is subjective (visual quality of simplification). Verification:

1. **Smoke test each method:** Load a test image, select each method in the picker, confirm simplification runs without crash and produces a visibly different result.
2. **Visual comparison:** For each method at strength 50%, check that edges/large structures are preserved while fine texture is reduced compared to the original.
3. **Strength slider:** Confirm that increasing strength produces more aggressive simplification for all methods.
4. **Mode stacking:** Confirm that tonal/value/color modes work correctly on top of each simplification method's output.
5. **Memory:** Switch between all 6 methods repeatedly, confirm no crash from memory pressure on a physical device.
