import SwiftUI
import os

// MARK: - Depth Processing & Contours

extension AppState {
    // MARK: - Depth processing

    func computeDepthMap() {
        processing.depthTask?.cancel()
        processing.depthTask = nil

        guard let source = displayBaseImage else {
            depth.depthProcessedImage = nil
            return
        }

        guard depth.depthConfig.enabled else {
            depth.depthProcessedImage = nil
            return
        }


        if let embedded = depth.embeddedDepthMap {
            let resized = DepthEstimator.resize(embedded, toMatch: source)
            let range = DepthEstimator.depthRange(from: resized)
            if shouldUseEmbeddedDepth(resized, range: range) {
                let isFirstCompute = depth.depthMap == nil
                depth.depthMap = resized
                depth.depthRange = range
                depth.depthSource = .embedded
                syncDepthCutoffs(to: range, resetToDefaults: isFirstCompute)
                logDepthDiagnostics(event: "embedded-depth-selected", depth: resized)
                applyDepthEffects()
                recomputeContours()
                return
            }

            AppState.depthLogger.warning(
                "Embedded depth rejected as sparse/flat (rangeSpan=\((range.upperBound - range.lowerBound), format: .fixed(precision: 6))); falling back to estimated depth"
            )
            depth.embeddedDepthMap = nil
        }

        let token = processing.start(
            for: .depthEstimation,
            label: "Estimating depth…",
            indeterminate: true
        )

        processing.depthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.depthMapOperation(source)
                try Task.checkCancellation()
                guard self.processing.isCurrent(token) else { return }

                let range = DepthEstimator.depthRange(from: result)

                let isFirstCompute = self.depth.depthMap == nil
                self.depth.depthMap = result
                self.depth.depthRange = range
                self.depth.depthSource = .estimated
                // Keep cutoffs aligned with the latest measured range.
                self.syncDepthCutoffs(to: range, resetToDefaults: isFirstCompute)
                self.logDepthDiagnostics(event: "estimated-depth-selected", depth: result)
                self.applyDepthEffects()
                self.recomputeContours()
            } catch is CancellationError {
                // superseded
            } catch {
                self.pipeline.errorMessage = error.localizedDescription
                self.processing.finish(token: token)
            }
        }
    }

    func applyDepthEffects() {
        processing.depthEffectTask?.cancel()

        guard depth.depthConfig.enabled, let depthMap = depth.depthMap else {
            depth.depthProcessedImage = nil
            return
        }

        guard let sourceImage = depthEffectSourceImage() else {
            depth.depthProcessedImage = nil
            return
        }

        let config = depth.depthConfig
        let token = processing.start(
            for: .depthEffects,
            label: "Applying depth…",
            indeterminate: true
        )

        processing.depthEffectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Let the synchronous operation run on a background thread
            let result = await Task.detached(priority: .userInitiated) {
                self.depthEffectOperation(sourceImage, depthMap, config)
            }.value
            
            try? Task.checkCancellation()
            guard !Task.isCancelled, self.processing.isCurrent(token) else { return }
            
            self.depth.depthProcessedImage = result
            self.processing.finish(token: token)
        }
    }

    func depthEffectSourceImage() -> UIImage? {
        if transform.activeMode == .original {
            return displayBaseImage
        }

        return pipeline.isolatedProcessedImage ?? processedImage ?? displayBaseImage
    }

    func resetDepthProcessing() {
        processing.depthTask?.cancel()
        processing.depthTask = nil
        processing.depthEffectTask?.cancel()
        processing.depthEffectTask = nil
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()
        depth.depthMap = nil
        depth.depthProcessedImage = nil
        depth.isEditingDepthThreshold = false
        depth.depthSliderActive = false
        depth.depthThresholdPreview = nil
        depth.cachedDepthTexture = nil
        depth.cachedSourceTexture = nil
        depth.depthRange = 0...1
        depth.contourSegments = []
    }

    func updateBackgroundDepthCutoff(_ newValue: Double) {
        guard newValue != depth.depthConfig.backgroundCutoff else {
            return
        }
        depth.depthConfig.backgroundCutoff = newValue
        depth.depthConfig.foregroundCutoff = min(depth.depthConfig.foregroundCutoff, newValue)
        refreshDepthThresholdOutput()
    }

    /// Regenerate the depth-threshold preview image showing which pixels
    /// fall into the background zone. Called while the user drags a cutoff slider.
    func updateDepthThresholdPreview() {
        guard let depthMap = depth.depthMap, let source = depthEffectSourceImage() else {
            depth.isEditingDepthThreshold = false
            depth.depthThresholdPreview = nil
            depth.cachedDepthTexture = nil
            depth.cachedSourceTexture = nil
            return
        }
        let bg = depth.depthConfig.backgroundCutoff
        let result = DepthProcessor.thresholdPreview(
            sourceImage: source,
            depthMap: depthMap,
            backgroundCutoff: bg,
            cachedDepthTexture: depth.cachedDepthTexture,
            cachedSourceTexture: depth.cachedSourceTexture
        )
        depth.isEditingDepthThreshold = true
        depth.depthThresholdPreview = result.image
        depth.cachedDepthTexture = result.cachedDepthTexture
        depth.cachedSourceTexture = result.cachedSourceTexture
        if let coverage = backgroundCoverage(in: depthMap, cutoff: bg) {
            AppState.depthLogger.debug(
                "Depth slider preview cutoff=\(bg, format: .fixed(precision: 4)) backgroundCoveragePct=\((coverage * 100.0), format: .fixed(precision: 2))"
            )
        }
    }

    /// Schedule auto-dismiss of the depth threshold preview as a safety net
    /// in case onEditingChanged(false) doesn't fire.
    func schedulePreviewDismissSafetyNet() {
        depthPreviewDismissTask?.cancel()
        depthPreviewDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s safety net
            guard !Task.isCancelled, let self else { return }
            guard !self.depth.depthSliderActive else { return }
            self.dismissDepthThresholdPreview()
        }
    }

    /// Dismiss the depth threshold preview and apply the current depth effects.
    func dismissDepthThresholdPreview() {
        depthPreviewDismissTask?.cancel()
        depth.depthSliderActive = false
        guard depth.isEditingDepthThreshold else {
            return
        }
        depth.isEditingDepthThreshold = false
        depth.depthThresholdPreview = nil
        depth.cachedDepthTexture = nil
        depth.cachedSourceTexture = nil
        applyDepthEffects()
        recomputeContours()
    }

    func refreshDepthThresholdOutput() {
        if depth.depthSliderActive {
            updateDepthThresholdPreview()
        } else if depth.isEditingDepthThreshold || depth.depthThresholdPreview != nil {
            dismissDepthThresholdPreview()
        } else {
            applyDepthEffects()
            recomputeContours()
        }
    }

    func logDepthDiagnostics(event: String, depth: UIImage) {
        let range = self.depth.depthRange
        let sourceSize = displayBaseImage?.size ?? .zero
        let depthSize = depth.size
        let coverage = backgroundCoverage(in: depth, cutoff: self.depth.depthConfig.backgroundCutoff)
        let pixels = grayscalePixels(from: depth)
        let globalHistogram = depthHistogramSummary(from: pixels, bins: 16, domain: 0.0...1.0)
        let localHistogram = depthHistogramSummary(from: pixels, bins: 24, domain: range)
        let percentiles = depthPercentileSummary(from: pixels)
        let nonZeroSummary = nonZeroDepthSummary(from: pixels)
        let tailSummary = tailOccupancySummary(from: pixels)
        let foregroundCutoff = self.depth.depthConfig.foregroundCutoff
        let backgroundCutoff = self.depth.depthConfig.backgroundCutoff
        AppState.depthLogger.info(
            "\(event, privacy: .public) source=\(Int(sourceSize.width))x\(Int(sourceSize.height)) depth=\(Int(depthSize.width))x\(Int(depthSize.height)) depthRange=[\(range.lowerBound, format: .fixed(precision: 6)), \(range.upperBound, format: .fixed(precision: 6))] fg=\(foregroundCutoff, format: .fixed(precision: 6)) bg=\(backgroundCutoff, format: .fixed(precision: 6)) bgCoverage=\(coverage ?? -1, format: .fixed(precision: 4)) nonZero=\(nonZeroSummary, privacy: .public) tail=\(tailSummary, privacy: .public) histGlobal=\(globalHistogram, privacy: .public) histLocal=\(localHistogram, privacy: .public) pct=\(percentiles, privacy: .public)"
        )
    }

    func syncDepthCutoffs(to range: ClosedRange<Double>, resetToDefaults: Bool) {
        let lower = range.lowerBound
        let upper = range.upperBound
        let span = max(upper - lower, 1.0 / 255.0)

        if resetToDefaults {
            depth.depthConfig.foregroundCutoff = lower + span / 3.0
            depth.depthConfig.backgroundCutoff = lower + span * 2.0 / 3.0
            return
        }

        let clampedForeground = min(upper, max(lower, depth.depthConfig.foregroundCutoff))
        let clampedBackground = min(upper, max(lower, depth.depthConfig.backgroundCutoff))
        depth.depthConfig.foregroundCutoff = min(clampedForeground, clampedBackground)
        depth.depthConfig.backgroundCutoff = max(clampedForeground, clampedBackground)
    }

    func backgroundCoverage(in depthImage: UIImage, cutoff: Double) -> Double? {
        guard let pixels = grayscalePixels(from: depthImage) else {
            return nil
        }

        let threshold = UInt8(max(0, min(255, Int((cutoff * 255.0).rounded()))))
        var count = 0
        for pixel in pixels where pixel >= threshold {
            count += 1
        }
        return Double(count) / Double(pixels.count)
    }

    func depthHistogramSummary(
        from pixels: [UInt8]?,
        bins: Int,
        domain: ClosedRange<Double>
    ) -> String {
        guard bins > 0, let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        let lo = max(0.0, min(1.0, domain.lowerBound))
        let hi = max(lo + (1.0 / 255.0), min(1.0, domain.upperBound))
        let span = hi - lo

        var counts = [Int](repeating: 0, count: bins)
        for pixel in pixels {
            let value = Double(pixel) / 255.0
            if value < lo || value > hi {
                continue
            }
            let normalized = (value - lo) / span
            let index = min(bins - 1, max(0, Int((normalized * Double(bins)).rounded(.down))))
            counts[index] += 1
        }

        let total = Double(pixels.count)
        let bucketDescriptions = counts.enumerated().map { idx, count -> String in
            let bucketLo = lo + (Double(idx) / Double(bins)) * span
            let bucketHi = lo + (Double(idx + 1) / Double(bins)) * span
            let pct = (Double(count) / total) * 100.0
            return String(format: "%.3f-%.3f:%d(%.3f%%)", bucketLo, bucketHi, count, pct)
        }

        return "[\(bucketDescriptions.joined(separator: ", "))]"
    }

    func depthPercentileSummary(from pixels: [UInt8]?) -> String {
        guard let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        var counts = [Int](repeating: 0, count: 256)
        for pixel in pixels {
            counts[Int(pixel)] += 1
        }

        let total = pixels.count
        func percentile(_ p: Double) -> Double {
            let target = Int((Double(total - 1) * p).rounded())
            var cumulative = 0
            for (value, count) in counts.enumerated() {
                cumulative += count
                if cumulative > target {
                    return Double(value) / 255.0
                }
            }
            return 1.0
        }

        let p10 = percentile(0.10)
        let p50 = percentile(0.50)
        let p90 = percentile(0.90)
        let p99 = percentile(0.99)
        let p999 = percentile(0.999)
        return String(format: "p10=%.4f,p50=%.4f,p90=%.4f,p99=%.4f,p99.9=%.4f", p10, p50, p90, p99, p999)
    }

    func tailOccupancySummary(from pixels: [UInt8]?) -> String {
        guard let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        let total = Double(pixels.count)
        let above98 = pixels.reduce(into: 0) { count, pixel in
            if pixel >= 250 { // >= 0.9804
                count += 1
            }
        }
        let above995 = pixels.reduce(into: 0) { count, pixel in
            if pixel >= 254 { // >= 0.9961
                count += 1
            }
        }

        return String(
            format: ">=0.98:%d(%.3f%%),>=0.996:%d(%.3f%%)",
            above98,
            (Double(above98) / total) * 100.0,
            above995,
            (Double(above995) / total) * 100.0
        )
    }

    func shouldUseEmbeddedDepth(_ depthImage: UIImage, range: ClosedRange<Double>) -> Bool {
        guard let pixels = grayscalePixels(from: depthImage), !pixels.isEmpty else {
            return false
        }

        let nonZeroCount = pixels.reduce(into: 0) { partialResult, pixel in
            if pixel > 0 {
                partialResult += 1
            }
        }

        let nonZeroRatio = Double(nonZeroCount) / Double(pixels.count)
        let span = range.upperBound - range.lowerBound

        // Treat maps as invalid when almost all pixels are zero or the span is
        // effectively quantized to a near-flat signal.
        let minNonZeroRatio = 0.001   // 0.1%
        let minSpan = 2.0 / 255.0

        if nonZeroRatio < minNonZeroRatio {
            AppState.depthLogger.warning(
                "Embedded depth nonZeroRatio too low: \(nonZeroRatio, format: .fixed(precision: 6))"
            )
            return false
        }

        if span < minSpan {
            AppState.depthLogger.warning(
                "Embedded depth span too low: \(span, format: .fixed(precision: 6))"
            )
            return false
        }

        return true
    }

    func nonZeroDepthSummary(from pixels: [UInt8]?) -> String {
        guard let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        var counts = [Int](repeating: 0, count: 256)
        for pixel in pixels {
            counts[Int(pixel)] += 1
        }

        let total = pixels.count
        let nonZeroCount = total - counts[0]
        if nonZeroCount == 0 {
            return "0/\(total) (0.000%)"
        }

        let minNonZeroByte = counts.enumerated().first(where: { $0.offset > 0 && $0.element > 0 })?.offset ?? 1
        var maxNonZeroByte = 255
        while maxNonZeroByte > 0 && counts[maxNonZeroByte] == 0 {
            maxNonZeroByte -= 1
        }

        let topLevels = counts.enumerated()
            .filter { $0.offset > 0 && $0.element > 0 }
            .sorted { lhs, rhs in
                if lhs.element == rhs.element {
                    return lhs.offset < rhs.offset
                }
                return lhs.element > rhs.element
            }
            .prefix(6)
            .map { "\($0.offset):\($0.element)" }
            .joined(separator: "|")

        let pct = (Double(nonZeroCount) / Double(total)) * 100.0
        return String(
            format: "%d/%d (%.3f%%) minNZ=%.4f maxNZ=%.4f topNZ=[%@]",
            nonZeroCount,
            total,
            pct,
            Double(minNonZeroByte) / 255.0,
            Double(maxNonZeroByte) / 255.0,
            topLevels
        )
    }

    func grayscalePixels(from depthImage: UIImage) -> [UInt8]? {
        guard let cgImage = depthImage.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    // MARK: - Contour line generation

    func recomputeContours() {
        contourTask?.cancel()
        guard transform.contourConfig.enabled, let depthMap = depth.depthMap else {
            depth.contourSegments = []
            return
        }
        let cfg = transform.contourConfig
        let depthCfg = depth.depthConfig
        let range = depth.depthRange
        contourTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let segs = await Task.detached(priority: .userInitiated) {
                ContourGenerator.generateSegments(
                    depthMap: depthMap,
                    levels: cfg.levels,
                    depthRange: range,
                    backgroundCutoff: depthCfg.backgroundCutoff
                )
            }.value
            
            try? Task.checkCancellation()
            guard !Task.isCancelled else { return }
            self.depth.contourSegments = segs
        }
    }

    func renderContoursOnto(_ image: UIImage) -> UIImage {
        let size = image.size
        let config = transform.contourConfig
        let segments = depth.contourSegments
        let lineWidth = max(1.0, min(size.width, size.height) / 1000.0)

        let resolved = ContourLineColorResolver.resolvedSegments(
            config: config,
            image: image,
            segments: segments
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.clip(to: CGRect(origin: .zero, size: size))

            for resolvedSegment in resolved {
                let mappedSegment = resolvedSegment.segment.mapped(
                    to: CGRect(origin: .zero, size: size)
                )
                let color = UIColor(resolvedSegment.color).withAlphaComponent(config.opacity)
                cg.setStrokeColor(color.cgColor)
                cg.move(to: mappedSegment.start)
                cg.addLine(to: mappedSegment.end)
                cg.strokePath()
            }
        }
    }
}
