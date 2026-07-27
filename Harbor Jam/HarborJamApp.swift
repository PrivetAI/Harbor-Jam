import SwiftUI

final class HarborJamRedirectTracker: NSObject, URLSessionTaskDelegate {
    var resolvedURL: URL?
    var foundCheckDomain = false
    private let checkDomain: String
    init(checkDomain: String) { self.checkDomain = checkDomain }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url?.absoluteString, url.contains(checkDomain) {
            foundCheckDomain = true
        }
        resolvedURL = request.url
        completionHandler(request) // never stop the chain
    }
}

@main
struct HarborJamApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = HJStore()
    @State private var harborJamLinkReady: Bool? = nil
    private let harborJamSourceLink = "https://harborjam.org/"
    private let harborJamCheckDomain = "harborjam.org/privacy-policy"

    var body: some Scene {
        WindowGroup {
            Group {
                if let ready = harborJamLinkReady {
                    if ready {
                        // Fullscreen web panel — frame respects the top safe area.
                        HarborJamWebPanel(urlString: harborJamSourceLink)
                            .edgesIgnoringSafeArea(.bottom)
                            .background(Color.black.ignoresSafeArea())
                    } else {
                        HJRootView()
                            .environmentObject(store)
                    }
                } else {
                    HarborJamLoadingScreen()
                        .onAppear { harborJamCheckLink() }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    store.persist()
                }
            }
        }
    }

    private func harborJamCheckLink() {
        guard let url = URL(string: harborJamSourceLink) else {
            harborJamLinkReady = false
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let tracker = HarborJamRedirectTracker(checkDomain: harborJamCheckDomain)
        let session = URLSession(configuration: .default, delegate: tracker, delegateQueue: nil)
        session.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if tracker.foundCheckDomain {
                    harborJamLinkReady = false; return
                }
                if let finalURL = tracker.resolvedURL?.absoluteString,
                   finalURL.contains(self.harborJamCheckDomain) {
                    harborJamLinkReady = false; return
                }
                if let httpResp = response as? HTTPURLResponse,
                   let respURL = httpResp.url?.absoluteString,
                   respURL.contains(self.harborJamCheckDomain) {
                    harborJamLinkReady = false; return
                }
                if error != nil {
                    harborJamLinkReady = false; return
                }
                harborJamLinkReady = true
            }
        }.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if harborJamLinkReady == nil { harborJamLinkReady = false }
        }
    }
}
