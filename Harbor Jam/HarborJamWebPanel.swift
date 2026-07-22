import SwiftUI
import WebKit

struct HarborJamWebPanel: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        // Belt-and-suspenders (the frame respecting the top safe area is the real fix).
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.isOpaque = true
        webView.backgroundColor = .black
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    // MUST stay empty — never reload on SwiftUI re-renders.
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
