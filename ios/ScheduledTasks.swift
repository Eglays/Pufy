import Foundation
import BackgroundTasks
import UserNotifications

// MARK: - Zamanlanmış Yapay Zeka Görevleri
//
// ESKİ DURUM: [AI_TASK] sadece bir bildirim kuruyordu; görev ancak kullanıcı bildirime dokununca çalışıyordu.
// YENİ: vakti gelince görev kendiliğinden çalışır ve SONUÇ bildirim olarak gelir ("GS ilk 11: Muslera, …").
//  • Uygulama açıkken: zamanı gelince hemen (dakikada bir kontrol).
//  • Uygulama kapalıyken: iOS'tan arka plan uyandırması istenir (BGAppRefreshTask). iOS bunu tam dakikasında
//    garanti etmez — telefonun kullanımına göre birkaç dakika ile daha uzun sürebilir. Vakti gelince yine de
//    bir bildirim düşer; dokunulursa görev o an çalışır.
//  • Olay bekleyen görevler ("ilk 11'ler açıklanınca yaz"): olay henüz olmadıysa model [HENÜZ_YOK] der,
//    görev 15 dakikada bir (en fazla ~3 saat) tekrar bakar.
//  • Sonuçlar görevin kendi sohbetine de yazılır; bildirime dokununca o sohbet açılır.

@MainActor
final class ScheduledTaskRunner: ObservableObject {
    static let shared = ScheduledTaskRunner()

    static let refreshID = "com.pufy.PufyAgent.aitask"
    static let notYetMarker = "[HENÜZ_YOK]"
    /// Sonuç kutusuna yeni sonuç düştü (sohbet ekranı içeri alır)
    static let resultReady = Notification.Name("PufyTaskResultReady")
    static let retryInterval: TimeInterval = 15 * 60
    static let maxAttempts = 12

    enum Outcome { case result, notYet, failed(String), skipped }

    /// Şu an çalışan görevler (görev sohbeti "bakıyorum" animasyonunu buradan gösterir)
    @Published private(set) var running: Set<UUID> = []
    private var foregroundTimer: Timer?
    /// Kullanıcı görevin sohbetine bakıyorsa sonuç için ayrıca bildirim gönderme (ChatViewModel ayarlar)
    var isViewingTask: ((Reminder) -> Bool)?

    // MARK: Arka plan

    /// didFinishLaunching içinde bir kez
    func registerHandler() {
        // iOS istisnası fırlatırsa uygulama çökmesin (bkz. PufyObjC)
        _ = PufyObjC.attempt {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: .main) { task in
                MainActor.assumeIsolated { ScheduledTaskRunner.shared.handle(task) }
            }
        }
    }

    private func handle(_ task: BGTask) {
        let work = Task {
            // Sunucu görevleri: sonuçları çek (gelirse "Sonuç hazır" bildirimi sonucun kendisiyle değişir)
            await SyncService.shared.syncNow()
            await runDue(background: true)
        }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            scheduleNextRefresh()
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    /// Sıradaki görev zamanı için arka plan uyandırması iste
    func scheduleNextRefresh() {
        _ = PufyObjC.attempt { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshID) }
        guard let next = ReminderManager.shared.pendingAITasks.compactMap({ dueDate(for: $0) }).min() else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshID)
        request.earliestBeginDate = max(next, Date().addingTimeInterval(30))
        var submitError: Error?
        _ = PufyObjC.attempt {
            do { try BGTaskScheduler.shared.submit(request) } catch { submitError = error }
        }
        if let submitError { print("⚠️ Görev uyandırması kurulamadı: \(submitError.localizedDescription)") }
    }

    // MARK: Ön plan

    /// Uygulama açıkken dakikada bir vakti gelen görevlere bak
    func startForegroundChecks() {
        foregroundTimer?.invalidate()
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Task { await ScheduledTaskRunner.shared.runDue() } }
        }
        Task { await runDue() }
    }

    func stopForegroundChecks() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        scheduleNextRefresh()
    }

    // MARK: Çalıştırma

    /// Görevin bir sonraki çalışma zamanı (bitmişse nil)
    func dueDate(for r: Reminder) -> Date? {
        guard r.isAITask, r.isActive, r.taskDone != true else { return nil }
        if let next = r.taskNextCheck { return next }
        if let every = r.taskIntervalMinutes {
            let next = r.taskLastRun.map { $0.addingTimeInterval(TimeInterval(every * 60)) } ?? r.date
            if let until = r.taskUntil, next > until { return nil }
            return next
        }
        if r.repeatType == .none { return r.date }
        let components = r.repeatType.triggerComponents(for: r.date)
        let after = r.taskLastRun ?? r.date.addingTimeInterval(-1)
        return Calendar.current.nextDate(after: after, matching: components, matchingPolicy: .nextTime)
    }

    func isRunning(_ id: UUID) -> Bool { running.contains(id) }

    /// Sunucu görevinin sonucu çekilirken "bakıyorum" animasyonu
    func setFetching(_ id: UUID, _ fetching: Bool) {
        if fetching { running.insert(id) } else { running.remove(id) }
    }

    /// Sunucudan gelen sonuç uygulama arka plandayken geldiyse: "Sonuç hazır" bildiriminin yerine sonucun kendisi
    func notifyServerResult(_ r: Reminder, text: String) {
        let content = UNMutableNotificationContent()
        content.title = PufyNotifications.clean(r.title)
        content.body = PufyNotifications.clean(String(Self.plainText(text).prefix(600)))
        content.sound = .default
        content.threadIdentifier = "pufytask.\(r.id.uuidString)"
        content.userInfo = ["taskReminderID": r.id.uuidString]
        let identifier = !r.isRepeatingTask ? (r.notificationIDs.first ?? "pufytask.\(r.id.uuidString)")
            : "pufytask.\(r.id.uuidString).\(Int(Date().timeIntervalSince1970))"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func runDue(background: Bool = false) async {
        // Süresi dolmuş dakikalık görevleri kapat (uygulama uzun süre kapalı kaldıysa)
        for task in ReminderManager.shared.pendingAITasks {
            if let until = task.taskUntil, until < Date(), task.taskIntervalMinutes != nil {
                ReminderManager.shared.updateTask(task.id) { $0.taskDone = true }
            }
        }
        let limit = Date().addingTimeInterval(20)
        let due = ReminderManager.shared.pendingAITasks.filter { (dueDate(for: $0) ?? .distantFuture) <= limit }
        for task in due {
            if Task.isCancelled { break }
            await run(task.id, background: background)
        }
        if !background { scheduleNextRefresh() }
    }

    /// - notify: sonucu bildirimle gönder (kullanıcı zaten sohbete bakıyorsa false)
    @discardableResult
    func run(_ id: UUID, background: Bool = false, notify: Bool = true) async -> Outcome {
        // Hesap açık ve sunucu görevleri destekliyorsa görev sunucuda çalışır (sonuç eşitlemeyle gelir)
        if SyncService.shared.managesTasks { return .skipped }
        guard !running.contains(id), let r = ReminderManager.shared.reminder(id: id),
              r.isAITask, r.taskDone != true else { return .skipped }
        running.insert(id)
        defer { running.remove(id) }

        let attempt = (r.taskAttempts ?? 0) + 1
        var system = Self.systemPrompt(for: r, attempt: attempt)
        if let liveBlock = await LiveScores.promptBlock(for: r.aiTaskPrompt) { system += "\n\n" + liveBlock }
        // "Her sabah hava durumunu bildir" gibi görevler: konumdaki gerçek tahmin (bkz. WeatherService)
        if let weather = await WeatherService.promptBlock(for: r.aiTaskPrompt, history: []) { system += "\n\n" + weather }
        do {
            let raw = try await GeminiService.shared.generateContent(
                prompt: r.aiTaskPrompt,
                systemPrompt: system,
                maxOutputTokens: 4096,
                timeout: background ? 25 : 120,
                useSearch: GeminiService.shared.canUseGoogleSearch
            )
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.contains(Self.notYetMarker) {
                guard attempt < Self.maxAttempts else {
                    finish(r, result: "Beklediğin bilgi yaklaşık \(attempt * 15) dakikadır kontrol ediyorum ama hâlâ yok. İstersen bana tekrar sor.", notify: notify)
                    return .result
                }
                ReminderManager.shared.updateTask(id) {
                    $0.taskAttempts = attempt
                    $0.taskNextCheck = Date().addingTimeInterval(Self.retryInterval)
                }
                return .notYet
            }
            finish(r, result: text, notify: notify)
            return .result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return .skipped }
            // Bağlantı sorunu: biraz sonra yeniden dene
            guard attempt < Self.maxAttempts else {
                finish(r, result: "Görevi çalıştıramadım: \(error.localizedDescription)", notify: notify)
                return .failed(error.localizedDescription)
            }
            ReminderManager.shared.updateTask(id) {
                $0.taskAttempts = attempt
                $0.taskNextCheck = Date().addingTimeInterval(5 * 60)
            }
            return .failed(error.localizedDescription)
        }
    }

    private func finish(_ r: Reminder, result: String, notify requested: Bool) {
        ReminderManager.shared.updateTask(r.id) {
            $0.taskInbox = ($0.taskInbox ?? []) + [result]
            $0.taskNextCheck = nil
            $0.taskAttempts = nil
            $0.taskRunCount = ($0.taskRunCount ?? 0) + 1
            if $0.isRepeatingTask {
                $0.taskLastRun = Date()
                // Dakikalık görevin süresi doldu
                if let every = $0.taskIntervalMinutes, let until = $0.taskUntil,
                   Date().addingTimeInterval(TimeInterval(every * 60)) > until {
                    $0.taskDone = true
                }
            } else {
                $0.taskDone = true
            }
        }
        // Kullanıcı zaten görevin sohbetine bakıyorsa ayrıca bildirim gönderme
        let notify = requested && !(isViewingTask?(r) ?? false)
        let center = UNUserNotificationCenter.current()
        if notify {
            let content = UNMutableNotificationContent()
            content.title = PufyNotifications.clean(r.title)
            content.body = PufyNotifications.clean(String(Self.plainText(result).prefix(600)))
            content.sound = .default
            content.threadIdentifier = "pufytask.\(r.id.uuidString)"
            content.userInfo = ["taskReminderID": r.id.uuidString]
            // Tek seferlik görevde: vakti gelince düşen "Bakıyorum" bildiriminin YERİNE geçer (aynı kimlik)
            let identifier = !r.isRepeatingTask
                ? (r.notificationIDs.first ?? "pufytask.\(r.id.uuidString)")
                : "pufytask.\(r.id.uuidString).\(Int(Date().timeIntervalSince1970))"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        } else if !r.isRepeatingTask {
            center.removeDeliveredNotifications(withIdentifiers: r.notificationIDs)
            center.removePendingNotificationRequests(withIdentifiers: r.notificationIDs)
        }
        NotificationCenter.default.post(name: Self.resultReady, object: r.id)
    }

    private static func systemPrompt(for r: Reminder, attempt: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy EEEE, HH:mm"
        let memory = MemoryStore.shared.promptText(for: r.aiTaskPrompt)
        return """
        Sen Pufy'sin, kullanıcının kişisel yapay zeka asistanı. Kullanıcı bu görevi önceden zamanladı ("\(r.title)").
        Şu an zamanı geldi ve görevi kendiliğinden çalıştırıyorsun; kullanıcı sohbette değil, cevabın bildirim olarak gidecek.
        Şu an: \(formatter.string(from: Date())).

        KURALLAR:
        - Güncel bilgi gerekiyorsa web'de ara. Uydurma; bulamadıysan bunu açıkça söyle.
        - İlk cümle doğrudan sonucu söylesin (bildirimde görünen kısım budur). Sonra gerekiyorsa kısa ayrıntı; madde işareti kullanabilirsin.
        - Selamlama, "görevinizi yaptım" gibi girişler, emoji ve köşeli parantezli etiketler yok.
        - Görev bir olayın gerçekleşmesini bekliyorsa (ilk 11'lerin açıklanması, sonucun belli olması, bir duyuru…) ve olay HENÜZ gerçekleşmediyse \
        hiçbir açıklama yazmadan sadece \(notYetMarker) yaz; 15 dakika sonra tekrar sorulacak. (Bu \(attempt). kontrol.)

        KULLANICI HAKKINDA:
        \(memory)
        """
    }

    /// Bildirim için düz metin: markdown işaretleri ve etiketler atılır
    static func plainText(_ markdown: String) -> String {
        var text = markdown
        let patterns: [(String, String)] = [
            ("\\[(?:SOURCES|IMAGES|NEXT|CHOICES|IMG)\\s*:[^\\]]*\\]", ""),
            ("\\[([^\\]]+)\\]\\([^)]+\\)", "$1"),          // [metin](bağlantı) → metin
            ("(?m)^#{1,6}\\s*", ""),
            ("\\*\\*|__|`", ""),
            ("(?m)^\\s*[-*•]\\s+", "• "),
            ("\\n{2,}", "\n")
        ]
        for (pattern, template) in patterns {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
