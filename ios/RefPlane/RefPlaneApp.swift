import SwiftUI

@main
struct RefPlaneApp: App {
    @State private var unlockManager = UnlockManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(unlockManager)
        }
    }
}
