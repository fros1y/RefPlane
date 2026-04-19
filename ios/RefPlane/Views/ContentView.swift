import SwiftUI
import TipKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = AppState()
    @State private var presentedSheet: StudioSheet?
    @State private var exportItem: ExportItem?
    @State private var exportDocument: ExportFileDocument?
    @State private var exportContentType: UTType = .png
    @State private var exportDefaultFilename = "underpaint"
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
                .inspector(
                    isPresented: Binding(
                        get: { currentWorkspaceLayout == .sidebar && !isInspectorCollapsed },
                        set: { isPresented in
                            if currentWorkspaceLayout == .sidebar {
                                isInspectorCollapsed = !isPresented
                            }
                        }
                    )
                ) {
                    if currentWorkspaceLayout == .sidebar {
                        ControlPanelView(
                            presentation: .sidebar,
                            onExport: requestExport,
                            onClose: collapseInspector
                        )
                        .environment(state)
                        .inspectorColumnWidth(392)
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .studioCommand)) { notification in
            guard let command = notification.object as? StudioCommand else { return }
            handleStudioCommand(command)
        }
        .sheet(item: $presentedSheet, content: presentedSheetView)
        .sheet(item: $exportItem) { item in
            ShareSheet(items: item.activityItems) {
                if let temporaryFileURL = item.temporaryFileURL {
                    removeTemporaryExport(at: temporaryFileURL)
                } else {
                    exportItem = nil
                }
            }
        }
        .fileExporter(
            isPresented: $showExportFileExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportDefaultFilename,
            onCompletion: handleExportCompletion
        )
        .alert(
            "Unable to Continue",
            isPresented: Binding(
                get: { state.pipeline.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        state.pipeline.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                state.pipeline.errorMessage = nil
            }
        } message: {
            Text(state.pipeline.errorMessage ?? "")
        }
    }

    private func workspaceCanvas(layout: StudioWorkspaceLayout) -> some View {
        StudioCanvasStage(
            layout: layout,
            isInspectorCollapsed: isInspectorCollapsed,
            onOpenPhoto: openPhotoLibrary,
            onOpenSamples: openSampleLibrary,
            onShowAbout: showAbout,
            onExport: requestExport,
            onToggleInspector: toggleInspector
        )
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
                    onExport: requestExport,
                    onClose: collapseInspector
                )
                .frame(maxWidth: .infinity)
                .frame(height: state.pipeline.isAnySliderActive
                    ? min(maxHeight * 0.25, 180)
                    : min(maxHeight * 0.8, 700))
                .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
                .overlay(alignment: .top) {
                    drawerDragHandle
                        .padding(.top, 10)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: state.pipeline.isAnySliderActive)
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
        .accessibilityIdentifier("studio.drawer-close")
    }

    @ViewBuilder
    private func presentedSheetView(_ sheet: StudioSheet) -> some View {
        switch sheet {
        case .photoLibrary:
            ImagePickerView(onImageSelected: loadImage)
        case .sampleLibrary:
            SampleImagePickerView(onImageSelected: loadImage)
                .environment(state)
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

    private func requestExport(_ action: StudioExportAction) {
        switch action {
        case .currentView:
            exportCurrentView()
        case .prepSheet(let format):
            exportPrepSheet(format: format)
        }
    }

    private func exportCurrentView() {
        guard let exportPayload = state.exportCurrentImagePayload() else { return }
        exportContentType = exportPayload.contentType
        exportDefaultFilename = currentViewExportFilename

        if prefersDesktopFileExport {
            exportDocument = ExportFileDocument(fileData: exportPayload.imageData)
            showExportFileExporter = true
        } else {
            do {
                exportItem = try makeShareExportItem(
                    data: exportPayload.imageData,
                    contentType: exportPayload.contentType,
                    defaultFilename: currentViewExportFilename
                )
            } catch {
                state.pipeline.errorMessage = error.localizedDescription
            }
        }
    }

    private func exportPrepSheet(format: PrepSheetExportFormat) {
        Task {
            do {
                let payload = try await state.exportPrepSheetPayload(format: format)
                exportContentType = payload.contentType
                exportDefaultFilename = payload.defaultFilename

                if prefersDesktopFileExport {
                    exportDocument = ExportFileDocument(fileData: payload.data)
                    showExportFileExporter = true
                } else {
                    exportItem = try makeShareExportItem(
                        data: payload.data,
                        contentType: payload.contentType,
                        defaultFilename: payload.defaultFilename
                    )
                }
            } catch {
                state.pipeline.errorMessage = error.localizedDescription
            }
        }
    }

    private func makeShareExportItem(
        data: Data,
        contentType: UTType,
        defaultFilename: String
    ) throws -> ExportItem {
        let fileURL = try writeTemporaryExport(
            data: data,
            contentType: contentType,
            defaultFilename: defaultFilename
        )
        let subject = fileURL.lastPathComponent

        return ExportItem(
            activityItems: [
                ExportFileActivityItemSource(fileURL: fileURL, subject: subject)
            ],
            temporaryFileURL: fileURL
        )
    }

    private func writeTemporaryExport(
        data: Data,
        contentType: UTType,
        defaultFilename: String
    ) throws -> URL {
        let fileExtension = contentType.preferredFilenameExtension ?? "png"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnderpaintExports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileURL = directory
            .appendingPathComponent("\(defaultFilename)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func removeTemporaryExport(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        if exportItem?.temporaryFileURL == fileURL {
            exportItem = nil
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            state.pipeline.errorMessage = error.localizedDescription
        }
        exportDocument = nil
        exportContentType = .png
        exportDefaultFilename = "underpaint"
    }

    private var currentViewExportFilename: String {
        let modeName = state.transform.activeMode.label
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

    private func handleStudioCommand(_ command: StudioCommand) {
        switch command {
        case .openLibrary:
            openPhotoLibrary()
        case .openSamples:
            openSampleLibrary()
        case .exportCurrentView:
            requestExport(.currentView)
        case .exportPrepSheetPDF:
            requestExport(.prepSheet(.pdf))
        case .exportPrepSheetPNG:
            requestExport(.prepSheet(.png))
        case .toggleCompare:
            state.pipeline.compareMode.toggle()
        case .toggleInspector:
            toggleInspector()
        case .selectMode(let mode):
            state.selectMode(mode)
        case .zoomIn, .zoomOut, .resetZoom:
            break
        }
    }
}

private enum StudioWorkspaceLayout: Equatable {
    case sidebar
    case drawer
}

enum StudioExportAction: Equatable {
    case currentView
    case prepSheet(PrepSheetExportFormat)
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
    let onExport: (StudioExportAction) -> Void
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
            return isInspectorCollapsed ? "sidebar.trailing" : "rectangle.righthalf.inset.filled"
        }
        return isInspectorCollapsed ? "slider.horizontal.3" : "rectangle.bottomthird.inset.filled"
    }
}

private struct StudioCanvasSurface: View {
    @Environment(AppState.self) private var state

    @Binding var showImagePicker: Bool
    @Binding var showSamplePicker: Bool

    var body: some View {
        if state.pipeline.compareMode,
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
    let onExport: (StudioExportAction) -> Void
    let onToggleInspector: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                chromeButton(
                    title: unlockManager.isUnlocked ? "Library" : "Library (Locked)",
                    systemImage: "photo.on.rectangle",
                    accessibilityID: "chrome.library",
                    showsLockBadge: !unlockManager.isUnlocked,
                    shortcut: KeyboardShortcut("n", modifiers: [.command]),
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
                    title: state.pipeline.compareMode ? "Hide compare" : "Compare",
                    systemImage: state.pipeline.compareMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                    isEnabled: state.displayBaseImage != nil,
                    accessibilityID: "chrome.compare",
                    shortcut: KeyboardShortcut("c", modifiers: [.command]),
                    action: toggleCompare
                )
                .popoverTip(CompareModeTip(), arrowEdge: .top)

                exportMenuButton
                .popoverTip(ExportTip(), arrowEdge: .top)

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
        state.pipeline.compareMode.toggle()
    }

    private var exportMenuButton: some View {
        Menu {
            Button("Current View") {
                onExport(.currentView)
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Painter's Kit (PDF)") {
                onExport(.prepSheet(.pdf))
            }
            .keyboardShortcut("E", modifiers: [.command, .shift])

            Button("Painter's Kit (PNG)") {
                onExport(.prepSheet(.png))
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.currentDisplayImage != nil ? .white : .white.opacity(0.25))
        .disabled(state.currentDisplayImage == nil)
        .accessibilityLabel("Export")
        .accessibilityIdentifier("chrome.export")
    }

    private func chromeButton(
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        accessibilityID: String,
        showsLockBadge: Bool = false,
        shortcut: KeyboardShortcut? = nil,
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
        .modifier(ConditionalKeyboardShortcut(shortcut: shortcut))
    }
}

private struct StudioModeDock: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RefPlaneMode.allCases) { mode in
                Button {
                    state.selectMode(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 15, weight: .semibold))

                        Text(mode.label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(state.transform.activeMode == mode ? Color.black : Color.white.opacity(0.9))
                    .frame(minWidth: 72)
                    .frame(height: 52)
                    .background(modeBackground(isSelected: state.transform.activeMode == mode))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(shortcut(for: mode), modifiers: [.command])
                .accessibilityLabel("\(mode.label) study")
                .accessibilityAddTraits(state.transform.activeMode == mode ? .isSelected : [])
                .accessibilityIdentifier("mode-dock.\(mode.rawValue)")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .popoverTip(ModeDockTip(), arrowEdge: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.mode-dock")
    }

    private func modeBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? Color.white : Color.white.opacity(0.08))
    }

    private func shortcut(for mode: RefPlaneMode) -> KeyEquivalent {
        switch mode {
        case .original:
            return "1"
        case .tonal:
            return "2"
        case .value:
            return "3"
        case .color:
            return "4"
        }
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let activityItems: [Any]
    let temporaryFileURL: URL?
}

private struct ConditionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

private struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg, .heic, .heif, .tiff, .pdf] }

    let fileData: Data

    init(fileData: Data) {
        self.fileData = fileData
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.fileData = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: fileData)
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
