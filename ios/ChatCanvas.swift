import SwiftUI
import WebKit

// MARK: - Ortak WKProcessPool
private enum ChatCanvasWKProcessPool {
    static let shared = WKProcessPool()
}

// MARK: - Yükseklik Önbelleği
final class ChatCanvasHeightCache {
    static let shared = ChatCanvasHeightCache()
    private var storage: [UUID: CGFloat] = [:]
    private let lock = NSLock()

    private init() {}

    func height(for id: UUID) -> CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    func setHeight(_ height: CGFloat, for id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        storage[id] = height
    }
}

// MARK: - HTML İskeleti Üretici
enum ChatCanvasHTMLBuilder {
    static let csp = "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src https: data:; font-src data:; media-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"

    static let baseStyles = "html,body{margin:0;padding:0;background:transparent !important;overflow:hidden} body{padding:16px;-webkit-text-size-adjust:100%} *{box-sizing:border-box;max-width:100%}"

    static let bridgeScript = """
    (function() {
      window.pufy = {
        send: function(text) {
          if (typeof text !== 'string') return;
          var clean = text.trim().slice(0, 500);
          if (!clean) return;
          try {
            window.webkit.messageHandlers.pufyCanvas.postMessage({ action: 'send', text: clean });
          } catch (e) {}
        },
        haptic: function() {
          try {
            window.webkit.messageHandlers.pufyCanvas.postMessage({ action: 'haptic' });
          } catch (e) {}
        },
        open: function(url) {
          if (typeof url !== 'string') return;
          try {
            window.webkit.messageHandlers.pufyCanvas.postMessage({ action: 'open', url: url });
          } catch (e) {}
        }
      };

      function updateHeight() {
        try {
          var doc = document.documentElement;
          var body = document.body;
          var h = Math.max(
            doc ? doc.scrollHeight : 0,
            doc ? doc.offsetHeight : 0,
            body ? body.scrollHeight : 0,
            body ? body.offsetHeight : 0
          );
          if (h > 640) {
            if (doc) doc.style.overflowY = 'auto';
            if (body) body.style.overflowY = 'auto';
          }
          window.webkit.messageHandlers.pufyCanvas.postMessage({ action: 'height', height: h });
        } catch (e) {}
      }

      if (window.ResizeObserver) {
        var ro = new ResizeObserver(function() { updateHeight(); });
        if (document.documentElement) ro.observe(document.documentElement);
        if (document.body) ro.observe(document.body);
      }
      window.addEventListener('load', updateHeight);
      window.addEventListener('resize', updateHeight);
      setTimeout(updateHeight, 30);
      setTimeout(updateHeight, 150);
    })();
    """

    static func build(bodyHTML: String) -> String {
        return """
        <!doctype html><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <style>
        \(PufyUIKit.css)
        \(baseStyles)
        </style>
        <script>
        \(bridgeScript)
        </script>
        \(bodyHTML)
        """
    }
}

// MARK: - Script Message Handler
private final class ChatCanvasScriptHandler: NSObject, WKScriptMessageHandler {
    weak var coordinator: ChatCanvasRepresentable.Coordinator?

    init(coordinator: ChatCanvasRepresentable.Coordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "height":
            if let h = body["height"] as? Double {
                coordinator?.handleHeight(CGFloat(h))
            }
        case "send":
            if let text = body["text"] as? String {
                coordinator?.handleSend(text)
            }
        case "haptic":
            coordinator?.handleHaptic()
        case "open":
            if let urlStr = body["url"] as? String {
                coordinator?.handleOpenURL(urlStr)
            }
        default:
            break
        }
    }
}

// MARK: - UIViewRepresentable WKWebView
struct ChatCanvasRepresentable: UIViewRepresentable {
    let html: String
    let messageID: UUID
    let colorScheme: ColorScheme
    let effectiveHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onSend: (String) -> Void
    let onHaptic: () -> Void
    let onOpenURL: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = ChatCanvasWKProcessPool.shared
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = false

        let controller = WKUserContentController()
        let handler = ChatCanvasScriptHandler(coordinator: context.coordinator)
        controller.add(handler, name: "pufyCanvas")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = false
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        let fullHTML = ChatCanvasHTMLBuilder.build(bodyHTML: html)
        webView.loadHTMLString(fullHTML, baseURL: nil)

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self

        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if uiView.overrideUserInterfaceStyle != style {
            uiView.overrideUserInterfaceStyle = style
        }

        let shouldScroll = effectiveHeight >= 640
        if uiView.scrollView.isScrollEnabled != shouldScroll {
            uiView.scrollView.isScrollEnabled = shouldScroll
            uiView.scrollView.bounces = shouldScroll
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: ChatCanvasRepresentable
        weak var webView: WKWebView?

        init(parent: ChatCanvasRepresentable) {
            self.parent = parent
        }

        func handleHeight(_ height: CGFloat) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onHeightChange(height)
            }
        }

        func handleSend(_ text: String) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSend(text)
            }
        }

        func handleHaptic() {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onHaptic()
            }
        }

        func handleOpenURL(_ urlString: String) {
            guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.onOpenURL(url)
            }
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // İlk sayfa yüklemesine izin ver
            if navigationAction.navigationType == .other && (navigationAction.request.url == nil || navigationAction.request.url?.absoluteString == "about:blank") {
                decisionHandler(.allow)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true && navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }
            // https bağlantıları Safari'de aç
            if let url = navigationAction.request.url, url.scheme?.lowercased() == "https" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        // MARK: WKUIDelegate
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // window.open engelle, https ise Safari'de aç
            if let url = navigationAction.request.url, url.scheme?.lowercased() == "https" {
                UIApplication.shared.open(url)
            }
            return nil
        }
    }
}

// MARK: - ChatCanvasCard
struct ChatCanvasCard: View {
    let canvasHTML: String
    let messageID: UUID

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pufyChatAction) private var sendToChat
    @State private var measuredHeight: CGFloat

    init(canvasHTML: String, messageID: UUID) {
        self.canvasHTML = canvasHTML
        self.messageID = messageID
        _measuredHeight = State(initialValue: ChatCanvasHeightCache.shared.height(for: messageID) ?? 0)
    }

    private var effectiveHeight: CGFloat {
        min(measuredHeight, 640)
    }

    var body: some View {
        Group {
            if measuredHeight > 0 {
                ChatCanvasRepresentable(
                    html: canvasHTML,
                    messageID: messageID,
                    colorScheme: colorScheme,
                    effectiveHeight: effectiveHeight,
                    onHeightChange: { newHeight in
                        guard newHeight > 0, abs(newHeight - measuredHeight) > 1 else { return }
                        ChatCanvasHeightCache.shared.setHeight(newHeight, for: messageID)
                        withAnimation(SmoothSpring.standard) {
                            measuredHeight = newHeight
                        }
                    },
                    onSend: { text in
                        sendToChat?(text)
                    },
                    onHaptic: {
                        PremiumHaptics.light()
                    },
                    onOpenURL: { url in
                        if url.scheme?.lowercased() == "https" {
                            UIApplication.shared.open(url)
                        }
                    }
                )
                .frame(height: effectiveHeight)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            } else {
                // İlk yükseklik ölçümü için görünmez render
                ChatCanvasRepresentable(
                    html: canvasHTML,
                    messageID: messageID,
                    colorScheme: colorScheme,
                    effectiveHeight: 0,
                    onHeightChange: { newHeight in
                        guard newHeight > 0 else { return }
                        ChatCanvasHeightCache.shared.setHeight(newHeight, for: messageID)
                        withAnimation(SmoothSpring.standard) {
                            measuredHeight = newHeight
                        }
                    },
                    onSend: { text in sendToChat?(text) },
                    onHaptic: { PremiumHaptics.light() },
                    onOpenURL: { url in
                        if url.scheme?.lowercased() == "https" { UIApplication.shared.open(url) }
                    }
                )
                .frame(height: 1)
                .opacity(0.001)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func canvasPulseSymbol() -> some View {
        if #available(iOS 17, *) {
            self.symbolEffect(.pulse)
        } else {
            self
        }
    }
}

// MARK: - ChatCanvasPlaceholderCard
struct ChatCanvasPlaceholderCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.pufySoft)
                Image(systemName: "macwindow")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .canvasPulseSymbol()
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                ShimmerText(text: String(localized: "Arayüz hazırlanıyor…"), font: .subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Önizleme (#Preview)
#Preview("Aydınlık") {
    let sampleHTML = """
    <div class="p-stack">
      <div class="p-hstack">
        <div class="p-title">Dinamik Arayüz</div>
        <div class="p-spacer"></div>
        <span class="p-badge">Canlı</span>
      </div>
      <div class="p-card">
        <div class="p-subtitle">Pufy UI Kit bileşenleri ile esnek içerik</div>
        <div class="p-divider"></div>
        <div class="p-hstack">
          <button class="p-btn small" onclick="pufy.haptic(); pufy.send('Detaylı bilgi ver')">Detaylar</button>
          <button class="p-btn secondary small" onclick="pufy.open('https://apple.com')">Bağlantı</button>
        </div>
      </div>
    </div>
    """
    VStack {
        ChatCanvasCard(canvasHTML: sampleHTML, messageID: UUID())
            .padding()
    }
    .background(Color(UIColor.systemBackground))
    .preferredColorScheme(.light)
}

#Preview("Koyu") {
    let sampleHTML = """
    <div class="p-stack">
      <div class="p-hstack">
        <div class="p-title">Dinamik Arayüz</div>
        <div class="p-spacer"></div>
        <span class="p-badge">Canlı</span>
      </div>
      <div class="p-card">
        <div class="p-subtitle">Pufy UI Kit bileşenleri ile esnek içerik</div>
        <div class="p-divider"></div>
        <div class="p-hstack">
          <button class="p-btn small" onclick="pufy.haptic(); pufy.send('Detaylı bilgi ver')">Detaylar</button>
          <button class="p-btn secondary small" onclick="pufy.open('https://apple.com')">Bağlantı</button>
        </div>
      </div>
    </div>
    """
    VStack {
        ChatCanvasCard(canvasHTML: sampleHTML, messageID: UUID())
            .padding()
    }
    .background(Color(UIColor.systemBackground))
    .preferredColorScheme(.dark)
}
