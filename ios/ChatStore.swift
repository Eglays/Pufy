import Foundation

/// Sohbet geçmişinin kalıcı deposu.
///
/// Neden UserDefaults değil? UserDefaults küçük ayarlar içindir; uygulama açılırken TAMAMI
/// belleğe okunur. Sohbetlerde fotoğraflar da olduğu için eski yöntemde her kayıtta onlarca MB
/// JSON (görseller base64 → %33 daha büyük) ana thread'de yazılıyordu.
/// Burada: binary plist (Data'yı base64'e çevirmez), arka plan kuyruğu, kısa gecikmeli birleştirme.
final class ChatStore {
    static let shared = ChatStore()

    private let legacyKey = "pufy_agent_chat_sessions"
    private let queue = DispatchQueue(label: "com.pufy.chatstore", qos: .utility)
    private var pendingWork: DispatchWorkItem?
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PufyAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sessions.plist")
    }

    func load() -> [ChatSession] {
        if let data = try? Data(contentsOf: fileURL) {
            do {
                return try PropertyListDecoder().decode([ChatSession].self, from: data)
            } catch {
                // Veriyi asla silme: bozuk dosyayı kenara kopyala, kullanıcı verisi kaybolmasın
                print("⚠️ Sohbet dosyası okunamadı: \(error)")
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("bozuk-\(Int(Date().timeIntervalSince1970)).plist")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                return []
            }
        }

        // Eski sürümden geçiş: UserDefaults'taki JSON'u dosyaya taşı
        if let legacy = UserDefaults.standard.data(forKey: legacyKey),
           let sessions = try? JSONDecoder().decode([ChatSession].self, from: legacy) {
            if Self.write(sessions, to: fileURL) {
                UserDefaults.standard.removeObject(forKey: legacyKey)
                print("✅ \(sessions.count) sohbet UserDefaults'tan dosyaya taşındı.")
            }
            return sessions
        }
        return []
    }

    /// Kısa aralıklarla gelen kayıt isteklerini birleştirip arka planda yazar.
    /// `immediately`: uygulama arka plana geçerken — yazma bitene kadar bekler.
    func save(_ sessions: [ChatSession], immediately: Bool = false) {
        pendingWork?.cancel()
        let url = fileURL
        let work = DispatchWorkItem { Self.write(sessions, to: url) }
        pendingWork = work
        if immediately {
            queue.sync(execute: work)
        } else {
            queue.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    @discardableResult
    private static func write(_ sessions: [ChatSession], to url: URL) -> Bool {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(sessions)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            print("❌ Sohbet geçmişi kaydedilemedi: \(error)")
            return false
        }
    }
}
