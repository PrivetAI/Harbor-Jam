import SwiftUI

@main
struct QuaylockApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = QLStore()
    @State private var showLoading = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                QLRootView()
                    .environmentObject(store)
                if showLoading {
                    QuaylockLoadingScreen()
                        .transition(.opacity)
                }
            }
            .onAppear {
                // Presentation only. There is no launch-time network check and
                // nothing to wait on, so this splash gates nothing — it just
                // covers the first frame while the shift corpus decodes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.easeOut(duration: 0.35)) { showLoading = false }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    store.persist()
                }
            }
        }
    }
}
