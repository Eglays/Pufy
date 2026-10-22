import SwiftUI
import WebKit

// MARK: - Mini App View

struct MiniAppView: View {
    @EnvironmentObject var tabManager: TabManager
    let app: MiniApp

    @StateObject private var console = MiniAppConsole()
    @State private var showEditor = false
    @State private var editorPrompt: String?
    @State private var reloadTrigger = false
    @State private var controlsExpanded = true
    @State private var collapseTask: Task<Void, Never>?
    /// Pufy düğmesinin köşesi (bkz. ControlSpot): sayfa o köşede dokunulabilir bir öğe gösterirse kendiliğinden boş köşeye geçer;
    /// kullanıcı sürükleyip bir köşeye koyarsa o uygulama için hatırlanır.
    @State private var autoSpot = 0
    @State private var manualSpot: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @AppStorage("hint_mini_exit_shown") private var hintMiniExitShown = false
    @State private var showExitHint = false

    private var spot: ControlSpot { ControlSpot(rawValue: manualSpot ?? autoSpot) ?? .bottomTrailing }
    private var spotKey: String { "pufy_control_spot_\(app.folderName ?? app.id.uuidString)" }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            Group {
                if app.appSpecJson?.isEmpty == false && app.folderName.map(MiniAppFiles.hasFiles) != true {
                    legacyNotice
                } else if let folder = app.folderName, !MiniAppFiles.hasFiles(folder), app.htmlContent.isEmpty {
                    // Başka cihazdan gelen uygulamanın dosyaları henüz inmediyse siyah ekran yerine açıklama
                    notDownloadedNotice
                } else {
                    WebView(app: app, console: console, onPinchOut: {
                        tabManager.showSwitcherFromPinch()
                    }, onControlSpot: { free in
                        guard free != autoSpot else { return }
                        withAnimation(SmoothSpring.standard) { autoSpot = free }
                    })
                        .id(reloadTrigger)
                        .ignoresSafeArea()   // tam ekran: native uygulama hissi
                }
            }
            .overlay(alignment: spot.alignment) { floatingControls }
            .overlay(alignment: .top) {
                if showExitHint {
                    HintBubbleView(text: "Çıkmak için iki parmakla kıstır.") {
                        hintMiniExitShown = true
                        withAnimation(SmoothSpring.standard) { showExitHint = false }
                    }
                    .padding(.top, 46)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = $0 }
            })
            .coordinateSpace(name: "miniAppArea")
        }
        .onAppear {
            if UserDefaults.standard.object(forKey: spotKey) != nil {
                manualSpot = UserDefaults.standard.integer(forKey: spotKey)
            }
            if !hintMiniExitShown {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !hintMiniExitShown {
                        withAnimation(SmoothSpring.standard) { showExitHint = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                            hintMiniExitShown = true
                            withAnimation(SmoothSpring.standard) { showExitHint = false }
                        }
                    }
                }
            }
        }
        // Ana ekran çizgisi oyunlardaki gibi geri çekilir (kaydırınca yine çıkar)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showEditor, onDismiss: { editorPrompt = nil }) {
            AppCreatorView(editingApp: app, initialPrompt: editorPrompt) { updated in
                tabManager.updateMiniApp(updated)
                console.reset()
                reloadTrigger.toggle()
            }
            .environmentObject(tabManager)
        }
    }

    private var notDownloadedNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(String(localized: "Uygulama bu cihaza inmedi"))
                .font(.headline)
            Text(String(localized: "Diğer cihazından gelen bu uygulamanın dosyaları henüz eşitlenmedi."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await SyncService.shared.fullResync(); reloadTrigger.toggle() }
            } label: {
                Label(String(localized: "Şimdi eşitle"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .pufyGlass(Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Kaldırılan "native motor" türündeki eski uygulamalar
    private var legacyNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(String(localized: "Bu uygulama eski türde"))
                .font(.headline)
            Text(String(localized: "Hazır motorlar kaldırıldı. Düzenle'ye basıp \"yeniden oluştur\" dersen yapay zeka bunu yeni sistemle baştan yazar."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Uygulamada hata yakalanınca: "Hata · Düzelt" (kendini onarma)
    @ViewBuilder
    private var errorPill: some View {
        if !console.errors.isEmpty {
            Button {
                PremiumHaptics.medium()
                editorPrompt = console.fixPrompt
                showEditor = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(console.errors.count == 1 ? String(localized: "Bir hata oluştu") : (AppLanguage.isEnglish ? "\(console.errors.count) errors occurred" : "\(console.errors.count) hata oluştu"))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Düzelt"))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.pufyOnPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.pufyPrimary))
                }
                .font(.footnote)
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .pufyGlass(Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Eskiden ekranın altında sabit bir çubuk vardı ve uygulamadan alan çalıyordu.
    /// Şimdi: açılışta birkaç saniye görünen küçük cam düğmeler, sonra tek bir küçük noktaya çekilir.
    private var floatingControls: some View {
        PufyGlassContainer(spacing: 6) {
            VStack(alignment: spot.isLeading ? .leading : .trailing, spacing: 10) {
                if !spot.isTop { errorPill }
                if controlsExpanded {
                    HStack(spacing: 10) {
                        GlassIconButton(systemImage: "pencil", size: 42, iconSize: 15, accessibilityLabel: String(localized: "Uygulamayı düzenle")) {
                            showEditor = true
                        }
                        GlassIconButton(systemImage: "square.grid.2x2", size: 42, iconSize: 15, accessibilityLabel: String(localized: "Uygulamalar")) {
                            withAnimation(SmoothSpring.standard) { tabManager.isTabSwitcherVisible = true }
                        }
                    }
                    .transition(.scale(scale: 0.5, anchor: spot.unitPoint).combined(with: .opacity))
                } else {
                    Button {
                        PremiumHaptics.light()
                        showControlsTemporarily()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .pufyGlass(Circle(), interactive: true)
                            .opacity(0.7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Uygulama seçenekleri"))
                    .accessibilityHint(String(localized: "Sürükleyerek başka bir köşeye taşıyabilirsin"))
                    .offset(dragOffset)
                    .gesture(dragToCorner)
                    .transition(.scale(scale: 0.5, anchor: spot.unitPoint).combined(with: .opacity))
                }
                if spot.isTop { errorPill }
            }
            .padding(spot.isLeading ? .leading : .trailing, 14)
            .padding(spot.isTop ? .top : .bottom, spot.isTop ? 8 : 4)
            .animation(SmoothSpring.standard, value: console.errors.count)
            .animation(SmoothSpring.standard, value: controlsExpanded)
        }
        .onAppear { showControlsTemporarily() }
    }

    /// Kullanıcı (15 Ekim 2026): "Uygulamaya sağ alta buton koymuş, Pufy düğmesi altında kalıyor, basamıyorum."
    /// Düğme otomatik olarak boş köşeye geçer; çizimle yapılmış (canvas) düğmeler için de kullanıcı sürükleyip taşıyabilir.
    private var dragToCorner: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("miniAppArea"))
            .onChanged { value in
                collapseTask?.cancel()
                dragOffset = value.translation
            }
            .onEnded { value in
                let target = ControlSpot.nearest(to: value.location, in: containerSize)
                PremiumHaptics.medium()
                withAnimation(SmoothSpring.standard) {
                    dragOffset = .zero
                    manualSpot = target.rawValue
                }
                UserDefaults.standard.set(target.rawValue, forKey: spotKey)
            }
    }

    private func showControlsTemporarily() {
        controlsExpanded = true
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { controlsExpanded = false }
        }
    }
}

// MARK: - Pufy düğmesinin köşesi

/// Sırası sayfadaki betikle aynı: 0 sağ alt, 1 sol alt, 2 sağ orta, 3 sol orta, 4 sağ üst, 5 sol üst
enum ControlSpot: Int {
    case bottomTrailing = 0, bottomLeading, trailing, leading, topTrailing, topLeading

    var alignment: Alignment {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .trailing: return .trailing
        case .leading: return .leading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .trailing: return .trailing
        case .leading: return .leading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }

    var isLeading: Bool { self == .bottomLeading || self == .leading || self == .topLeading }
    var isTop: Bool { self == .topTrailing || self == .topLeading }

    static func nearest(to point: CGPoint, in size: CGSize) -> ControlSpot {
        guard size.width > 0, size.height > 0 else { return .bottomTrailing }
        let leading = point.x < size.width / 2
        if point.y < size.height * 0.3 { return leading ? .topLeading : .topTrailing }
        if point.y > size.height * 0.7 { return leading ? .bottomLeading : .bottomTrailing }
        return leading ? .leading : .trailing
    }

    /// Sayfada çalışır: düğmenin olabileceği köşelerden altında dokunulabilir öğe (buton, bağlantı, giriş…) OLMAYAN ilkini bulur,
    /// değişince Pufy'ye bildirir. Kayan içerikteki öğeler sayılmaz (kaydırınca altından çıkar); sabit çubuklar, yüzen butonlar sayılır.
    static let pageScript = """
    (function(){
      if (window.__pufyFreeSpot) return;
      var probe = null;
      function insets(){
        if (!probe) {
          probe = document.createElement('div');
          probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;' +
            'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
          (document.body || document.documentElement).appendChild(probe);
        }
        var s = getComputedStyle(probe);
        return { t: parseFloat(s.paddingTop) || 0, r: parseFloat(s.paddingRight) || 0, b: parseFloat(s.paddingBottom) || 0, l: parseFloat(s.paddingLeft) || 0 };
      }
      function spots(){
        var W = innerWidth, H = innerHeight, i = insets(), size = 46;
        var bottom = H - i.b - 4 - 34 - 6, top = i.t + 8 - 6, mid = H * 0.5 - 23;
        var right = W - i.r - 14 - 34 - 6, left = i.l + 14 - 6;
        return [[right, bottom], [left, bottom], [right, mid], [left, mid], [right, top], [left, top]]
          .map(function(p){ return { x: p[0], y: p[1], w: size, h: size }; });
      }
      var SEL = 'button,a[href],input:not([type=hidden]),select,textarea,label,summary,[role=button],[role=tab],[role=switch],' +
                '[role=checkbox],[role=link],[onclick],[tabindex]:not([tabindex="-1"]),.p-btn,.p-chip,.p-icon-btn';
      function scrollsAway(el){
        var doc = document.scrollingElement || document.documentElement;
        var docScrolls = doc.scrollHeight > innerHeight + 4;
        for (var e = el; e && e !== document.body && e !== document.documentElement; e = e.parentElement) {
          var cs = getComputedStyle(e);
          if (cs.position === 'fixed' || cs.position === 'sticky') return false;
          if (/(auto|scroll)/.test(cs.overflowY) && e.scrollHeight > e.clientHeight + 4) return true;
        }
        return docScrolls;
      }
      function blocked(r){
        var els = document.querySelectorAll(SEL);
        for (var k = 0; k < els.length; k++) {
          var el = els[k], b = el.getBoundingClientRect();
          if (b.width < 2 || b.height < 2) continue;
          if (b.right < r.x || b.left > r.x + r.w || b.bottom < r.y || b.top > r.y + r.h) continue;
          var cs = getComputedStyle(el);
          if (cs.visibility === 'hidden' || cs.pointerEvents === 'none' || parseFloat(cs.opacity) < 0.05) continue;
          if (scrollsAway(el)) continue;
          var cx = Math.min(Math.max(r.x + r.w / 2, b.left + 1), b.right - 1);
          var cy = Math.min(Math.max(r.y + r.h / 2, b.top + 1), b.bottom - 1);
          var hit = document.elementFromPoint(cx, cy);
          if (hit && (hit === el || el.contains(hit) || hit.contains(el))) return true;
        }
        return false;
      }
      window.__pufyFreeSpot = function(){
        var s = spots();
        for (var i = 0; i < s.length; i++) { if (!blocked(s[i])) return i; }
        return 0;
      };
      var last = -1, timer = null, lastRun = 0;
      function check(){
        timer = null; lastRun = Date.now();
        var i = window.__pufyFreeSpot();
        if (i !== last) { last = i; try { window.webkit.messageHandlers.pufyLayout.postMessage(i); } catch (e) {} }
      }
      function soon(){ if (!timer) timer = setTimeout(check, Math.max(400, 1000 - (Date.now() - lastRun))); }
      new MutationObserver(soon).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'hidden', 'style'] });
      addEventListener('resize', soon); addEventListener('load', soon); document.addEventListener('scroll', soon, true);
      setTimeout(check, 300); setTimeout(check, 1500);
    })();
    """
}

// MARK: - Native App Shell View
// Native app'ları temiz tam ekran gösterir (footer yok)

struct NativeAppShellView: View {
    @EnvironmentObject var tabManager: TabManager
    let nativeApp: NativeBuiltinApp

    var body: some View {
        // App ID'ye göre doğru engine yüklenir
        NativeWebView(urlString: nativeApp.urlString)
            .ignoresSafeArea()
    }
}

// MARK: - Local Scheme Handler for Persistent Storage
class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let host = url.host else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalScheme", code: 400, userInfo: nil))
            return
        }
        
        let path = url.path.isEmpty || url.path == "/" ? "/index.html" : url.path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let appRoot = docs.appendingPathComponent("MiniApps").appendingPathComponent(host).standardizedFileURL
        let fileURL = appRoot.appendingPathComponent(path).standardizedFileURL
        
        // "../" ile uygulama klasörünün dışına (ör. ayarlar, sohbet dosyası) çıkılmasın
        guard fileURL.path.hasPrefix(appRoot.path + "/"), let data = try? Data(contentsOf: fileURL) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }
        
        let mimeTypes: [String: String] = [
            "html": "text/html", "htm": "text/html", "js": "application/javascript", "mjs": "application/javascript",
            "css": "text/css", "json": "application/json", "png": "image/png", "jpg": "image/jpeg",
            "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
            "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "mp4": "video/mp4",
            "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "txt": "text/plain"
        ]
        let mimeType = mimeTypes[fileURL.pathExtension.lowercased()] ?? "application/octet-stream"
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

// MARK: - WKWebView Wrapper

struct WebView: UIViewRepresentable {
    let app: MiniApp
    /// Uygulama değiştirici önizlemesi: JS uyarı pencereleri ve köprü kapalı
    var isPreview: Bool = false
    /// Çalışma hatalarını toplar (kendini onarma)
    var console: MiniAppConsole? = nil
    /// İki parmakla kıstırınca (uygulamalar ekranını açmak için)
    var onPinchOut: (() -> Void)? = nil
    /// Sayfa, Pufy düğmesi için boş köşeyi bildirince (bkz. ControlSpot)
    var onControlSpot: ((Int) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Pufy köprüsü + hata yakalama — sayfa betiklerinden ÖNCE yüklenir
        if !isPreview, let folder = app.folderName {
            PufyUIKit.refreshIfUsed(folder)      // tasarım kitinin güncel hali
            let bridge = PufyBridge(folder: folder, appName: app.name, appIcon: app.icon,
                                    appColorHex: app.colorHex, console: console)
            context.coordinator.bridge = bridge
            let name = UserDefaults.standard.string(forKey: "pufy_agent_user_name") ?? ""
            config.userContentController.addUserScript(WKUserScript(source: PufyBridgeScript.source(userName: name),
                                                                    injectionTime: .atDocumentStart, forMainFrameOnly: true))
            config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "pufy")
            config.userContentController.add(bridge, name: "pufyLog")
        }
        config.allowsInlineMediaPlayback = true
        // Pufy arka plana alınınca sayfa askıya alınmasın (iş süren uygulamalar için; bkz. MiniAppBackground.swift)
        if #available(iOS 17.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "pufyapp")
        
        // Disable Zooming
        // ESKİ HATA: Sayfanın kendi viewport ayarının üstüne "viewport-fit=cover" OLMADAN yenisi
        // ekleniyordu → env(safe-area-inset-*) sıfırlanıyor, sayfa çentik/alt bölgeyi kullanamıyor,
        // uygulama ekranda bir pencere içinde açılmış gibi kırpık görünüyordu.
        let zoomScriptSource = """
        (function(){var c='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
        var m=document.querySelector('meta[name=viewport]');
        if(m){m.setAttribute('content',c);}else{m=document.createElement('meta');m.name='viewport';m.content=c;(document.head||document.documentElement).appendChild(m);}})();
        """
        let zoomScript = WKUserScript(source: zoomScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(zoomScript)
        if !isPreview, onControlSpot != nil {
            config.userContentController.addUserScript(WKUserScript(source: ControlSpot.pageScript, injectionTime: .atDocumentEnd,
                                                                    forMainFrameOnly: true))
            config.userContentController.add(context.coordinator, name: "pufyLayout")
            context.coordinator.onControlSpot = onControlSpot
        }
        
        let wv = PufyWebView(frame: .zero, configuration: config)
        wv.scrollView.bounces         = false
        // Sayfa ekranın tamamına yayılsın; güvenli alanları sayfa CSS'i (env(safe-area-inset-*)) yönetir
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.isOpaque                   = false
        wv.backgroundColor            = .clear
        wv.scrollView.backgroundColor = .clear
        wv.uiDelegate                 = context.coordinator
        wv.navigationDelegate         = context.coordinator
        context.coordinator.isPreview = isPreview
        context.coordinator.bridge?.webView = wv
        if !isPreview, onPinchOut != nil {
            // WKWebView kendi dokunuşlarını yuttuğu için SwiftUI kıstırması uygulama içinde çalışmıyordu
            let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
            pinch.delegate = context.coordinator
            wv.addGestureRecognizer(pinch)
            context.coordinator.onPinchOut = onPinchOut
        }

        loadIfNeeded(wv, coordinator: context.coordinator)
        return wv
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Köprü ↔ WebView döngüsünü kır (yoksa kapatılan uygulamalar bellekte kalır)
        uiView.configuration.userContentController.removeAllScriptMessageHandlers()
        uiView.stopLoading()
    }

    /// ESKİ HATA: Sayfa burada koşulsuz yükleniyordu. updateUIView her SwiftUI güncellemesinde
    /// (sheet açılması, uygulama değiştirici, tema...) çağrıldığı için mini uygulama/oyun her
    /// seferinde baştan başlıyordu. Artık sadece içerik gerçekten değiştiyse yüklenir.
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.isPreview = isPreview
        loadIfNeeded(uiView, coordinator: context.coordinator)
    }

    private var contentKey: String {
        "\(app.id)|\(app.folderName ?? "-")|\(app.entryPoint ?? "")|\(app.updatedAt.timeIntervalSince1970)|\(app.htmlContent.count)"
    }

    private func loadIfNeeded(_ webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.loadedKey != contentKey else { return }
        coordinator.loadedKey = contentKey

        // ESKİ HATA (iPad): sayfa, görünüm henüz 0×0 iken yükleniyordu → ekranı açılışta bir kez ölçen uygulamalar
        // küçük boyutla başlayıp sol üstte kalıyordu. Görünüm gerçek boyutunu alınca yüklenir.
        if let pufyView = webView as? PufyWebView, pufyView.bounds.width < 2 || pufyView.bounds.height < 2 {
            let load = { [self] in self.performLoad(webView) }
            pufyView.pendingLoad = load
            return
        }
        performLoad(webView)
    }

    private func performLoad(_ webView: WKWebView) {
        if let folderName = app.folderName {
            let entry = app.entryPoint ?? "index.html"
            let entryPath = entry.hasPrefix("/") ? entry : "/\(entry)"
            if let url = URL(string: "pufyapp://\(folderName)\(entryPath)") {
                webView.load(URLRequest(url: url))
                return
            }
        }
        // Klasör yapısı olmayan eski uygulamalar
        webView.loadHTMLString(app.htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler {
        var loadedKey: String?
        var isPreview = false
        var bridge: PufyBridge?
        var onPinchOut: (() -> Void)?
        var onControlSpot: ((Int) -> Void)?
        private var pinchFired = false

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pufyLayout", let spot = (message.body as? NSNumber)?.intValue, (0...5).contains(spot) else { return }
            DispatchQueue.main.async { self.onControlSpot?(spot) }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .changed where recognizer.scale < 0.78 && !pinchFired:
                pinchFired = true
                PremiumHaptics.medium()
                onPinchOut?()
            case .ended, .cancelled, .failed:
                pinchFired = false
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Kamera/mikrofon: kendi yerel mini uygulamalarımıza otomatik izin,
        /// dış sitelere (uygulama içinden açılan bağlantılar) sistem sorusu
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(origin.protocol == "pufyapp" ? .grant : .prompt)
        }
        
        func webView(
            _ webView: WKWebView,
            requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(origin.protocol == "pufyapp" ? .grant : .prompt)
        }
        
        // MARK: JS alert / confirm / prompt
        // ESKİ HATA: alert() hiç gösterilmiyordu ("Oyun bitti!" görünmüyordu) ve confirm()
        // her zaman true dönüyordu ("Her şeyi silmek istiyor musun?" sorusu otomatik onaylanıyordu).

        private func presenter(for webView: WKWebView) -> UIViewController? {
            guard !isPreview else { return nil }
            var controller = webView.window?.rootViewController
            while let presented = controller?.presentedViewController { controller = presented }
            return controller
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let presenter = presenter(for: webView) else { completionHandler(); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Tamam"), style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }
        
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let presenter = presenter(for: webView) else { completionHandler(false); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Vazgeç"), style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: String(localized: "Tamam"), style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let presenter = presenter(for: webView) else { completionHandler(nil); return }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: String(localized: "Vazgeç"), style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: String(localized: "Tamam"), style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }
        
        // target="_blank" bağlantıları aynı görünümde aç
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

// MARK: - Boyutunu bilen WebView

/// Gerçek boyutu gelmeden sayfayı yüklemez; boyut değişince (döndürme, Split View) sayfaya 'resize' gönderir.
final class PufyWebView: WKWebView {
    var pendingLoad: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if let load = pendingLoad {
            pendingLoad = nil
            lastSize = size
            load()
            return
        }
        if lastSize != .zero, abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5 {
            evaluateJavaScript("window.dispatchEvent(new Event('resize')); window.dispatchEvent(new Event('orientationchange'));")
        }
        lastSize = size
    }
}
