import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var showImagePicker = false

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape / iPad: side by side
                HStack(spacing: 0) {
                    ImageCanvasView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().background(Color.white.opacity(0.15))
                    ControlPanelView(showImagePicker: $showImagePicker)
                        .frame(width: 284)
                }
            } else {
                // Portrait: canvas top, panel bottom
                ZStack(alignment: .bottom) {
                    ImageCanvasView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ControlPanelView(showImagePicker: $showImagePicker)
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
        .sheet(isPresented: $state.showCrop) {
            if let img = state.originalImage {
                CropView(image: img) { crop in
                    state.applyCrop(crop)
                }
            }
        }
        .sheet(isPresented: $state.showCompare) {
            if let base = state.displayBaseImage, let processed = state.processedImage {
                CompareView(beforeImage: base, afterImage: processed)
            } else {
                Text("Process an image first")
                    .foregroundColor(.secondary)
            }
        }
    }
}
