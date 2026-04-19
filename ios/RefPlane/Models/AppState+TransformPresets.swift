import SwiftUI
import os

// MARK: - Transform Preset Management

extension AppState {
    var hasPreviousTransformSnapshot: Bool {
        transform.previousTransformSnapshot != nil
    }

    var shouldShowPreviousSettingsOption: Bool {
        guard let previousTransformSnapshot = transform.previousTransformSnapshot else {
            return true
        }
        return matchingSavedPresetID(for: previousTransformSnapshot) == nil
    }

    var availableTransformPresetSelections: [TransformPresetSelection] {
        var options: [TransformPresetSelection] = []
        if shouldShowPreviousSettingsOption {
            options.append(.previous)
        }
        options.append(.appDefault)
        options.append(contentsOf: transform.savedTransformPresets.map { .saved($0.id) })
        return options
    }

    var selectedTransformPresetLabel: String {
        label(for: transform.selectedTransformPresetSelection)
    }

    func label(for selection: TransformPresetSelection) -> String {
        switch selection {
        case .previous:
            return "Previous Settings"
        case .appDefault:
            return "Default"
        case .saved(let presetID):
            return transform.savedTransformPresets.first(where: { $0.id == presetID })?.name ?? "Saved Settings"
        }
    }

    func saveCurrentTransformPreset(named rawName: String) throws {
        let snapshot = makeTransformationSnapshot()
        let id = try transform.presetManager.savePreset(named: rawName, snapshot: snapshot)
        transform.selectedTransformPresetSelection = .saved(id)
    }

    func renameTransformPreset(id: UUID, to rawName: String) throws {
        try transform.presetManager.renamePreset(id: id, to: rawName)
    }

    func deleteTransformPreset(id: UUID) {
        transform.presetManager.deletePreset(id: id)
    }

    func selectTransformPreset(_ selection: TransformPresetSelection) {
        switch selection {
        case .previous:
            if let previousTransformSnapshot = transform.previousTransformSnapshot {
                applyTransformationSnapshot(previousTransformSnapshot)
            }
        case .appDefault:
            applyTransformationSnapshot(Self.defaultTransformationSnapshot())
        case .saved(let presetID):
            guard let preset = transform.savedTransformPresets.first(where: { $0.id == presetID }) else {
                return
            }
            applyTransformationSnapshot(preset.snapshot)
        }

        transform.selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()
    }

    func suggestedTransformPresetName() -> String {
        var index = 1
        while true {
            let candidate = "Preset \(index)"
            let normalized = normalizedPresetName(candidate)
            if !transform.savedTransformPresets.contains(where: { normalizedPresetName($0.name) == normalized }) {
                return candidate
            }
            index += 1
        }
    }

    func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func makeTransformationSnapshot() -> TransformationSnapshot {
        TransformationSnapshot(
            activeMode: transform.activeMode,
            abstractionStrength: transform.abstractionStrength,
            abstractionMethod: transform.abstractionMethod,
            gridEnabled: transform.gridConfig.enabled,
            gridDivisions: transform.gridConfig.divisions,
            gridShowDiagonals: transform.gridConfig.showDiagonals,
            gridLineStyle: transform.gridConfig.lineStyle,
            gridCustomColor: CodableColor(transform.gridConfig.customColor),
            gridOpacity: transform.gridConfig.opacity,
            grayscaleConversion: transform.valueConfig.grayscaleConversion,
            valueLevels: transform.valueConfig.levels,
            valueThresholds: transform.valueConfig.thresholds,
            valueDistribution: transform.valueConfig.distribution,
            valueQuantizationBias: transform.valueConfig.quantizationBias,
            paletteSelectionEnabled: transform.colorConfig.paletteSelectionEnabled,
            colorLimit: transform.colorConfig.numShades,
            enabledPigmentIDs: transform.colorConfig.enabledPigmentIDs.sorted(),
            paletteSpread: transform.colorConfig.paletteSpread,
            colorQuantizationBias: transform.colorConfig.quantizationBias,
            maxPigmentsPerMix: transform.colorConfig.maxPigmentsPerMix,
            minConcentration: transform.colorConfig.minConcentration,
            depthEnabled: depth.depthConfig.enabled,
            foregroundCutoff: depth.depthConfig.foregroundCutoff,
            backgroundCutoff: depth.depthConfig.backgroundCutoff,
            depthEffectIntensity: depth.depthConfig.effectIntensity,
            backgroundMode: depth.depthConfig.backgroundMode,
            contourEnabled: transform.contourConfig.enabled,
            contourLevels: transform.contourConfig.levels,
            contourLineStyle: transform.contourConfig.lineStyle,
            contourCustomColor: CodableColor(transform.contourConfig.customColor),
            contourOpacity: transform.contourConfig.opacity
        )
    }

    func applyTransformationSnapshot(_ snapshot: TransformationSnapshot) {
        loadTransformationSnapshot(snapshot)
        invalidateFocusIsolation(clearSelection: true)
        updatePreviousTransformSnapshot()

        if transform.abstractionIsEnabled {
            applyAbstraction()
        } else {
            if depth.depthConfig.enabled {
                computeDepthMap()
            }
            triggerProcessing()
        }
    }

    func loadTransformationSnapshot(_ snapshot: TransformationSnapshot) {
        transform.activeMode = snapshot.activeMode
        transform.abstractionStrength = snapshot.abstractionStrength
        transform.abstractionMethod = snapshot.abstractionMethod

        transform.gridConfig = GridConfig(
            enabled: snapshot.gridEnabled,
            divisions: snapshot.gridDivisions,
            showDiagonals: snapshot.gridShowDiagonals,
            lineStyle: snapshot.gridLineStyle,
            customColor: snapshot.gridCustomColor.color,
            opacity: snapshot.gridOpacity
        )

        transform.valueConfig = ValueConfig(
            grayscaleConversion: snapshot.grayscaleConversion,
            levels: snapshot.valueLevels,
            thresholds: snapshot.valueThresholds,
            distribution: snapshot.valueDistribution,
            quantizationBias: snapshot.valueQuantizationBias
        )

        transform.colorConfig = ColorConfig(
            paletteSelectionEnabled: snapshot.paletteSelectionEnabled,
            numShades: snapshot.colorLimit,
            enabledPigmentIDs: Set(snapshot.enabledPigmentIDs),
            paletteSpread: snapshot.paletteSpread,
            quantizationBias: snapshot.colorQuantizationBias,
            maxPigmentsPerMix: snapshot.maxPigmentsPerMix,
            minConcentration: snapshot.minConcentration
        )

        depth.depthConfig = DepthConfig(
            enabled: snapshot.depthEnabled,
            foregroundCutoff: snapshot.foregroundCutoff,
            backgroundCutoff: snapshot.backgroundCutoff,
            effectIntensity: snapshot.depthEffectIntensity,
            backgroundMode: snapshot.backgroundMode
        )

        transform.contourConfig = ContourConfig(
            enabled: snapshot.contourEnabled,
            levels: snapshot.contourLevels,
            lineStyle: snapshot.contourLineStyle,
            customColor: snapshot.contourCustomColor.color,
            opacity: snapshot.contourOpacity
        )
    }

    func canonicalSelectionForCurrentSettings() -> TransformPresetSelection {
        let currentSnapshot = makeTransformationSnapshot()

        if let savedPresetID = matchingSavedPresetID(for: currentSnapshot) {
            return .saved(savedPresetID)
        }

        if currentSnapshot == Self.defaultTransformationSnapshot() {
            return .appDefault
        }

        if shouldShowPreviousSettingsOption {
            return .previous
        }

        return .appDefault
    }

    func matchingSavedPresetID(for snapshot: TransformationSnapshot) -> UUID? {
        transform.savedTransformPresets.first(where: { $0.snapshot == snapshot })?.id
    }

    func updatePreviousTransformSnapshot() {
        transform.selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()

        presetPersistenceTask?.cancel()
        presetPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            self.transform.presetManager.savePreviousSnapshot(self.makeTransformationSnapshot())
            self.persistCurrentSession()
        }
    }

    func restoreInitialTransformSnapshotSelection() {
        guard let previousSnapshot = transform.presetManager.previousSnapshot else {
            transform.selectedTransformPresetSelection = .appDefault
            return
        }

        if let matchingPresetID = matchingSavedPresetID(for: previousSnapshot) {
            transform.selectedTransformPresetSelection = .saved(matchingPresetID)
        } else {
            transform.selectedTransformPresetSelection = .previous
        }
    }

    static func defaultTransformationSnapshot() -> TransformationSnapshot {
        TransformationSnapshot(
            activeMode: .original,
            abstractionStrength: 0.5,
            abstractionMethod: .apisr,
            gridEnabled: false,
            gridDivisions: 4,
            gridShowDiagonals: false,
            gridLineStyle: .autoContrast,
            gridCustomColor: CodableColor(.white),
            gridOpacity: 0.7,
            grayscaleConversion: .none,
            valueLevels: 3,
            valueThresholds: defaultThresholds(for: 3),
            valueDistribution: .even,
            valueQuantizationBias: 0,
            paletteSelectionEnabled: false,
            colorLimit: 24,
            enabledPigmentIDs: SpectralDataStore.essentialPigments.map(\.id).sorted(),
            paletteSpread: 1,
            colorQuantizationBias: 0,
            maxPigmentsPerMix: 3,
            minConcentration: 0.02,
            depthEnabled: false,
            foregroundCutoff: 0.33,
            backgroundCutoff: 0.66,
            depthEffectIntensity: 0.5,
            backgroundMode: .none,
            contourEnabled: false,
            contourLevels: 5,
            contourLineStyle: .autoContrast,
            contourCustomColor: CodableColor(.white),
            contourOpacity: 0.7
        )
    }
}
