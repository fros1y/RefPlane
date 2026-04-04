import UIKit
import SwiftUI
import Dispatch

// MARK: - Color study pipeline

enum ColorRegionsProcessor {

    private static let histogramLBins = 12
    private static let histogramABins = 24
    private static let histogramBBins = 24
    private static let histogramAMin: Float = -0.45
    private static let histogramAMax: Float = 0.45
    private static let histogramBMin: Float = -0.45
    private static let histogramBMax: Float = 0.45
    private static let histogramChromaBoost: Float = 2.0

    private struct HistogramCandidate {
        let color: OklabColor
        let weight: Float
    }

    struct Result {
        let image: UIImage
        /// Palette colors grouped by family index.
        let palette: [Color]
        let paletteBands: [Int]
        let pixelBands: [Int]
        /// Oklab centroids for each quantized region (one per palette entry).
        let quantizedCentroids: [OklabColor]
        /// Per-pixel label index into quantizedCentroids.
        let pixelLabels: [Int32]
        
        let pixelLab: [Float]
        let clusterPixelCounts: [Int]
        let clusterSalience: [Float]
    }

    static func process(image: UIImage, config: ColorConfig, minRegionSize: MinRegionSize = .off, overclusterK: Int? = nil) -> Result? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let (pixels, width, height) = image.toPixelData() else { return nil }

        if let gpu = MetalContext.shared,
           let result = processGPU(
               gpu: gpu,
               pixels: pixels,
               width: width,
               height: height,
               config: config,
               minRegionSize: minRegionSize,
               overclusterK: overclusterK
           ) {
            let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[ColorStudy] GPU path in \(String(format: "%.1f", totalMs)) ms")
            return result
        }

        let result = processCPU(
            pixels: pixels,
            width: width,
            height: height,
            config: config,
            minRegionSize: minRegionSize,
            overclusterK: overclusterK
        )
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
        config: ColorConfig,
        minRegionSize: MinRegionSize,
        overclusterK: Int?
    ) -> Result? {
        let total = width * height
        let numShades = overclusterK ?? max(2, config.numShades)
        let luminanceExponent = QuantizationBias.luminanceExponent(
            for: config.quantizationBias
        )

        var stepStart = CFAbsoluteTimeGetCurrent()
        guard let (displayLabArray, srcBuffer, displayLabBuffer) = gpu.rgbToOklab(
            pixels: pixels,
            width: width,
            height: height
        ) else {
            return nil
        }
        let distanceLabArray = applyingLuminanceBias(
            to: displayLabArray,
            exponent: luminanceExponent
        )
        guard let distanceLabBuffer = luminanceExponent == 1
            ? displayLabBuffer
            : gpu.device.makeBuffer(
                bytes: distanceLabArray,
                length: distanceLabArray.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ) else {
            return nil
        }
        print("[ColorStudy][GPU] rgb_to_oklab: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        let centroids: [OklabColor]
        if let gpuCentroids = selectFamilyCentroids(
            gpu: gpu,
            labBuffer: distanceLabBuffer,
            count: total,
            k: numShades,
            lWeight: 0.3,
            spreadBias: Float(config.paletteSpread)
        ) {
            centroids = gpuCentroids
            print("[ColorStudy][GPU] choose_shades: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        } else {
            centroids = selectFamilyCentroids(
                labArray: distanceLabArray,
                k: numShades,
                lWeight: 0.3,
                spreadBias: Float(config.paletteSpread)
            )
            print("[ColorStudy][CPU] choose_shades_fallback: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        }

        return processGPUWithCentroids(
            gpu: gpu,
            displayLabArray: displayLabArray,
            srcBuffer: srcBuffer,
            distanceLabBuffer: distanceLabBuffer,
            width: width,
            height: height,
            numShades: numShades,
            centroids: centroids,
            minRegionFactor: minRegionSize.factor
        )
    }

    private static func processGPUWithCentroids(
        gpu: MetalContext,
        displayLabArray: [Float],
        srcBuffer: MTLBuffer,
        distanceLabBuffer: MTLBuffer,
        width: Int,
        height: Int,
        numShades: Int,
        centroids: [OklabColor],
        minRegionFactor: Double?
    ) -> Result? {
        let total = width * height
        guard !centroids.isEmpty else { return nil }

        var stepStart = CFAbsoluteTimeGetCurrent()
        let flatCentroids = centroids.flatMap { [$0.L, $0.a, $0.b] }
        guard let assignments = gpu.kmeansAssign(
            pixelLabBuffer: distanceLabBuffer,
            count: total,
            centroidLab: flatCentroids,
            k: centroids.count,
            lWeight: 0.3
        ) else {
            return nil
        }
        print("[ColorStudy][GPU] assign_shades: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        var globalLabels = assignments.map { Int32($0) }

        if let factor = minRegionFactor {
            stepStart = CFAbsoluteTimeGetCurrent()
            RegionCleaner.clean(
                labels: &globalLabels,
                width: width,
                height: height,
                minFactor: factor,
                labelCapacity: numShades
            )
            print("[ColorStudy][CPU] region_cleanup: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        }

        stepStart = CFAbsoluteTimeGetCurrent()
        let (quantizedCentroids, clusterPixelCounts) = computeCentroidsAndCounts(
            pixelLab: displayLabArray,
            labels: globalLabels,
            k: numShades
        )
        let clusterSalience = computeSalience(centroids: quantizedCentroids, counts: clusterPixelCounts)
        print("[ColorStudy][CPU] compute_centroids: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        let palette: [Color] = quantizedCentroids.map { c in
            let (r, g, b) = oklabToRGB(c)
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }

        let flatQuantizedCentroids = quantizedCentroids.flatMap { [$0.L, $0.a, $0.b] }
        stepStart = CFAbsoluteTimeGetCurrent()
        guard let outputPixels = gpu.remapByLabel(
            srcBuffer: srcBuffer,
            labels: globalLabels,
            centroids: flatQuantizedCentroids,
            count: total
        ),
        let image = UIImage.fromPixelData(outputPixels, width: width, height: height) else {
            return nil
        }
        print("[ColorStudy][GPU] remap_by_label: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        return Result(
            image: image,
            palette: palette,
            paletteBands: (0..<numShades).map { $0 },
            pixelBands: globalLabels.map { Int($0) },
            quantizedCentroids: quantizedCentroids,
            pixelLabels: globalLabels,
            pixelLab: displayLabArray,
            clusterPixelCounts: clusterPixelCounts,
            clusterSalience: clusterSalience
        )
    }

    // MARK: - CPU path

    private static func processCPU(
        pixels: [UInt8],
        width: Int,
        height: Int,
        config: ColorConfig,
        minRegionSize: MinRegionSize,
        overclusterK: Int?
    ) -> Result? {
        let total = width * height
        let numShades = overclusterK ?? max(2, config.numShades)
        let luminanceExponent = QuantizationBias.luminanceExponent(
            for: config.quantizationBias
        )

        var stepStart = CFAbsoluteTimeGetCurrent()
        var displayPoints = [OklabColor](repeating: OklabColor(L: 0, a: 0, b: 0), count: total)
        var displayLabArray = [Float](repeating: 0, count: total * 3)
        for i in 0..<total {
            let base = i * 4
            let ok = rgbToOklab(r: pixels[base], g: pixels[base + 1], b: pixels[base + 2])
            displayPoints[i] = ok
            displayLabArray[i * 3] = ok.L
            displayLabArray[i * 3 + 1] = ok.a
            displayLabArray[i * 3 + 2] = ok.b
        }
        let distancePoints = applyingLuminanceBias(
            to: displayPoints,
            exponent: luminanceExponent
        )
        print("[ColorStudy][CPU] rgb_to_oklab: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        let centroids = selectFamilyCentroids(
            points: distancePoints,
            k: numShades,
            lWeight: 0.3,
            spreadBias: Float(config.paletteSpread)
        )
        print("[ColorStudy][CPU] choose_shades: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        guard !centroids.isEmpty else { return nil }

        stepStart = CFAbsoluteTimeGetCurrent()
        let assignments = assignFamiliesCPU(
            points: distancePoints,
            centroids: centroids,
            lWeight: 0.3
        )
        print("[ColorStudy][CPU] assign_shades: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        var globalLabels = assignments.map { Int32($0) }

        if let factor = minRegionSize.factor {
            stepStart = CFAbsoluteTimeGetCurrent()
            RegionCleaner.clean(
                labels: &globalLabels,
                width: width,
                height: height,
                minFactor: factor,
                labelCapacity: numShades
            )
            print("[ColorStudy][CPU] region_cleanup: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        }

        stepStart = CFAbsoluteTimeGetCurrent()
        let (quantizedCentroids, clusterPixelCounts) = computeCentroidsAndCounts(
            pixelLab: displayLabArray,
            labels: globalLabels,
            k: numShades
        )
        let clusterSalience = computeSalience(centroids: quantizedCentroids, counts: clusterPixelCounts)
        print("[ColorStudy][CPU] compute_centroids: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        var out = [UInt8](repeating: 255, count: total * 4)
        for i in 0..<total {
            let label = min(max(Int(globalLabels[i]), 0), numShades - 1)
            let (r, g, b) = oklabToRGB(quantizedCentroids[label])
            let base = i * 4
            out[base]     = r
            out[base + 1] = g
            out[base + 2] = b
            out[base + 3] = pixels[base + 3]
        }
        print("[ColorStudy][CPU] remap_pixels: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        guard let image = UIImage.fromPixelData(out, width: width, height: height) else {
            return nil
        }

        let palette: [Color] = quantizedCentroids.map { c in
            let (r, g, b) = oklabToRGB(c)
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }

        return Result(
            image: image,
            palette: palette,
            paletteBands: (0..<numShades).map { $0 },
            pixelBands: globalLabels.map { Int($0) },
            quantizedCentroids: quantizedCentroids,
            pixelLabels: globalLabels,
            pixelLab: displayLabArray,
            clusterPixelCounts: clusterPixelCounts,
            clusterSalience: clusterSalience
        )
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

    private static func applyingLuminanceBias(
        to labArray: [Float],
        exponent: Float
    ) -> [Float] {
        guard abs(exponent - 1) > 0.0001 else { return labArray }

        var transformed = labArray
        var index = 0
        while index < transformed.count {
            let lightness = max(0, min(1, transformed[index]))
            transformed[index] = powf(lightness, exponent)
            index += 3
        }
        return transformed
    }

    private static func applyingLuminanceBias(
        to points: [OklabColor],
        exponent: Float
    ) -> [OklabColor] {
        guard abs(exponent - 1) > 0.0001 else { return points }

        return points.map { point in
            OklabColor(
                L: powf(max(0, min(1, point.L)), exponent),
                a: point.a,
                b: point.b
            )
        }
    }

    private static func selectFamilyCentroids(
        gpu: MetalContext,
        labBuffer: MTLBuffer,
        count: Int,
        k: Int,
        lWeight: Float,
        spreadBias: Float
    ) -> [OklabColor]? {
        guard count > 0, k > 0,
              let histogram = gpu.buildColorHistogram(
                labBuffer: labBuffer,
                count: count,
                lBins: histogramLBins,
                aBins: histogramABins,
                bBins: histogramBBins,
                aMin: histogramAMin,
                aMax: histogramAMax,
                bMin: histogramBMin,
                bMax: histogramBMax
              ) else { return nil }

        let candidates = buildHistogramCandidates(
            counts: histogram.counts,
            sumL: histogram.sumL,
            sumA: histogram.sumA,
            sumB: histogram.sumB
        )
        guard !candidates.isEmpty else { return nil }

        let targetCount = min(k, candidates.count)
        var centroids = seededFamilyCentroids(
            candidates: candidates,
            k: targetCount,
            lWeight: lWeight,
            spreadBias: spreadBias
        )

        for _ in 0..<4 {
            var sums = [(L: Float, a: Float, b: Float, weight: Float)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )

            for candidate in candidates {
                let index = nearestRefinementCentroidIndex(
                    for: candidate.color,
                    centroids: centroids,
                    lWeight: lWeight,
                    spreadBias: spreadBias
                )
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
        labArray: [Float],
        k: Int,
        lWeight: Float,
        spreadBias: Float
    ) -> [OklabColor] {
        guard !labArray.isEmpty, k > 0 else { return [] }

        let candidates = buildHistogramCandidates(labArray: labArray)
        guard !candidates.isEmpty else { return [] }

        let targetCount = min(k, candidates.count)
        var centroids = seededFamilyCentroids(
            candidates: candidates,
            k: targetCount,
            lWeight: lWeight,
            spreadBias: spreadBias
        )

        for _ in 0..<4 {
            var sums = [(L: Float, a: Float, b: Float, weight: Float)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )

            for candidate in candidates {
                let index = nearestRefinementCentroidIndex(
                    for: candidate.color,
                    centroids: centroids,
                    lWeight: lWeight,
                    spreadBias: spreadBias
                )
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
        lWeight: Float,
        spreadBias: Float
    ) -> [OklabColor] {
        guard !points.isEmpty, k > 0 else { return [] }

        let candidates = buildHistogramCandidates(points: points)
        guard !candidates.isEmpty else { return [] }

        let targetCount = min(k, candidates.count)
        var centroids = seededFamilyCentroids(
            candidates: candidates,
            k: targetCount,
            lWeight: lWeight,
            spreadBias: spreadBias
        )

        for _ in 0..<4 {
            var sums = [(L: Float, a: Float, b: Float, weight: Float)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )

            for candidate in candidates {
                let index = nearestRefinementCentroidIndex(
                    for: candidate.color,
                    centroids: centroids,
                    lWeight: lWeight,
                    spreadBias: spreadBias
                )
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
            let avgA = sumA[histogramBin] * inverseCount
            let avgB = sumB[histogramBin] * inverseCount
            let chroma = sqrtf(avgA * avgA + avgB * avgB)
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(
                        L: sumL[histogramBin] * inverseCount,
                        a: avgA,
                        b: avgB
                    ),
                    weight: Float(count) * (1.0 + histogramChromaBoost * chroma)
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
            let avgA = sumA[index] * inverseCount
            let avgB = sumB[index] * inverseCount
            let color = OklabColor(
                L: sumL[index] * inverseCount,
                a: avgA,
                b: avgB
            )
            let chroma = sqrtf(avgA * avgA + avgB * avgB)
            candidates.append(HistogramCandidate(color: color, weight: Float(count) * (1.0 + histogramChromaBoost * chroma)))
        }

        if candidates.isEmpty {
            return points.prefix(1).map { HistogramCandidate(color: $0, weight: Float(points.count)) }
        }

        return candidates.sorted(by: histogramCandidateSort)
    }

    private static func buildHistogramCandidates(
        counts: [UInt32],
        sumL: [UInt32],
        sumA: [UInt32],
        sumB: [UInt32]
    ) -> [HistogramCandidate] {
        let totalBins = histogramLBins * histogramABins * histogramBBins
        guard counts.count == totalBins,
              sumL.count == totalBins,
              sumA.count == totalBins,
              sumB.count == totalBins else { return [] }

        var candidates: [HistogramCandidate] = []
        candidates.reserveCapacity(totalBins)

        let aRange = histogramAMax - histogramAMin
        let bRange = histogramBMax - histogramBMin

        for index in 0..<totalBins {
            let count = counts[index]
            guard count > 0 else { continue }

            let inverseCount = 1 / Float(count)
            let averageL = (Float(sumL[index]) * inverseCount) / 255
            let averageA = histogramAMin + ((Float(sumA[index]) * inverseCount) / 255) * aRange
            let averageB = histogramBMin + ((Float(sumB[index]) * inverseCount) / 255) * bRange

            let chroma = sqrtf(averageA * averageA + averageB * averageB)
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(L: averageL, a: averageA, b: averageB),
                    weight: Float(count) * (1.0 + histogramChromaBoost * chroma)
                )
            )
        }

        return candidates.sorted(by: histogramCandidateSort)
    }

    private static func seededFamilyCentroids(
        candidates: [HistogramCandidate],
        k: Int,
        lWeight: Float,
        spreadBias: Float
    ) -> [OklabColor] {
        guard !candidates.isEmpty, k > 0 else { return [] }

        let clampedSpreadBias = max(0, min(1, spreadBias))
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
                let dominanceFactor = 0.35 + 0.65 * prominence
                let hueCoverage = normalizedHueCoverage(for: candidate.color, against: centroids)
                let biasFactor = ((1 - clampedSpreadBias) * dominanceFactor) + (clampedSpreadBias * hueCoverage)
                let score = minDistance * biasFactor

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

    private static func normalizedHueCoverage(
        for color: OklabColor,
        against centroids: [OklabColor]
    ) -> Float {
        let candidateChroma = sqrtf((color.a * color.a) + (color.b * color.b))
        let chromaStrength = min(1, candidateChroma / 0.14)
        guard chromaStrength > 0.001 else { return 0.2 }

        let candidateHue = atan2f(color.b, color.a)
        var bestHueDistance = Float.pi
        var foundColorfulCentroid = false

        for centroid in centroids {
            let centroidChroma = sqrtf((centroid.a * centroid.a) + (centroid.b * centroid.b))
            guard centroidChroma > 0.02 else { continue }
            foundColorfulCentroid = true

            let centroidHue = atan2f(centroid.b, centroid.a)
            let rawDistance = abs(candidateHue - centroidHue)
            let wrappedDistance = min(rawDistance, (2 * Float.pi) - rawDistance)
            bestHueDistance = min(bestHueDistance, wrappedDistance)
        }

        if !foundColorfulCentroid {
            return 0.7 + (0.3 * chromaStrength)
        }

        let normalizedDistance = bestHueDistance / Float.pi
        return (0.2 + (0.8 * normalizedDistance)) * chromaStrength
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

    private static func nearestRefinementCentroidIndex(
        for point: OklabColor,
        centroids: [OklabColor],
        lWeight: Float,
        spreadBias: Float
    ) -> Int {
        let clampedSpreadBias = max(0, min(1, spreadBias))
        guard clampedSpreadBias > 0.001 else {
            return nearestCentroidIndex(for: point, centroids: centroids, lWeight: lWeight)
        }

        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude

        for (index, centroid) in centroids.enumerated() {
            let baseDistance = oklabDistanceColorWeighted(point, centroid, lWeight: lWeight)
            let huePenalty = refinementHuePenalty(between: point, and: centroid)
            let distance = baseDistance * (1 + (clampedSpreadBias * huePenalty))

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func refinementHuePenalty(
        between lhs: OklabColor,
        and rhs: OklabColor
    ) -> Float {
        let lhsChroma = sqrtf((lhs.a * lhs.a) + (lhs.b * lhs.b))
        let rhsChroma = sqrtf((rhs.a * rhs.a) + (rhs.b * rhs.b))
        let chromaStrength = min(1, min(lhsChroma, rhsChroma) / 0.12)
        guard chromaStrength > 0.001 else { return 0 }

        let lhsHue = atan2f(lhs.b, lhs.a)
        let rhsHue = atan2f(rhs.b, rhs.a)
        let rawDistance = abs(lhsHue - rhsHue)
        let wrappedDistance = min(rawDistance, (2 * Float.pi) - rawDistance)
        let normalizedDistance = wrappedDistance / Float.pi

        return 4 * sqrtf(normalizedDistance) * chromaStrength
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

    private static func workerCount(for pointCount: Int) -> Int {
        let cpuCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let desiredWorkers = max(1, pointCount / 250_000)
        return min(cpuCount, desiredWorkers)
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

    private static func computeCentroids(points: [OklabColor], labels: [Int32], k: Int) -> [OklabColor] {
        var sumL = [Float](repeating: 0, count: k)
        var sumA = [Float](repeating: 0, count: k)
        var sumB = [Float](repeating: 0, count: k)
        var counts = [Int](repeating: 0, count: k)
        for (i, point) in points.enumerated() {
            let label = Int(labels[i])
            guard label >= 0 && label < k else { continue }
            sumL[label] += point.L; sumA[label] += point.a; sumB[label] += point.b
            counts[label] += 1
        }
        return (0..<k).map { j in
            counts[j] > 0
                ? OklabColor(L: sumL[j] / Float(counts[j]), a: sumA[j] / Float(counts[j]), b: sumB[j] / Float(counts[j]))
                : OklabColor(L: 0.5, a: 0, b: 0)
        }
    }

    private static func computeCentroids(labArray: [Float], labels: [Int32], k: Int) -> [OklabColor] {
        var sumL = [Float](repeating: 0, count: k)
        var sumA = [Float](repeating: 0, count: k)
        var sumB = [Float](repeating: 0, count: k)
        var counts = [Int](repeating: 0, count: k)
        for i in 0..<labels.count {
            let label = Int(labels[i])
            guard label >= 0 && label < k else { continue }
            sumL[label] += labArray[i * 3]; sumA[label] += labArray[i * 3 + 1]; sumB[label] += labArray[i * 3 + 2]
            counts[label] += 1
        }
        return (0..<k).map { j in
            counts[j] > 0
                ? OklabColor(L: sumL[j] / Float(counts[j]), a: sumA[j] / Float(counts[j]), b: sumB[j] / Float(counts[j]))
                : OklabColor(L: 0.5, a: 0, b: 0)
        }
    }

    // MARK: - Public Helpers
    
    static func reassignLabels(pixelLab: [Float], centroids: [OklabColor], lWeight: Float) -> [Int32] {
        if let gpu = MetalContext.shared {
            let total = pixelLab.count / 3
            let length = pixelLab.count * MemoryLayout<Float>.stride
            if let pixelLabBuffer = gpu.device.makeBuffer(bytes: pixelLab, length: length, options: .storageModeShared) {
                let flatCentroids = centroids.flatMap { [$0.L, $0.a, $0.b] }
                if let assignments = gpu.kmeansAssign(
                    pixelLabBuffer: pixelLabBuffer,
                    count: total,
                    centroidLab: flatCentroids,
                    k: centroids.count,
                    lWeight: lWeight
                ) {
                    return assignments.map { Int32($0) }
                }
            }
        }
        
        let points = labArrayToColors(pixelLab)
        let labels = assignFamiliesCPU(points: points, centroids: centroids, lWeight: lWeight)
        return labels.map { Int32($0) }
    }

    static func computeCentroidsAndCounts(pixelLab: [Float], labels: [Int32], k: Int) -> (centroids: [OklabColor], counts: [Int]) {
        var sumL = [Float](repeating: 0, count: k)
        var sumA = [Float](repeating: 0, count: k)
        var sumB = [Float](repeating: 0, count: k)
        var counts = [Int](repeating: 0, count: k)
        
        pixelLab.withUnsafeBufferPointer { labPtr in
            labels.withUnsafeBufferPointer { labelPtr in
                for i in 0..<labelPtr.count {
                    let label = Int(labelPtr[i])
                    if label >= 0 && label < k {
                        sumL[label] += labPtr[i * 3]
                        sumA[label] += labPtr[i * 3 + 1]
                        sumB[label] += labPtr[i * 3 + 2]
                        counts[label] += 1
                    }
                }
            }
        }
        
        let centroids = (0..<k).map { j in
            counts[j] > 0
                ? OklabColor(L: sumL[j] / Float(counts[j]), a: sumA[j] / Float(counts[j]), b: sumB[j] / Float(counts[j]))
                : OklabColor(L: 0.5, a: 0, b: 0)
        }
        return (centroids, counts)
    }

    // MARK: - Quantized-centroid fast helpers

    /// Maps each quantized centroid to the nearest recipe centroid.
    /// O(qCount × recipeCount) — typically O(50 × 12): negligible vs O(pixels × k).
    static func assignQuantizedToRecipes(
        quantizedCentroids: [OklabColor],
        recipeCentroids: [OklabColor],
        lWeight: Float
    ) -> [Int32] {
        guard !recipeCentroids.isEmpty else {
            return [Int32](repeating: 0, count: quantizedCentroids.count)
        }
        return quantizedCentroids.map { qc -> Int32 in
            var best: Int32 = 0
            var bestD = Float.greatestFiniteMagnitude
            for (ri, rc) in recipeCentroids.enumerated() {
                let dL = (qc.L - rc.L) * lWeight
                let da = qc.a - rc.a
                let db = qc.b - rc.b
                let d = dL*dL + da*da + db*db
                if d < bestD { bestD = d; best = Int32(ri) }
            }
            return best
        }
    }

    /// Projects per-pixel quantized labels through a centroid→recipe map.
    /// O(pixels) with a single lookup and no arithmetic per pixel.
    static func projectQuantizedLabels(
        pixelQuantizedLabels: [Int32],
        centroidToRecipe: [Int32]
    ) -> [Int32] {
        guard !centroidToRecipe.isEmpty else {
            return [Int32](repeating: 0, count: pixelQuantizedLabels.count)
        }

        return pixelQuantizedLabels.map { label in
            let centroidIndex = Int(label)
            guard centroidToRecipe.indices.contains(centroidIndex) else { return 0 }
            return centroidToRecipe[centroidIndex]
        }
    }

    /// Compute recipe centroids and counts using the small quantized centroid set.
    /// O(qCount) — avoids touching the full per-pixel array.
    static func computeCentroidsAndCountsQuantized(
        quantizedCentroids: [OklabColor],
        quantizedPixelCounts: [Int],
        centroidToRecipe: [Int32],
        recipeCount: Int
    ) -> (centroids: [OklabColor], counts: [Int]) {
        var sumL = [Float](repeating: 0, count: recipeCount)
        var sumA = [Float](repeating: 0, count: recipeCount)
        var sumB = [Float](repeating: 0, count: recipeCount)
        var counts = [Int](repeating: 0, count: recipeCount)
        for qi in 0..<quantizedCentroids.count {
            let ri = Int(centroidToRecipe[qi])
            guard ri >= 0, ri < recipeCount else { continue }
            let pw = quantizedPixelCounts[qi]
            let qc = quantizedCentroids[qi]
            sumL[ri] += qc.L * Float(pw)
            sumA[ri] += qc.a * Float(pw)
            sumB[ri] += qc.b * Float(pw)
            counts[ri] += pw
        }
        let centroids = (0..<recipeCount).map { j -> OklabColor in
            counts[j] > 0
                ? OklabColor(
                    L: sumL[j] / Float(counts[j]),
                    a: sumA[j] / Float(counts[j]),
                    b: sumB[j] / Float(counts[j]))
                : OklabColor(L: 0.5, a: 0, b: 0)
        }
        return (centroids, counts)
    }

    private static func computeSalience(centroids: [OklabColor], counts: [Int]) -> [Float] {
        guard !centroids.isEmpty else { return [] }
        let totalCount = max(1, counts.reduce(0, +))
        var meanL: Float = 0, meanA: Float = 0, meanB: Float = 0
        for (c, count) in zip(centroids, counts) {
            let weight = Float(count) / Float(totalCount)
            meanL += c.L * weight
            meanA += c.a * weight
            meanB += c.b * weight
        }
        let mean = OklabColor(L: meanL, a: meanA, b: meanB)
        
        return centroids.map { c in
            let chroma = sqrtf(c.a * c.a + c.b * c.b)
            let dist = oklabDistance(c, mean)
            // baseline 0.75, boost by chroma (up to 0.75) and distance from mean (up to 0.5)
            let salience = 0.75 + (min(chroma, 0.2) / 0.2) * 0.75 + (min(dist, 0.3) / 0.3) * 0.5
            return min(2.0, max(0.75, salience))
        }
    }
}
