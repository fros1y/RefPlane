import UIKit
import SwiftUI

// MARK: - Color study pipeline

enum ColorRegionsProcessor {

    private static let familyLWeight: Float = 0.08
    private static let histogramLBins = 12
    private static let histogramABins = 24
    private static let histogramBBins = 24
    private static let histogramAMin: Float = -0.45
    private static let histogramAMax: Float = 0.45
    private static let histogramBMin: Float = -0.45
    private static let histogramBMax: Float = 0.45

    private struct HistogramCandidate {
        let color: OklabColor
        let weight: Float
    }

    struct Result {
        let image: UIImage
        /// Palette colors grouped by family index.
        let palette: [Color]
        let paletteBands: [Int]
    }

    static func process(image: UIImage, config: ColorConfig) -> Result? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let (pixels, width, height) = image.toPixelData() else { return nil }

        if let gpu = MetalContext.shared,
           let result = processGPU(gpu: gpu, pixels: pixels, width: width, height: height, config: config) {
            let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[ColorStudy] GPU path in \(String(format: "%.1f", totalMs)) ms")
            return result
        }

        let result = processCPU(pixels: pixels, width: width, height: height, config: config)
        let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[ColorStudy] CPU path in \(String(format: "%.1f", totalMs)) ms")
        return result
    }

    // MARK: - GPU path

    private static func processGPU(
        gpu: MetalContext,
        pixels: [UInt8],
        width: Int,
        height: Int,
        config: ColorConfig
    ) -> Result? {
        let total = width * height
        let colorFamilies = max(2, min(6, config.colorFamilies))
        let valuesPerFamily = max(1, min(4, config.valuesPerFamily))
        let thresholds = normalizedThresholds(config.valueThresholds, levels: valuesPerFamily)

        var stepStart = CFAbsoluteTimeGetCurrent()
        guard let (labArray, srcBuffer, labBuffer) = gpu.rgbToOklab(pixels: pixels, width: width, height: height) else {
            return nil
        }
        print("[ColorStudy][GPU] rgb_to_oklab: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        var familyCentroids = selectFamilyCentroids(labArray: labArray, k: colorFamilies, lWeight: familyLWeight)
        print("[ColorStudy][CPU] choose_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        if config.warmCoolEmphasis != 0 {
            familyCentroids = applyWarmCoolEmphasis(to: familyCentroids, amount: config.warmCoolEmphasis)
        }

        guard !familyCentroids.isEmpty else { return nil }

        stepStart = CFAbsoluteTimeGetCurrent()
        let assignments = assignFamiliesGPU(
            gpu: gpu,
            pixelLabBuffer: labBuffer,
            count: total,
            centroids: familyCentroids,
            lWeight: familyLWeight
        )
        print("[ColorStudy][GPU] assign_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        var globalLabels = buildLabels(
            labArray: labArray,
            familyAssignments: assignments,
            familyCount: familyCentroids.count,
            valuesPerFamily: valuesPerFamily,
            thresholds: thresholds
        )
        print("[ColorStudy][CPU] build_labels: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        if let factor = config.minRegionSize.factor {
            stepStart = CFAbsoluteTimeGetCurrent()
            RegionCleaner.clean(
                labels: &globalLabels,
                width: width,
                height: height,
                minFactor: factor,
                labelCapacity: familyCentroids.count * valuesPerFamily
            )
            print("[ColorStudy][CPU] region_cleanup: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        }

        stepStart = CFAbsoluteTimeGetCurrent()
        let quantized = makeQuantizedCentroids(
            labArray: labArray,
            labels: globalLabels,
            familyCentroids: familyCentroids,
            valuesPerFamily: valuesPerFamily,
            thresholds: thresholds
        )
        print("[ColorStudy][CPU] quantize_values: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        let flatCentroids = quantized.centroids.flatMap { [$0.L, $0.a, $0.b] }
        stepStart = CFAbsoluteTimeGetCurrent()
        guard let outputPixels = gpu.remapByLabel(
            srcBuffer: srcBuffer,
            labels: globalLabels,
            centroids: flatCentroids,
            count: total
        ),
        let image = UIImage.fromPixelData(outputPixels, width: width, height: height) else {
            return nil
        }
        print("[ColorStudy][GPU] remap_by_label: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        return Result(image: image, palette: quantized.palette, paletteBands: quantized.paletteBands)
    }

    // MARK: - CPU path

    private static func processCPU(
        pixels: [UInt8],
        width: Int,
        height: Int,
        config: ColorConfig
    ) -> Result? {
        let total = width * height
        let colorFamilies = max(2, min(6, config.colorFamilies))
        let valuesPerFamily = max(1, min(4, config.valuesPerFamily))
        let thresholds = normalizedThresholds(config.valueThresholds, levels: valuesPerFamily)

        var stepStart = CFAbsoluteTimeGetCurrent()
        var points = [OklabColor](repeating: OklabColor(L: 0, a: 0, b: 0), count: total)
        for i in 0..<total {
            let base = i * 4
            points[i] = rgbToOklab(r: pixels[base], g: pixels[base + 1], b: pixels[base + 2])
        }
        print("[ColorStudy][CPU] rgb_to_oklab: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        var familyCentroids = selectFamilyCentroids(points: points, k: colorFamilies, lWeight: familyLWeight)
        print("[ColorStudy][CPU] choose_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        if config.warmCoolEmphasis != 0 {
            familyCentroids = applyWarmCoolEmphasis(to: familyCentroids, amount: config.warmCoolEmphasis)
        }

        guard !familyCentroids.isEmpty else { return nil }

        stepStart = CFAbsoluteTimeGetCurrent()
        let assignments = assignFamiliesCPU(points: points, centroids: familyCentroids, lWeight: familyLWeight)
        print("[ColorStudy][CPU] assign_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        var globalLabels = buildLabels(
            points: points,
            familyAssignments: assignments,
            familyCount: familyCentroids.count,
            valuesPerFamily: valuesPerFamily,
            thresholds: thresholds
        )
        print("[ColorStudy][CPU] build_labels: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        if let factor = config.minRegionSize.factor {
            stepStart = CFAbsoluteTimeGetCurrent()
            RegionCleaner.clean(
                labels: &globalLabels,
                width: width,
                height: height,
                minFactor: factor,
                labelCapacity: familyCentroids.count * valuesPerFamily
            )
            print("[ColorStudy][CPU] region_cleanup: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        }

        stepStart = CFAbsoluteTimeGetCurrent()
        let quantized = makeQuantizedCentroids(
            points: points,
            labels: globalLabels,
            familyCentroids: familyCentroids,
            valuesPerFamily: valuesPerFamily,
            thresholds: thresholds
        )
        print("[ColorStudy][CPU] quantize_values: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        var out = [UInt8](repeating: 255, count: total * 4)
        for i in 0..<total {
            var label = Int(globalLabels[i])
            if label < 0 || label >= quantized.centroids.count {
                label = 0
            }

            let color = quantized.centroids[label]
            let (r, g, b) = oklabToRGB(color)
            let base = i * 4
            out[base] = r
            out[base + 1] = g
            out[base + 2] = b
            out[base + 3] = pixels[base + 3]
        }
        print("[ColorStudy][CPU] remap_pixels: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        guard let image = UIImage.fromPixelData(out, width: width, height: height) else {
            return nil
        }

        return Result(image: image, palette: quantized.palette, paletteBands: quantized.paletteBands)
    }

    // MARK: - Shared helpers

    private static func labArrayToColors(_ labArray: [Float]) -> [OklabColor] {
        stride(from: 0, to: labArray.count, by: 3).map { index in
            OklabColor(
                L: labArray[index],
                a: labArray[index + 1],
                b: labArray[index + 2]
            )
        }
    }

    private static func selectFamilyCentroids(
        labArray: [Float],
        k: Int,
        lWeight: Float
    ) -> [OklabColor] {
        guard !labArray.isEmpty, k > 0 else { return [] }

        let candidates = buildHistogramCandidates(labArray: labArray)
        guard !candidates.isEmpty else { return [] }

        let targetCount = min(k, candidates.count)
        var centroids = seededFamilyCentroids(candidates: candidates, k: targetCount, lWeight: lWeight)

        for _ in 0..<4 {
            var sums = [(L: Float, a: Float, b: Float, weight: Float)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )

            for candidate in candidates {
                let index = nearestCentroidIndex(for: candidate.color, centroids: centroids, lWeight: lWeight)
                sums[index].L += candidate.color.L * candidate.weight
                sums[index].a += candidate.color.a * candidate.weight
                sums[index].b += candidate.color.b * candidate.weight
                sums[index].weight += candidate.weight
            }

            var maxShift: Float = 0
            for index in 0..<centroids.count where sums[index].weight > 0 {
                let inverseWeight = 1 / sums[index].weight
                let refined = OklabColor(
                    L: sums[index].L * inverseWeight,
                    a: sums[index].a * inverseWeight,
                    b: sums[index].b * inverseWeight
                )
                maxShift = max(maxShift, oklabDistance(centroids[index], refined))
                centroids[index] = refined
            }

            if maxShift < 0.0005 {
                break
            }
        }

        return centroids
    }

    private static func selectFamilyCentroids(
        points: [OklabColor],
        k: Int,
        lWeight: Float
    ) -> [OklabColor] {
        guard !points.isEmpty, k > 0 else { return [] }

        let candidates = buildHistogramCandidates(points: points)
        guard !candidates.isEmpty else { return [] }

        let targetCount = min(k, candidates.count)
        var centroids = seededFamilyCentroids(candidates: candidates, k: targetCount, lWeight: lWeight)

        for _ in 0..<4 {
            var sums = [(L: Float, a: Float, b: Float, weight: Float)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )

            for candidate in candidates {
                let index = nearestCentroidIndex(for: candidate.color, centroids: centroids, lWeight: lWeight)
                sums[index].L += candidate.color.L * candidate.weight
                sums[index].a += candidate.color.a * candidate.weight
                sums[index].b += candidate.color.b * candidate.weight
                sums[index].weight += candidate.weight
            }

            var maxShift: Float = 0
            for index in 0..<centroids.count where sums[index].weight > 0 {
                let inverseWeight = 1 / sums[index].weight
                let refined = OklabColor(
                    L: sums[index].L * inverseWeight,
                    a: sums[index].a * inverseWeight,
                    b: sums[index].b * inverseWeight
                )
                maxShift = max(maxShift, oklabDistance(centroids[index], refined))
                centroids[index] = refined
            }

            if maxShift < 0.0005 {
                break
            }
        }

        return centroids
    }

    private static func buildHistogramCandidates(labArray: [Float]) -> [HistogramCandidate] {
        let totalBins = histogramLBins * histogramABins * histogramBBins
        var counts = [Int](repeating: 0, count: totalBins)
        var sumL = [Float](repeating: 0, count: totalBins)
        var sumA = [Float](repeating: 0, count: totalBins)
        var sumB = [Float](repeating: 0, count: totalBins)

        var index = 0
        while index < labArray.count {
            let color = OklabColor(
                L: labArray[index],
                a: labArray[index + 1],
                b: labArray[index + 2]
            )
            let histogramBin = histogramIndex(for: color)
            counts[histogramBin] += 1
            sumL[histogramBin] += color.L
            sumA[histogramBin] += color.a
            sumB[histogramBin] += color.b
            index += 3
        }

        let pointCount = labArray.count / 3
        let minimumWeight = max(4, pointCount / 100_000)
        var candidates: [HistogramCandidate] = []
        candidates.reserveCapacity(totalBins)

        for histogramBin in 0..<totalBins {
            let count = counts[histogramBin]
            guard count >= minimumWeight else { continue }

            let inverseCount = 1 / Float(count)
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(
                        L: sumL[histogramBin] * inverseCount,
                        a: sumA[histogramBin] * inverseCount,
                        b: sumB[histogramBin] * inverseCount
                    ),
                    weight: Float(count)
                )
            )
        }

        if candidates.isEmpty, pointCount > 0 {
            return [
                HistogramCandidate(
                    color: OklabColor(L: labArray[0], a: labArray[1], b: labArray[2]),
                    weight: Float(pointCount)
                )
            ]
        }

        return candidates.sorted(by: histogramCandidateSort)
    }

    private static func buildHistogramCandidates(points: [OklabColor]) -> [HistogramCandidate] {
        let totalBins = histogramLBins * histogramABins * histogramBBins
        var counts = [Int](repeating: 0, count: totalBins)
        var sumL = [Float](repeating: 0, count: totalBins)
        var sumA = [Float](repeating: 0, count: totalBins)
        var sumB = [Float](repeating: 0, count: totalBins)

        for point in points {
            let index = histogramIndex(for: point)
            counts[index] += 1
            sumL[index] += point.L
            sumA[index] += point.a
            sumB[index] += point.b
        }

        let minimumWeight = max(4, points.count / 100_000)
        var candidates: [HistogramCandidate] = []
        candidates.reserveCapacity(totalBins)

        for index in 0..<totalBins {
            let count = counts[index]
            guard count >= minimumWeight else { continue }

            let inverseCount = 1 / Float(count)
            let color = OklabColor(
                L: sumL[index] * inverseCount,
                a: sumA[index] * inverseCount,
                b: sumB[index] * inverseCount
            )
            candidates.append(HistogramCandidate(color: color, weight: Float(count)))
        }

        if candidates.isEmpty {
            return points.prefix(1).map { HistogramCandidate(color: $0, weight: Float(points.count)) }
        }

        return candidates.sorted(by: histogramCandidateSort)
    }

    private static func seededFamilyCentroids(
        candidates: [HistogramCandidate],
        k: Int,
        lWeight: Float
    ) -> [OklabColor] {
        guard !candidates.isEmpty, k > 0 else { return [] }

        let maxWeight = candidates.first?.weight ?? 1
        var centroids = [candidates[0].color]

        while centroids.count < k {
            var bestCandidate: HistogramCandidate?
            var bestScore = -Float.greatestFiniteMagnitude

            for candidate in candidates {
                let minDistance = centroids.reduce(Float.greatestFiniteMagnitude) { best, centroid in
                    min(best, oklabDistanceColorWeighted(candidate.color, centroid, lWeight: lWeight))
                }
                guard minDistance > 0.000001 else { continue }
                let prominence = sqrtf(candidate.weight / maxWeight)
                let score = minDistance * (0.35 + 0.65 * prominence)

                if score > bestScore + 0.000001 ||
                    (abs(score - bestScore) <= 0.000001 && isPreferredHistogramCandidate(candidate, over: bestCandidate)) {
                    bestScore = score
                    bestCandidate = candidate
                }
            }

            guard let selected = bestCandidate else { break }
            centroids.append(selected.color)
        }

        return centroids
    }

    private static func nearestCentroidIndex(
        for point: OklabColor,
        centroids: [OklabColor],
        lWeight: Float
    ) -> Int {
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude

        for (index, centroid) in centroids.enumerated() {
            let distance = oklabDistanceColorWeighted(point, centroid, lWeight: lWeight)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func histogramIndex(for color: OklabColor) -> Int {
        let lIndex = quantizeHistogramComponent(color.L, min: 0, max: 1, bins: histogramLBins)
        let aIndex = quantizeHistogramComponent(color.a, min: histogramAMin, max: histogramAMax, bins: histogramABins)
        let bIndex = quantizeHistogramComponent(color.b, min: histogramBMin, max: histogramBMax, bins: histogramBBins)
        return (lIndex * histogramABins + aIndex) * histogramBBins + bIndex
    }

    private static func quantizeHistogramComponent(
        _ value: Float,
        min: Float,
        max: Float,
        bins: Int
    ) -> Int {
        guard bins > 1 else { return 0 }
        let normalized = (value - min) / (max - min)
        let scaled = Int((normalized * Float(bins)).rounded(.down))
        return Swift.max(0, Swift.min(bins - 1, scaled))
    }

    private static func histogramCandidateSort(
        _ lhs: HistogramCandidate,
        _ rhs: HistogramCandidate
    ) -> Bool {
        if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
        if lhs.color.L != rhs.color.L { return lhs.color.L > rhs.color.L }
        if lhs.color.a != rhs.color.a { return lhs.color.a > rhs.color.a }
        return lhs.color.b > rhs.color.b
    }

    private static func isPreferredHistogramCandidate(
        _ lhs: HistogramCandidate,
        over rhs: HistogramCandidate?
    ) -> Bool {
        guard let rhs else { return true }

        return histogramCandidateSort(lhs, rhs)
    }

    private static func assignFamiliesGPU(
        gpu: MetalContext,
        pixelLabBuffer: MTLBuffer,
        count: Int,
        centroids: [OklabColor],
        lWeight: Float
    ) -> [Int] {
        let flatCentroids = centroids.flatMap { [$0.L, $0.a, $0.b] }
        guard let assignments = gpu.kmeansAssign(
            pixelLabBuffer: pixelLabBuffer,
            count: count,
            centroidLab: flatCentroids,
            k: centroids.count,
            lWeight: lWeight
        ) else {
            return Array(repeating: 0, count: count)
        }

        return assignments.map(Int.init)
    }

    private static func assignFamiliesCPU(
        points: [OklabColor],
        centroids: [OklabColor],
        lWeight: Float
    ) -> [Int] {
        points.map { point in
            var bestIndex = 0
            var bestDistance = Float.greatestFiniteMagnitude
            for (index, centroid) in centroids.enumerated() {
                let distance = oklabDistanceColorWeighted(point, centroid, lWeight: lWeight)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            return bestIndex
        }
    }

    private static func buildLabels(
        points: [OklabColor],
        familyAssignments: [Int],
        familyCount: Int,
        valuesPerFamily: Int,
        thresholds: [Float]
    ) -> [Int32] {
        var labels = [Int32](repeating: 0, count: points.count)
        for i in 0..<points.count {
            let familyIndex = min(max(familyAssignments[i], 0), familyCount - 1)
            let valueIndex = valueBucket(for: points[i].L, thresholds: thresholds)
            labels[i] = Int32(familyIndex * valuesPerFamily + valueIndex)
        }
        return labels
    }

    private static func buildLabels(
        labArray: [Float],
        familyAssignments: [Int],
        familyCount: Int,
        valuesPerFamily: Int,
        thresholds: [Float]
    ) -> [Int32] {
        let pointCount = labArray.count / 3
        var labels = [Int32](repeating: 0, count: pointCount)
        for i in 0..<pointCount {
            let familyIndex = min(max(familyAssignments[i], 0), familyCount - 1)
            let valueIndex = valueBucket(for: labArray[i * 3], thresholds: thresholds)
            labels[i] = Int32(familyIndex * valuesPerFamily + valueIndex)
        }
        return labels
    }

    private static func makeQuantizedCentroids(
        points: [OklabColor],
        labels: [Int32],
        familyCentroids: [OklabColor],
        valuesPerFamily: Int,
        thresholds: [Float]
    ) -> (centroids: [OklabColor], palette: [Color], paletteBands: [Int]) {
        let familyCount = familyCentroids.count
        let labelCount = familyCount * valuesPerFamily

        var luminanceSums = [Float](repeating: 0, count: labelCount)
        var luminanceCounts = [Int](repeating: 0, count: labelCount)

        for i in 0..<points.count {
            let label = Int(labels[i])
            guard label >= 0 && label < labelCount else { continue }
            luminanceSums[label] += points[i].L
            luminanceCounts[label] += 1
        }

        return finalizeQuantizedCentroids(
            luminanceSums: luminanceSums,
            luminanceCounts: luminanceCounts,
            familyCentroids: familyCentroids,
            valuesPerFamily: valuesPerFamily,
            thresholds: thresholds
        )
    }

    private static func makeQuantizedCentroids(
        labArray: [Float],
        labels: [Int32],
        familyCentroids: [OklabColor],
        valuesPerFamily: Int,
        thresholds: [Float]
    ) -> (centroids: [OklabColor], palette: [Color], paletteBands: [Int]) {
        let familyCount = familyCentroids.count
        let labelCount = familyCount * valuesPerFamily

        var luminanceSums = [Float](repeating: 0, count: labelCount)
        var luminanceCounts = [Int](repeating: 0, count: labelCount)

        for i in 0..<labels.count {
            let label = Int(labels[i])
            guard label >= 0 && label < labelCount else { continue }
            luminanceSums[label] += labArray[i * 3]
            luminanceCounts[label] += 1
        }

        return finalizeQuantizedCentroids(
            luminanceSums: luminanceSums,
            luminanceCounts: luminanceCounts,
            familyCentroids: familyCentroids,
            valuesPerFamily: valuesPerFamily,
            thresholds: thresholds
        )
    }

    private static func finalizeQuantizedCentroids(
        luminanceSums: [Float],
        luminanceCounts: [Int],
        familyCentroids: [OklabColor],
        valuesPerFamily: Int,
        thresholds: [Float]
    ) -> (centroids: [OklabColor], palette: [Color], paletteBands: [Int]) {
        var centroids = [OklabColor]()
        var palette = [Color]()
        var paletteBands = [Int]()

        for familyIndex in 0..<familyCentroids.count {
            let familyCentroid = familyCentroids[familyIndex]
            for valueIndex in 0..<valuesPerFamily {
                let label = familyIndex * valuesPerFamily + valueIndex
                let luminance: Float

                if luminanceCounts[label] > 0 {
                    luminance = luminanceSums[label] / Float(luminanceCounts[label])
                } else {
                    luminance = bucketMidpoint(for: valueIndex, thresholds: thresholds)
                }

                let quantized = OklabColor(
                    L: luminance,
                    a: familyCentroid.a,
                    b: familyCentroid.b
                )

                centroids.append(quantized)

                let (r, g, b) = oklabToRGB(quantized)
                palette.append(Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255))
                paletteBands.append(familyIndex)
            }
        }

        return (centroids, palette, paletteBands)
    }

    private static func applyWarmCoolEmphasis(to centroids: [OklabColor], amount: Double) -> [OklabColor] {
        let angle = Float(amount) * Float.pi / 4
        return centroids.map { centroid in
            let radius = sqrtf(centroid.a * centroid.a + centroid.b * centroid.b)
            let theta = atan2f(centroid.b, centroid.a) + angle
            return OklabColor(
                L: centroid.L,
                a: radius * cosf(theta),
                b: radius * sinf(theta)
            )
        }
    }

    private static func normalizedThresholds(_ thresholds: [Double], levels: Int) -> [Float] {
        let expectedCount = max(0, levels - 1)
        guard expectedCount > 0 else { return [] }

        var normalized = thresholds
            .filter { $0 > 0 && $0 < 1 }
            .sorted()

        while normalized.count < expectedCount {
            normalized.append(Double(normalized.count + 1) / Double(expectedCount + 1))
        }

        if normalized.count > expectedCount {
            normalized = Array(normalized.prefix(expectedCount))
        }

        return normalized.sorted().map(Float.init)
    }

    private static func valueBucket(for luminance: Float, thresholds: [Float]) -> Int {
        var bucket = 0
        for threshold in thresholds where luminance >= threshold {
            bucket += 1
        }
        return min(bucket, thresholds.count)
    }

    private static func bucketMidpoint(for valueIndex: Int, thresholds: [Float]) -> Float {
        let lower = valueIndex == 0 ? 0 : thresholds[valueIndex - 1]
        let upper = valueIndex < thresholds.count ? thresholds[valueIndex] : 1
        return (lower + upper) * 0.5
    }
}
