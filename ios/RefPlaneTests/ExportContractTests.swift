import UIKit
import Testing
@testable import Underpaint

@MainActor
@Test
func originalModeExportPrefersFullResolutionSource() {
    let fullResolution = TestImageFactory.makeSolid(width: 2400, height: 1200, color: .red)
    let workingCopy = TestImageFactory.makeSolid(width: 1600, height: 800, color: .red)
    let state = AppState()

    state.fullResolutionOriginalImage = fullResolution
    state.originalImage = workingCopy
    state.sourceImage = workingCopy
    state.activeMode = .original

    let exported = state.exportCurrentImage()

    #expect(exported?.size == fullResolution.size)
}
