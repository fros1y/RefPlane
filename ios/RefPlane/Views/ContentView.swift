import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = AppState()
    @State private var presentedSheet: StudioSheet?
    @State private var exportItem: ExportItem?
    @State private var exportDocument: ExportImageDocument?
    @State private var exportContentType: UTType = .png
    @State private var showExportFileExporter = false
    @State private var isInspectorCollapsed = true
    @State private var didSetInitialInspectorState = false
    @State private var currentWorkspaceLayout: StudioWorkspaceLayout = .drawer
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = workspaceLayout(for: proxy.size)

                ZStack(alignment: .bottomTrailing) {
                    workspaceCanvas(layout: layout)

                    if layout == .drawer {
                        inspectorDrawer(maxHeight: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .onChange(of: proxy.size, initial: true) { _, newSize in
                    synchronizeInspectorState(for: newSize)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(state)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedSheet, content: presentedSheetView)
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.fileURL]) {
                removeTemporaryExport(at: item.fileURL)
            }
        }
        .fileExporter(
            isPresented: $showExportFileExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename,
            onCompletion: handleExportCompletion
        )
        .alert(
            "Unable to Continue",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        state.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                state.errorMessage = nil
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private func workspaceCanvas(layout: StudioWorkspaceLayout) -> some View {
        HStack(spacing: 0) {
            StudioCanvasStage(
                layout: layout,
                isInspectorCollapsed: isInspectorCollapsed,
                onOpenPhoto: openPhotoLibrary,
                onOpenSamples: openSampleLibrary,
                onShowAbout: showAbout,
                onExport: exportImage,
                onToggleInspector: toggleInspector
            )

            if layout == .sidebar {
                if !isInspectorCollapsed {
                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    ControlPanelView(
                        presentation: .sidebar,
                        onExport: exportImage,
                        onClose: collapseInspector
                    )
                    .frame(width: 392)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    sidebarRevealHandle
                }
            }
        }
        .animation(workspaceAnimation, value: isInspectorCollapsed)
    }

    private func inspectorDrawer(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if isInspectorCollapsed {
                collapsedDrawerHandle
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                ControlPanelView(
                    presentation: .bottomPanel,
                    onExport: exportImage,
                    onClose: collapseInspector
                )
                .frame(maxWidth: .infinity)
                .frame(height: min(maxHeight * 0.8, 700))
                .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
                .overlay(alignment: .top) {
                    drawerDragHandle
                        .padding(.top, 10)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(workspaceAnimation, value: isInspectorCollapsed)
    }

    private var sidebarRevealHandle: some View {
        Button(action: expandInspector) {
            VStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                Text("Studio")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show studio controls")
        .accessibilityIdentifier("studio.sidebar-reveal")
    }

    private var collapsedDrawerHandle: some View {
        Button(action: expandInspector) {
            Label("Open Studio", systemImage: "slider.horizontal.3")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show studio controls")
        .accessibilityIdentifier("studio.drawer-reveal")
    }

    private var drawerDragHandle: some View {
        Button(action: collapseInspector) {
            Capsule()
                .fill(.secondary)
                .frame(width: 40, height: 5)
                .frame(width: 80, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide studio controls")
        .accessibilityHidden(true)
        .accessibilityIdentifier("studio.drawer-close")
    }

    @ViewBuilder
    private func presentedSheetView(_ sheet: StudioSheet) -> some View {
        switch sheet {
        case .photoLibrary:
            ImagePickerView(onImageSelected: loadImage)
        case .sampleLibrary:
            SampleImagePickerView(onImageSelected: loadImage)
        case .about:
            AboutPrivacyView()
                .environment(state)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var workspaceAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.2)
            : .spring(response: 0.34, dampingFraction: 0.88)
    }

    private func workspaceLayout(for size: CGSize) -> StudioWorkspaceLayout {
        if size.width >= 700 || size.width >= size.height {
            return .sidebar
        }
        return .drawer
    }

    private func synchronizeInspectorState(for size: CGSize) {
        let layout = workspaceLayout(for: size)
        currentWorkspaceLayout = layout

        guard didSetInitialInspectorState else {
            didSetInitialInspectorState = true
            isInspectorCollapsed = !(layout == .sidebar && size.width >= 700)
            return
        }

        if layout == .sidebar, size.width >= 700, state.currentDisplayImage == nil {
            isInspectorCollapsed = false
        }
    }

    private func toggleInspector() {
        withAnimation(workspaceAnimation) {
            isInspectorCollapsed.toggle()
        }
    }

    private func expandInspector() {
        withAnimation(workspaceAnimation) {
            isInspectorCollapsed = false
        }
    }

    private func collapseInspector() {
        withAnimation(workspaceAnimation) {
            isInspectorCollapsed = true
        }
    }

    @Environment(UnlockManager.self) private var unlockManager

    private func openPhotoLibrary() {
        if unlockManager.isUnlocked {
            presentedSheet = .photoLibrary
        } else {
            showPaywall = true
        }
    }

    private func openSampleLibrary() {
        presentedSheet = .sampleLibrary
    }

    private func showAbout() {
        presentedSheet = .about
    }

    private func loadImage(_ image: UIImage) {
        loadImage(ImportedImagePayload(image: image))
    }

    private func loadImage(_ payload: ImportedImagePayload) {
        state.loadImage(payload)

        if currentWorkspaceLayout == .sidebar {
            isInspectorCollapsed = false
        }
    }

    private func exportImage() {
        guard let exportPayload = state.exportCurrentImagePayload() else { return }
        exportContentType = exportPayload.contentType

        if prefersDesktopFileExport {
            exportDocument = ExportImageDocument(imageData: exportPayload.imageData)
            showExportFileExporter = true
        } else {
            do {
                exportItem = ExportItem(fileURL: try writeTemporaryExport(exportPayload))
            } catch {
                state.errorMessage = error.localizedDescription
            }
        }
    }

    private func writeTemporaryExport(_ payload: ExportedImagePayload) throws -> URL {
        let fileExtension = payload.contentType.preferredFilenameExtension ?? "png"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefPlaneExports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileURL = directory
            .appendingPathComponent("\(exportFilename)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try payload.imageData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func removeTemporaryExport(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        if exportItem?.fileURL == fileURL {
            exportItem = nil
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            state.errorMessage = error.localizedDescription
        }
        exportDocument = nil
        exportContentType = .png
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
        ProcessInfo.processInfo.isiOSAppOnMac
#endif
    }
}

private enum StudioWorkspaceLayout: Equatable {
    case sidebar
    case drawer
}

private enum StudioSheet: String, Identifiable {
    case photoLibrary
    case sampleLibrary
    case about

    var id: String { rawValue }
}

private struct StudioCanvasStage: View {
    @Environment(AppState.self) private var state

    let layout: StudioWorkspaceLayout
    let isInspectorCollapsed: Bool
    let onOpenPhoto: () -> Void
    let onOpenSamples: () -> Void
    let onShowAbout: () -> Void
    let onExport: () -> Void
    let onToggleInspector: () -> Void

    @State private var showImagePicker = false
    @State private var showSamplePicker = false

    var body: some View {
        ZStack {
            StudioCanvasSurface(
                showImagePicker: $showImagePicker,
                showSamplePicker: $showSamplePicker
            )

            VStack(spacing: 16) {
                StudioCanvasChrome(
                    isInspectorCollapsed: isInspectorCollapsed,
                    inspectorIcon: inspectorIconName,
                    onOpenPhoto: onOpenPhoto,
                    onOpenSamples: onOpenSamples,
                    onShowAbout: onShowAbout,
                    onExport: onExport,
                    onToggleInspector: onToggleInspector
                )

                Spacer(minLength: 0)

                if showsModeDock {
                    StudioModeDock()
                        .padding(.bottom, layout == .sidebar ? 0 : 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, canvasBottomPadding)
        }
        .onChange(of: showImagePicker) { _, isPresented in
            if isPresented {
                showImagePicker = false
                onOpenPhoto()
            }
        }
        .onChange(of: showSamplePicker) { _, isPresented in
            if isPresented {
                showSamplePicker = false
                onOpenSamples()
            }
        }
    }

    private var showsModeDock: Bool {
        state.currentDisplayImage != nil && isInspectorCollapsed
    }

    private var canvasBottomPadding: CGFloat {
        guard layout == .drawer else { return 16 }

        if state.currentDisplayImage != nil, isInspectorCollapsed {
            return 84
        }

        return isInspectorCollapsed ? 16 : 20
    }

    private var inspectorIconName: String {
        if layout == .sidebar {
            return isInspectorCollapsed ? "sidebar.trailing" : "sidebar.trailing"
        }
        return isInspectorCollapsed ? "slider.horizontal.3" : "rectangle.bottomthird.inset.filled"
    }
}

private struct StudioCanvasSurface: View {
    @Environment(AppState.self) private var state

    @Binding var showImagePicker: Bool
    @Binding var showSamplePicker: Bool

    var body: some View {
        if state.compareMode,
           let beforeImage = state.compareBeforeImage,
           let afterImage = state.compareAfterImage {
            CompareSliderView(beforeImage: beforeImage, afterImage: afterImage)
        } else {
            ImageCanvasView(
                showImagePicker: $showImagePicker,
                showSamplePicker: $showSamplePicker
            )
        }
    }
}

private struct StudioCanvasChrome: View {
    @Environment(AppState.self) private var state
    @Environment(UnlockManager.self) private var unlockManager

    let isInspectorCollapsed: Bool
    let inspectorIcon: String
    let onOpenPhoto: () -> Void
    let onOpenSamples: () -> Void
    let onShowAbout: () -> Void
    let onExport: () -> Void
    let onToggleInspector: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                chromeButton(
                    title: unlockManager.isUnlocked ? "Library" : "Library (Locked)",
                    systemImage: "photo.on.rectangle",
                    accessibilityID: "chrome.library",
                    showsLockBadge: !unlockManager.isUnlocked,
                    action: onOpenPhoto
                )

                chromeButton(
                    title: "Samples",
                    systemImage: "sparkles.rectangle.stack",
                    accessibilityID: "chrome.samples",
                    action: onOpenSamples
                )
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                chromeButton(
                    title: state.compareMode ? "Hide compare" : "Compare",
                    systemImage: state.compareMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                    isEnabled: state.displayBaseImage != nil,
                    accessibilityID: "chrome.compare",
                    action: toggleCompare
                )

                chromeButton(
                    title: "Export",
                    systemImage: "square.and.arrow.up",
                    isEnabled: state.currentDisplayImage != nil,
                    accessibilityID: "chrome.export",
                    action: onExport
                )

                chromeButton(
                    title: isInspectorCollapsed ? "Show studio" : "Hide studio",
                    systemImage: inspectorIcon,
                    accessibilityID: "chrome.studio",
                    action: onToggleInspector
                )

                chromeButton(
                    title: "About",
                    systemImage: "info.circle",
                    accessibilityID: "chrome.about",
                    action: onShowAbout
                )
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func toggleCompare() {
        state.compareMode.toggle()
    }

    private func chromeButton(
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        accessibilityID: String,
        showsLockBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .overlay(alignment: .bottomTrailing) {
                    if showsLockBadge {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.accentColor, in: Circle())
                            .offset(x: 2, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .white : .white.opacity(0.25))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct StudioModeDock: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RefPlaneMode.allCases) { mode in
                Button {
                    state.setMode(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 15, weight: .semibold))

                        Text(mode.label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(state.activeMode == mode ? Color.black : Color.white.opacity(0.9))
                    .frame(minWidth: 72)
                    .frame(height: 52)
                    .background(modeBackground(isSelected: state.activeMode == mode))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.label) study")
                .accessibilityAddTraits(state.activeMode == mode ? .isSelected : [])
                .accessibilityIdentifier("mode-dock.\(mode.rawValue)")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.mode-dock")
    }

    private func modeBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? Color.white : Color.white.opacity(0.08))
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct ExportImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg, .heic, .heif, .tiff] }

    let imageData: Data

    init(imageData: Data) {
        self.imageData = imageData
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

#Preview("iPhone Drawer") {
    ContentView()
        .environment(UnlockManager())
        .frame(width: 393, height: 852)
}

#Preview("iPad Sidebar") {
    ContentView()
        .environment(UnlockManager())
        .frame(width: 1180, height: 820)
}

#Preview("Large Type") {
    ContentView()
        .environment(UnlockManager())
        .frame(width: 393, height: 852)
        .environment(\.dynamicTypeSize, .accessibility3)
}
