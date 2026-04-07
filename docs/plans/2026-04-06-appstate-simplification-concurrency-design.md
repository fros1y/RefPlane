# AppState Simplification and Concurrency Modernization

## Objective
`AppState` has slowly grown into a "god object" (~2000 lines), mixing UI state, heavy image processing orchestration, transformation preset logic, export formatting, and depth diagnostics. Furthermore, it manages concurrency using brittle integer-based "generation counters" (`processingGeneration`, `abstractionGeneration`, etc.) to reject stale async results.

This design document outlines the strategy to decompose `AppState` and replace manual generation tracking with Swift's built-in structured concurrency.

## Phase 1: Modernize Concurrency (Remove Generation Counters)

Currently, async task bodies capture a generation snapshot and verify it upon returning to the main thread:
```swift
abstractionGeneration += 1
let generation = abstractionGeneration

abstractionTask = Task {
    let result = try await operation()
    await MainActor.run {
        guard self.abstractionGeneration == generation else { return }
        self.abstractedImage = result
    }
}
```

**New Approach: Structured Task Cancellation**
Rely natively on `Task.checkCancellation()` and `@MainActor` task isolation. Since SwiftUI processes are tied to the main actor, bridging the Task directly to `@MainActor` avoids synchronous interleaving gaps where stale data might be applied.

```swift
abstractionTask?.cancel()

abstractionTask = Task { @MainActor in
    do {
        // operation goes off-thread internally, but the Task itself is bound to MainActor
        let result = try await operation()
        
        // throws CancellationError if another task cancelled this one
        try Task.checkCancellation() 
        
        // Direct property access, guaranteed not to interleave with new tasks
        self.abstractedImage = result
        self.triggerProcessing()
    } catch is CancellationError {
        // Task superseded; ignore silently
    } catch {
        self.errorMessage = error.localizedDescription
    }
}
```

**Action Items:**
1. Remove `processingGeneration`, `abstractionGeneration`, `focusIsolationGeneration`, `depthGeneration`, `depthEffectGeneration`, and `contourGeneration` properties.
2. Refactor `triggerProcessing()`, `applyAbstraction()`, `computeDepthMap()`, `applyDepthEffects()`, `refreshIsolatedProcessedImage()`, and `recomputeContours()` to use `@MainActor` Tasks.
3. Ensure every heavy async operation is followed by `try Task.checkCancellation()`.

## Phase 2: Decompose AppState (Cure God-Object Syndrome)

To trim `AppState` down without unnecessarily breaking hundreds of View bindings, we will extract business logic into stateless managers and specialized formatters.

### 1. Extract Preset Management (`TransformPresetManager`)
- Move `SavedTransformPreset`, `TransformationSnapshot`, and `TransformPresetStore` definitions to a new file.
- Extract `saveCurrentTransformPreset`, `renameTransformPreset`, `deleteTransformPreset`, `applyTransformationSnapshot`, and persistence code.
- `AppState` will hold an instance of `PresetManager` (or delegate directly) while still exposing `selectedTransformPresetSelection` for the Views.

### 2. Extract Export Formatters (`ExportCoordinator`)
- `AppState` currently has 300+ lines dedicated to generating export outputs (e.g., `makeExportSoftwareDescription`, `makeExportSettingsSnapshot`, `generatedPaletteDescription`, `renderGridOnto`).
- Relocate these functions into a new `ExportCoordinator` or `ExportFormatter` that takes a lightweight snapshot of `AppState` and returns the finalized `String` payloads and `UIImage` composites.

### 3. Extract Depth Diagnostics (`DepthDiagnosticsFormatter`)
- Move histogram generations, percentile calculations, tail summaries, and zero-depth coverage logic (`depthHistogramSummary`, `depthPercentileSummary`, `tailOccupancySummary`, `nonZeroDepthSummary`) to a specialized file.
- This cleans out ~200 lines of highly specialized math code that doesn't need to pollute UI state.

### 4. Refactor Processing Pipeline Orchestration
- The coordination logic linking `loadImage` -> `applyAbstraction` -> `computeDepthMap` -> `triggerProcessing` can be modeled clearer if separated from raw UI event handling. 
- Create an `ImagePipeline` structure or extension of `AppState` isolating these lifecycle transitions.

## Expected Outcome
- **Resilience:** Concurrency is mathematically provable against race conditions via Swift's built-in cooperative cancellation, ending the reliance on generations escaping block closures.
- **Maintainability:** `AppState` is reduced from 2000+ lines to ~500 lines of pure `@Observable` state values and lightweight intents, making it easier to read and audit.
