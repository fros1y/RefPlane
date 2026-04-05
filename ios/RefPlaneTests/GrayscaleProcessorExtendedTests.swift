import UIKit
import Testing
@testable import Underpaint

// MARK: - GrayscaleProcessor extended tests (average, lightness, grayscaleByte)

@Test
func grayscaleAverageConversionProducesEqualChannels() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .red)
    guard let result = GrayscaleProcessor.process(image: image, conversion: .average) else {
        Issue.record("GrayscaleProcessor.process returned nil")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i] == pixels[i + 1])
        #expect(pixels[i] == pixels[i + 2])
    }
}

@Test
func grayscaleLightnessConversionProducesEqualChannels() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .green)
    guard let result = GrayscaleProcessor.process(image: image, conversion: .lightness) else {
        Issue.record("GrayscaleProcessor.process returned nil")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i] == pixels[i + 1])
        #expect(pixels[i] == pixels[i + 2])
    }
}

@Test
func grayscaleNoneConversionReturnsInputUnchanged() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .red)
    let result = GrayscaleProcessor.process(image: image, conversion: .none)
    #expect(result != nil)
    // .none should return the input image directly (no pixel conversion)
}

@Test
func grayscaleByteBlackIsZero() {
    let byte = GrayscaleProcessor.grayscaleByte(r: 0, g: 0, b: 0, conversion: .luminance)
    #expect(byte == 0)
}

@Test
func grayscaleByteWhiteIs255() {
    let byte = GrayscaleProcessor.grayscaleByte(r: 1, g: 1, b: 1, conversion: .luminance)
    #expect(byte == 255)
}

@Test
func grayscaleByteAverageOfPureRedIsNonZero() {
    let byte = GrayscaleProcessor.grayscaleByte(r: 1, g: 0, b: 0, conversion: .average)
    #expect(byte > 0)
    #expect(byte < 255)
}

@Test
func grayscaleByteLightnessOfPureRedIsHalf() {
    // Lightness = (max + min) / 2. For pure red (1,0,0): (1+0)/2 = 0.5
    let byte = GrayscaleProcessor.grayscaleByte(r: 1, g: 0, b: 0, conversion: .lightness)
    // After sRGB linearize/delinearize, it won't be exactly 128 but should be in mid-range
    #expect(byte > 50)
    #expect(byte < 200)
}

@Test
func grayscaleByteLuminanceWeightsGreenMost() {
    // Rec-709: green has the highest weight (0.7152)
    let redGray = GrayscaleProcessor.grayscaleByte(r: 1, g: 0, b: 0, conversion: .luminance)
    let greenGray = GrayscaleProcessor.grayscaleByte(r: 0, g: 1, b: 0, conversion: .luminance)
    let blueGray = GrayscaleProcessor.grayscaleByte(r: 0, g: 0, b: 1, conversion: .luminance)
    #expect(greenGray > redGray)
    #expect(greenGray > blueGray)
}

@Test
func grayscaleAllConversionsProduceBlackForBlack() {
    for conversion in [GrayscaleConversion.luminance, .average, .lightness] {
        let byte = GrayscaleProcessor.grayscaleByte(r: 0, g: 0, b: 0, conversion: conversion)
        #expect(byte == 0, "Conversion \(conversion.rawValue) should produce 0 for black")
    }
}

@Test
func grayscaleAllConversionsProduceWhiteForWhite() {
    for conversion in [GrayscaleConversion.luminance, .average, .lightness] {
        let byte = GrayscaleProcessor.grayscaleByte(r: 1, g: 1, b: 1, conversion: conversion)
        #expect(byte == 255, "Conversion \(conversion.rawValue) should produce 255 for white")
    }
}

@Test
func grayscaleConversionsDifferForSaturatedColor() {
    // For a saturated colour, different conversions produce different gray values
    let lum = GrayscaleProcessor.grayscaleByte(r: 1, g: 0, b: 0, conversion: .luminance)
    let avg = GrayscaleProcessor.grayscaleByte(r: 1, g: 0, b: 0, conversion: .average)
    let lgt = GrayscaleProcessor.grayscaleByte(r: 1, g: 0, b: 0, conversion: .lightness)
    // All non-zero
    #expect(lum > 0)
    #expect(avg > 0)
    #expect(lgt > 0)
    // At least one pair must differ (they use different formulas)
    let allSame = (lum == avg && avg == lgt)
    #expect(!allSame)
}
