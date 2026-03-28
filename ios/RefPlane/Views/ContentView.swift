import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var state = AppState()
    @State private var showImagePicker = false
    @State private var showInspector = false
    @State private var showAbout = false
    @State private var exportItem: ExportItem?
    @State private var usesSidebarLayout = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let showsSidebar = geo.size.width > geo.size.height

                mainLayout(showsSidebar: showsSidebar, size: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .onAppear {
                        usesSidebarLayout = showsSidebar
                    }
                    .onChange(of: showsSidebar) { isSidebar in
                        usesSidebarLayout = isSidebar
                        if isSidebar {
                            showInspector = false
                        }
                    }
            }
            .navigationTitle("Underpaint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("Open", systemImage: "photo.on.rectangle")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        state.compareMode.toggle()
                    } label: {
                        Image(systemName: state.compareMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    }
                    .disabled(state.displayBaseImage == nil)
                    .accessibilityLabel(state.compareMode ? "Hide comparison" : "Show comparison")

                    Button {
                        if let image = state.exportCurrentImage() {
                            exportItem = ExportItem(image: image)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(state.currentDisplayImage == nil)
                    .accessibilityLabel("Export image")

                    Button {
                        toggleInspector()
                    } label: {
                        Image(systemName: inspectorIconName)
                    }
                    .accessibilityLabel(inspectorAccessibilityLabel)

                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About and privacy")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
        }
        .environmentObject(state)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                state.loadImage(image)
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.image])
        }
        .sheet(isPresented: $showAbout) {
            AboutPrivacyView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInspector) {
            NavigationStack {
                ControlPanelView(
                    presentation: .sheet,
                    onClose: { showInspector = false }
                )
                .environmentObject(state)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Unable to Continue", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    state.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                state.errorMessage = nil
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func mainLayout(showsSidebar: Bool, size: CGSize) -> some View {
        if showsSidebar {
            HStack(spacing: 0) {
                canvasArea

                if !state.panelCollapsed {
                    Divider()
                    ControlPanelView(
                        presentation: .sidebar,
                        onClose: { state.panelCollapsed = true }
                    )
                    .frame(width: min(max(size.width * 0.32, 320), 360))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(sidebarAnimation, value: state.panelCollapsed)
        } else {
            canvasArea
        }
    }

    @ViewBuilder
    private var canvasArea: some View {
        if state.compareMode, let base = state.displayBaseImage {
            let beforeImage = state.originalImage ?? base
            let afterImage = state.processedImage ?? base
            CompareSliderView(beforeImage: beforeImage, afterImage: afterImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ImageCanvasView(showImagePicker: $showImagePicker)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebarAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.2)
            : .spring(response: 0.3, dampingFraction: 0.85)
    }

    private func toggleInspector() {
        if usesSidebarLayout {
            withAnimation(sidebarAnimation) {
                state.panelCollapsed.toggle()
            }
        } else {
            showInspector.toggle()
        }
    }

    private var inspectorIconName: String {
        if usesSidebarLayout, !state.panelCollapsed {
            return "sidebar.trailing"
        }
        return "slider.horizontal.3"
    }

    private var inspectorAccessibilityLabel: String {
        if usesSidebarLayout {
            return state.panelCollapsed ? "Show adjustments" : "Hide adjustments"
        }
        return showInspector ? "Hide adjustments" : "Show adjustments"
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let image: UIImage
}
