import SwiftUI
import WebKit
import PhotosUI
import UserNotifications

// MARK: - Mini Uygulama Dosyaları ve Sürümleri
//
// Uygulama dosyaları: Documents/MiniApps/<klasör>/
// Sürümler:           Application Support/PufyAgent/MiniAppVersions/<klasör>/<zaman>/
// Uygulama verisi:    Application Support/PufyAgent/MiniAppData/<klasör>.json  (pufy.storage)

struct MiniAppVersion: Identifiable {
    let id: String
    let date: Date
    let label: String
    let url: URL
}

enum MiniAppFiles {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MiniApps")
    }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PufyAgent")
    }

    static var versionsRoot: URL { support.appendingPathComponent("MiniAppVersions") }
    static var dataRoot: URL { support.appendingPathComponent("MiniAppData") }

    static func folderURL(_ folder: String) -> URL { root.appendingPathComponent(folder) }

    /// Yapay zekanın verdiği yol güvenli mi? ("../" ile klasör dışına çıkılamaz)
    static func sanitized(_ path: String) -> String? {
        let parts = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }

    static func hasFiles(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: folderURL(folder).appendingPathComponent("index.html").path)
    }

    static func read(_ path: String, folder: String) -> String? {
        guard let safe = sanitized(path) else { return nil }
        return try? String(contentsOf: folderURL(folder).appendingPathComponent(safe), encoding: .utf8)
    }

    @discardableResult
    static func write(_ path: String, content: String, folder: String) -> Bool {
        guard let safe = sanitized(path) else { return false }
        let url = folderURL(folder).appendingPathComponent(safe)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("⚠️ Dosya yazılamadı \(safe): \(error)")
            return false
        }
    }

    static func delete(_ path: String, folder: String) {
        guard let safe = sanitized(path) else { return }
        try? FileManager.default.removeItem(at: folderURL(folder).appendingPathComponent(safe))
    }

    /// Klasördeki metin dosyaları (göreli yol, içerik)
    static func textFiles(_ folder: String) -> [(path: String, content: String)] {
        let base = folderURL(folder)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        let textExtensions: Set<String> = ["html", "htm", "css", "js", "mjs", "json", "txt", "svg", "md"]
        // ESKİ HATA (bkz. AppBundle.files): telefonda klasör "/var/…", liste "/private/var/…" veriyor → göreli yol yerine
        // tam yol çıkıyordu; yapay zeka dosyaları "/private/var/…/index.html" diye görüyor, yamaları tutmuyordu.
        let rootPath = base.resolvingSymlinksInPath().path
        var result: [(String, String)] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  textExtensions.contains(url.pathExtension.lowercased()),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath + "/") else { continue }
            result.append((String(path.dropFirst(rootPath.count + 1)), content))
        }
        // index.html en başta, sonra alfabetik
        return result.sorted { a, b in
            if a.0 == "index.html" { return true }
            if b.0 == "index.html" { return false }
            return a.0 < b.0
        }
    }

    /// Yapay zekaya gönderilecek "mevcut dosyalar" metni
    static func promptText(_ folder: String) -> String {
        textFiles(folder)
            .filter { $0.path != "pufy-card.html" && $0.path != PufyUIKit.fileName }   // kapak kartı ve tasarım kiti uygulamanın kodu değil
            .map { "<<<FILE \($0.path)>>>\n\($0.content)\n<<<END>>>" }.joined(separator: "\n\n")
    }

    // MARK: Sürümler

    /// Değişiklikten ÖNCE çağrılır: mevcut hali kenara kopyalar (en fazla 20 sürüm tutulur)
    @discardableResult
    static func snapshot(_ folder: String, label: String) -> MiniAppVersion? {
        guard hasFiles(folder) else { return nil }
        let date = Date()
        let id = String(Int(date.timeIntervalSince1970 * 1000))
        let dir = versionsRoot.appendingPathComponent(folder).appendingPathComponent(id)
        do {
            try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: folderURL(folder), to: dir)
            try label.prefix(120).description.write(to: dir.appendingPathComponent(".pufy-version-label"), atomically: true, encoding: .utf8)
        } catch {
            print("⚠️ Sürüm kaydedilemedi: \(error)")
            return nil
        }
        let all = versions(folder)
        for old in all.dropFirst(20) { try? FileManager.default.removeItem(at: old.url) }
        return MiniAppVersion(id: id, date: date, label: label, url: dir)
    }

    static func versions(_ folder: String) -> [MiniAppVersion] {
        let dir = versionsRoot.appendingPathComponent(folder)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { url -> MiniAppVersion? in
            guard let ms = Double(url.lastPathComponent) else { return nil }
            let label = (try? String(contentsOf: url.appendingPathComponent(".pufy-version-label"), encoding: .utf8)) ?? ""
            return MiniAppVersion(id: url.lastPathComponent, date: Date(timeIntervalSince1970: ms / 1000), label: label, url: url)
        }
        .sorted { $0.date > $1.date }
    }

    /// Bir sürüme dön (dönmeden önce şimdiki hal de sürüm olarak saklanır → geri dönüş geri alınabilir)
    static func restore(_ version: MiniAppVersion, folder: String) {
        snapshot(folder, label: "Geri dönmeden önceki hal")
        let target = folderURL(folder)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: version.url, to: target)
        try? FileManager.default.removeItem(at: target.appendingPathComponent(".pufy-version-label"))
    }

    static func deleteAll(_ folder: String) {
        let prefix = "pufyapp.\(folder)."
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
        Task { @MainActor in
            for id in LiveActivityCenter.ids(prefix: prefix) { LiveActivityCenter.end(id: id) }
        }
        MiniAppSecrets.removeAll(folder: folder)
        try? FileManager.default.removeItem(at: folderURL(folder))
        try? FileManager.default.removeItem(at: versionsRoot.appendingPathComponent(folder))
        try? FileManager.default.removeItem(at: dataRoot.appendingPathComponent("\(folder).json"))
        try? FileManager.default.removeItem(at: support.appendingPathComponent("MiniAppPreviews/\(folder)-card.jpg"))
    }

    // MARK: Dışa aktarma

    /// Tüm yerel CSS/JS'yi içine gömerek tek bir HTML dosyası üretir (paylaşmak için)
    static func exportSingleHTML(folder: String, name: String) -> URL? {
        guard var html = read("index.html", folder: folder) else { return nil }

        // <link rel="stylesheet" href="yerel.css">
        if let regex = try? NSRegularExpression(pattern: "<link[^>]*href=\"(?!https?:)([^\"]+\\.css)\"[^>]*>", options: [.caseInsensitive]) {
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                guard let r = Range(match.range, in: html), let p = Range(match.range(at: 1), in: html),
                      let css = read(String(html[p]), folder: folder) else { continue }
                html.replaceSubrange(r, with: "<style>\n\(css)\n</style>")
            }
        }
        // <script src="yerel.js"></script>
        if let regex = try? NSRegularExpression(pattern: "<script([^>]*)src=\"(?!https?:)([^\"]+\\.m?js)\"([^>]*)>\\s*</script>", options: [.caseInsensitive]) {
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                guard let r = Range(match.range, in: html), let p = Range(match.range(at: 2), in: html),
                      let js = read(String(html[p]), folder: folder) else { continue }
                html.replaceSubrange(r, with: "<script>\n\(js)\n</script>")
            }
        }
        // pufy köprüsü dışarıda yok: çağrılar sessizce boş dönsün
        let shim = "<script>window.pufy=window.pufy||{storage:{get:async k=>JSON.parse(localStorage.getItem(k)),set:async(k,v)=>localStorage.setItem(k,JSON.stringify(v)),remove:async k=>localStorage.removeItem(k),keys:async()=>Object.keys(localStorage)},haptic:()=>{},notify:async()=>{},remind:async()=>{},ai:async()=>'',pickPhoto:async()=>null,takePhoto:async()=>null,share:async()=>{},user:{}};</script>"
        if let head = html.range(of: "<head>", options: .caseInsensitive) {
            html.insert(contentsOf: "\n" + shim, at: head.upperBound)
        } else {
            html = shim + html
        }

        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "Uygulama" : safeName).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Hata Konsolu (kendini onarma için)

@MainActor
final class MiniAppConsole: ObservableObject {
    @Published private(set) var errors: [String] = []

    func report(_ message: String) {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !errors.contains(clean) else { return }
        // Tailwind CDN'in "üretimde kullanmayın" uyarısı gerçek hata değil
        if clean.contains("cdn.tailwindcss.com should not be used in production") { return }
        errors.append(String(clean.prefix(600)))
        if errors.count > 10 { errors.removeFirst() }
    }

    func reset() { errors.removeAll() }

    /// Yapay zekaya gönderilecek düzeltme isteği
    var fixPrompt: String {
        """
        Uygulama çalışırken şu hatalar oluştu. Sebebini bul ve düzelt (sadece gerekeni değiştir):
        \(errors.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}

// MARK: - Pufy Köprüsü (window.pufy)
//
// Mini uygulamalara yerel yetenekler: kalıcı hafıza, titreşim, bildirim, hatırlatıcı,
// fotoğraf/kamera, paylaşma ve kullanıcının yapay zekasına soru (API anahtarı sayfaya hiç gitmez).

enum PufyBridgeScript {
    static func source(userName: String) -> String {
        let name = (try? String(data: JSONEncoder().encode(userName), encoding: .utf8)) ?? "\"\""
        return """
        (function(){
          if (window.pufy) return;
          var send = function(action, payload) {
            var msg = Object.assign({action: action}, payload || {});
            return window.webkit.messageHandlers.pufy.postMessage(msg);
          };
          var report = function(kind, message, extra) {
            try { window.webkit.messageHandlers.pufyLog.postMessage(Object.assign({kind: kind, message: String(message)}, extra || {})); } catch (e) {}
          };
          window.addEventListener('error', function(e) {
            report('error', e.message + (e.filename ? ' (' + e.filename.split('/').pop() + ':' + e.lineno + ')' : ''));
          });
          window.addEventListener('unhandledrejection', function(e) {
            var r = e.reason; report('error', 'Promise: ' + ((r && (r.stack || r.message)) || r));
          });
          var origError = console.error;
          console.error = function() {
            var args = Array.prototype.slice.call(arguments);
            report('console', args.map(function(x){ return (x && x.stack) || (typeof x === 'object' ? JSON.stringify(x) : String(x)); }).join(' '));
            origError.apply(console, args);
          };
          window.pufy = {
            version: 1,
            user: { name: \(name) },
            storage: {
              get: function(key) { return send('storage.get', {key: key}).then(function(v){ return v == null ? null : JSON.parse(v); }); },
              set: function(key, value) { return send('storage.set', {key: key, value: JSON.stringify(value === undefined ? null : value)}); },
              remove: function(key) { return send('storage.remove', {key: key}); },
              keys: function() { return send('storage.keys'); }
            },
            haptic: function(style) { send('haptic', {style: style || 'light'}); },
            notify: function(title, body, seconds, opts) { opts = opts || {}; return send('notify', {title: String(title), body: String(body || ''), seconds: Number(seconds || 0), repeat: !!opts.repeat}); },
            notifyDaily: function(title, body, hour, minute) { return send('notifyDaily', {title: String(title), body: String(body || ''), hour: Number(hour), minute: Number(minute || 0)}); },
            cancelNotification: function(id) { return send('cancelNotification', {id: String(id)}); },
            cancelAllNotifications: function() { return send('cancelNotification', {id: ''}); },
            remind: function(title, date, note) { return send('remind', {title: String(title), date: (date instanceof Date ? date.toISOString() : String(date)), note: String(note || '')}); },
            ai: function(prompt, opts) { opts = opts || {}; return send('ai', {prompt: String(prompt), system: String(opts.system || ''), json: !!opts.json, search: !!opts.search}).then(function(t){ return opts.json ? JSON.parse(t) : t; }); },
            fetch: function(url, opts) { opts = opts || {}; return send('fetch', {url: String(url), method: String(opts.method || 'GET'), headers: opts.headers || {}, body: (opts.body == null ? null : (typeof opts.body === 'string' ? opts.body : JSON.stringify(opts.body)))}).then(function(r){ r = JSON.parse(r); try { r.json = JSON.parse(r.text); } catch (e) { r.json = null; } return r; }); },
            secret: function(name) { return send('secret', {name: String(name)}); },
            pickPhoto: function() { return send('photo', {source: 'library'}); },
            takePhoto: function() { return send('photo', {source: 'camera'}); },
            share: function(text) { return send('share', {text: String(text)}); },
            work: {
              start: function(title) { return send('work.start', {title: String(title || '')}); },
              update: function(o) { o = o || {}; return send('work.update', {progress: (o.progress == null ? -1 : Number(o.progress)), status: String(o.status || '')}); },
              end: function() { return send('work.end'); }
            },
            live: {
              start: function(o) { o = o || {}; return send('live.start', {title: String(o.title || ''), subtitle: String(o.subtitle || ''), seconds: Number(o.seconds || 0), progress: (o.progress == null ? -1 : Number(o.progress)), status: String(o.status || ''), template: JSON.stringify(o)}); },
              update: function(id, o) { o = o || {}; return send('live.update', {id: String(id), title: (o.title == null ? null : String(o.title)), subtitle: (o.subtitle == null ? null : String(o.subtitle)), seconds: (o.seconds == null ? -1 : Number(o.seconds)), progress: (o.progress == null ? -1 : Number(o.progress)), status: (o.status == null ? null : String(o.status)), template: JSON.stringify(o)}); },
              end: function(id, o) { o = o || {}; return send('live.end', {id: String(id || ''), status: String(o.status || '')}); }
            }
          };
          document.dispatchEvent(new Event('pufyready'));
        })();
        """
    }
}

@MainActor
final class PufyBridge: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler {
    let folder: String
    /// Bildirim ve canlı etkinliklerde "hangi uygulamadan" bilgisi
    let appName: String
    let appIcon: String
    let appColorHex: String?
    weak var webView: WKWebView?
    weak var console: MiniAppConsole?
    private var photoDelegate: PhotoReplyDelegate?

    // Arka planda sürdürme (bkz. MiniAppBackground.swift)
    private(set) var inFlight = 0
    private(set) var lastActivity: Date?
    private(set) var explicitWork = false
    private(set) var workStatus: String?
    private(set) var workProgress: Double?
    var hasLiveActivity = false
    /// Uygulama şu an bir iş yapıyor mu? (son 2 dakikada istek, süren istek, açık iş ya da canlı etkinlik)
    var isBusy: Bool {
        explicitWork || inFlight > 0 || hasLiveActivity || (lastActivity.map { Date().timeIntervalSince($0) < 120 } ?? false)
    }

    init(folder: String, appName: String, appIcon: String, appColorHex: String?, console: MiniAppConsole?) {
        self.folder = folder
        self.appName = appName
        self.appIcon = appIcon
        self.appColorHex = appColorHex
        self.console = console
        super.init()
        MiniAppBackgroundKeeper.shared.register(self)
    }

    /// Canlı etkinlik şablonu: {style:"score", home:{name,short,color}, away:{…}, homeScore, awayScore, minute}
    /// ya da {style:"metric", value, unit, trend, change}. Verilmeyen alanlar olduğu gibi kalır.
    static func applyTemplate(_ json: String?, to state: inout PufyLiveActivityAttributes.ContentState) {
        guard let json, let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func side(_ any: Any?) -> PufyLiveActivityAttributes.ContentState.Side? {
            guard let d = any as? [String: Any], let name = d["name"] as? String, !name.isEmpty else { return nil }
            return .init(name: PufyNotifications.clean(name), short: d["short"] as? String, color: d["color"] as? String)
        }
        func int(_ any: Any?) -> Int? { (any as? Int) ?? (any as? Double).map(Int.init) ?? (any as? String).flatMap { Int($0) } }
        func str(_ any: Any?) -> String? {
            if let s = any as? String { return s }
            if let n = any as? NSNumber { return n.stringValue }
            return nil
        }
        if let style = o["style"] as? String { state.style = style }
        if let h = side(o["home"]) { state.home = h }
        if let a = side(o["away"]) { state.away = a }
        if let v = int(o["homeScore"]) { state.homeScore = v }
        if let v = int(o["awayScore"]) { state.awayScore = v }
        if let v = str(o["minute"]) { state.minute = v }
        if let v = str(o["value"]) { state.value = v }
        if let v = str(o["unit"]) { state.unit = v }
        if let v = o["trend"] as? String { state.trend = v }
        if let v = str(o["change"]) { state.change = v }
        if let finished = o["finished"] as? Bool { state.isFinished = finished }
    }

    /// Mini uygulama bildirimi: başlıkta uygulamanın adı, sağda uygulamanın ikonu, emoji yok.
    /// Dokununca o uygulama açılır.
    private func notificationContent(title rawTitle: String, body rawBody: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let title = PufyNotifications.clean(rawTitle)
        content.title = appName
        if !title.isEmpty, title.compare(appName, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
            content.subtitle = title
        }
        content.body = PufyNotifications.clean(rawBody)
        content.sound = .default
        content.threadIdentifier = "pufyapp.\(folder)"
        content.userInfo = ["miniAppFolder": folder]
        if let icon = PufyNotifications.iconAttachment(symbol: appIcon, colorHex: appColorHex, folder: folder) {
            content.attachments = [icon]
        }
        return content
    }

    // MARK: Hata kayıtları (yanıtsız kanal)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pufyLog", let body = message.body as? [String: Any],
              let text = body["message"] as? String else { return }
        console?.report(text)
    }

    // MARK: Yanıtlı kanal

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            replyHandler(nil, "Geçersiz istek")
            return
        }

        // Ağ/yapay zeka istekleri: uygulama "iş yapıyor" sayılır (arka plana alınınca durmasın)
        var reply = replyHandler
        if action == "ai" || action == "fetch" {
            inFlight += 1
            lastActivity = Date()
            reply = { [weak self] value, error in
                self?.inFlight -= 1
                self?.lastActivity = Date()
                replyHandler(value, error)
            }
        }
        handle(action: action, body: body, replyHandler: reply)
    }

    private func handle(action: String, body: [String: Any], replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        switch action {
        // Uzun iş: iOS'un arka plan ilerleme arayüzüyle sürer (maç tarama, indirme, işleme…)
        case "work.start":
            explicitWork = true
            workStatus = PufyNotifications.clean(body["title"] as? String ?? "").nilIfEmpty
            workProgress = nil
            MiniAppBackgroundKeeper.shared.explicitWorkStarted(self)
            replyHandler(true, nil)
        case "work.update":
            if let p = body["progress"] as? Double, p >= 0 { workProgress = min(p, 1) }
            if let status = (body["status"] as? String).map(PufyNotifications.clean), !status.isEmpty { workStatus = status }
            lastActivity = Date()
            MiniAppBackgroundKeeper.shared.explicitWorkUpdated(self)
            replyHandler(true, nil)
        case "work.end":
            explicitWork = false
            workProgress = nil
            MiniAppBackgroundKeeper.shared.explicitWorkEnded(self)
            replyHandler(true, nil)
        case "storage.get":
            replyHandler(storage()[body["key"] as? String ?? ""] ?? NSNull(), nil)
        case "storage.set":
            var s = storage()
            s[body["key"] as? String ?? ""] = body["value"] as? String ?? "null"
            saveStorage(s)
            replyHandler(true, nil)
        case "storage.remove":
            var s = storage()
            s.removeValue(forKey: body["key"] as? String ?? "")
            saveStorage(s)
            replyHandler(true, nil)
        case "storage.keys":
            replyHandler(Array(storage().keys), nil)

        case "haptic":
            switch body["style"] as? String {
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
            case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            replyHandler(true, nil)

        case "notify", "notifyDaily":
            let content = notificationContent(title: body["title"] as? String ?? "", body: body["body"] as? String ?? "")
            // Kimlik uygulamaya özel önekle: uygulama kendi bildirimlerini iptal edebilsin
            let id = "pufyapp.\(folder).\(UUID().uuidString)"
            let trigger: UNNotificationTrigger?
            if action == "notifyDaily" {
                var components = DateComponents()
                components.hour = (body["hour"] as? Int) ?? Int(body["hour"] as? Double ?? 9)
                components.minute = (body["minute"] as? Int) ?? Int(body["minute"] as? Double ?? 0)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            } else {
                let seconds = (body["seconds"] as? Double) ?? 0
                let repeats = (body["repeat"] as? Bool) ?? false
                // iOS kuralı: tekrarlayan bildirim aralığı en az 60 sn
                trigger = seconds > 0 || repeats
                    ? UNTimeIntervalNotificationTrigger(timeInterval: repeats ? max(seconds, 60) : max(seconds, 1), repeats: repeats)
                    : nil
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                Task { @MainActor in replyHandler(error == nil ? id : nil, error?.localizedDescription) }
            }

        case "cancelNotification":
            let target = body["id"] as? String ?? ""
            let prefix = "pufyapp.\(folder)."
            let center = UNUserNotificationCenter.current()
            center.getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter { target.isEmpty ? $0.hasPrefix(prefix) : $0 == target }
                center.removePendingNotificationRequests(withIdentifiers: ids)
                Task { @MainActor in replyHandler(ids.count, nil) }
            }

        case "remind":
            let title = body["title"] as? String ?? "Hatırlatıcı"
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let raw = body["date"] as? String ?? ""
            let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
            guard let date, date > Date() else {
                replyHandler(nil, "Geçersiz veya geçmiş tarih")
                return
            }
            let note = PufyNotifications.clean(body["note"] as? String ?? "")
            ReminderManager.shared.add(Reminder(title: PufyNotifications.clean(title),
                                                note: note.isEmpty ? "\(appName) uygulamasından" : "\(note) · \(appName)",
                                                date: date))
            replyHandler(true, nil)

        // Canlı etkinlik: kilit ekranı + Dinamik Ada (uygulamanın adı, ikonu ve rengiyle)
        case "live.start":
            let id = "pufyapp.\(folder).\(UUID().uuidString.prefix(8))"
            let seconds = (body["seconds"] as? Double) ?? 0
            let progress = (body["progress"] as? Double) ?? -1
            let status = PufyNotifications.clean(body["status"] as? String ?? "")
            let state = PufyLiveActivityAttributes.ContentState(
                title: PufyNotifications.clean(body["title"] as? String ?? appName).nilIfEmpty ?? appName,
                subtitle: PufyNotifications.clean(body["subtitle"] as? String ?? ""),
                startDate: Date(),
                endDate: seconds > 0 ? Date().addingTimeInterval(min(seconds, 8 * 3600)) : nil,
                progress: progress >= 0 ? min(progress, 1) : nil,
                status: status.isEmpty ? nil : status)
            var templated = state
            Self.applyTemplate(body["template"] as? String, to: &templated)
            let ok = LiveActivityCenter.start(id: id, kind: .app, state: templated,
                                              appName: appName, symbol: appIcon, colorHex: appColorHex)
            if ok { hasLiveActivity = true }
            replyHandler(ok ? id : nil, ok ? nil : "Canlı etkinlikler kapalı ya da desteklenmiyor")

        case "live.update":
            let id = body["id"] as? String ?? ""
            guard id.hasPrefix("pufyapp.\(folder).") else { replyHandler(false, "Geçersiz kimlik"); return }
            LiveActivityCenter.update(id: id) { state in
                if let t = body["title"] as? String { state.title = PufyNotifications.clean(t) }
                if let s = body["subtitle"] as? String { state.subtitle = PufyNotifications.clean(s) }
                if let st = body["status"] as? String { state.status = st.isEmpty ? nil : PufyNotifications.clean(st) }
                if let p = body["progress"] as? Double, p >= 0 { state.progress = min(p, 1) }
                if let sec = body["seconds"] as? Double, sec >= 0 {
                    state.startDate = Date()
                    state.endDate = sec > 0 ? Date().addingTimeInterval(min(sec, 8 * 3600)) : nil
                }
                Self.applyTemplate(body["template"] as? String, to: &state)
            }
            replyHandler(true, nil)

        case "live.end":
            hasLiveActivity = false
            let id = body["id"] as? String ?? ""
            let status = PufyNotifications.clean(body["status"] as? String ?? "")
            let ids = id.isEmpty ? LiveActivityCenter.ids(prefix: "pufyapp.\(folder).") : [id]
            for target in ids where target.hasPrefix("pufyapp.\(folder).") {
                LiveActivityCenter.end(id: target, finalState: { state in
                    state.isFinished = true
                    state.endDate = nil
                    state.progress = 1
                    if !status.isEmpty { state.status = status }
                }, dismissAfter: status.isEmpty ? nil : 60 * 5)
            }
            replyHandler(true, nil)

        case "ai":
            let prompt = body["prompt"] as? String ?? ""
            var system = body["system"] as? String ?? ""
            let json = body["json"] as? Bool ?? false
            // search:true → web araması (Gemini'de JSON modu ile arama birlikte çalışmaz: JSON metinden ayıklanır)
            let search = (body["search"] as? Bool ?? false) && GeminiService.shared.canUseGoogleSearch
            if search {
                let f = DateFormatter()
                f.locale = Locale(identifier: "tr_TR")
                f.dateFormat = "d MMMM yyyy EEEE HH:mm"
                system += "\nŞu an: \(f.string(from: Date())) (Türkiye). Web'de ara; sadece gerçek, doğrulanmış bilgi ver, uydurma."
                    + (json ? " SADECE istenen JSON'u yaz; açıklama ya da kod bloğu yazma." : "")
            }
            Task {
                do {
                    let text = try await GeminiService.shared.generateContent(
                        prompt: prompt,
                        systemPrompt: system.isEmpty ? nil : system,
                        responseMimeType: (json && !search) ? "application/json" : nil,
                        timeout: search ? 120 : nil,
                        useSearch: search
                    )
                    if json, let s = text.firstIndex(of: "{") ?? text.firstIndex(of: "["),
                       let e = text.lastIndex(of: "}") ?? text.lastIndex(of: "]"), s < e {
                        replyHandler(String(text[s...e]), nil)
                    } else {
                        replyHandler(text, nil)
                    }
                } catch {
                    replyHandler(nil, error.localizedDescription)
                }
            }

        // Dış API / sayfa isteği (sayfanın kendi fetch'i pufyapp:// kökeninden CORS'a takılır)
        case "fetch":
            guard let urlString = body["url"] as? String, let url = URL(string: urlString),
                  url.scheme == "https" || url.scheme == "http" else {
                replyHandler(nil, "Geçersiz adres")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = (body["method"] as? String)?.uppercased() ?? "GET"
            request.timeoutInterval = 30
            for (key, value) in (body["headers"] as? [String: Any]) ?? [:] {
                request.setValue("\(value)", forHTTPHeaderField: key)
            }
            if let text = body["body"] as? String { request.httpBody = text.data(using: .utf8) }
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let http = response as? HTTPURLResponse
                    let headers = (http?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
                    let text = String(data: data.prefix(3_000_000), encoding: .utf8) ?? ""
                    let payload: [String: Any] = ["ok": (200...299).contains(http?.statusCode ?? 0),
                                                  "status": http?.statusCode ?? 0, "headers": headers, "text": text]
                    let json = try JSONSerialization.data(withJSONObject: payload)
                    replyHandler(String(data: json, encoding: .utf8), nil)
                } catch {
                    replyHandler(nil, error.localizedDescription)
                }
            }

        // Kullanıcının bu uygulama için verdiği API anahtarı
        case "secret":
            let name = body["name"] as? String ?? ""
            replyHandler(MiniAppSecrets.get(name, folder: folder) ?? NSNull(), nil)

        case "photo":
            presentPhotoPicker(camera: (body["source"] as? String) == "camera", reply: replyHandler)

        case "share":
            let text = body["text"] as? String ?? ""
            if let presenter = topPresenter() {
                let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = webView
                presenter.present(sheet, animated: true)
            }
            replyHandler(true, nil)

        default:
            replyHandler(nil, "Bilinmeyen işlem: \(action)")
        }
    }

    // MARK: Depolama

    private var storageURL: URL { MiniAppFiles.dataRoot.appendingPathComponent("\(folder).json") }

    private func storage() -> [String: String] {
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private func saveStorage(_ dict: [String: String]) {
        try? FileManager.default.createDirectory(at: MiniAppFiles.dataRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: storageURL, options: .atomic) }
    }

    // MARK: Fotoğraf

    private func topPresenter() -> UIViewController? {
        var controller = webView?.window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private func presentPhotoPicker(camera: Bool, reply: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let presenter = topPresenter() else { reply(nil, "Ekran bulunamadı"); return }
        let delegate = PhotoReplyDelegate { [weak self] image in
            self?.photoDelegate = nil
            guard let image, let data = ImageUtils.preparedJPEG(from: image, maxDimension: 1280, quality: 0.8) else {
                reply(NSNull(), nil)   // kullanıcı vazgeçti
                return
            }
            reply("data:image/jpeg;base64," + data.base64EncodedString(), nil)
        }
        photoDelegate = delegate

        if camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = delegate
            presenter.present(picker, animated: true)
        } else {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = delegate
            presenter.present(picker, animated: true)
        }
    }
}

private final class PhotoReplyDelegate: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: @MainActor (UIImage?) -> Void

    init(completion: @escaping @MainActor (UIImage?) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            Task { @MainActor in completion(nil) }
            return
        }
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            let image = object as? UIImage
            Task { @MainActor in self.completion(image) }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let image = info[.originalImage] as? UIImage
        Task { @MainActor in completion(image) }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        Task { @MainActor in completion(nil) }
    }
}

// MARK: - Paylaşım yardımcısı

@MainActor
func presentShareSheet(_ items: [Any]) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard var controller = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
    while let presented = controller.presentedViewController { controller = presented }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = controller.view
    controller.present(sheet, animated: true)
}

// MARK: - Eski kapak görüntülerinin temizliği
// (Ekran görüntüsü / HTML kart denemelerinden kalan dosyalar — artık kullanılmıyor)
extension MiniAppFiles {
    static func removeLegacyPreviews() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PufyAgent/MiniAppPreviews")
        try? FileManager.default.removeItem(at: dir)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Mini uygulama anahtarları (Anahtar Zinciri)
// Kullanıcı "şu API anahtarımı kullan" deyince anahtar koda yazılmaz (paylaşılan uygulamada sızmasın);
// uygulamaya özel saklanır, sayfa await pufy.secret("AD") ile alır.

enum MiniAppSecrets {
    private static func account(_ folder: String) -> String { "miniapp.secrets.\(folder)" }

    static func all(folder: String) -> [String: String] {
        guard let raw = Keychain.get(account(folder)), let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func get(_ name: String, folder: String) -> String? {
        all(folder: folder)[name]
    }

    static func merge(_ secrets: [String: String], folder: String) {
        var current = all(folder: folder)
        current.merge(secrets) { _, new in new }
        if let data = try? JSONEncoder().encode(current), let raw = String(data: data, encoding: .utf8) {
            Keychain.set(raw, for: account(folder))
        }
    }

    static func removeAll(folder: String) {
        Keychain.set("", for: account(folder))
    }
}
