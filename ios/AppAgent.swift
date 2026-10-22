import Foundation
import UIKit
import Vision
import CoreImage
import WebKit

// MARK: - Uygulama Ajanı (planla → görsel üret → yaz → dene → bak → düzelt)
//
// Kullanıcı (15 Ekim 2026): "Uygulama kaliteleri berbat, 3 sene önceki web uygulaması hissi veriyor. Meyveler meyve gibi
// gözüksün diyorum, beceremiyor; elinde yeterli şey yok. Tek bir mesajla bir kere çalışmasın; Antigravity / Claude Code
// gibi sürekli çalışan, kendine görev veren ajantik bir yapı olsun."
// Sorun model değil, kullanış biçimiydi: uygulama tek seferde yazılıyor, hiç denenmiyor, ekrana bakılmıyor, gerçek görsel
// yoktu (meyveler CSS daireleriydi). Artık:
//   1) PLAN: zor işler modeli ekranları, görsel yönü, yapılacakları ve gereken görselleri çıkarır (ekranda yapılacaklar listesi).
//   2) GÖRSELLER: görsel modeli nesneleri (meyve, karakter, yemek…) çizer; iPhone'un "konuyu ayır" özelliği arka planı
//      temizler → uygulama klasörüne şeffaf PNG (assets/…). Yazar bu dosyaları kullanmak ZORUNDA.
//   3) KOD: dosyalar yazılır (mevcut FILE/PATCH protokolü).
//   4) DENEME: uygulama görünmez bir pencerede iPhone boyutunda açılır; konsol hataları toplanır, ekran görüntüsü alınır,
//      "Başla"ya basılıp ikinci görüntü alınır.
//   5) BAKIŞ: zor işler modeli ekran görüntülerine bakar, puan verir, somut sorunları yazar.
//   6) DÜZELTME: sorunlar yamalanır, tekrar denenir (en fazla 2 tur ya da puan yeterli olana kadar).

struct AgentStep: Identifiable, Equatable {
    enum State: Equatable { case pending, running, done, failed }
    let id: String
    var title: String
    var state: State = .pending
    var detail: String? = nil
}

struct AppPlan: Decodable {
    struct Asset: Decodable {
        let file: String
        let prompt: String
        let kind: String?
        let note: String?
    }
    var chat: Bool?
    var summary: String?
    var style: String?
    var todo: [String]?
    var assets: [Asset]?
}

struct AppReview: Decodable {
    var score: Double?
    var issues: [String]?
    var fix: String?
}

enum AppAgent {
    // MARK: Plan

    static func plan(request: String, history: [Message], folder: String, hasApp: Bool) async -> AppPlan? {
        let ai = GeminiService.shared
        let existing = hasApp ? MiniAppFiles.textFiles(folder).map { "\($0.path) (\($0.content.count) karakter)" }.joined(separator: ", ") : "yok (yeni uygulama)"
        let assets = existingAssets(folder).joined(separator: ", ")
        let system = """
        Sen üst düzey bir mobil ürün tasarımcısı ve oyun yapımcısısın. Kullanıcının isteği için yapım planı çıkar. SADECE JSON yaz:
        {"chat": false,
         "summary": "tek cümle: ne yapılacak",
         "style": "görsel yön: Pufy tasarım rehberine uygun vurgu paleti (mono|ocean|forest|sunset|sand|slate|crimson|teal|gold) + uygulamanın kişiliği (sakin, sıcak, oyunbaz, ciddi…) + düzen fikri — sade, iOS'a yakın; neon, parlama, mor-pembe gradyan YOK",
         "todo": ["3-7 kısa adım, kullanıcıya gösterilecek (ör. 'Meyve düşme fiziği', 'Skor ve rekor ekranı')"],
         "assets": [{"file": "assets/elma.png", "kind": "sprite", "prompt": "English image prompt", "note": "Türkçe: ne için kullanılacak"}]}
        Kurallar:
        - chat: kullanıcı sadece sohbet ediyor/soru soruyorsa true (kod yazılmayacak, diğer alanlar boş).
        - assets: CSS/SVG/emoji ile güzel görünmeyecek GERÇEK nesneler için görsel iste: meyve, yemek, hayvan, karakter, araç,
          eşya, oyun nesnesi, arka plan/manzara, illüstrasyon. Her farklı nesne ayrı dosya (elma, muz, çilek ayrı). En fazla 8.
          Basit arayüzler (liste, form, sayaç, tablo, ayarlar) için BOŞ bırak. Mevcut görseller tekrar istenmez.
        - kind: "sprite" (tek nesne, arka planı temizlenecek) | "background" (tam ekran arka plan) | "illustration" (boş durum/kapak çizimi).
        - prompt (İngilizce): nesneyi net tarif et + temiz, sade bir çizim tarzı (ör. "clean 3D game sprite of a ripe red apple with a green
          leaf, soft studio lighting, natural colors, minimal"). Neon, glow, aşırı doygun renk isteme. Sprite'lar için arka plan/gölge/yazı isteme.
        - Düzenleme isteği küçükse (renk, metin, tek buton) todo 1-2 adım, assets boş.
        Mevcut dosyalar: \(existing). Mevcut görseller: \(assets.isEmpty ? "yok" : assets).
        """
        let context = history.suffix(4).map { "\($0.role == .user ? "Kullanıcı" : "Pufy"): \($0.content.prefix(500))" }.joined(separator: "\n")
        guard let raw = try? await ai.generateContent(prompt: (context.isEmpty ? "" : "Önceki konuşma:\n\(context)\n\n") + "İstek: \(request)",
                                                      systemPrompt: system, maxOutputTokens: 4000, modelOverride: ai.deepModel,
                                                      responseMimeType: "application/json", timeout: 60, thinking: "high"),
              let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AppPlan.self, from: data)
    }

    // MARK: Görseller

    static func existingAssets(_ folder: String) -> [String] {
        let dir = MiniAppFiles.folderURL(folder).appendingPathComponent("assets")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { ["png", "jpg", "jpeg", "webp"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted().map { "assets/\($0)" }
    }

    /// Görseli üretir, sprite ise arka planını temizler, uygulama klasörüne yazar. Dönen: yazılan yol + boyut
    static func makeAsset(_ asset: AppPlan.Asset, style: String?, folder: String) async -> (path: String, size: CGSize)? {
        guard let safe = MiniAppFiles.sanitized(asset.file) else { return nil }
        let kind = asset.kind ?? "sprite"
        let styleText = style.map { " Overall art direction: \($0)." } ?? ""
        let prompt: String
        switch kind {
        case "background":
            prompt = "\(asset.prompt).\(styleText) Full-bleed background image for a mobile app/game screen, portrait orientation, no text, no UI, no characters in the foreground, clean composition with calm areas for UI."
        case "illustration":
            prompt = "\(asset.prompt).\(styleText) Single centered illustration, plain pure white background, no text, no border."
        default:
            prompt = "\(asset.prompt).\(styleText) Single object only, centered, fully visible with margin around it, isolated on a plain pure white background, no shadow on the ground, no text, no border, crisp edges, high detail game asset."
        }
        guard let data = try? await GeminiService.shared.generateImageData(prompt: prompt, timeout: 180),
              let image = UIImage(data: data) else { return nil }
        var output = image
        if kind != "background", let cut = removeBackground(image) { output = cut }
        let maxSide: CGFloat = kind == "background" ? 1280 : 512
        output = output.pufyScaled(maxSide: maxSide)
        let isJPEG = kind == "background"
        let path = isJPEG ? (safe as NSString).deletingPathExtension + ".jpg" : (safe as NSString).deletingPathExtension + ".png"
        guard let bytes = isJPEG ? output.jpegData(compressionQuality: 0.85) : output.pngData() else { return nil }
        let url = MiniAppFiles.folderURL(folder).appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? bytes.write(to: url, options: .atomic)) != nil else { return nil }
        return (path, output.size)
    }

    /// iPhone'un "konuyu ayır" özelliği (iOS 17+): nesneyi kesip şeffaf arka planlı, kenarlarına kırpılmış görsel
    static func removeBackground(_ image: UIImage) -> UIImage? {
        guard #available(iOS 17.0, *), let cg = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        } catch {
            return nil
        }
    }

    // MARK: Deneme (görünmez pencerede aç, hataları topla, ekran görüntüsü al)

    struct TestRun {
        var shots: [Data] = []
        var errors: [String] = []
        var interacted = false
        /// Son ekran görüntüsü gece modunda mı alındı?
        var darkShot = false
    }

    @MainActor
    static func test(folder: String, entry: String = "index.html") async -> TestRun {
        let tester = AppTester()
        return await tester.run(folder: folder, entry: entry)
    }

    // MARK: Bakış (ekran görüntülerine bakıp puan + sorunlar)

    static func review(request: String, plan: AppPlan?, run: TestRun, round: Int) async -> AppReview? {
        let ai = GeminiService.shared
        let system = """
        Sen titiz bir App Store inceleme ekibisin (tasarım + kalite). Bir mobil uygulamanın iPhone ekran görüntülerine bakıp
        2026 standartlarına göre değerlendirirsin. SADECE JSON: {"score": 0-10, "issues": ["somut sorun: hangi ekranda, ne yanlış"], "fix": "geliştiriciye kısa, net düzeltme talimatı"}
        Ölçütler: İsteği gerçekten karşılıyor mu? Nesneler/karakterler gerçekten ne olduklarına benziyor mu (meyve meyve gibi mi,
        düz renkli daire değil)? Tasarım modern, ferah, özgün ve tutarlı mı (eski/ucuz web sayfası hissi yok)? Yazılar okunur, kontrast
        yeterli mi? Ekran güvenli alanlara uyuyor mu, taşan/kesilen/üst üste binen öğe var mı? Boş, beyaz ya da bozuk ekran var mı?
        Konsol hatası var mı? Hareket ve geri bildirim hissi (butonlar, geçişler) var mı?
        Pufy tasarım dili: sade zemin + yumuşak gri yüzeyler + TEK vurgu rengi mi? Neon, parlama (glow), mor-pembe/gökkuşağı gradyan,
        "cyber" koyu lacivert+neon görünüm varsa puanı en fazla 6 ver ve düzeltmesini iste. Gece modu ekranında (varsa son ekran) yazılar
        okunuyor mu, aydınlık modda kalmış beyaz kutu/siyah yazı var mı?
        Not: Deneme ortamında yapay zeka/ağ verisi gelmez (pufy.ai ve pufy.fetch boş döner); veri bekleyen alanların yükleniyor/boş
        görünmesi sorun DEĞİL — ama boş durum tasarımı özenli olmalı.
        Puan: 9-10 yayınlanabilir; 7-8 iyi ama gözle görülür kusurlar; ≤6 belirgin sorunlar. Sorun yoksa issues boş.
        """
        var text = "[KULLANICI İSTEĞİ]\n\(request)\n"
        if let plan {
            text += "\n[PLAN]\n\(plan.summary ?? "")\nStil: \(plan.style ?? "-")\nYapılacaklar: \((plan.todo ?? []).joined(separator: "; "))\n"
        }
        text += "\n[KONSOL HATALARI]\n" + (run.errors.isEmpty ? "yok" : run.errors.prefix(8).joined(separator: "\n"))
        text += "\n\n[EKRANLAR] 1: açılış" + (run.shots.count > 1 ? (run.interacted ? ", 2: ana düğmeye basıldıktan sonra" : ", 2: birkaç saniye sonra") : "")
            + (run.darkShot ? ", SON: aynı ekran telefon GECE MODUNDAYKEN" : "")
        text += "\nDeneme turu: \(round)"
        guard let raw = try? await ai.generateContent(prompt: text, imageDatas: run.shots, systemPrompt: system, maxOutputTokens: 3000,
                                                      modelOverride: ai.deepModel, responseMimeType: "application/json",
                                                      timeout: 120, thinking: "high"),
              let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AppReview.self, from: data)
    }
}

// MARK: - Görünmez deneme penceresi

@MainActor
private final class AppTester: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var errors: [String] = []
    private var loaded: CheckedContinuation<Void, Never>?

    /// Uygulamanın kullandığı köprü olmadan da çalışabilsin: depolama bellekte, yapay zeka/ağ boş döner
    private static let stubBridge = """
    (function(){
      var mem = {};
      var log = function(m){ try { window.webkit.messageHandlers.pufyTestLog.postMessage(String(m)); } catch(e){} };
      window.addEventListener('error', function(e){ log(e.message + (e.lineno ? ' (satır ' + e.lineno + ')' : '')); });
      window.addEventListener('unhandledrejection', function(e){ var r = e.reason; log('Promise: ' + ((r && (r.stack || r.message)) || r)); });
      var oe = console.error; console.error = function(){ log(Array.prototype.slice.call(arguments).join(' ')); oe.apply(console, arguments); };
      var ok = function(v){ return Promise.resolve(v); };
      window.pufy = { version: 1, user: { name: 'Deniz' },
        storage: { get: function(k){ return ok(k in mem ? JSON.parse(mem[k]) : null); }, set: function(k, v){ mem[k] = JSON.stringify(v); return ok(true); },
                   remove: function(k){ delete mem[k]; return ok(true); }, keys: function(){ return ok(Object.keys(mem)); } },
        haptic: function(){}, notify: function(){ return ok('t'); }, notifyDaily: function(){ return ok('t'); },
        cancelNotification: function(){ return ok(0); }, cancelAllNotifications: function(){ return ok(0); },
        remind: function(){ return ok(true); },
        ai: function(p, o){ return ok(o && o.json ? {} : ''); },
        fetch: function(){ return ok({ok: false, status: 0, headers: {}, text: '', json: null}); },
        secret: function(){ return ok(null); }, pickPhoto: function(){ return ok(null); }, takePhoto: function(){ return ok(null); },
        share: function(){ return ok(true); },
        work: { start: function(){ return ok(true); }, update: function(){ return ok(true); }, end: function(){ return ok(true); } },
        live: { start: function(){ return ok(null); }, update: function(){ return ok(true); }, end: function(){ return ok(true); } } };
      document.dispatchEvent(new Event('pufyready'));
    })();
    """

    func run(folder: String, entry: String) async -> AppAgent.TestRun {
        var result = AppAgent.TestRun()
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: Self.stubBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: ControlSpot.pageScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(self, name: "pufyTestLog")
        config.allowsInlineMediaPlayback = true
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "pufyapp")
        if #available(iOS 17.0, *) { config.preferences.inactiveSchedulingPolicy = .none }

        // iPhone 15 Pro boyutu; pencerede ama Pufy'nin ARKASINDA (kullanıcı görmez). Ekran dışına konursa WebKit
        // "görünmüyor" sayıp çizmeyebiliyor; arkada kalan görünüm ise normal çizilir ve ekran görüntüsü alınabilir.
        let size = CGSize(width: 393, height: 852)
        let web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        web.navigationDelegate = self
        web.isOpaque = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        // Önce aydınlık modda denenir, sonunda aynı ekran gece modunda (prefers-color-scheme) çekilir
        web.overrideUserInterfaceStyle = .light
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
        window?.insertSubview(web, at: 0)
        defer {
            web.removeFromSuperview()
            web.configuration.userContentController.removeAllScriptMessageHandlers()
        }

        guard let url = URL(string: "pufyapp://\(folder)/\(entry)") else { return result }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loaded = c
            web.load(URLRequest(url: url))
            // Yüklenemezse de takılmasın
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.finishLoad() }
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if let shot = await snapshot(web) { result.shots.append(shot) }

        // Ana eyleme bas ("Başla", "Oyna"…); yoksa ortaya dokun (oyunlar için)
        let clicked = (try? await web.evaluateJavaScript("""
        (function(){
          var re = /(başla|oyna|play|start|hadi|devam|yeni oyun|giriş|keşfet)/i;
          var els = Array.prototype.slice.call(document.querySelectorAll('button, [role=button], a, .btn, .button'));
          var el = els.find(function(e){ return re.test((e.innerText || e.textContent || '').trim()) && e.offsetParent !== null; });
          if (el) { el.click(); return true; }
          var c = document.elementFromPoint(innerWidth/2, innerHeight*0.6);
          if (c) { ['pointerdown','touchstart','mousedown','pointerup','touchend','mouseup','click'].forEach(function(t){
            try { c.dispatchEvent(new Event(t, {bubbles: true})); } catch(e){} }); }
          return false;
        })();
        """)) as? Bool ?? false
        result.interacted = clicked
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if let shot = await snapshot(web) { result.shots.append(shot) }
        // Pufy düğmesinin yeri (sağ alt) boş mu? Değilse düğme kaçar ama tasarım baştan doğru olsun
        if let free = try? await web.evaluateJavaScript("window.__pufyFreeSpot ? window.__pufyFreeSpot() : 0") as? Int, free != 0 {
            errors.append("Sağ alt köşede (Pufy düğmesinin yeri: sağdan ~64px, alttan güvenli alan + ~50px) dokunulabilir bir öğe var; "
                          + "o köşeyi boş bırak (yüzen butonu sola/ortaya al, alt çubukta sağdan boşluk bırak).")
        }
        // Gece modu: telefon koyuya geçince uygulama da kendiliğinden koyu olmalı (Pufy tasarım rehberi)
        web.overrideUserInterfaceStyle = .dark
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let shot = await snapshot(web) {
            result.shots.append(shot)
            result.darkShot = true
        }
        result.errors = Array(NSOrderedSet(array: errors).compactMap { $0 as? String }.prefix(10))
        return result
    }

    private func finishLoad() {
        loaded?.resume()
        loaded = nil
    }

    /// Ekran güncellenmezse (Pufy arka plana alındı) takeSnapshot hiç dönmüyordu → 6 sn sınır
    private func snapshot(_ web: WKWebView) async -> Data? {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        let image: UIImage? = await withCheckedContinuation { c in
            var resumed = false
            let finish: (UIImage?) -> Void = { image in
                guard !resumed else { return }
                resumed = true
                c.resume(returning: image)
            }
            web.takeSnapshot(with: config) { image, _ in finish(image) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { finish(nil) }
        }
        return image?.jpegData(compressionQuality: 0.7)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoad() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.errors.append("Sayfa yüklenemedi: \(error.localizedDescription)")
            self.finishLoad()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.errors.append("Sayfa açılamadı: \(error.localizedDescription)")
            self.finishLoad()
        }
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        Task { @MainActor in
            // Tailwind CDN uyarısı gerçek hata değil
            if text.contains("should not be used in production") { return }
            self.errors.append(String(text.prefix(300)))
        }
    }
}

extension UIImage {
    /// En uzun kenarı en fazla maxSide olacak şekilde küçült (büyütmez)
    func pufyScaled(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
