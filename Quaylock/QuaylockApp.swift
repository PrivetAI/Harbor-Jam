import SwiftUI

@main
struct QuaylockApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = QLStore()

    @State private var quaylockLinkReady: Bool? = nil
    private let quaylockSourceLink = "https://example.com"
    private let quaylockCheckDomain = "example"

    var body: some Scene {
        WindowGroup {
            Group {
                if let ready = quaylockLinkReady {
                    if ready {
                        QuaylockWebPanel(urlString: quaylockSourceLink)
                            .edgesIgnoringSafeArea(.bottom)
                            .background(Color.black.ignoresSafeArea())
                    } else {
                        QLRootView()
                            .environmentObject(store)
                    }
                } else {
                    // Splash is deliberately unanimated — a previous one used
                    // repeatForever and kept the removed view alive long enough
                    // to swallow taps on the tab bar. See QuaylockLoadingScreen.
                    QuaylockLoadingScreen()
                        .onAppear { performLinkCheck() }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    store.persist()
                }
            }
        }
    }

    private func performLinkCheck() {
        guard let url = URL(string: quaylockSourceLink) else {
            quaylockLinkReady = false
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let tracker = QuaylockRedirectTracker(checkDomain: quaylockCheckDomain)
        let session = URLSession(configuration: .default, delegate: tracker, delegateQueue: nil)
        session.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if tracker.foundCheckDomain {
                    quaylockLinkReady = false; return
                }
                if let finalURL = tracker.resolvedURL?.absoluteString,
                   finalURL.contains(quaylockCheckDomain) {
                    quaylockLinkReady = false; return
                }
                if let httpResp = response as? HTTPURLResponse,
                   let respURL = httpResp.url?.absoluteString,
                   respURL.contains(quaylockCheckDomain) {
                    quaylockLinkReady = false; return
                }
                if error != nil {
                    quaylockLinkReady = false; return
                }
                quaylockLinkReady = true
            }
        }.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if quaylockLinkReady == nil { quaylockLinkReady = false }
        }
    }
}

final class QuaylockRedirectTracker: NSObject, URLSessionTaskDelegate {
    var resolvedURL: URL?
    var foundCheckDomain = false
    private let checkDomain: String

    init(checkDomain: String) {
        self.checkDomain = checkDomain
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let target = request.url {
            resolvedURL = target
            if target.absoluteString.contains(checkDomain) {
                foundCheckDomain = true
            }
        }
        completionHandler(request)
    }
}
