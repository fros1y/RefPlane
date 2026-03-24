import SwiftUI

struct ModeBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RefPlaneMode.allCases) { mode in
                ModeButton(mode: mode)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.07))
        .cornerRadius(10)
    }
}

private struct ModeButton: View {
    @EnvironmentObject private var state: AppState
    let mode: RefPlaneMode

    var isSelected: Bool { state.activeMode == mode }

    var body: some View {
        Button(action: { state.setMode(mode) }) {
            VStack(spacing: 3) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Text(mode.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.7) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
