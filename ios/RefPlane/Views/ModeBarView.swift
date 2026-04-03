import SwiftUI

struct ModeBarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { state.activeMode },
            set: { state.setMode($0) }
        )) {
            ForEach(RefPlaneMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Study mode")
    }
}
