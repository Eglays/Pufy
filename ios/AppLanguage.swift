import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic = "auto"
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Otomatik")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    /// Kullanıcının seçimi veya sistem dili doğrultusunda çözümlenen 2 harfli dil kodu ("tr" veya "en")
    static var resolvedLanguageCode: String {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "auto"
        if saved == "tr" { return "tr" }
        if saved == "en" { return "en" }
        // Otomatik: sistem tercihli dillerinde Türkçe varsa "tr", aksi halde "en"
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        if preferred.lowercased().hasPrefix("tr") {
            return "tr"
        }
        return "en"
    }

    /// Çözümlenen dil koduna göre Foundation Locale nesnesi
    static var currentLocale: Locale {
        resolvedLanguageCode == "tr" ? Locale(identifier: "tr_TR") : Locale(identifier: "en_US")
    }

    /// SwiftUI View hiyerarşisinde .environment(\.locale, ...) için SwiftUI Locale nesnesi
    static var swiftUILocale: SwiftUI.Locale {
        SwiftUI.Locale(identifier: resolvedLanguageCode)
    }

    static func swiftUILocale(for code: String) -> SwiftUI.Locale {
        if code == "tr" {
            return SwiftUI.Locale(identifier: "tr")
        } else if code == "en" {
            return SwiftUI.Locale(identifier: "en")
        } else {
            return SwiftUI.Locale(identifier: resolvedLanguageCode)
        }
    }

    /// Arayüz İngilizce mi?
    static var isEnglish: Bool {
        resolvedLanguageCode == "en"
    }
}
