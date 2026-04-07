import Testing
@testable import Underpaint

// MARK: - MetalError tests

@Test
func metalErrorFunctionNotFoundDescription() {
    let error = MetalError.functionNotFound("test_kernel")
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("test_kernel"))
}

@Test
func metalErrorFunctionNotFoundIncludesName() {
    let error = MetalError.functionNotFound("grayscale")
    #expect(error.errorDescription!.contains("grayscale"))
}

@Test
func metalContextSharedExists() {
    // MetalContext.shared may be nil (simulator) or non-nil (device)
    // This just exercises the lazy initialization path
    let _ = MetalContext.shared
}
