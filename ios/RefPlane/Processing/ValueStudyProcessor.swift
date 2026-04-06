import UIKit
import os

// MARK: - Value Study: grayscale → quantize into bands → optional cleanup

enum ValueStudyProcessor {

    private static let logger = AppInstrumentation.logger(category: "Processing.ValueStudy")
    private static let signpostLog = AppInstrumentation.signpostLog(category: "Processing.ValueStudy")

    struct Result {
        let image: UIImage
        /// Grayscale swatch for each level (0 = darkest)
        let levelColors: [UIColor]
        let pixelBands: [Int]
    }

    static func process(image: UIImage, config: ValueConfig, minRegionSize: MinRegionSize = .off) -> Result? {
        AppInstrumentation.measure("ProcessValueStudy", log: signpostLog) {
            guard let (pixels, width, height) = AppInstrumentation.measure("DecodePixels", log: signpostLog, {
                image.toPixelData()
            }) else {
                return nil
            }

            let levels = max(2, min(8, config.levels))
            let thresholds = config.thresholds
            let conversion = config.grayscaleConversion == .none
                ? GrayscaleConversion.luminance
                : config.grayscaleConversion

            if conversion.usesGPUShortcut, let gpu = MetalContext.shared {
                return AppInstrumentation.measure("RunGPUPipeline", log: signpostLog) {
                    processGPU(
                        gpu: gpu,
                        pixels: pixels,
                        width: width,
                        height: height,
                        levels: levels,
                        thresholds: thresholds,
                        minRegionSize: minRegionSize
                    )
                }
            }

            if conversion.usesGPUShortcut {
                logger.notice("Falling back to CPU value-study processing; Metal is unavailable")
            }

            return AppInstrumentation.measure("RunCPUPipeline", log: signpostLog) {
                processCPU(
                    pixels: pixels,
                    width: width,
                    height: height,
                    levels: levels,
                    thresholds: thresholds,
                    minRegionSize: minRegionSize,
                    conversion: conversion
                )
            }
        }
    }

    // MARK: - GPU path

    private static func processGPU(
        gpu: MetalContext, pixels: [UInt8], width: Int, height: Int,
        levels: Int, thresholds: [Double], minRegionSize: MinRegionSize
    ) -> Result? {
        let total = width * height
        let thresholdFloats = thresholds.map { Float($0) }

        guard let (srcBuffer, labelMap) = AppInstrumentation.measure("GPUQuantizeBands", log: signpostLog, {
            gpu.quantize(
                pixels: pixels,
                width: width,
                height: height,
                thresholds: thresholdFloats,
                totalLevels: levels
            )
        }) else {
            logger.notice("GPU quantize failed; falling back to CPU value-study processing")
            return AppInstrumentation.measure("CPUFallbackQuantize", log: signpostLog) {
                processCPU(
                    pixels: pixels,
                    width: width,
                    height: height,
                    levels: levels,
                    thresholds: thresholds,
                    minRegionSize: minRegionSize,
                    conversion: .luminance
                )
            }
        }

        var labels = labelMap

        AppInstrumentation.measure("CleanupRegions", log: signpostLog) {
            if let factor = minRegionSize.factor {
                RegionCleaner.clean(
                    labels: &labels,
                    width: width,
                    height: height,
                    minFactor: factor,
                    labelCapacity: levels
                )
            }
        }

        // Build level colors
        var levelColors: [UIColor] = []
        for lvl in 0..<levels {
            let t: UInt8
            if levels == 1 {
                t = 128
            } else {
                t = UInt8(Int(Float(lvl) / Float(levels - 1) * 255 + 0.5))
            }
            levelColors.append(UIColor(white: CGFloat(t) / 255.0, alpha: 1))
        }

        guard let out = AppInstrumentation.measure("RenderBands", log: signpostLog, {
            gpu.valueRemap(srcBuffer: srcBuffer, labels: labels,
                           count: total, totalLevels: levels)
        }) else {
            return nil
        }

        guard let img = AppInstrumentation.measure("EncodeImage", log: signpostLog, {
            UIImage.fromPixelData(out, width: width, height: height)
        }) else {
            return nil
        }
        return Result(image: img, levelColors: levelColors, pixelBands: labels.map(Int.init))
    }

    // MARK: - CPU fallback

    private static func processCPU(
        pixels: [UInt8], width: Int, height: Int,
        levels: Int, thresholds: [Double], minRegionSize: MinRegionSize,
        conversion: GrayscaleConversion
    ) -> Result? {
        let total = width * height

        let thresholdBytes = thresholds.map { UInt8(max(0, min(255, Int($0 * 255)))) }

        var labelMap = [Int32](repeating: 0, count: total)

        for i in 0..<total {
            let base = i * 4
            let r = Float(pixels[base])     / 255.0
            let g = Float(pixels[base + 1]) / 255.0
            let b = Float(pixels[base + 2]) / 255.0
            let gray = GrayscaleProcessor.grayscaleByte(
                r: r,
                g: g,
                b: b,
                conversion: conversion
            )

            var level = 0
            for t in thresholdBytes { if gray >= t { level += 1 } }
            level = min(level, levels - 1)
            labelMap[i] = Int32(level)
        }

        if let factor = minRegionSize.factor {
            RegionCleaner.clean(
                labels: &labelMap,
                width: width,
                height: height,
                minFactor: factor,
                labelCapacity: levels
            )
        }

        var out = [UInt8](repeating: 255, count: total * 4)
        var levelColors: [UIColor] = []

        for lvl in 0..<levels {
            let t: UInt8
            if levels == 1 {
                t = 128
            } else {
                t = UInt8(Int(Float(lvl) / Float(levels - 1) * 255 + 0.5))
            }
            levelColors.append(UIColor(white: CGFloat(t) / 255.0, alpha: 1))
        }

        for i in 0..<total {
            let base = i * 4
            let level = Int(labelMap[i])
            let t: UInt8
            if levels == 1 {
                t = 128
            } else {
                t = UInt8(Int(Float(level) / Float(levels - 1) * 255 + 0.5))
            }
            out[base]     = t
            out[base + 1] = t
            out[base + 2] = t
            out[base + 3] = pixels[base + 3]
        }

        guard let img = UIImage.fromPixelData(out, width: width, height: height) else { return nil }
        return Result(image: img, levelColors: levelColors, pixelBands: labelMap.map(Int.init))
    }
}
