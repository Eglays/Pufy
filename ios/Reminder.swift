import Foundation
import UserNotifications
import ActivityKit

// MARK: - Reminder Repeat Type

enum ReminderRepeat: String, Codable, CaseIterable {
    case none     = "none"
    case daily    = "daily"
    case weekly   = "weekly"
    case monthly  = "monthly"
    case yearly   = "yearly"
    
    var localizedName: String {
        switch self {
        case .none:    return String(localized: "Tekrar Yok")
        case .daily:   return String(localized: "Her Gün")
        case .weekly:  return String(localized: "Her Hafta")
        case .monthly: return String(localized: "Her Ay")
        case .yearly:  return String(localized: "Her Yıl")
        }
    }
    
    var icon: String {
        switch self {
        case .none:    return "bell"
        case .daily:   return "arrow.clockwise"
        case .weekly:  return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .yearly:  return "star.circle"
        }
    }

    /// Bildirim tetikleyicisinin eşleşeceği tarih bileşenleri.
    /// ESKİ HATA: haftalık için "ayın günü" kullanılıyordu (ayda bir çalıyordu), aylık için ay
    /// bileşeni bırakılmıştı (yılda bir çalıyordu), yıllık için yıl bırakılmıştı (bir kez çalıyordu).
    func triggerComponents(for date: Date, calendar: Calendar = .current) -> DateComponents {
        switch self {
        case .none:    return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        case .daily:   return calendar.dateComponents([.hour, .minute], from: date)
        case .weekly:  return calendar.dateComponents([.weekday, .hour, .minute], from: date)
        case .monthly: return calendar.dateComponents([.day, .hour, .minute], from: date)
        case .yearly:  return calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        }
    }
}

// MARK: - Reminder Model

struct Reminder: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var note: String = ""
    var date: Date
    var repeatType: ReminderRepeat = .none
    var isActive: Bool = true
    var notificationIDs: [String] = []
    var createdAt: Date = Date()
    var aiTaskPrompt: String = ""   // Boş değilse bu bir AI görevidir
    /// Zamanlayıcı ise toplam süresi (sn). Opsiyonel: eski kayıtlarda alan yok.
    var timerSeconds: Int? = nil
    var isTimer: Bool { timerSeconds != nil }
    var isAITask: Bool { !aiTaskPrompt.isEmpty }

    // Zamanlanmış görev durumu (bkz. ScheduledTaskRunner) — eski kayıtlarda alanlar yok
    var taskAttempts: Int? = nil
    /// Olay beklenirken bir sonraki kontrol zamanı
    var taskNextCheck: Date? = nil
    /// Tekrarlayan görevin son çalıştığı an
    var taskLastRun: Date? = nil
    var taskDone: Bool? = nil
    /// Sohbete henüz yazılmamış sonuçlar
    var taskInbox: [String]? = nil
    /// Görevin sonuçlarının yazıldığı sohbet
    var taskSessionID: UUID? = nil
    /// Dakikalık tekrar ("her 5 dakikada bir BTC fiyatı") — günlük/haftalık tekrar repeatType'tadır
    var taskIntervalMinutes: Int? = nil
    /// Tekrarlayan görevin bitişi (yoksa durdurulana kadar)
    var taskUntil: Date? = nil
    var taskRunCount: Int? = nil
    /// Sunucudaki göreve "şimdi çalıştır" isteği (zaman damgası)
    var taskRunNow: Int? = nil

    var isRepeatingTask: Bool { isAITask && (repeatType != .none || taskIntervalMinutes != nil) }

    /// Süresi geçti mi? (listeden kalkar, Ayarlar'daki geçmişe taşınır)
    /// Kullanıcı (14 Ekim 2026): "Dünkü maçın kadrosunu söyle demişim; maç bitti, gün geçti, hâlâ orada duruyor."
    /// ESKİ KURAL: sonucu gelmemiş tek seferlik görev sonsuza kadar listede kalıyordu.
    func isExpired(at now: Date = Date()) -> Bool {
        if isAITask {
            if taskDone == true { return true }
            if let until = taskUntil, until <= now { return true }
            // Tek seferlik görev: olay beklese bile 6 saat sonra bitmiş sayılır (sunucu en fazla 3 saat tekrar bakar)
            if !isRepeatingTask { return date.addingTimeInterval(6 * 3600) <= now }
            return false
        }
        return repeatType == .none && date <= now
    }

    /// Listede gösterilecek tarih: tekrarlayan hatırlatıcılarda ilk tarih geçmişte kalır,
    /// bu yüzden bir sonraki çalma zamanı hesaplanır.
    var nextOccurrence: Date {
        guard repeatType != .none, date < Date() else { return date }
        let components = repeatType.triggerComponents(for: date)
        return Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? date
    }
}

// MARK: - Reminder Manager

@MainActor
class ReminderManager: ObservableObject {
    static let shared = ReminderManager()
    
    @Published var reminders: [Reminder] = []
    @Published var pastReminders: [Reminder] = []
    
    private let storageKey = "pufy_reminders_v1"
    private let pastStorageKey = "pufy_past_reminders_v1"
    
    private init() {
        loadReminders()
        rescheduleRepeatingRemindersOnce()
    }

    /// Eski sürümde yanlış tetikleyiciyle kurulmuş tekrarlayan hatırlatıcıları bir kereliğine yeniden kurar.
    private func rescheduleRepeatingRemindersOnce() {
        let flag = "pufy_reminder_trigger_fix_v2"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        for index in reminders.indices where reminders[index].repeatType != .none {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: reminders[index].notificationIDs)
            reminders[index].notificationIDs = scheduleNotifications(for: reminders[index])
        }
        save()
    }

    /// Uygulama öne gelince: 30 dk içinde çalacak hatırlatıcılar için canlı etkinlik başlat
    /// (hatırlatıcı kurulduğunda 30 dk'dan uzaksa Live Activity hiç başlamıyordu).
    func startUpcomingLiveActivities() {
        for reminder in reminders {
            startLiveActivityIfNeeded(for: reminder)
        }
    }
    
    // MARK: CRUD
    
    func add(_ reminder: Reminder) {
        var r = reminder
        let notifIDs = scheduleNotifications(for: r)
        r.notificationIDs = notifIDs
        reminders.insert(r, at: 0)
        save()
        // Canlı bildirim başlat (≤30 dk ise)
        startLiveActivityIfNeeded(for: r)
        if r.isAITask { ScheduledTaskRunner.shared.scheduleNextRefresh() }
    }
    
    /// Zamanlayıcı: hemen canlı geri sayım + süre dolunca bildirim
    @discardableResult
    func addTimer(seconds: Int, title: String) -> Reminder {
        var timer = Reminder(title: title, note: "", date: Date().addingTimeInterval(TimeInterval(seconds)))
        timer.timerSeconds = seconds
        add(timer)
        return timer
    }

    func delete(_ reminder: Reminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminder.notificationIDs)
        // Canlı bildirimi durdur
        stopLiveActivity(for: reminder)
        reminders.removeAll { $0.id == reminder.id }
        save()
        if reminder.isAITask { ScheduledTaskRunner.shared.scheduleNextRefresh() }
    }

    // MARK: Zamanlanmış görevler

    /// Listede gösterilecekler: süresi geçenler (uygulama açıkken geçse bile) hemen gizlenir
    var visibleReminders: [Reminder] {
        let now = Date()
        return reminders.filter { !$0.isExpired(at: now) }
    }

    /// Henüz bitmemiş yapay zeka görevleri
    var pendingAITasks: [Reminder] {
        reminders.filter { $0.isAITask && $0.isActive && $0.taskDone != true }
    }

    /// Sohbete yazılmayı bekleyen sonucu olan görevler (bitmiş olanlar geçmiş listesinde olabilir)
    var aiTasksWithResults: [Reminder] {
        (reminders + pastReminders).filter { $0.isAITask && !($0.taskInbox ?? []).isEmpty }
    }

    func reminder(id: UUID) -> Reminder? {
        reminders.first { $0.id == id } ?? pastReminders.first { $0.id == id }
    }

    /// Görev durumunu güncelle (aktif ya da geçmiş listede)
    func updateTask(_ id: UUID, _ mutate: (inout Reminder) -> Void) {
        if let index = reminders.firstIndex(where: { $0.id == id }) {
            mutate(&reminders[index])
            save()
        } else if let index = pastReminders.firstIndex(where: { $0.id == id }) {
            mutate(&pastReminders[index])
            savePast()
        }
    }
    
    func update(_ updated: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == updated.id }) else { return }
        // Eski bildirimleri iptal et
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminders[index].notificationIDs)
        // Eski Live Activity'yi durdur
        stopLiveActivity(for: reminders[index])
        var r = updated
        let notifIDs = scheduleNotifications(for: r)
        r.notificationIDs = notifIDs
        reminders[index] = r
        save()
        // Yeni Live Activity başlat (≤30 dk ise)
        startLiveActivityIfNeeded(for: r)
    }
    
    // MARK: - Live Activity
    
    /// Hatırlatıcıya 30 dakika veya daha az kaldıysa canlı bildirim başlatır.
    func startLiveActivityIfNeeded(for reminder: Reminder) {
        guard #available(iOS 16.2, *), reminder.isActive else { return }
        let fireDate = reminder.nextOccurrence
        let remaining = fireDate.timeIntervalSinceNow
        // Zamanlayıcılar hemen (8 saate kadar), hatırlatıcılar son 30 dakikada canlı etkinlik olur
        let window: TimeInterval = reminder.isTimer ? 8 * 3600 : 1800
        guard remaining > 0, remaining <= window else { return }

        let state = PufyLiveActivityAttributes.ContentState(
            title: reminder.isTimer ? Self.timerTitle(reminder) : PufyNotifications.clean(reminder.title),
            subtitle: reminder.isTimer ? "" : PufyNotifications.clean(reminder.note),
            startDate: reminder.isTimer ? reminder.createdAt : Date(),
            endDate: fireDate
        )
        LiveActivityCenter.start(id: reminder.id.uuidString,
                                 kind: reminder.isTimer ? .timer : .reminder,
                                 state: state,
                                 symbol: reminder.isTimer ? "timer" : "bell.fill")
    }

    /// "Zamanlayıcı · 5 dakika" / "Çay demleme · 5 dakika"
    static func timerTitle(_ reminder: Reminder) -> String {
        let seconds = reminder.timerSeconds ?? 0
        let duration: String
        if seconds >= 3600 {
            let h = seconds / 3600, m = (seconds % 3600) / 60
            duration = m > 0 ? "\(h) saat \(m) dakika" : "\(h) saat"
        } else if seconds >= 60 {
            let m = seconds / 60, sec = seconds % 60
            duration = sec > 0 ? "\(m) dakika \(sec) saniye" : "\(m) dakika"
        } else {
            duration = "\(seconds) saniye"
        }
        let name = PufyNotifications.clean(reminder.title)
        let generic = name.isEmpty || name.lowercased(with: Locale(identifier: "tr_TR")).contains("zamanlayıcı")
            || name.lowercased(with: Locale(identifier: "tr_TR")).contains("sayaç")
        return "\(generic ? "Zamanlayıcı" : name) · \(duration)"
    }

    /// Belirtilen hatırlatıcı için aktif canlı etkinliği durdurur.
    func stopLiveActivity(for reminder: Reminder) {
        guard #available(iOS 16.2, *) else { return }
        LiveActivityCenter.end(id: reminder.id.uuidString)
    }

    /// Süresi dolmuş / silinmiş hatırlatıcıların canlı etkinliklerini temizler (açılışta).
    func cleanExpiredLiveActivities() {
        guard #available(iOS 16.2, *) else { return }
        LiveActivityCenter.endExpired()
        for activity in Activity<PufyLiveActivityAttributes>.activities
        where activity.attributes.kind == .reminder || activity.attributes.kind == .timer {
            if !reminders.contains(where: { $0.id.uuidString == activity.attributes.reminderID }) {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    // MARK: Notification Scheduling
    
    @discardableResult
    private func scheduleNotifications(for reminder: Reminder) -> [String] {
        // Tekrarlayan hatırlatıcının ilk tarihi geçmiş olabilir — yine de kurulmalı
        guard reminder.isActive, reminder.repeatType != .none || reminder.date > Date() else { return [] }
        // Dakikalık görevlerde "bakıyorum" bildirimi kurulmaz; her sonuç kendi bildirimiyle gelir
        guard reminder.taskIntervalMinutes == nil else { return [] }

        let content = UNMutableNotificationContent()
        // Bildirimlerde emoji yok (kullanıcı isteği)
        if reminder.isAITask {
            // Görev bu saatte kendiliğinden çalışır; sonuç gelince bu bildirimin yerine geçer
            content.title = PufyNotifications.clean(reminder.title)
            // Görev sunucuda çalışıyorsa: sonuç saatinde hazır olur, dokununca gelir
            content.body = SyncService.shared.managesTasks
                ? "Sonuç hazır, görmek için dokun."
                : "Şimdi bakıyorum, sonucu buraya yazacağım. Beklemek istemezsen dokun."
        } else if reminder.isTimer {
            content.title = "Süre doldu"
            content.body = Self.timerTitle(reminder)
        } else {
            content.title = PufyNotifications.clean(reminder.title)
            content.body = PufyNotifications.clean(String(reminder.note.prefix(140)))
            content.categoryIdentifier = PufyNotifications.reminderCategory   // "10 dk ertele" / "Tamam"
        }
        content.sound = .default
        // AI görevi bilgisini bildirim içine göm — tap sırasında alınabilsin
        if !reminder.aiTaskPrompt.isEmpty {
            content.userInfo = [
                "aiTaskPrompt": reminder.aiTaskPrompt,
                "aiTaskTitle": reminder.title,
                "taskReminderID": reminder.id.uuidString
            ]
            content.threadIdentifier = "pufytask.\(reminder.id.uuidString)"
        }
        
        let id = UUID().uuidString
        let components = reminder.repeatType.triggerComponents(for: reminder.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components,
                                                    repeats: reminder.repeatType != .none)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            if let error { print("⚠️ Bildirim kurulamadı: \(error.localizedDescription)") }
        }
        return [id]
    }
    
    // MARK: Persistence
    
    private func save() {
        SyncService.shared.scheduleSync()
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    // MARK: Eşitleme (diğer cihazdan gelen) — bildirim bu cihazda yeniden kurulur

    func applyRemote(_ remote: Reminder) {
        if let index = reminders.firstIndex(where: { $0.id == remote.id }) {
            let current = reminders[index]
            guard current.title != remote.title || current.note != remote.note || current.date != remote.date
                    || current.repeatType != remote.repeatType || current.isActive != remote.isActive else { return }
            var merged = current
            merged.title = remote.title
            merged.note = remote.note
            merged.date = remote.date
            merged.repeatType = remote.repeatType
            merged.isActive = remote.isActive
            update(merged)
        } else if remote.repeatType != .none || remote.date > Date() {
            add(remote)
        }
    }

    /// Diğer cihazda kurulan / değişen sunucu görevi
    func applyRemoteTask(id: UUID, _ o: [String: Any]) {
        guard let title = o["title"] as? String, let prompt = o["prompt"] as? String, let date = (o["date"] as? NSNumber)?.doubleValue else { return }
        let repeatType = ReminderRepeat(rawValue: o["repeat"] as? String ?? "none") ?? .none
        let every = (o["everyMinutes"] as? NSNumber)?.intValue
        let until = (o["until"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let active = o["active"] as? Bool ?? true
        let runNow = (o["runNow"] as? NSNumber)?.intValue
        if let index = reminders.firstIndex(where: { $0.id == id }) {
            var r = reminders[index]
            let scheduleChanged = r.date.timeIntervalSince1970 != date || r.repeatType != repeatType || r.isActive != active
            r.title = title; r.aiTaskPrompt = prompt; r.date = Date(timeIntervalSince1970: date); r.repeatType = repeatType
            r.taskIntervalMinutes = every; r.taskUntil = until; r.isActive = active; r.taskRunNow = runNow
            if scheduleChanged { update(r) } else { reminders[index] = r; save() }
        } else if let index = pastReminders.firstIndex(where: { $0.id == id }) {
            // Geçmişteki görev (bitti): sadece bilgileri güncellenir, listeye geri dönmez
            pastReminders[index].title = title
            pastReminders[index].aiTaskPrompt = prompt
            savePast()
        } else if active {
            var r = Reminder(title: title, note: "AI görevi: \(prompt)", date: Date(timeIntervalSince1970: date), repeatType: repeatType)
            r.id = id; r.aiTaskPrompt = prompt; r.taskIntervalMinutes = every; r.taskUntil = until; r.taskRunNow = runNow
            if r.isExpired() {
                // Yeniden kurulumda dünkü görevler listeye geri gelmesin (sonuçları için geçmişte durur)
                pastReminders.insert(r, at: 0)
                savePast()
            } else {
                add(r)
            }
        }
    }

    func applyRemoteDeletion(_ id: UUID) {
        guard let reminder = reminders.first(where: { $0.id == id }) else { return }
        delete(reminder)
    }

    /// Görev diğer cihazda silindi: bitmişse geçmişe taşı (sonuçları dursun), bitmemişse kullanıcı silmiştir → sil
    func applyRemoteTaskDeletion(_ id: UUID) {
        guard let reminder = reminders.first(where: { $0.id == id }) else { return }
        if reminder.isExpired() { cleanExpiredNonRepeatingReminders() } else { delete(reminder) }
    }

    
    private func savePast() {
        if let data = try? JSONEncoder().encode(pastReminders) {
            UserDefaults.standard.set(data, forKey: pastStorageKey)
        }
    }
    
    func cleanExpiredNonRepeatingReminders() {
        let now = Date()
        // Kurallar Reminder.isExpired'da: geçmiş hatırlatıcı, biten görev, 6 saati geçen tek seferlik görev,
        // bitişi geçen tekrarlayan görev. Geçmişe taşınan sunucudan da silinir (yeniden kurulumda geri gelmez).
        let expired = reminders.filter { $0.isExpired(at: now) }
        if !expired.isEmpty {
            // Geçmiş listesine ekle
            for r in expired {
                if !pastReminders.contains(where: { $0.id == r.id }) {
                    pastReminders.insert(r, at: 0)
                }
            }
            savePast()
            
            reminders.removeAll { r in expired.contains(where: { $0.id == r.id }) }
            save()
        }
    }
    
    func clearPastReminders() {
        pastReminders.removeAll()
        savePast()
    }

    func deleteAll() {
        reminders.forEach { stopLiveActivity(for: $0) }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        reminders.removeAll()
        pastReminders.removeAll()
        save()
        savePast()
    }
    
    private func loadReminders() {
        loadPastReminders()
        
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = decoded
        cleanExpiredNonRepeatingReminders()
    }
    
    private func loadPastReminders() {
        guard let data = UserDefaults.standard.data(forKey: pastStorageKey),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        pastReminders = decoded
    }
    
    // MARK: AI Response Parser
    
    /// AI cevabındaki [REMINDER:...] etiketini parse eder — cevabın herhangi bir yerinde olabilir.
    /// Temizlenmiş cevap stringini (etiketsiz) döner.
    func parseAndExtract(from response: String) -> (Reminder?, String) {
        // [REMINDER: { JSON }] formatını yakalamak için esnek regex
        let pattern = "\\[REMINDER\\s*:\\s*(\\{.+?\\})\\s*\\]"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (nil, response)
        }
        
        let nsString = response as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        guard let match = regex.firstMatch(in: response, options: [], range: range) else {
            print("⚠️ Response içinde [REMINDER:...] formatı bulunamadı.")
            return (nil, response)
        }
        
        // JSON kısmını al
        let jsonRange = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)
        
        // Response'tan etiketi temizle
        let fullMatchRange = match.range(at: 0)
        let cleanText = nsString.replacingCharacters(in: fullMatchRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        guard let jsonData = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("⚠️ JSON serialization hatası. JSON string: \(jsonString)")
            return (nil, response)
        }
        
        let title = obj["title"] as? String ?? "Hatırlatıcı"
        let note = obj["note"] as? String ?? ""
        let repeatStr = obj["repeat"] as? String ?? "none"
        let repeatType = ReminderRepeat(rawValue: repeatStr) ?? .none
        
        // Tarihi parse et — birden fazla format dene
        var date = Date().addingTimeInterval(3600)
        if let dtString = obj["datetime"] as? String {
            date = parseFlexibleDate(from: dtString) ?? date
        }
        
        print("✅ Hatırlatıcı başarıyla parse edildi: \(title) - \(date) - \(repeatType.rawValue)")
        let reminder = Reminder(title: title, note: note, date: date, repeatType: repeatType)
        return (reminder, cleanText)
    }
    
    // MARK: AI Görevi Parse
    
    /// AI cevabındaki [AI_TASK:...] etiketini parse eder ve aiTaskPrompt alanı dolu bir Reminder döner.
    func parseAndExtractAITask(from response: String) -> (Reminder?, String) {
        let pattern = "\\[AI_TASK\\s*:\\s*(\\{.+?\\})\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (nil, response)
        }
        let nsString = response as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: response, options: [], range: range) else {
            return (nil, response)
        }
        
        let jsonRange  = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)
        let fullRange  = match.range(at: 0)
        let cleanText  = nsString.replacingCharacters(in: fullRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonString.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, response)
        }
        
        let title      = obj["title"]  as? String ?? "AI Görevi"
        let prompt     = obj["prompt"] as? String ?? ""
        var date       = Date().addingTimeInterval(3600)
        if let dtStr   = obj["datetime"] as? String {
            date = parseFlexibleDate(from: dtStr) ?? date
        }
        
        var reminder = Reminder(
            title: title,
            note: "AI görevi: \(prompt)",
            date: date,
            repeatType: (obj["repeat"] as? String).flatMap(ReminderRepeat.init(rawValue:)) ?? .none
        )
        reminder.aiTaskPrompt = prompt
        // "her 5 dakikada bir": dakikalık tekrar (en az 2 dk)
        let every = (obj["every_minutes"] as? Int) ?? (obj["every_minutes"] as? Double).map(Int.init)
            ?? (obj["every_minutes"] as? String).flatMap { Int($0) }
        if let every, every > 0 {
            reminder.taskIntervalMinutes = max(every, 2)
            reminder.repeatType = .none
            if let untilString = obj["until"] as? String, let until = parseFlexibleDate(from: untilString), until > date {
                reminder.taskUntil = until
            } else {
                // Bitiş söylenmediyse: sık tekrarlarda 2 saat, seyreklerde 1 gün (sonsuz API çağrısı olmasın)
                reminder.taskUntil = date.addingTimeInterval(every < 60 ? 2 * 3600 : 24 * 3600)
            }
        }
        
        print("✅ AI görevi planlandı: \(title) — \(date)")
        return (reminder, cleanText)
    }
    
    /// AI cevabındaki [DELETE_REMINDER:...] etiketini parse eder ve siler.
    /// Temizlenmiş cevap stringini döner.
    func parseAndDelete(from response: String) -> (String, String?) {
        let pattern = "\\[DELETE_REMINDER\\s*:\\s*(\\{.+?\\})\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (response, nil)
        }
        
        let nsString = response as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        guard let match = regex.firstMatch(in: response, options: [], range: range) else {
            return (response, nil)
        }
        
        let jsonRange = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)
        
        let fullMatchRange = match.range(at: 0)
        let cleanText = nsString.replacingCharacters(in: fullMatchRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        guard let jsonData = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let idStr = obj["id"] as? String,
              let uuid = UUID(uuidString: idStr) else {
            return (cleanText, nil)
        }
        
        // Silme işlemini yap
        if let reminderToDelete = reminders.first(where: { $0.id == uuid }) {
            let title = reminderToDelete.title
            delete(reminderToDelete)
            return (cleanText, title)
        }
        
        return (cleanText, nil)
    }
    
    /// AI cevabındaki [UPDATE_REMINDER:...] etiketini parse eder ve günceller.
    /// Temizlenmiş cevap stringini döner.
    func parseAndUpdate(from response: String) -> (String, String?) {
        let pattern = "\\[UPDATE_REMINDER\\s*:\\s*(\\{.+?\\})\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (response, nil)
        }
        
        let nsString = response as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        guard let match = regex.firstMatch(in: response, options: [], range: range) else {
            return (response, nil)
        }
        
        let jsonRange = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)
        
        let fullMatchRange = match.range(at: 0)
        let cleanText = nsString.replacingCharacters(in: fullMatchRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        guard let jsonData = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let idStr = obj["id"] as? String,
              let uuid = UUID(uuidString: idStr) else {
            return (cleanText, nil)
        }
        
        if let index = reminders.firstIndex(where: { $0.id == uuid }) {
            var updated = reminders[index]
            
            if let title = obj["title"] as? String {
                updated.title = title
            }
            if let note = obj["note"] as? String {
                updated.note = note
            }
            if let repeatStr = obj["repeat"] as? String,
               let repeatType = ReminderRepeat(rawValue: repeatStr) {
                updated.repeatType = repeatType
            }
            if let dtString = obj["datetime"] as? String,
               let parsedDate = parseFlexibleDate(from: dtString) {
                updated.date = parsedDate
            }
            
            update(updated)
            return (cleanText, updated.title)
        }
        
        return (cleanText, nil)
    }
    
    // Formatter'lar pahalı — her parse'ta yeniden oluşturulmasın
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return f
    }()

    private static let flexibleFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm"
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private func parseFlexibleDate(from dtString: String) -> Date? {
        let trimmed = dtString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = Self.isoFormatter.date(from: trimmed) { return date }
        // Küçük harf "t" yazan modeller için
        let normalized = trimmed.replacingOccurrences(of: "t", with: "T")
        for formatter in Self.flexibleFormatters {
            if let date = formatter.date(from: normalized) { return date }
        }
        return nil
    }
}
