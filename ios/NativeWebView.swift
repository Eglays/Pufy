import SwiftUI
import WebKit

// MARK: - Generic Native Web Engine
// Herhangi bir URL'yi Safari "Ana Ekrana Ekle" (PWA) modu gibi tam ekran yükler
// Kullanım: NativeWebView(urlString: "https://example.com")

struct NativeWebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback         = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor              = .systemBackground
        webView.isOpaque                     = false
        webView.scrollView.bounces           = true
        webView.scrollView.alwaysBounceVertical = true
        webView.allowsBackForwardNavigationGestures = false // PWA hissi

        // iPhone Safari mobil user-agent (PWA modunu açar)
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/17.5 Mobile/15E148 Safari/604.1"

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // URL değiştiyse (farklı native app'a geçilince) yeniden yükle
        guard let currentURL = uiView.url?.absoluteString else { return }
        if !currentURL.hasPrefix(urlString) {
            if let url = URL(string: urlString) {
                uiView.load(URLRequest(url: url))
            }
        }
    }
}

