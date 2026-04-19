import SwiftUI

enum StudioCommand: Equatable {
    case openLibrary
    case openSamples
    case exportCurrentView
    case exportPrepSheetPDF
    case exportPrepSheetPNG
    case toggleCompare
    case toggleInspector
    case selectMode(RefPlaneMode)
    case zoomIn
    case zoomOut
    case resetZoom
}

extension Notification.Name {
    static let studioCommand = Notification.Name("Underpaint.StudioCommand")
}

private func postStudioCommand(_ command: StudioCommand) {
    NotificationCenter.default.post(name: .studioCommand, object: command)
}

@main
struct RefPlaneApp: App {
    @State private var unlockManager = UnlockManager()

    init() {
        AppTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(unlockManager)
        }
        .commands {
            CommandMenu("File") {
                Button("Open Photo Library") {
                    postStudioCommand(.openLibrary)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Browse Samples") {
                    postStudioCommand(.openSamples)
                }
            }

            CommandMenu("Export") {
                Button("Current View") {
                    postStudioCommand(.exportCurrentView)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Painter's Kit (PDF)") {
                    postStudioCommand(.exportPrepSheetPDF)
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])

                Button("Painter's Kit (PNG)") {
                    postStudioCommand(.exportPrepSheetPNG)
                }
            }

            CommandMenu("View") {
                Button("Original") {
                    postStudioCommand(.selectMode(.original))
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Tonal") {
                    postStudioCommand(.selectMode(.tonal))
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Value") {
                    postStudioCommand(.selectMode(.value))
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Color") {
                    postStudioCommand(.selectMode(.color))
                }
                .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Button("Compare") {
                    postStudioCommand(.toggleCompare)
                }
                .keyboardShortcut("c", modifiers: [.command])

                Button("Show or Hide Studio") {
                    postStudioCommand(.toggleInspector)
                }
                .keyboardShortcut("i", modifiers: [.command, .control])

                Divider()

                Button("Zoom In") {
                    postStudioCommand(.zoomIn)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Zoom Out") {
                    postStudioCommand(.zoomOut)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Actual Size") {
                    postStudioCommand(.resetZoom)
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}
