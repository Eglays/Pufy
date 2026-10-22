import Foundation

// MARK: - Senkron yok
// Pufy'de hesap ve sunucu yoktur; tüm veriler cihazda kalır. Bu tür, uygulamanın kaydetme
// noktalarının çağırdığı ama hiçbir şey yapmayan bir kancadır. Kendi eşitleme altyapını
// eklemek istersen buradan başlayabilirsin.
//
// There is no account and no server: all data stays on the device. This type is a no-op
// hook that the app's save points call; plug your own sync in here if you need one.

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()
    private init() {}

    weak var chat: ChatViewModel?
    /// Zamanlanmış görevler her zaman cihazda çalışır / Scheduled tasks always run on device
    var managesTasks: Bool { false }

    func scheduleSync(after delay: TimeInterval = 0) {}
    func syncNow() async {}
    func fullResync() async {}
    func flushPending() async {}
    func avatarChanged() {}
}
