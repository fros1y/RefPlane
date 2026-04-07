import SwiftUI
import os

// MARK: - Transform Preset Management

extension AppState {
    var hasPreviousTransformSnapshot: Bool {
        previousTransformSnapshot != nil
    }

    var shouldShowPreviousSettingsOption: Bool {
        guard let previousTransformSnapshot else { return true }
        return matchingSavedPresetID(for: previousTransformSnapshot) == nil
    }

    var availableTransformPresetSelections: [TransformPresetSelection] {
        var options: [TransformPresetSelection] = []
        if shouldShowPreviousSettingsOption {
            options.append(.previous)
        }
        options.append(.appDefault)
        options.append(contentsOf: savedTransformPresets.map { .saved($0.id) })
        return options
    }

    var selectedTransformPresetLabel: String {
        label(for: selectedTransformPresetSelection)
    }

    func label(for selection: TransformPresetSelection) -> String {
        switch selection {
        case .previous:
            return "Previous Settings"
        case .appDefault:
            return "Default"
        case .saved(let presetID):
            return savedTransformPresets.first(where: { $0.id == presetID })?.name ?? "Saved Settings"
        }
    }

    func saveCurrentTransformPreset(named rawName: String) throws {
        let snapshot = makeTransformationSnapshot()
        let id = try presetManager.savePreset(named: rawName, snapshot: snapshot)
        selectedTransformPresetSelection = .saved(id)
    }

    func renameTransformPreset(id: UUID, to rawName: String) throws {
        try presetManager.renamePreset(id: id, to: rawName)
    }

    func deleteTransformPreset(id: UUID) {
        presetManager.deletePreset(id: id)
    }

    func selectTransformPreset(_ selection: TransformPresetSelection) {
        switch selection {
        case .previous:
            if let previousTransformSnapshot {
                applyTransformationSnapshot(previousTransformSnapshot)
            }
        case .appDefault:
            applyTransformationSnapshot(Self.defaultTransformationSnapshot())
        case .saved(let presetID):
            guard let preset = savedTransformPresets.first(where: { $0.id == presetID }) else { return }
            applyTransformationSnapshot(preset.snapshot)
        }

        selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()
    }

    func suggestedTransformPresetName() -> String {
        var index = 1
        while true {
            let candidate = "Preset \(index)"
            let normalized = normalizedPresetName(candidate)
            if !savedTransformPresets.contains(where: { normalizedPresetName($0.name) == normalized }) {
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
            activeMode: activeMode,
            abstractionStrength: abstractionStrength,
            abstractionMethod: abstractionMethod,
            gridEnabled: gridConfig.enabled,
            gridDivisions: gridConfig.divisions,
            gridShowDiagonals: gridConfig.showDiagonals,
            gridLineStyle: gridConfig.lineStyle,
            gridCustomColor: CodableColor(gridConfig.customColor),
            gridOpacity: gridConfig.opacity,
            grayscaleConversion: valueConfig.grayscaleConversion,
            valueLevels: valueConfig.levels,
            valueThresholds: valueConfig.thresholds,
            valueDistribution: valueConfig.distribution,
            valueQuantizationBias: valueConfig.quantizationBias,
            paletteSelectionEnabled: colorConfig.paletteSelectionEnabled,
            colorLimit: colorConfig.numShades,
            enabledPigmentIDs: colorConfig.enabledPigmentIDs.sorted(),
            paletteSpread: colorConfig.paletteSpread,
            colorQuantizationBias: colorConfig.quantizationBias,
            maxPigmentsPerMix: colorConfig.maxPigmentsPerMix,
            minConcentration: colorConfig.minConcentration,
            depthEnabled: depthConfig.enabled,
            foregroundCutoff: depthConfig.foregroundCutoff,
            backgroundCutoff: depthConfig.backgroundCutoff,
            depthEffectIntensity: depthConfig.effectIntensity,
            backgroundMode: depthConfig.backgroundMode,
            contourEnabled: contourConfig.enabled,
            contourLevels: contourConfig.levels,
            contourLineStyle: contourConfig.lineStyle,
            contourCustomColor: CodableColor(contourConfig.customColor),
            contourOpacity: contourConfig.opacity
        )
    }

    func applyTransformationSnapshot(_ snapshot: TransformationSnapshot) {
        activeMode = snapshot.activeMode
        abstractionStrength = snapshot.abstractionStrength
        abstractionMethod = snapshot.abstractionMethod

        gridConfig = GridConfig(
            enabled: snapshot.gridEnabled,
            divisions: snapshot.gridDivisions,
            showDiagonals: snapshot.gridShowDiagonals,
            lineStyle: snapshot.gridLineStyle,
            customColor: snapshot.gridCustomColor.color,
            opacity: snapshot.gridOpacity
        )

        valueConfig = ValueConfig(
            grayscaleConversion: snapshot.grayscaleConversion,
            levels: snapshot.valueLevels,
            thresholds: snapshot.valueThresholds,
            distribution: snapshot.valueDistribution,
            quantizationBias: snapshot.valueQuantizationBias
        )

        colorConfig = ColorConfig(
            paletteSelectionEnabled: snapshot.paletteSelectionEnabled,
            numShades: snapshot.colorLimit,
            enabledPigmentIDs: Set(snapshot.enabledPigmentIDs),
            paletteSpread: snapshot.paletteSpread,
            quantizationBias: snapshot.colorQuantizationBias,
            maxPigmentsPerMix: snapshot.maxPigmentsPerMix,
            minConcentration: snapshot.minConcentration
        )

        depthConfig = DepthConfig(
            enabled: snapshot.depthEnabled,
            foregroundCutoff: snapshot.foregroundCutoff,
            backgroundCutoff: snapshot.backgroundCutoff,
            effectIntensity: snapshot.depthEffectIntensity,
            backgroundMode: snapshot.backgroundMode
        )

        contourConfig = ContourConfig(
            enabled: snapshot.contourEnabled,
            levels: snapshot.contourLevels,
            lineStyle: snapshot.contourLineStyle,
            customColor: snapshot.contourCustomColor.color,
            opacity: snapshot.contourOpacity
        )

        invalidateFocusIsolation(clearSelection: true)

        updatePreviousTransformSnapshot()

        if abstractionIsEnabled {
            applyAbstraction()
        } else {
            if depthConfig.enabled {
                computeDepthMap()
            }
            triggerProcessing()
        }
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
        savedTransformPresets.first(where: { $0.snapshot == snapshot })?.id
    }

    func updatePreviousTransformSnapshot() {
        selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()

        presetPersistenceTask?.cancel()
        presetPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            self.presetManager.savePreviousSnapshot(self.makeTransformationSnapshot())
        }
    }





    func restoreInitialTransformSnapshotSelection() {
        guard let prev = presetManager.previousSnapshot else {
            selectedTransformPresetSelection = .appDefault
            return
        }
        if let matchingPresetID = matchingSavedPresetID(for: prev) {
            selectedTransformPresetSelection = .saved(matchingPresetID)
        } else {
            selectedTransformPresetSelection = .previous
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
