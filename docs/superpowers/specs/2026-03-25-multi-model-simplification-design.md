# Multi-Model Image Simplification

## Problem

The current iOS simplification pipeline uses a single `RealESRGAN_x4` model in a downsample-then-upscale cycle. The previous TypeScript version used APISR `GRL_GAN` and produced better simplification for this product goal: preserve edges and large forms while removing fine texture.

`RealESRGAN_x4` is a good super-resolution model, but it is biased toward restoring realistic detail. That is almost the opposite of the simplification aesthetic we want.

We want a small exploration framework inside the iOS app so we can compare multiple simplification methods on real images without rebuilding the whole pipeline for each experiment.

## Goals

- Support multiple simplification methods behind one app-facing API.
- Keep the existing user workflow intact: source image -> optional simplify -> tonal/value/color modes.
- Make method switching cheap in the UI so visual comparison is fast.
- Reuse the current tiling and resize infrastructure where that is actually valid.
- Avoid baking model-specific preprocessing assumptions into random parts of the app.

## Non-Goals

- No side-by-side comparison UI in this phase.
- No model download-on-demand.
- No quantization or aggressive performance tuning.
- No downstream processing changes in tonal/value/color modes.
- No promise that every candidate method ships in the first implementation pass.

## Delivery Strategy

The original draft treated all six methods as one implementation unit. That is too much risk at once because the CoreML conversion, runtime contract, and visual quality risk are not evenly distributed.

Implementation should be phased:

1. Phase 1: ship the method-switching infrastructure with the three 4x SR methods:
   `RealESRGAN`, `APISR`, `SwinIR`
2. Phase 2: add style-transfer methods only if conversion produces a stable image-to-image CoreML contract:
   `White-box Cartoonization`, `AnimeGANv3`
3. Phase 3: add the anisotropic Kuwahara shader after Phase 1 visual evaluation confirms we still want a non-ML baseline

The architecture should support all six methods from day one, but the app should only expose methods that are actually bundled and validated in the current build.

## Candidate Methods

| Method | Paradigm | Runtime Shape | Conversion Risk | Visual Risk | Phase |
|---|---|---|---|---|---|
| RealESRGAN_x4 | Super-resolution | tiled 256 -> 1024 | low | medium | 1 |
| APISR GRL_GAN 4x | Super-resolution | tiled 256 -> 1024 | medium | low | 1 |
| SwinIR-S Lightweight 4x | Super-resolution | tiled 256 -> 1024 | medium | medium | 1 |
| White-box Cartoonization | Style transfer | full image -> full image | high | medium | 2 |
| AnimeGANv3 | Style transfer | full image -> full image | high | high | 2 |
| Anisotropic Kuwahara | Metal shader | full image -> full image | medium | medium | 3 |

## Unified Pipeline

All methods share the same outer pipeline:

```text
source image (already capped to max 1600px)
    -> downsample by strength factor (2x to 12x)
    -> method-specific processing
    -> resize back to original dimensions
```

The strength slider always maps to downsample factor. More downsampling means more simplification regardless of method.

Method-specific processing:

- Super-resolution methods:
  reuse tile-based 4x inference and stitch back together
- Style-transfer methods:
  run on the full downsampled image with no tiling
- Shader methods:
  run on the full downsampled image through Metal

## Critical Runtime Contract

This is the most important design correction in the review.

The iOS app should not depend on model-specific normalization details discovered late in conversion. Every bundled method must satisfy an explicit app-facing contract:

### Super-Resolution Contract

- Fixed input size: `256x256`
- Fixed output size: `1024x1024`
- RGB image-in / image-out preferred
- If the exported model uses `MLMultiArray`, it must still conform to the existing `[1, 3, H, W]` float32 convention expected by the app helpers

### Style-Transfer Contract

- Flexible input shape within the app's actual range
- Output spatial dimensions must match input spatial dimensions
- RGB image-in / image-out strongly preferred
- Any normalization such as `[0, 1] -> [-1, 1]` must be baked into the exported CoreML model or handled by an explicit per-method adapter, not assumed by the generic `runModel()` path

### Shader Contract

- Accept a downsampled `CGImage`
- Return a `UIImage` of the same pixel size

If a candidate model cannot be exported to one of these contracts cleanly, it should not be exposed in the picker yet.

## Data Model

### SimplificationMethod

`AppModels.swift` gets a new enum with method metadata:

```swift
enum SimplificationProcessingKind {
    case superResolution4x
    case fullImageModel
    case metalShader
}

enum SimplificationMethod: String, CaseIterable, Identifiable {
    case realESRGAN = "RealESRGAN"
    case apisr = "APISR"
    case swinIR = "SwinIR"
    case whitebox = "Cartoonize"
    case animeGAN = "AnimeGAN"
    case kuwahara = "Kuwahara"

    var id: String { rawValue }
    var label: String { rawValue }

    var processingKind: SimplificationProcessingKind {
        switch self {
        case .realESRGAN, .apisr, .swinIR:
            return .superResolution4x
        case .whitebox, .animeGAN:
            return .fullImageModel
        case .kuwahara:
            return .metalShader
        }
    }

    var modelBundleName: String? {
        switch self {
        case .realESRGAN: return "RealESRGAN_x4"
        case .apisr: return "APISR_GRL_x4"
        case .swinIR: return "SwinIR_Lightweight_x4"
        case .whitebox: return "WhiteBoxCartoonization"
        case .animeGAN: return "AnimeGANv3"
        case .kuwahara: return nil
        }
    }
}
```

### AppState

Add:

```swift
@Published var simplificationMethod: SimplificationMethod = .realESRGAN
private var simplifyTask: Task<Void, Never>? = nil
private var simplifyGeneration: Int = 0
```

The current `applySimplify()` launches work without cancellation or generation tracking. That is already racy today, and a runtime picker will make it much easier for stale work to overwrite newer user choices.

`applySimplify()` should cancel the previous simplification task and only apply the latest result:

```swift
func applySimplify() {
    guard let source = sourceImage else { return }

    simplifyTask?.cancel()
    simplifyGeneration += 1
    let generation = simplifyGeneration

    let downscale = CGFloat(2.0 + simplifyStrength * 10.0)
    let method = simplificationMethod

    isProcessing = true
    errorMessage = nil

    simplifyTask = Task {
        do {
            let simplified = try await ImageSimplifier.simplify(
                image: source,
                downscale: downscale,
                method: method
            )
            try Task.checkCancellation()

            await MainActor.run {
                guard self.simplifyGeneration == generation else { return }
                self.simplifiedImage = simplified
                self.isProcessing = false
                self.triggerProcessing()
            }
        } catch is CancellationError {
        } catch {
            await MainActor.run {
                guard self.simplifyGeneration == generation else { return }
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
```

This also means simplification failure does not silently replace the image with the unsimplified original.

## ImageSimplifier Refactor

### Public API

Change the API to throw:

```swift
static func simplify(
    image: UIImage,
    downscale: CGFloat = 4.0,
    method: SimplificationMethod = .realESRGAN
) async throws -> UIImage
```

Returning the original image on failure hides real errors and makes unsupported methods look like valid but weak simplifiers.

### Model Cache

Do not keep the cache as an unsynchronized static dictionary mutated from detached tasks. That will race as soon as the user changes methods quickly.

Use an actor-backed store:

```swift
private actor SimplificationModelStore {
    private var cachedModels: [SimplificationMethod: MLModel] = [:]
    func model(for method: SimplificationMethod) -> MLModel? { cachedModels[method] }
    func insert(_ model: MLModel, for method: SimplificationMethod) { cachedModels[method] = model }
    func clear() { cachedModels.removeAll() }
}
```

`ImageSimplifier` holds one static instance of that actor.

### Memory Policy

Lazy loading is still correct, but the original draft understated memory risk. Bundle size is not the same as runtime residency, and CoreML models can consume materially more memory once compiled and loaded.

For this exploration phase:

- keep lazy loading
- clear the cache on memory warning
- do not pre-load every model at launch
- treat "all methods loaded simultaneously" as a stress case, not normal behavior

### Model Loading

Generalize model loading by method:

```swift
private static func loadModel(for method: SimplificationMethod) async throws -> MLModel
```

Loading order remains:

1. bundled `.mlmodelc`
2. bundled `.mlpackage`
3. bundled `.mlmodel`

If loading fails, throw `SimplificationError.modelUnavailable(method)`.

### Pipeline Routing

After downsampling, route by `processingKind`:

```swift
switch method.processingKind {
case .superResolution4x:
    let model = try await loadModel(for: method)
    guard let smallCG = small.cgImage,
          let upscaled = processInTiles(smallCG, model: model) else {
        throw SimplificationError.inferenceFailed(method)
    }
    return resizeToPixels(upscaled, width: origW, height: origH)

case .fullImageModel:
    let model = try await loadModel(for: method)
    guard let smallCG = small.cgImage,
          let result = runModel(model, input: smallCG) else {
        throw SimplificationError.inferenceFailed(method)
    }
    return resizeToPixels(result, width: origW, height: origH)

case .metalShader:
    guard let smallCG = small.cgImage,
          let ctx = MetalContext.shared,
          let result = ctx.anisotropicKuwahara(smallCG) else {
        throw SimplificationError.inferenceFailed(method)
    }
    return resizeToPixels(result, width: origW, height: origH)
}
```

### Generic Helpers

The existing helpers can stay mostly intact:

- `processInTiles`
- `reflectPad`
- `resizeToPixels`
- format converters

But `runModel()` only remains generic if the exported models honor the runtime contract above. If a style-transfer export requires custom normalization or a different tensor layout, that logic belongs in a method-specific adapter layer, not in ad hoc call sites.

### Error Type

Add a small error enum:

```swift
enum SimplificationError: LocalizedError {
    case modelUnavailable(SimplificationMethod)
    case unsupportedModelContract(SimplificationMethod)
    case inferenceFailed(SimplificationMethod)
}
```

## Method Availability

The original draft showed every method in the picker even when the model might not exist in the bundle. That creates a bad exploration UX because "selecting a method" can silently do nothing useful.

The UI should expose only validated methods for the current build:

- always include shader-only methods that are compiled into the app
- include CoreML methods only when their bundle resource exists and they pass a lightweight manifest check

The simplest implementation is a computed list:

```swift
var availableSimplificationMethods: [SimplificationMethod]
```

This list can be built from bundle resource checks plus a small conversion manifest shipped with the models.

## CoreML Conversion

A Python script `scripts/convert_models.py` converts and validates candidate models, but its job is not just format conversion. It must enforce the app-facing contract.

### Required Script Outputs

For each converted model:

- `.mlpackage`
- a small JSON manifest with:
  - method id
  - expected processing kind
  - input type
  - output type
  - fixed or flexible shape metadata
  - test inference status

### Super-Resolution Validation

For `APISR` and `SwinIR`, validate:

- input shape is exactly `1x3x256x256` or `ImageType 256x256`
- output shape is exactly 4x larger in both axes
- a test inference succeeds on a synthetic `256x256` input

### Style-Transfer Validation

For `White-box Cartoonization` and `AnimeGANv3`, validate:

- full-image inference succeeds at `256x256`
- full-image inference also succeeds at one non-square size such as `320x192`
- output spatial dimensions equal input spatial dimensions
- input/output preprocessing is either embedded in the model or described in the manifest for an explicit adapter

If flexible-shape conversion is unstable, do not ship that method yet. Do not degrade the architecture by pretending a fixed-size export is equivalent to a true full-image model.

### Conversion Notes

- `APISR GRL_GAN 4x`:
  `spandrel -> trace at 256 -> coremltools`
- `SwinIR-S Lightweight 4x`:
  same path, fixed-size trace remains appropriate
- `White-box Cartoonization`:
  ONNX to CoreML only if the result preserves an image-to-image contract cleanly
- `AnimeGANv3`:
  same requirement as White-box; this model is exploratory and lower confidence

The conversion script does not modify the Xcode project. Adding new bundled models still requires project file changes.

## Anisotropic Kuwahara Shader

The shader approach is still worthwhile, but it should be treated as its own phase because it adds a second execution stack with separate validation needs.

Implementation remains:

- `Shaders.metal` adds `kuwahara_structure_tensor`
- `Shaders.metal` adds `kuwahara_filter`
- `MetalContext.swift` adds:
  - two new pipeline states
  - `anisotropicKuwahara(_ image: CGImage, radius: Int = 6) -> UIImage?`

This path should use texture-based dispatch and manage its own command buffer rather than trying to force-fit the existing 1D buffer helper.

## UI Changes

`ControlPanelView.swift` gets a method picker inside the Simplify section.

Two changes from the original draft:

- keep the picker bound to `state.simplificationMethod`
- populate it from `state.availableSimplificationMethods`, not `SimplificationMethod.allCases`

Example:

```swift
Picker("Method", selection: Binding(
    get: { state.simplificationMethod },
    set: { method in
        state.simplificationMethod = method
        if state.simplifyEnabled {
            state.applySimplify()
        }
    }
)) {
    ForEach(state.availableSimplificationMethods) { method in
        Text(method.label).tag(method)
    }
}
.pickerStyle(.menu)
```

The toggle label should change from `UltraSharp` to something method-agnostic such as `Enable Simplification`.

## File Changes Summary

| File | Change |
|---|---|
| `ios/RefPlane/Models/AppModels.swift` | add `SimplificationMethod` and `SimplificationProcessingKind` |
| `ios/RefPlane/Models/AppState.swift` | add selected method, available methods list, simplification task cancellation, error handling |
| `ios/RefPlane/Processing/ImageSimplifier.swift` | route by method, throw errors, actor-backed model cache |
| `ios/RefPlane/Processing/MetalContext.swift` | add Kuwahara pipelines and texture-based execution method |
| `ios/RefPlane/Processing/Shaders.metal` | add `kuwahara_structure_tensor` and `kuwahara_filter` kernels |
| `ios/RefPlane/Views/ControlPanelView.swift` | add method picker and rename toggle label |
| `scripts/convert_models.py` | convert plus validate models and emit manifests |
| `ios/RefPlane.xcodeproj/project.pbxproj` | register new bundled `.mlpackage` resources |

## Housekeeping

- fix the stale `AppState.swift` comment that still says simplify strength maps to downscale `2-8`; the code already maps to `2-12`
- update the MetalContext startup log from `7` pipelines to `9` once the Kuwahara kernels are added

## Verification

1. Smoke test each bundled method on device: no crash, image changes, processing completes.
2. Rapidly switch methods and move the strength slider: only the latest requested result should win.
3. Remove one bundled model intentionally: the method should disappear from the picker or fail with a visible error, not silently return the original image.
4. For each shipped method at 50% strength, verify large forms remain readable while fine texture is reduced.
5. Verify tonal, value, and color modes still work on top of each simplification result.
6. For any style-transfer method, verify at least one non-square image path.
7. Repeatedly cycle through all bundled methods on a physical device and watch for memory regressions.
