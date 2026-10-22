import Foundation
import UIKit
import WebKit

// MARK: - Mini uygulamalar arka planda da çalışsın
//
// Kullanıcı (15 Ekim 2026): "Maçları tarayan bir uygulama yaptırdım; arka plana aldığımda hata veriyor, taramayı bırakıyor."
// Sebep: iOS arka plana atılan uygulamayı birkaç saniyede askıya alır, WebKit de sayfanın JavaScript'ini durdurur;
// yarıda kalan istekler "bağlantı koptu" hatası verir.
// Çözüm:
//  1) Uygulama bir iş yapıyorsa (son 2 dakikada ağ/yapay zeka isteği, süren istek, canlı etkinlik ya da açıkça
//     pufy.work.start) Pufy arka plana geçerken iOS 26'nın "devam eden iş"i başlatılır: iOS uygulamayı askıya almaz,
//     kilit ekranında/Dinamik Ada'da "<Uygulama> çalışıyor" ilerlemesi görünür. Eski iOS'ta ~30 sn ek süre alınır.
//  2) WebKit'e "görünmezken de normal çalış" denir (inactiveSchedulingPolicy = .none) ve sayfaya birkaç saniyede
//     bir dokunulur (askıya alınmasın).
//  3) Uygulama açıkça uzun iş bildirebilir: pufy.work.start("Maçlar taranıyor") → update({progress, status}) → end().
//     Gerçek ilerleme sistemin arayüzünde görünür.

@MainActor
final class MiniAppBackgroundKeeper {
    static let shared = MiniAppBackgroundKeeper()

    /// Açık uygulamaların köprüleri (zayıf referans)
    private var bridges: [String: WeakBridge] = [:]
    private struct WeakBridge { weak var bridge: PufyBridge? }

    /// Arka planda sürdürülen işler (klasör → iş kimliği)
    private var running: [String: String] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var pinger: Timer?
    private var startedAt = Date()

    func register(_ bridge: PufyBridge) {
        bridges[bridge.folder] = WeakBridge(bridge: bridge)
    }

    private var liveBridges: [PufyBridge] {
        bridges = bridges.filter { $0.value.bridge != nil }
        return bridges.values.compactMap(\.bridge)
    }

    /// Pufy arka plana geçmek üzere (hâlâ ön planda: iOS işi ancak şimdi başlatmaya izin verir)
    func appWillResignActive() {
        let busy = liveBridges.filter(\.isBusy)
        guard !busy.isEmpty else { return }
        startedAt = Date()
        for bridge in busy where running[bridge.folder] == nil {
            let id = "app-\(bridge.folder.prefix(12))-\(UUID().uuidString.prefix(6))"
            running[bridge.folder] = id
            BackgroundWork.begin(id: id, title: "\(bridge.appName) çalışıyor",
                                 subtitle: bridge.workStatus ?? "Arka planda devam ediyor")
        }
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PufyMiniApp") { [weak self] in
                Task { @MainActor in self?.stopAll() }
            }
        }
        // Sayfayı uyanık tut + ilerlemeyi güncelle + iş bittiyse kapat
        pinger?.invalidate()
        pinger = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in MiniAppBackgroundKeeper.shared.tick() }
        }
    }

    func appDidBecomeActive() { stopAll() }

    private func tick() {
        let elapsed = Date().timeIntervalSince(startedAt)
        for bridge in liveBridges {
            guard let id = running[bridge.folder] else { continue }
            // İş bitti (2 dk hareketsiz, süren istek yok, açık iş yok) ya da 30 dk doldu → kapat
            if !bridge.isBusy || elapsed > 30 * 60 {
                BackgroundWork.finish(id: id, success: true)
                running[bridge.folder] = nil
                continue
            }
            bridge.webView?.evaluateJavaScript("void 0", completionHandler: nil)
            let progress = bridge.workProgress ?? min(0.95, elapsed / (30 * 60))
            BackgroundWork.update(id: id, progress: progress, title: "\(bridge.appName) çalışıyor",
                                  subtitle: bridge.workStatus ?? "Arka planda devam ediyor")
        }
        if running.isEmpty { stopAll() }
    }

    private func stopAll() {
        pinger?.invalidate()
        pinger = nil
        for id in running.values { BackgroundWork.finish(id: id, success: true) }
        running = [:]
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    /// Uygulama açıkça uzun iş başlattı (pufy.work.start): ön plandayken hemen başlatılır
    func explicitWorkStarted(_ bridge: PufyBridge) {
        guard running[bridge.folder] == nil, UIApplication.shared.applicationState != .background else { return }
        let id = "app-\(bridge.folder.prefix(12))-\(UUID().uuidString.prefix(6))"
        running[bridge.folder] = id
        startedAt = Date()
        BackgroundWork.begin(id: id, title: "\(bridge.appName) çalışıyor", subtitle: bridge.workStatus ?? "Çalışıyor…")
    }

    func explicitWorkUpdated(_ bridge: PufyBridge) {
        guard let id = running[bridge.folder] else { return }
        BackgroundWork.update(id: id, progress: bridge.workProgress ?? 0.05, title: "\(bridge.appName) çalışıyor",
                              subtitle: bridge.workStatus ?? "Çalışıyor…")
    }

    func explicitWorkEnded(_ bridge: PufyBridge) {
        guard let id = running[bridge.folder] else { return }
        BackgroundWork.finish(id: id, success: true)
        running[bridge.folder] = nil
    }
}
