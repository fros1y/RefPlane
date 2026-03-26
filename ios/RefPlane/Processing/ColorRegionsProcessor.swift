import UIKit
import SwiftUI

// MARK: - Color study pipeline

enum ColorRegionsProcessor {

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

        let points = labArrayToColors(labArray)
        stepStart = CFAbsoluteTimeGetCurrent()
        var familyCentroids = kmeansGPU(gpu: gpu, points: points, pixelLabBuffer: labBuffer, k: colorFamilies, lWeight: 0.08)
        print("[ColorStudy][GPU] kmeans_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

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
            lWeight: 0.08
        )
        print("[ColorStudy][GPU] assign_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

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
            RegionCleaner.clean(labels: &globalLabels, width: width, height: height, minFactor: factor)
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
        var familyCentroids = KMeansClusterer.cluster(points: points, k: colorFamilies, lWeight: 0.08).centroids
        print("[ColorStudy][CPU] kmeans_families: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        if config.warmCoolEmphasis != 0 {
            familyCentroids = applyWarmCoolEmphasis(to: familyCentroids, amount: config.warmCoolEmphasis)
        }

        guard !familyCentroids.isEmpty else { return nil }

        stepStart = CFAbsoluteTimeGetCurrent()
        let assignments = assignFamiliesCPU(points: points, centroids: familyCentroids, lWeight: 0.08)
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
            RegionCleaner.clean(labels: &globalLabels, width: width, height: height, minFactor: factor)
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

    private static func kmeansGPU(
        gpu: MetalContext,
        points: [OklabColor],
        pixelLabBuffer: MTLBuffer,
        k: Int,
        lWeight: Float
    ) -> [OklabColor] {
        guard !points.isEmpty, k > 0 else { return [] }

        let k = min(k, points.count)
        var centroids = KMeansClusterer.forgyInit(points: points, k: k)
        var assignments = [Int](repeating: 0, count: points.count)

        for _ in 0..<8 {
            let flatCentroids = centroids.flatMap { [$0.L, $0.a, $0.b] }
            guard let gpuAssignments = gpu.kmeansAssign(
                pixelLabBuffer: pixelLabBuffer,
                count: points.count,
                centroidLab: flatCentroids,
                k: centroids.count,
                lWeight: lWeight
            ) else {
                return KMeansClusterer.cluster(points: points, k: k, lWeight: lWeight).centroids
            }

            var changed = false
            for i in 0..<points.count {
                let newAssignment = Int(gpuAssignments[i])
                if assignments[i] != newAssignment {
                    assignments[i] = newAssignment
                    changed = true
                }
            }

            var sums = [(L: Float, a: Float, b: Float, count: Int)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )

            for i in 0..<points.count {
                let cluster = assignments[i]
                sums[cluster].L += points[i].L
                sums[cluster].a += points[i].a
                sums[cluster].b += points[i].b
                sums[cluster].count += 1
            }

            var maxShift: Float = 0
            for cluster in 0..<centroids.count {
                if sums[cluster].count > 0 {
                    let n = Float(sums[cluster].count)
                    let newCentroid = OklabColor(
                        L: sums[cluster].L / n,
                        a: sums[cluster].a / n,
                        b: sums[cluster].b / n
                    )
                    maxShift = max(maxShift, oklabDistance(centroids[cluster], newCentroid))
                    centroids[cluster] = newCentroid
                }
            }

            if !changed || maxShift < 0.001 {
                break
            }
        }

        return centroids
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

        var centroids = [OklabColor]()
        var palette = [Color]()
        var paletteBands = [Int]()

        for familyIndex in 0..<familyCount {
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
