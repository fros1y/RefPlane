import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var showImagePicker = false

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape / iPad: side by side
                HStack(spacing: 0) {
                    if state.compareMode,
                       let base = state.displayBaseImage {
                        // Determine what to show on the right side
                        let afterImage = state.processedImage ?? base
                        CompareSliderView(beforeImage: base, afterImage: afterImage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ImageCanvasView(showImagePicker: $showImagePicker)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Divider().background(Color.white.opacity(0.15))
                    ControlPanelView()
                        .frame(width: 284)
                }
            } else {
                // Portrait: canvas top, panel bottom
                ZStack(alignment: .bottom) {
                    if state.compareMode,
                       let base = state.displayBaseImage {
                        // Determine what to show on the right side
                        let afterImage = state.processedImage ?? base
                        CompareSliderView(beforeImage: base, afterImage: afterImage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ImageCanvasView(showImagePicker: $showImagePicker)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    ControlPanelView()
                        .frame(maxHeight: geo.size.height * 0.46)
                }
            }
        }
        .environmentObject(state)
        .background(Color.black)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                state.loadImage(image)
            }
        }
        .overlay(alignment: .top) {
            if let msg = state.errorMessage {
                ErrorToastView(message: msg) {
                    state.errorMessage = nil
                }
                .padding(.top, 8)
            }
        }
    }
}
