import Testing
import TipKit
@testable import Underpaint

@Test
func appTipsShareImageLoadedGate() {
    #expect(AppTips.imageLoaded.id == "image-loaded")
    #expect(SimplificationTip().rules.count == 1)
    #expect(BackgroundDepthTip().rules.count == 1)
    #expect(CompareModeTip().rules.count == 1)
    #expect(PresetsTip().rules.count == 1)
    #expect(ExportTip().rules.count == 1)
    #expect(PaletteSelectionTip().rules.count == 1)
}

@Test
func appTipsAreSingleDisplayInformationalTips() {
    #expect(hasSingleDisplayLimit(SimplificationTip()))
    #expect(hasSingleDisplayLimit(BackgroundDepthTip()))
    #expect(hasSingleDisplayLimit(CompareModeTip()))
    #expect(hasSingleDisplayLimit(PresetsTip()))
    #expect(hasSingleDisplayLimit(ExportTip()))
    #expect(hasSingleDisplayLimit(PaletteSelectionTip()))

    #expect(SimplificationTip().actions.isEmpty)
    #expect(BackgroundDepthTip().actions.isEmpty)
    #expect(CompareModeTip().actions.isEmpty)
    #expect(PresetsTip().actions.isEmpty)
    #expect(ExportTip().actions.isEmpty)
    #expect(PaletteSelectionTip().actions.isEmpty)
}

@Test
func appTipCopyMatchesDesignPlan() {
    #expect(SimplificationTip.titleText == "Simplify Your Reference")
    #expect(SimplificationTip.messageText == "Reduce detail to see the essential shapes and values - useful for blocking in.")

    #expect(BackgroundDepthTip.titleText == "Separate Foreground & Background")
    #expect(BackgroundDepthTip.messageText == "Use AI depth estimation to blur, compress, or remove the background.")

    #expect(CompareModeTip.titleText == "Compare Before & After")
    #expect(CompareModeTip.messageText == "Slide to compare your original image with the current study.")

    #expect(PresetsTip.titleText == "Save Your Settings")
    #expect(PresetsTip.messageText == "Save the current mode and settings as a preset you can reapply to any image.")

    #expect(ExportTip.titleText == "Export Your Study")
    #expect(ExportTip.messageText == "Export the processed image with overlays baked in.")

    #expect(PaletteSelectionTip.titleText == "Match to Real Pigments")
    #expect(PaletteSelectionTip.messageText == "Enable palette selection to decompose colors into paintable pigment recipes.")
}

private func hasSingleDisplayLimit<T: Tip>(_ tip: T) -> Bool {
    tip.options.contains { $0 is Tips.MaxDisplayCount }
}