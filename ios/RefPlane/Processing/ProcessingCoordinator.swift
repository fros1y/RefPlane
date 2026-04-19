import Foundation
import Observation

@Observable
@MainActor
final class ProcessingCoordinator {
    enum Intent: Equatable {
        case loadingImage
        case abstraction
        case transform(RefPlaneMode)
        case depthEstimation
        case depthEffects
        case prepSheet(PrepSheetExportFormat)
    }

    @ObservationIgnored var loadingTask: Task<Void, Never>? = nil
    @ObservationIgnored var processingDebounceTask: Task<Void, Never>? = nil
    @ObservationIgnored var processingTask: Task<Void, Never>? = nil
    @ObservationIgnored var abstractionTask: Task<Void, Never>? = nil
    @ObservationIgnored var depthTask: Task<Void, Never>? = nil
    @ObservationIgnored var depthEffectTask: Task<Void, Never>? = nil
    @ObservationIgnored var exportTask: Task<Void, Never>? = nil

    private(set) var currentIntent: Intent? = nil
    private(set) var label: String = "Processing…"
    private(set) var progress: Double = 0
    private(set) var isIndeterminate: Bool = false
    private(set) var isSimplifying: Bool = false

    @ObservationIgnored private var generation = UUID()

    var isProcessing: Bool {
        currentIntent != nil
    }

    @discardableResult
    func start(
        for intent: Intent,
        label: String,
        progress: Double = 0,
        indeterminate: Bool = false,
        isSimplifying: Bool = false
    ) -> UUID {
        generation = UUID()
        currentIntent = intent
        self.label = label
        self.progress = progress
        isIndeterminate = indeterminate
        self.isSimplifying = isSimplifying
        return generation
    }

    func updateProgress(_ value: Double, token: UUID) {
        guard generation == token else { return }
        progress = value
    }

    func updateLabel(_ value: String, token: UUID) {
        guard generation == token else { return }
        label = value
    }

    func updateIndeterminate(_ value: Bool, token: UUID) {
        guard generation == token else { return }
        isIndeterminate = value
    }

    func isCurrent(_ token: UUID) -> Bool {
        generation == token
    }

    func finish(token: UUID? = nil) {
        guard token == nil || token == generation else { return }
        currentIntent = nil
        progress = 0
        label = "Processing…"
        isIndeterminate = false
        isSimplifying = false
    }

    func cancelScheduledProcessing() {
        processingDebounceTask?.cancel()
        processingDebounceTask = nil
        processingTask?.cancel()
        processingTask = nil
    }

    func cancel() {
        loadingTask?.cancel()
        loadingTask = nil
        cancelScheduledProcessing()
        abstractionTask?.cancel()
        abstractionTask = nil
        depthTask?.cancel()
        depthTask = nil
        depthEffectTask?.cancel()
        depthEffectTask = nil
        exportTask?.cancel()
        exportTask = nil
        generation = UUID()
        finish()
    }
}
