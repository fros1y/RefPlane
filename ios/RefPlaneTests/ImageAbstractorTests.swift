import Testing
@testable import Underpaint

// MARK: - ImageAbstractor / AbstractionError tests

@Test
func abstractionErrorDescriptionsAreNonEmpty() {
    let modelError = AbstractionError.modelUnavailable(.apisr)
    #expect(modelError.errorDescription != nil)
    #expect(!modelError.errorDescription!.isEmpty)

    let contractError = AbstractionError.unsupportedModelContract(.apisr)
    #expect(contractError.errorDescription != nil)
    #expect(!contractError.errorDescription!.isEmpty)

    let inferenceError = AbstractionError.inferenceFailed(.apisr)
    #expect(inferenceError.errorDescription != nil)
    #expect(!inferenceError.errorDescription!.isEmpty)
}

@Test
func abstractionErrorDescriptionsAreDifferent() {
    let e1 = AbstractionError.modelUnavailable(.apisr).errorDescription!
    let e2 = AbstractionError.unsupportedModelContract(.apisr).errorDescription!
    let e3 = AbstractionError.inferenceFailed(.apisr).errorDescription!
    // Each error should have a distinct message
    #expect(e1 != e2)
    #expect(e2 != e3)
    #expect(e1 != e3)
}

@Test
func clearModelCacheDoesNotCrash() {
    // Simply calling clearModelCache should not throw or crash
    ImageAbstractor.clearModelCache()
}
