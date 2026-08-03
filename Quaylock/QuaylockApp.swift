import SwiftUI

@main
struct QuaylockApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = QLStore()

    var body: some Scene {
        WindowGroup {
            // Straight into the game. There is no launch-time network check and
            // nothing to wait on, so there is no splash either — one was tried
            // and its repeatForever animations kept the removed view alive long
            // enough to swallow taps on the tab bar.
            QLRootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        store.persist()
                    }
                }
        }
    }
}
