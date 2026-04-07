import SwiftUI

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
    }
}
