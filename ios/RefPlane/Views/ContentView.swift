import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var state = AppState()
    @State private var showImagePicker = false
    @State private var showSamplePicker = false
    @State private var showInspector = false
    @State private var showAbout = false
    @State private var exportItem: ExportItem?
    @State private var exportDocument: ExportImageDocument?
    @State private var showExportFileExporter = false
    @State private var usesSidebarLayout = false  // device landscape: horizontal sidebar
    @State private var usesBottomPanel = false    // device portrait + landscape image: vertical split

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                let showsBottomPanel = !isLandscape && isLandscapeImage
                // On iPad (regular size class) always embed the panel — either as a
                // bottom panel (landscape image in portrait device) or as a sidebar
                // (everything else). This prevents the panel from floating as a sheet.
                let showsSidebar = isLandscape || (horizontalSizeClass == .regular && !showsBottomPanel)

                mainLayout(showsSidebar: showsSidebar, showsBottomPanel: showsBottomPanel, size: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .onAppear {
                        usesSidebarLayout = showsSidebar
                        usesBottomPanel = showsBottomPanel
                        // On iPhone, start with the panel hidden so the canvas
                        // isn't crowded before an image is loaded.
                        if horizontalSizeClass == .compact {
                            state.panelCollapsed = true
                        }
                    }
                    .onChange(of: showsSidebar) { isSidebar in
                        usesSidebarLayout = isSidebar
                        usesBottomPanel = !isSidebar && isLandscapeImage
                        if isSidebar || usesBottomPanel {
                            showInspector = false
                        }
                    }
                    .onChange(of: state.originalImage?.size) { _ in
                        let isLandscape = geo.size.width > geo.size.height
                        let isBottom = !isLandscape && isLandscapeImage
                        let isSidebar = isLandscape || (horizontalSizeClass == .regular && !isBottom)
                        usesSidebarLayout = isSidebar
                        usesBottomPanel = isBottom
                        if isBottom { showInspector = false }
                    }
            }
            .toolbar {
                // Left side: open photo + export (Photos app convention)
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showImagePicker = true
                    } label: {
                        Image(systemName: "photo")
                    }
                    .accessibilityLabel("Open photo")

                    Button {
                        if let image = state.exportCurrentImage() {
                            if prefersDesktopFileExport {
                                exportDocument = ExportImageDocument(image: image)
                                showExportFileExporter = true
                            } else {
                                exportItem = ExportItem(image: image)
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(state.currentDisplayImage == nil)
                    .accessibilityLabel("Export image")
                }

                // Right side: secondary controls
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        state.compareMode.toggle()
                    } label: {
                        Image(systemName: state.compareMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    }
                    .disabled(state.displayBaseImage == nil)
                    .accessibilityLabel(state.compareMode ? "Hide comparison" : "Show comparison")

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
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .environmentObject(state)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                state.loadImage(image)
            }
        }
        .sheet(isPresented: $showSamplePicker) {
            SampleImagePickerView { image in
                state.loadImage(image)
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.image])
        }
        .fileExporter(
            isPresented: $showExportFileExporter,
            document: exportDocument,
            contentType: .png,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                state.errorMessage = error.localizedDescription
            }
            exportDocument = nil
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
    private func mainLayout(showsSidebar: Bool, showsBottomPanel: Bool, size: CGSize) -> some View {
        if showsSidebar {
            // Landscape/iPad: image left, controls right.
            // The handle strip is always visible at the canvas/panel boundary so
            // the user can drag or tap it to reveal/hide the panel — no need to
            // reach for the toolbar button.
            HStack(spacing: 0) {
                canvasArea

                TrailingPanelHandleStrip(collapsed: state.panelCollapsed) {
                    withAnimation(sidebarAnimation) {
                        state.panelCollapsed.toggle()
                    }
                }

                if !state.panelCollapsed {
                    ControlPanelView(
                        presentation: .sidebar,
                        onClose: { state.panelCollapsed = true }
                    )
                    .frame(width: min(max(size.width * 0.32, 300), 360))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(sidebarAnimation, value: state.panelCollapsed)
        } else if showsBottomPanel {
            // Portrait device + landscape image: image on top, controls below.
            // The handle strip is always visible so the interaction point is
            // always at the bottom — not buried in the navigation bar.
            VStack(spacing: 0) {
                canvasArea
                    .frame(height: bottomPanelCanvasHeight(size: size))
                    .clipped()

                BottomPanelHandleStrip(collapsed: state.panelCollapsed) {
                    withAnimation(sidebarAnimation) {
                        state.panelCollapsed.toggle()
                    }
                }

                if !state.panelCollapsed {
                    ControlPanelView(
                        presentation: .bottomPanel,
                        onClose: { state.panelCollapsed = true }
                    )
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(sidebarAnimation, value: state.panelCollapsed)
        } else {
            canvasArea
        }
    }

    /// Fixed height of the always-visible bottom handle strip.
    private let bottomHandleHeight: CGFloat = 52

    /// Height for the image canvas in the vertical split layout.
    /// The handle strip (bottomHandleHeight) is always present and already
    /// accounted for here, so canvas + handle + panel == size.height.
    private func bottomPanelCanvasHeight(size: CGSize) -> CGFloat {
        if state.panelCollapsed {
            // Canvas fills everything except the handle strip.
            return size.height - bottomHandleHeight
        }
        guard let img = state.originalImage ?? state.sourceImage else {
            return size.height - bottomHandleHeight
        }
        let aspect = img.size.width / img.size.height
        let naturalHeight = size.width / aspect
        // Panel content + handle must fit in remaining space (≥ 30% or 280pt).
        let minimumPanelHeight = max(280, size.height * 0.30) + bottomHandleHeight
        return min(naturalHeight, size.height - minimumPanelHeight)
    }

    /// True when the loaded image is wider than it is tall.
    private var isLandscapeImage: Bool {
        guard let img = state.originalImage ?? state.sourceImage else { return false }
        return img.size.width >= img.size.height
    }

    @ViewBuilder
    private var canvasArea: some View {
        if state.compareMode,
           let beforeImage = state.compareBeforeImage,
           let afterImage = state.compareAfterImage {
            CompareSliderView(beforeImage: beforeImage, afterImage: afterImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ImageCanvasView(showImagePicker: $showImagePicker, showSamplePicker: $showSamplePicker)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebarAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.2)
            : .spring(response: 0.3, dampingFraction: 0.85)
    }

    private func toggleInspector() {
        if usesSidebarLayout || usesBottomPanel {
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
        if usesBottomPanel, !state.panelCollapsed {
            return "rectangle.bottomthird.inset.filled"
        }
        return "slider.horizontal.3"
    }

    private var inspectorAccessibilityLabel: String {
        if usesSidebarLayout || usesBottomPanel {
            return state.panelCollapsed ? "Show adjustments" : "Hide adjustments"
        }
        return showInspector ? "Hide adjustments" : "Show adjustments"
    }

    private var exportFilename: String {
        let modeName = state.activeMode.label
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        return "underpaint-\(modeName)"
    }

    private var prefersDesktopFileExport: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        if #available(iOS 14.0, *) {
            ProcessInfo.processInfo.isiOSAppOnMac
        } else {
            false
        }
#endif
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ExportImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    let imageData: Data

    init(image: UIImage) {
        self.imageData = image.pngData() ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.imageData = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: imageData)
    }
}

/// A grab-handle strip that sits between the image canvas and the bottom panel.
/// Always visible — tapping or dragging it toggles the panel so the interaction
/// point stays near the panel, not in the navigation bar.
private struct BottomPanelHandleStrip: View {
    let collapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Pill drag indicator — matches iOS sheet presentation style.
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)

            // Label fades in when collapsed to communicate "tap to expand".
            Label("Adjustments", systemImage: "chevron.up")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .opacity(collapsed ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .top) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    let draggedUp   = value.translation.height < -20
                    let draggedDown = value.translation.height > 20
                    if (collapsed && draggedUp) || (!collapsed && draggedDown) {
                        onToggle()
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(collapsed ? "Show adjustments" : "Hide adjustments")
        .accessibilityAddTraits(.isButton)
    }
}

/// A grab-handle strip that sits between the image canvas and the trailing sidebar.
/// Always visible — tapping or dragging left/right toggles the panel without
/// requiring the user to reach the toolbar button.
private struct TrailingPanelHandleStrip: View {
    let collapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Divider()

            VStack(spacing: 6) {
                // Vertical pill — standard drag-handle indicator.
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 5, height: 36)

                // Chevron fades in when collapsed to hint at the drag direction.
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(collapsed ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .frame(width: 24)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    let draggedLeft  = value.translation.width < -20
                    let draggedRight = value.translation.width > 20
                    if (collapsed && draggedLeft) || (!collapsed && draggedRight) {
                        onToggle()
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(collapsed ? "Show adjustments" : "Hide adjustments")
        .accessibilityAddTraits(.isButton)
    }
}
