import UIKit
import Testing
@testable import Underpaint

// MARK: - UIImage pixel data helpers

@Test
func toPixelDataAndFromPixelDataRoundTrip() {
    // Create a known 2×2 image and verify pixel data survives roundtrip.
    let pixels: [(UInt8, UInt8, UInt8)] = [
        (255, 0, 0), (0, 255, 0),
        (0, 0, 255), (128, 128, 128),
    ]
    let image = TestImageFactory.makeSplitColors(pixels: pixels, width: 2, height: 2)

    guard let (data, w, h) = image.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    #expect(w == 2)
    #expect(h == 2)
    #expect(data.count == 2 * 2 * 4)

    // Verify each pixel (RGBA, A channel is padding)
    #expect(data[0] == 255); #expect(data[1] == 0); #expect(data[2] == 0)      // red
    #expect(data[4] == 0); #expect(data[5] == 255); #expect(data[6] == 0)      // green
    #expect(data[8] == 0); #expect(data[9] == 0); #expect(data[10] == 255)     // blue
    #expect(abs(Int(data[12]) - 128) <= 1)                                       // gray R

    // Roundtrip back to UIImage
    let rebuilt = UIImage.fromPixelData(data, width: w, height: h)
    #expect(rebuilt != nil)
    guard let (data2, w2, h2) = rebuilt?.toPixelData() else {
        Issue.record("roundtrip toPixelData returned nil")
        return
    }
    #expect(w2 == 2)
    #expect(h2 == 2)
    #expect(data2 == data)
}

@Test
func fromPixelDataReturnsNilForEmptyData() {
    let result = UIImage.fromPixelData([], width: 0, height: 0)
    #expect(result == nil)
}

@Test
func toPixelDataReturnsNilForEmptyImage() {
    let empty = UIImage()
    #expect(empty.toPixelData() == nil)
}

@Test
func scaledDownPreservesSmallImage() {
    let small = TestImageFactory.makeSolid(width: 50, height: 30, color: .red)
    let result = small.scaledDown(toMaxDimension: 100)
    // Image is already smaller than max; should be unchanged
    guard let cg = result.cgImage else {
        Issue.record("scaledDown result has no cgImage")
        return
    }
    #expect(cg.width == 50)
    #expect(cg.height == 30)
}

@Test
func scaledDownReducesLargeImage() {
    let large = TestImageFactory.makeSolid(width: 200, height: 100, color: .blue)
    let result = large.scaledDown(toMaxDimension: 50)
    guard let cg = result.cgImage else {
        Issue.record("scaledDown result has no cgImage")
        return
    }
    // Longest dimension (200) should be capped to 50
    #expect(cg.width == 50)
    #expect(cg.height == 25)
}

@Test
func scaledDownMaintainsAspectRatio() {
    let image = TestImageFactory.makeSolid(width: 300, height: 150, color: .green)
    let result = image.scaledDown(toMaxDimension: 100)
    guard let cg = result.cgImage else {
        Issue.record("scaledDown result has no cgImage")
        return
    }
    // 300:150 = 2:1 aspect ratio should be preserved
    let ratio = Double(cg.width) / Double(cg.height)
    #expect(abs(ratio - 2.0) < 0.1)
    #expect(max(cg.width, cg.height) <= 100)
}

@Test
func croppedWithFullRectReturnsFullImage() {
    let image = TestImageFactory.makeSolid(width: 100, height: 100, color: .white)
    let cropped = image.cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
    guard let cg = cropped.cgImage else {
        Issue.record("cropped result has no cgImage")
        return
    }
    #expect(cg.width == 100)
    #expect(cg.height == 100)
}

@Test
func croppedWithHalfRectReturnsHalfImage() {
    let image = TestImageFactory.makeSolid(width: 100, height: 100, color: .white)
    let cropped = image.cropped(to: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
    guard let cg = cropped.cgImage else {
        Issue.record("cropped result has no cgImage")
        return
    }
    #expect(cg.width == 50)
    #expect(cg.height == 50)
}

@Test
func solidColorPixelDataIsUniform() {
    let image = TestImageFactory.makeSolid(width: 4, height: 4, color: .red)
    guard let (pixels, w, h) = image.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    #expect(w == 4)
    #expect(h == 4)

    // Every pixel should be red (255, 0, 0)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i] >= 253)      // R
        #expect(pixels[i + 1] <= 2)    // G
        #expect(pixels[i + 2] <= 2)    // B
    }
}

@Test
func scaledDownAsyncMatchesSyncResult() async {
    let image = TestImageFactory.makeSolid(width: 200, height: 100, color: .blue)
    let syncResult = image.scaledDown(toMaxDimension: 50)
    let asyncResult = await image.scaledDownAsync(toMaxDimension: 50)

    guard let syncCG = syncResult.cgImage, let asyncCG = asyncResult.cgImage else {
        Issue.record("One of the results has no cgImage")
        return
    }
    #expect(syncCG.width == asyncCG.width)
    #expect(syncCG.height == asyncCG.height)
}
