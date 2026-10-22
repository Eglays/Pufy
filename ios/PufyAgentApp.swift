import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Hatırlatıcı bildirim düğmeleri ("10 dk ertele", "Tamam")
        PufyNotifications.registerCategories()
        // iOS 26: arka plana alınan uzun işler (uygulama üretimi) sürsün — açılışta kaydedilmeli
        MainActor.assumeIsolated {
            BackgroundWork.registerHandler()
            // Zamanlanmış yapay zeka görevleri: vakti gelince arka planda kendiliğinden çalışır
            ScheduledTaskRunner.shared.registerHandler()
        }
        
        // Bildirim izni iste
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("⚠️ Bildirim izni hatası: \(error.localizedDescription)")
            }
        }
        return true
    }
    
    // Uygulama ön plandayken gelen bildirimler
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
        let info = notification.request.content.userInfo
        DispatchQueue.main.async {
            ReminderManager.shared.cleanExpiredNonRepeatingReminders()
            // Uygulama açıkken görevin vakti geldi → hemen çalıştır
            if info["aiTaskPrompt"] != nil, let raw = info["taskReminderID"] as? String, let id = UUID(uuidString: raw) {
                Task { await ScheduledTaskRunner.shared.run(id) }
            }
        }
    }
    
    // Kullanıcı bildirime dokunduğunda
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // "10 dk ertele": aynı bildirimi 10 dakika sonra tekrar kur
        if response.actionIdentifier == PufyNotifications.snoozeAction {
            let original = response.notification.request.content
            let content = UNMutableNotificationContent()
            content.title = original.title
            content.body = original.body
            content.sound = .default
            content.categoryIdentifier = PufyNotifications.reminderCategory
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: UUID().uuidString, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
        }
        
        // Mini uygulama bildirimi → o uygulamayı aç
        if let folder = userInfo["miniAppFolder"] as? String, !folder.isEmpty {
            DispatchQueue.main.async { TabManager.shared.openMiniApp(folder: folder) }
        }

        // Zamanlanmış görev bildirimi → görevin sohbeti açılır (sonuç yoksa görev o an çalışır)
        if let raw = userInfo["taskReminderID"] as? String, UUID(uuidString: raw) != nil {
            UserDefaults.standard.set(raw, forKey: "pufy_open_task")
        } else if let aiTaskPrompt = userInfo["aiTaskPrompt"] as? String, !aiTaskPrompt.isEmpty {
            // Eski sürümün bildirimleri (görev kimliği yok)
            let aiTaskTitle = userInfo["aiTaskTitle"] as? String ?? "Planlanmış Görev"
            // UserDefaults'a yaz — app aktif olunca alınacak
            UserDefaults.standard.set(aiTaskPrompt, forKey: "pufy_pending_ai_task")
            UserDefaults.standard.set(aiTaskTitle, forKey: "pufy_pending_ai_title")
            print("🤖 Zamanlanmış AI görevi beklemeye alındı: \(aiTaskPrompt.prefix(60))")
        }
        
        DispatchQueue.main.async {
            ReminderManager.shared.cleanExpiredNonRepeatingReminders()
        }
        completionHandler()
    }
}

@main
struct PufyAgentApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("app_language") private var appLanguage: String = "auto"
    @StateObject private var viewModel = ChatViewModel.shared
    
    init() {
        // Endpoint, model, format, anahtarlar (Keychain) — eski düz metin anahtar burada Keychain'e taşınır
        AIConfig.loadIntoServices()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(\.locale, AppLanguage.swiftUILocale(for: appLanguage))
                .tint(.pufyPrimary)
                // Paylaşılan uygulamayı ekleme ekranı + "bağlantı hazırlanıyor" göstergesi
                // Canlı etkinliğe dokununca: pufy://app/<klasör> → o mini uygulama
                .onOpenURL { url in
                    guard url.scheme == "pufy" else { return }
                    let last = url.lastPathComponent
                    guard !last.isEmpty, last != "/" else { return }
                    switch url.host {
                    case "app": TabManager.shared.openMiniApp(folder: last)
                    default: break
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .inactive:
                        // Arka plana geçmek üzere: iş yapan mini uygulama varsa sürdür (iOS bunu ancak ön plandayken başlatır)
                        MiniAppBackgroundKeeper.shared.appWillResignActive()
                    case .active:
                        MiniAppBackgroundKeeper.shared.appDidBecomeActive()
                        // Bekleyen AI görevi var mı kontrol et
                        checkPendingAITask()
                        viewModel.importTaskResults()
                        // Açılışta bir kez: diğer cihazlardaki yenilikleri al (sürekli kontrol yok — bkz. SyncService)
                        Task { await SyncService.shared.syncNow() }
                        ReminderManager.shared.cleanExpiredNonRepeatingReminders()
                        ScheduledTaskRunner.shared.startForegroundChecks()
                        // Süresi dolmuş Live Activity'leri temizle, yaklaşanları başlat
                        ReminderManager.shared.cleanExpiredLiveActivities()
                        ReminderManager.shared.startUpcomingLiveActivities()
                    case .background:
                        // Arka plana geçerken bekleyen kaydı hemen diske yaz
                        viewModel.forceSaveSessions()
                        // Bekleyen gönderim varsa hemen gönder (uygulama askıya alınmadan)
                        let flush = UIApplication.shared.beginBackgroundTask(withName: "PufySyncFlush") {}
                        Task {
                            await SyncService.shared.flushPending()
                            UIApplication.shared.endBackgroundTask(flush)
                        }
                        ScheduledTaskRunner.shared.stopForegroundChecks()
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "pufy_agent_last_exit")
                    default:
                        break
                    }
                }
        }
    }
    
    // MARK: - Pending AI Task
    
    @MainActor
    private func checkPendingAITask() {
        if let raw = UserDefaults.standard.string(forKey: "pufy_open_task"), let id = UUID(uuidString: raw) {
            UserDefaults.standard.removeObject(forKey: "pufy_open_task")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { viewModel.openTaskSession(reminderID: id) }
            return
        }
        guard let prompt = UserDefaults.standard.string(forKey: "pufy_pending_ai_task"),
              !prompt.isEmpty else { return }
        let title = UserDefaults.standard.string(forKey: "pufy_pending_ai_title") ?? "Planlanmış Görev"
        
        // Temizle — bir kez çalıştır
        UserDefaults.standard.removeObject(forKey: "pufy_pending_ai_task")
        UserDefaults.standard.removeObject(forKey: "pufy_pending_ai_title")
        
        print("🤖 Zamanlanmış AI görevi çalıştırılıyor: \(prompt.prefix(60))")
        
        // Kısa bir gecikme — ContentView yüklenmesini bekle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            viewModel.executeScheduledTask(prompt: prompt, title: title)
        }
    }
}
