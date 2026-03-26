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
                        let beforeImage = state.originalImage ?? base
                        let afterImage = state.processedImage ?? base
                        CompareSliderView(beforeImage: beforeImage, afterImage: afterImage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ImageCanvasView(showImagePicker: $showImagePicker)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if state.panelCollapsed {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                state.panelCollapsed = false
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 28)
                                .frame(maxHeight: .infinity)
                                .background(Color(white: 0.12))
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .trailing))
                    } else {
                        Divider().background(Color.white.opacity(0.15))
                        ControlPanelView()
                            .frame(width: 284)
                            .transition(.move(edge: .trailing))
                    }
                }
            } else {
                // Portrait: canvas top, panel bottom
                ZStack(alignment: .bottom) {
                    if state.compareMode,
                       let base = state.displayBaseImage {
                        // Determine what to show on the right side
                        let beforeImage = state.originalImage ?? base
                        let afterImage = state.processedImage ?? base
                        CompareSliderView(beforeImage: beforeImage, afterImage: afterImage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ImageCanvasView(showImagePicker: $showImagePicker)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if state.panelCollapsed {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                state.panelCollapsed = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Show Panel")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(white: 0.15).opacity(0.95))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        ControlPanelView()
                            .frame(maxHeight: geo.size.height * 0.46)
                            .transition(.move(edge: .bottom))
                    }
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
