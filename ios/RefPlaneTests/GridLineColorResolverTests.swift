import Testing
@testable import Underpaint

@Test
func autoContrastChoosesTheHigherContrastTone() {
    for percentage in 0...100 {
        let luminance = Double(percentage) / 100.0
        let tone = GridLineColorResolver.autoContrastTone(forAverageLuminance: luminance)
        let blackContrast = GridLineColorResolver.contrastDistance(from: luminance, to: .black)
        let whiteContrast = GridLineColorResolver.contrastDistance(from: luminance, to: .white)

        switch tone {
        case .black:
            #expect(blackContrast >= whiteContrast)
        case .white:
            #expect(whiteContrast >= blackContrast)
        }
    }
}

@Test
func autoContrastDefaultsToWhiteWithoutImageData() {
    #expect(GridLineColorResolver.autoContrastTone(forAverageLuminance: nil) == .white)
}
