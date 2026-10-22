import ActivityKit
import Foundation

// MARK: - Pufy Canlı Etkinlik Modeli
// Ana uygulama ve Widget eklentisi tarafından paylaşılır.
// Tek model, dört tür: hatırlatıcı, zamanlayıcı, uygulama üretimi (görev) ve mini uygulamaların
// kendi canlı etkinlikleri (window.pufy.live).

struct PufyLiveActivityAttributes: ActivityAttributes {

    enum Kind: String, Codable, Hashable {
        case reminder   // hatırlatıcı: çalma zamanına geri sayım
        case timer      // zamanlayıcı: "5 dk" geri sayım + ilerleme halkası
        case task       // uzun iş (ör. uygulama üretimi): durum + ilerleme
        case app        // mini uygulamanın kendi etkinliği
    }

    // MARK: Değişen içerik
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String = ""
        /// Geri sayımın başladığı an (ilerleme çubuğu için)
        var startDate: Date = Date()
        /// Geri sayımın bittiği an — nil ise geri sayım yok
        var endDate: Date? = nil
        /// Belirli ilerleme 0…1 (görevler için) — nil ise gösterilmez
        var progress: Double? = nil
        /// Kısa durum metni ("Hazırlanıyor…", "Tamamlandı")
        var status: String? = nil
        var isFinished: Bool = false

        // MARK: Şablon (13 Ekim 2026): canlı bildirim sadece geri sayım değil
        /// "countdown" (varsayılan, endDate varsa) | "progress" | "score" | "metric"
        var style: String? = nil
        // score: iki taraf + skor + dakika (maç, oyun, yarış)
        var home: Side? = nil
        var away: Side? = nil
        var homeScore: Int? = nil
        var awayScore: Int? = nil
        /// "67'", "İY", "MS"
        var minute: String? = nil
        // metric: tek büyük değer (fiyat, kur, adım, sıcaklık…)
        var value: String? = nil
        var unit: String? = nil
        /// "up" | "down" | "flat"
        var trend: String? = nil
        var change: String? = nil

        struct Side: Codable, Hashable {
            var name: String
            /// Rozette görünen kısa ad (en fazla 3-4 harf): "GS", "FB"
            var short: String? = nil
            /// Rozet rengi #RRGGBB
            var color: String? = nil
        }

        var resolvedStyle: String {
            if let style { return style }
            if home != nil && away != nil { return "score" }
            if value != nil { return "metric" }
            if endDate != nil { return "countdown" }
            return "progress"
        }
    }

    // MARK: Sabit içerik
    var kind: Kind
    /// Eşleştirme kimliği (hatırlatıcı kimliği, görev kimliği, uygulama klasörü)
    var reminderID: String
    /// Mini uygulamanın adı ("Damla") — Pufy'nin kendi etkinliklerinde nil
    var appName: String? = nil
    /// SF Symbol (mini uygulamalar ve türe göre ikon)
    var symbol: String = "bell.fill"
    /// Mini uygulamanın kimlik rengi (#RRGGBB)
    var colorHex: String? = nil
}
