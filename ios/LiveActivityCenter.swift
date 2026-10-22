import Foundation
import ActivityKit
import BackgroundTasks
import UserNotifications
import SwiftUI

// MARK: - Canlı Etkinlik Merkezi
// Hatırlatıcı, zamanlayıcı, uzun görev (uygulama üretimi) ve mini uygulama etkinliklerinin tek yönetim noktası.

@MainActor
enum LiveActivityCenter {
    typealias Attributes = PufyLiveActivityAttributes

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Aynı kimlikle çalışan bir etkinlik varsa onu döndürür
    static func activity(id: String) -> Activity<Attributes>? {
        Activity<Attributes>.activities.first { $0.attributes.reminderID == id }
    }

    static func ids(prefix: String) -> [String] {
        Activity<Attributes>.activities.map(\.attributes.reminderID).filter { $0.hasPrefix(prefix) }
    }

    @discardableResult
    static func start(id: String, kind: Attributes.Kind, state: Attributes.ContentState,
                      appName: String? = nil, symbol: String = "bell.fill", colorHex: String? = nil) -> Bool {
        guard isAvailable else { return false }
        if let existing = activity(id: id) {
            Task { await existing.update(ActivityContent(state: state, staleDate: state.endDate)) }
            return true
        }
        let attributes = Attributes(kind: kind, reminderID: id, appName: appName, symbol: symbol, colorHex: colorHex)
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: ActivityContent(state: state, staleDate: state.endDate),
                                     pushType: nil)
            return true
        } catch {
            print("⚠️ Canlı etkinlik başlatılamadı: \(error.localizedDescription)")
            return false
        }
    }

    static func update(id: String, _ mutate: (inout Attributes.ContentState) -> Void) {
        guard let activity = activity(id: id) else { return }
        var state = activity.content.state
        mutate(&state)
        Task { await activity.update(ActivityContent(state: state, staleDate: state.endDate)) }
    }

    /// - dismissAfter: bitmiş hali kilit ekranında bu kadar saniye kalır (nil → hemen kaldır)
    static func end(id: String, finalState: ((inout Attributes.ContentState) -> Void)? = nil, dismissAfter: TimeInterval? = nil) {
        guard let activity = activity(id: id) else { return }
        var state = activity.content.state
        finalState?(&state)
        let policy: ActivityUIDismissalPolicy = dismissAfter.map { .after(Date().addingTimeInterval($0)) } ?? .immediate
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }

    /// Süresi geçmiş zamanlayıcı/hatırlatıcı etkinliklerini kapat
    static func endExpired() {
        for activity in Activity<Attributes>.activities {
            guard activity.attributes.kind != .task,
                  let end = activity.content.state.endDate, end < Date().addingTimeInterval(-60) else { continue }
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// MARK: - Arka Planda Devam Eden İşler (iOS 26)
//
// Kullanıcının başlattığı uzun bir iş (ör. uygulama üretimi) sürerken uygulama arka plana alınırsa,
// iOS 26'nın BGContinuedProcessingTask'ı işi sürdürür ve sistemin kendi canlı ilerleme arayüzünü gösterir.
// iOS 26 öncesinde ~30 sn'lik klasik arka plan süresi + kendi canlı etkinliğimiz kullanılır.

@MainActor
final class BackgroundWork {
    static let identifierPrefix = "com.pufy.PufyAgent.work"

    private static var running: [String: AnyObject] = [:]       // id → BGContinuedProcessingTask
    private static var progressValues: [String: Double] = [:]
    private static var lastReport: [String: Date] = [:]
    private static var heartbeats: [String: Timer] = [:]
    private static var classicTasks: [String: UIBackgroundTaskIdentifier] = [:]
    /// Birim sayısı yüksek: küçük ilerlemeler de sisteme "iş sürüyor" diye yansısın
    private static let units: Int64 = 1000

    /// ESKİ ÇÖKME: açılışta "com.pufy.PufyAgent.work.*" kalıbıyla işleyici kaydediliyordu; iOS 26+'da submit
    /// bu kalıbı eşleştiremeyip "No launch handler registered…" istisnası fırlatıyor ve uygulama çöküyordu
    /// (uygulama oluştururken Gönder'e basınca). Apple forumlarında bilinen sorun.
    /// Artık her iş için TAM kimlikle, iş başlarken kayıt yapılıyor (bu görev türü açılışta kayıt kuralından muaf)
    /// ve iOS'un Objective-C istisnaları PufyObjC ile yakalanıyor — arka plan özelliği olmasa da uygulama çökmez.
    static func registerHandler() {}

    /// Sistem bu işin arka planda sürmesine hâlâ izin veriyor mu?
    static func isAlive(_ id: String) -> Bool { running[id] != nil }

    /// İşi başlat (uygulama ön plandayken çağrılmalı)
    ///
    /// Kullanıcı (15 Ekim 2026): "Uygulama üretirken Instagram'a geçince hata veriyor, 'sunucu yoğun, yeniden deneniyor'
    /// diyor ve hiç bitmiyor." SEBEP: ilerleme sadece oluşturucu EKRANI güncellenince bildiriliyordu; arka planda ekran
    /// güncellenmediği için iOS işi "ilerlemiyor" sayıp sonlandırıyor, uygulama askıya alınıyor, bağlantı kopuyordu.
    /// Artık ilerlemeyi işin kendisi bildiriyor, ayrıca birkaç saniyede bir "hâlâ çalışıyor" nabzı atılıyor.
    static func begin(id: String, title: String, subtitle: String) {
        progressValues[id] = 0.02
        lastReport[id] = Date()
        // iOS 26 öncesi ve sistem işi başlatana kadar: klasik arka plan süresi (~30 sn)
        let classic = UIApplication.shared.beginBackgroundTask(withName: "PufyWork-\(id)") {
            Task { @MainActor in BackgroundWork.endClassic(id) }
        }
        if classic != .invalid { classicTasks[id] = classic }
        startHeartbeat(id)
        #if targetEnvironment(macCatalyst)
        return      // Mac'te uygulama arka planda zaten çalışır; iOS'un arka plan görevi yok
        #else
        guard #available(iOS 26, *) else { return }
        let identifier = "\(identifierPrefix).\(id)"
        let handler: (BGTask) -> Void = { task in
            DispatchQueue.main.async {
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                task.progress.totalUnitCount = units
                task.progress.completedUnitCount = Int64((progressValues[id] ?? 0.02) * Double(units))
                // Süre dolma bildirimi herhangi bir kuyruktan gelebilir → ana kuyruğa geç. İş iptal EDİLMEZ:
                // uygulama askıya alınırsa iş, Pufy tekrar açılınca kaldığı yerden sürer (bkz. AppBuilder.stream)
                task.expirationHandler = { DispatchQueue.main.async { running[id] = nil } }
                running[id] = task
            }
        }
        var registered = false
        let ok = PufyObjC.attempt {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil, launchHandler: handler)
        }
        guard ok, registered else {
            print("⚠️ Arka plan işi kaydedilemedi: \(identifier)")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        var submitError: Error?
        let submitted = PufyObjC.attempt {
            do { try BGTaskScheduler.shared.submit(request) } catch { submitError = error }
        }
        if !submitted || submitError != nil {
            print("⚠️ Arka plan işi gönderilemedi: \(submitError?.localizedDescription ?? "iOS istisnası")")
        }
        #endif
    }

    static func update(id: String, progress: Double, title: String? = nil, subtitle: String? = nil) {
        guard progressValues[id] != nil else { return }
        // İlerleme hiç geri gitmez (sistem arayüzü zıplamasın)
        let value = max(progressValues[id] ?? 0, min(max(progress, 0), 0.99))
        progressValues[id] = value
        lastReport[id] = Date()
        guard #available(iOS 26, *), let task = running[id] as? BGContinuedProcessingTask else { return }
        task.progress.completedUnitCount = Int64(value * Double(units))
        if let title, let subtitle { task.updateTitle(title, subtitle: subtitle) }
    }

    static func finish(id: String, success: Bool) {
        progressValues[id] = nil
        lastReport[id] = nil
        heartbeats[id]?.invalidate()
        heartbeats[id] = nil
        endClassic(id)
        guard #available(iOS 26, *), let task = running[id] as? BGContinuedProcessingTask else { return }
        task.progress.completedUnitCount = units
        task.setTaskCompleted(success: success)
        running[id] = nil
    }

    private static func endClassic(_ id: String) {
        guard let classic = classicTasks.removeValue(forKey: id) else { return }
        UIApplication.shared.endBackgroundTask(classic)
    }

    /// Uzun sessiz anlarda (model düşünürken, görsel çizilirken) 3 sn'de bir binde bir ilerleme: iş canlı görünsün
    private static func startHeartbeat(_ id: String) {
        heartbeats[id]?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                guard let current = progressValues[id] else { return }
                guard Date().timeIntervalSince(lastReport[id] ?? .distantPast) >= 3 else { return }
                let nudged = min(current + 0.001, 0.97)
                progressValues[id] = nudged
                lastReport[id] = Date()
                guard #available(iOS 26, *), let task = running[id] as? BGContinuedProcessingTask else { return }
                task.progress.completedUnitCount = Int64(nudged * Double(units))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeats[id] = timer
    }
}

// MARK: - Bildirim Yardımcıları

enum PufyNotifications {
    static let reminderCategory = "PUFY_REMINDER"
    static let snoozeAction = "PUFY_SNOOZE_10"
    static let doneAction = "PUFY_DONE"

    /// Hatırlatıcı bildirimlerinde "10 dk ertele" ve "Tamam" düğmeleri
    static func registerCategories() {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "10 dk ertele", options: [])
        let done = UNNotificationAction(identifier: doneAction, title: "Tamam", options: [])
        let category = UNNotificationCategory(identifier: reminderCategory, actions: [snooze, done],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Bildirimlerde emoji kullanılmaz (kullanıcı isteği) — metindeki emoji ve fazla boşluklar temizlenir
    static func clean(_ text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            let p = scalar.properties
            // Rakamlar ve # gibi karakterler de "emoji" sayılabildiği için sadece gerçek emoji sunumunu ele
            return !(p.isEmojiPresentation || (p.isEmoji && scalar.value > 0x238C) || scalar.value == 0xFE0F || scalar.value == 0x200D)
        }
        return String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mini uygulama ikonunu bildirim küçük resmi yapar (sağdaki görsel)
    @MainActor
    static func iconAttachment(symbol: String, colorHex: String?, folder: String) -> UNNotificationAttachment? {
        let renderer = ImageRenderer(content: MiniAppIconTile(icon: symbol, colorHex: colorHex, size: 120).padding(4))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pufy-icon-\(folder)-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "icon", url: url, options: nil)
        } catch {
            return nil
        }
    }
}
