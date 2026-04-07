import SwiftUI
import os

// MARK: - Focus Isolation

extension AppState {
    func toggleFocusedBand(_ band: Int) {
        var updatedBands = focusedBands
        if updatedBands.contains(band) {
            updatedBands.remove(band)
        } else {
            updatedBands.insert(band)
        }
        focusedBands = updatedBands
        refreshIsolatedProcessedImage()
    }

    func toggleFocusedBand(atNormalizedPoint point: CGPoint) {
        guard let band = band(atNormalizedPoint: point) else { return }
        toggleFocusedBand(band)
    }

    func toggleIsolatedBand(_ band: Int) {
        toggleFocusedBand(band)
    }

    func toggleIsolatedBand(atNormalizedPoint point: CGPoint) {
        toggleFocusedBand(atNormalizedPoint: point)
    }

    func clearFocusedBands() {
        guard !focusedBands.isEmpty else { return }
        focusedBands = []
        refreshIsolatedProcessedImage()
    }

    func clearIsolatedBandSelection() {
        clearFocusedBands()
    }

    func refreshIsolatedProcessedImage() {
        invalidateFocusIsolation(clearSelection: false)

        guard activeMode == .value || activeMode == .color,
              !focusedBands.isEmpty,
              let processedImage else {
            return
        }

        let pixelBands = processedPixelBands
        let selectedBands = focusedBands

        focusIsolationTask = Task { @MainActor [weak self] in
            let isolated = await BandIsolationRenderer.isolateAsync(
                image: processedImage,
                pixelBands: pixelBands,
                selectedBands: selectedBands
            )
            try? Task.checkCancellation()
            guard !Task.isCancelled, let self else { return }

            self.isolatedProcessedImage = isolated
        }
    }

    func invalidateFocusIsolation(clearSelection: Bool) {
        focusIsolationTask?.cancel()
        focusIsolationTask = nil
        isolatedProcessedImage = nil
        if clearSelection {
            focusedBands = []
        }
    }
}
