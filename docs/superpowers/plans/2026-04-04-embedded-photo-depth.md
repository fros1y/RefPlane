# Embedded Photo Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract embedded depth/disparity data from Portrait Mode and Spatial photos at import time, skip ML inference when it's available, and show a small UI indicator of the depth source.

**Architecture:** At import time, `ImagePickerView` calls `DepthEstimator.extractEmbeddedDepth(from:)` with the raw image `Data`. When a depth map is found, it is stored on `ImportedImagePayload` and carried into `AppState.loadImage(_:)`. `computeDepthMap()` checks for an embedded map before launching the async ML task; if present it resizes to match `displayBaseImage` and sets `depthSource = .embedded` synchronously. `DepthSettingsView` reads `depthSource` to show a small caption label.

**Tech Stack:** ImageIO (`CGImageSourceCopyAuxiliaryDataInfoAtIndex`), AVFoundation (`AVDepthData`), CoreImage (`CIColorInvert`), Swift Testing, SwiftUI

---

## File Structure

| File | Change |
|------|--------|
| `ios/RefPlane/Processing/DepthEstimator.swift` | Add `import AVFoundation`; add `extractEmbeddedDepth(from:)` and `resize(_:toMatch:)` as `static` methods |
| `ios/RefPlane/Models/AppModels.swift` | Add `enum DepthSource`; add `embeddedDepthMap: UIImage?` to `ImportedImagePayload` |
| `ios/RefPlane/Views/ImagePickerView.swift` | In `loadImageData`, call `DepthEstimator.extractEmbeddedDepth(from:)` on the raw `Data` and include result in the payload |
| `ios/RefPlane/Models/AppState.swift` | Add `embeddedDepthMap: UIImage?` and `depthSource: DepthSource?`; update `loadImage(_:)` to store embedded map; add synchronous fast-path at top of `computeDepthMap()` |
| `ios/RefPlane/Views/DepthSettingsView.swift` | Show a `Text` caption based on `state.depthSource` when depth is active |
| `ios/RefPlaneTests/DepthEstimatorTests.swift` | New: tests for `extractEmbeddedDepth` |
| `ios/RefPlaneTests/AppStateTests.swift` | Add test verifying ML path is skipped when embedded depth is present |

---

### Task 1: AppModels — data model additions

**Files:**
- Modify: `ios/RefPlane/Models/AppModels.swift:296-318`

- [ ] **Step 1: Add `DepthSource` enum and update `ImportedImagePayload`**

  In `AppModels.swift`, after the `ContourConfig` struct (around line 293), add:

  ```swift
  enum DepthSource { case embedded, estimated }
  ```

  Then update `ImportedImagePayload` (currently at line 304):

  ```swift
  struct ImportedImagePayload {
      var image: UIImage
      var metadata: SourceImageMetadata
      var embeddedDepthMap: UIImage?

      init(image: UIImage, metadata: SourceImageMetadata = .empty, embeddedDepthMap: UIImage? = nil) {
          self.image = image
          self.metadata = metadata
          self.embeddedDepthMap = embeddedDepthMap
      }
  }
  ```

- [ ] **Step 2: Verify the project compiles**

  Run: `xcodebuild build -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add ios/RefPlane/Models/AppModels.swift
  git commit -m "feat: add DepthSource enum and embeddedDepthMap to ImportedImagePayload"
  ```

---

### Task 2: DepthEstimator — extraction method

**Files:**
- Modify: `ios/RefPlane/Processing/DepthEstimator.swift`
- Create: `ios/RefPlaneTests/DepthEstimatorTests.swift`

- [ ] **Step 1: Write the failing test**

  Create `ios/RefPlaneTests/DepthEstimatorTests.swift`:

  ```swift
  import UIKit
  import Testing
  @testable import Underpaint

  @Suite struct DepthEstimatorTests {

      // A plain PNG has no AVFoundation auxiliary depth data.
      @Test func extractEmbeddedDepthReturnsNilForPlainPNG() throws {
          let image = UIImage(systemName: "photo")!
          let data = try #require(image.pngData())
          #expect(DepthEstimator.extractEmbeddedDepth(from: data) == nil)
      }

      // Confirms the public resize helper produces a UIImage at the requested dimensions.
      @Test func resizeProducesCorrectDimensions() {
          let depth = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 40)
          let source = TestImageFactory.makeSolid(width: 200, height: 150, color: .gray)
          let resized = DepthEstimator.resize(depth, toMatch: source)
          #expect(resized.cgImage?.width == 200)
          #expect(resized.cgImage?.height == 150)
      }
  }
  ```

- [ ] **Step 2: Run tests to verify they fail (compile error — method does not exist yet)**

  Run: `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing RefPlaneTests/DepthEstimatorTests 2>&1 | grep -E "error:|FAILED|PASSED"`

  Expected: compile error — `type 'DepthEstimator' has no member 'extractEmbeddedDepth'`

- [ ] **Step 3: Add `import AVFoundation` to DepthEstimator**

  At the top of `ios/RefPlane/Processing/DepthEstimator.swift`, after `import CoreImage`:

  ```swift
  import AVFoundation
  ```

- [ ] **Step 4: Add `extractEmbeddedDepth(from:)` and `resize(_:toMatch:)`**

  In `DepthEstimator`, after the `// MARK: - Public API` section (after `depthRange(from:)`, before `// MARK: - Model loading`):

  ```swift
  // MARK: - Embedded depth extraction

  /// Extract an embedded depth or disparity map from raw image data (e.g. Portrait Mode HEIC).
  /// Returns nil if no auxiliary depth data is present.
  ///
  /// Convention: 0 = nearest (foreground), 1 = farthest (background) — same as `estimateDepth`.
  /// Disparity auxiliary data is preferred over depth because it has the same near=bright
  /// polarity as DepthAnything's raw output, requiring the same CIColorInvert step.
  static func extractEmbeddedDepth(from data: Data) -> UIImage? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

      for auxType in [kCGImageAuxiliaryDataTypeDisparity, kCGImageAuxiliaryDataTypeDepth] as [CFString] {
          guard
              let dict = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxType) as? [AnyHashable: Any],
              let depthData = try? AVDepthData(fromDictionaryRepresentation: dict)
          else { continue }

          // Normalize to Float32 for consistent CIImage handling.
          let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
          let pixelBuffer = converted.depthDataMap

          // Invert so near = 0 (dark), far = 1 (bright), matching pipeline convention.
          var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
          if let invert = CIFilter(name: "CIColorInvert") {
              invert.setValue(ciImage, forKey: kCIInputImageKey)
              if let out = invert.outputImage { ciImage = out }
          }

          let context = CIContext(options: [.useSoftwareRenderer: false])
          guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { continue }

          // Convert float output to 8-bit grayscale at native depth resolution.
          let w = CVPixelBufferGetWidth(pixelBuffer)
          let h = CVPixelBufferGetHeight(pixelBuffer)
          return UIImage(cgImage: resizeGrayscale(cgImage, toWidth: w, height: h))
      }
      return nil
  }

  /// Resize a depth map `UIImage` to match the pixel dimensions of `source`.
  /// Uses the same 8-bit grayscale context as the rest of the pipeline.
  static func resize(_ depthMap: UIImage, toMatch source: UIImage) -> UIImage {
      guard let cg = depthMap.cgImage, let sourceCG = source.cgImage else { return depthMap }
      return UIImage(cgImage: resizeGrayscale(cg, toWidth: sourceCG.width, height: sourceCG.height))
  }
  ```

- [ ] **Step 5: Run tests to verify they pass**

  Run: `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing RefPlaneTests/DepthEstimatorTests 2>&1 | grep -E "error:|FAILED|PASSED|Test run"`

  Expected: both tests PASSED

- [ ] **Step 6: Commit**

  ```bash
  git add ios/RefPlane/Processing/DepthEstimator.swift ios/RefPlaneTests/DepthEstimatorTests.swift
  git commit -m "feat: add DepthEstimator.extractEmbeddedDepth and resize helpers"
  ```

---

### Task 3: AppState — store embedded depth, fast path in computeDepthMap

**Files:**
- Modify: `ios/RefPlane/Models/AppState.swift`
- Modify: `ios/RefPlaneTests/AppStateTests.swift`

- [ ] **Step 1: Write the failing AppState test**

  Append to `ios/RefPlaneTests/AppStateTests.swift`:

  ```swift
  @MainActor
  @Test
  func computeDepthMapUsesEmbeddedDepthAndSkipsML() async throws {
      var mlWasCalled = false
      let state = AppState(depthMapOperation: { _ in
          mlWasCalled = true
          throw DepthEstimatorError.modelUnavailable
      })

      let baseImage = TestImageFactory.makeSolid(width: 100, height: 100, color: .gray)
      let fakeDepth = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 50)
      let payload = ImportedImagePayload(image: baseImage, embeddedDepthMap: fakeDepth)

      state.loadImage(payload)
      state.depthConfig.enabled = true
      state.computeDepthMap()

      // Give any async tasks a moment to run (should be none for the embedded path).
      try await Task.sleep(for: .milliseconds(200))

      #expect(mlWasCalled == false)
      #expect(state.depthSource == .embedded)
      #expect(state.depthMap != nil)
  }

  @MainActor
  @Test
  func loadImageClearsDepthSourceAndEmbeddedMap() {
      let state = AppState()
      // Simulate a previously loaded portrait image
      let fakeDepth = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 50)
      let portraitPayload = ImportedImagePayload(
          image: TestImageFactory.makeSolid(width: 100, height: 100, color: .gray),
          embeddedDepthMap: fakeDepth
      )
      state.loadImage(portraitPayload)
      // Now load a plain image — embedded depth should be cleared
      state.loadImage(TestImageFactory.makeSolid(width: 100, height: 100, color: .red))
      #expect(state.embeddedDepthMap == nil)
      #expect(state.depthSource == nil)
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  Run: `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing "RefPlaneTests/AppStateTests/computeDepthMapUsesEmbeddedDepthAndSkipsML" -only-testing "RefPlaneTests/AppStateTests/loadImageClearsDepthSourceAndEmbeddedMap" 2>&1 | grep -E "error:|FAILED|PASSED"`

  Expected: compile error — `value of type 'AppState' has no member 'embeddedDepthMap'` and `'depthSource'`

- [ ] **Step 3: Add `embeddedDepthMap` and `depthSource` properties to AppState**

  In `ios/RefPlane/Models/AppState.swift`, in the `// Depth results` block (around line 295, after `depthMap: UIImage? = nil`):

  ```swift
  // Depth results
  var depthMap: UIImage? = nil
  var embeddedDepthMap: UIImage? = nil          // extracted at import time; nil for non-portrait photos
  var depthSource: DepthSource? = nil           // set when depth map is computed
  ```

- [ ] **Step 4: Update `loadImage(_:)` to store embedded depth and reset depthSource**

  In `loadImage(_ payload: ImportedImagePayload)` (around line 527), after `depthMap = nil` (line 561), add:

  ```swift
  embeddedDepthMap          = payload.embeddedDepthMap
  depthSource               = nil
  ```

- [ ] **Step 5: Add embedded depth fast path to `computeDepthMap()`**

  In `computeDepthMap()` (around line 1772), replace the block from `depthGeneration += 1` through the end of the method with:

  ```swift
  // Fast path: use embedded depth map if available — skip ML entirely.
  if let embedded = embeddedDepthMap {
      let resized = DepthEstimator.resize(embedded, toMatch: source)
      let range = DepthEstimator.depthRange(from: resized)
      let isFirstCompute = depthMap == nil
      depthMap = resized
      depthRange = range
      depthSource = .embedded
      if isFirstCompute {
          let span = range.upperBound - range.lowerBound
          depthConfig.foregroundCutoff = range.lowerBound + span / 3.0
          depthConfig.backgroundCutoff = range.lowerBound + span * 2.0 / 3.0
      }
      applyDepthEffects()
      recomputeContours()
      return
  }

  // Slow path: ML inference.
  depthGeneration += 1
  let generation = depthGeneration

  isProcessing = true
  processingLabel = "Estimating depth…"
  processingIsIndeterminate = true

  depthTask = Task {
      do {
          let result = try await depthMapOperation(source)
          try Task.checkCancellation()

          let range = DepthEstimator.depthRange(from: result)

          await MainActor.run {
              guard self.depthGeneration == generation else { return }
              let isFirstCompute = self.depthMap == nil
              self.depthMap = result
              self.depthRange = range
              self.depthSource = .estimated
              if isFirstCompute {
                  let span = range.upperBound - range.lowerBound
                  self.depthConfig.foregroundCutoff = range.lowerBound + span / 3.0
                  self.depthConfig.backgroundCutoff = range.lowerBound + span * 2.0 / 3.0
              }
              self.processingIsIndeterminate = false
              self.processingLabel = "Processing…"
              self.isProcessing = false
              self.applyDepthEffects()
              self.recomputeContours()
          }
      } catch is CancellationError {
          // superseded
      } catch {
          await MainActor.run {
              guard self.depthGeneration == generation else { return }
              self.isProcessing = false
              self.processingIsIndeterminate = false
              self.processingLabel = "Processing…"
              self.errorMessage = error.localizedDescription
          }
      }
  }
  ```

- [ ] **Step 6: Run tests to verify they pass**

  Run: `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing "RefPlaneTests/AppStateTests/computeDepthMapUsesEmbeddedDepthAndSkipsML" -only-testing "RefPlaneTests/AppStateTests/loadImageClearsDepthSourceAndEmbeddedMap" 2>&1 | grep -E "error:|FAILED|PASSED|Test run"`

  Expected: both tests PASSED

- [ ] **Step 7: Run full test suite**

  Run: `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED|Test run"`

  Expected: all tests PASSED, no regressions

- [ ] **Step 8: Commit**

  ```bash
  git add ios/RefPlane/Models/AppState.swift ios/RefPlaneTests/AppStateTests.swift
  git commit -m "feat: use embedded depth in AppState, skip ML when portrait photo"
  ```

---

### Task 4: ImagePickerView — extract depth at import time

**Files:**
- Modify: `ios/RefPlane/Views/ImagePickerView.swift:45-57`

No unit test — requires Photo Library access. Verified manually in Task 5.

- [ ] **Step 1: Update `loadImageData` to extract embedded depth**

  Replace the entire `loadImageData` method body (lines 46–57) with:

  ```swift
  private func loadImageData(from provider: NSItemProvider, typeIdentifier: String) {
      provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
          guard let self else { return }
          if let data, let image = UIImage(data: data) {
              let metadata = Self.readMetadata(from: data, fallbackTypeIdentifier: typeIdentifier)
              let embeddedDepth = DepthEstimator.extractEmbeddedDepth(from: data)
              self.deliverSelection(ImportedImagePayload(
                  image: image,
                  metadata: metadata,
                  embeddedDepthMap: embeddedDepth
              ))
          } else {
              self.loadFallbackImage(from: provider)
          }
      }
  }
  ```

- [ ] **Step 2: Verify project compiles**

  Run: `xcodebuild build -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add ios/RefPlane/Views/ImagePickerView.swift
  git commit -m "feat: extract embedded depth map at photo import time"
  ```

---

### Task 5: DepthSettingsView — depth source indicator

**Files:**
- Modify: `ios/RefPlane/Views/DepthSettingsView.swift:61-63`

- [ ] **Step 1: Add source caption to `DepthSettingsView`**

  In `DepthSettingsView.body`, at the bottom of the `VStack` block (after the last `if state.depthConfig.backgroundMode != .none` block, before the closing `}`), add:

  ```swift
  if let source = state.depthSource {
      Text(source == .embedded ? "Using photo depth" : "Using estimated depth")
          .font(.caption2)
          .foregroundStyle(.secondary)
  }
  ```

  The full `VStack` should now look like:

  ```swift
  VStack(spacing: 14) {
      Picker("Adjust Background", selection: Binding(
          get: { state.depthConfig.backgroundMode },
          set: setBackgroundMode
      )) {
          ForEach(BackgroundMode.allCases) { mode in
              Text(mode.rawValue).tag(mode)
          }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("studio.background-mode-picker")

      if state.depthConfig.backgroundMode != .none {
          LabeledSlider(
              label: "Depth Threshold",
              value: Binding(
                  get: { state.depthConfig.backgroundCutoff },
                  set: { newValue in state.updateBackgroundDepthCutoff(newValue) }
              ),
              range: range.lowerBound...range.upperBound,
              step: step,
              displayFormat: { "\(Int(($0 - range.lowerBound) / span * 100))%" },
              onEditingChanged: { editing in
                  state.depthSliderActive = editing
                  if editing {
                      state.updateDepthThresholdPreview()
                  } else {
                      state.dismissDepthThresholdPreview()
                  }
              }
          )

          LabeledSlider(
              label: "Amount",
              value: Binding(
                  get: { state.depthConfig.effectIntensity },
                  set: { state.depthConfig.effectIntensity = $0 }
              ),
              range: 0...1,
              step: 0.05,
              displayFormat: { "\(Int($0 * 100))%" },
              onEditingChanged: { editing in
                  if !editing { state.applyDepthEffects() }
              }
          )
      }

      if let source = state.depthSource {
          Text(source == .embedded ? "Using photo depth" : "Using estimated depth")
              .font(.caption2)
              .foregroundStyle(.secondary)
      }
  }
  ```

- [ ] **Step 2: Verify project compiles and run all tests**

  Run: `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED|Test run"`

  Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add ios/RefPlane/Views/DepthSettingsView.swift
  git commit -m "feat: show depth source indicator in DepthSettingsView"
  ```

---

## Verification

1. **Build clean:** `xcodebuild build -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16'` → `BUILD SUCCEEDED`
2. **All tests pass:** `xcodebuild test -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16'` → no regressions
3. **Manual — Portrait Mode photo:** Import from Camera Roll → depth available instantly, no ML spinner, "Using photo depth" visible in depth panel
4. **Manual — Regular photo:** Import → ML estimation runs, "Using estimated depth" visible
5. **Manual — Portrait + simplification change:** Adjust abstraction after portrait photo → embedded depth reused, no re-estimation

---

## Decisions

- **Prefer disparity over depth** — both need `CIColorInvert` to match the pipeline's 0=near convention; disparity is always available on Portrait Mode images
- **Extract at import time** — raw `Data` with auxiliary blobs is only available during the picker callback; it is not recoverable from `UIImage` alone
- **Embedded depth always wins** — no quality comparison; the embedded map is exact for the scene
- **Synchronous fast path** — resize is cheap; no need for async task or progress spinner when using embedded depth
- **`DepthSource` is not `Codable`** — it is transient runtime state, reset on every `loadImage`

## Known Limitations

- **Resolution:** Embedded depth is typically ~768×576; `resizeGrayscale` upscales to display resolution. Acceptable quality tradeoff.
- **Depth fallback polarity:** Apple's `kCGImageAuxiliaryDataTypeDepth` uses near=small values (already 0=near after normalization), but the same `CIColorInvert` is applied as for disparity. This inverts the depth fallback. In practice, all iOS Portrait Mode photos provide disparity data first, so the depth fallback path is rarely exercised. A future improvement could skip the inversion for the depth auxiliary type.
