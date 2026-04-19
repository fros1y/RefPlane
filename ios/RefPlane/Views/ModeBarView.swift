import SwiftUI

struct ModeBarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { state.transform.activeMode },
            set: { state.selectMode($0) }
        )) {
            ForEach(RefPlaneMode.allCases) { mode in
                Text(mode.label)
                    .tag(mode)
                    .accessibilityIdentifier("inspector-mode.\(mode.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Study mode")
    }
}
