import Foundation
import Security
import UIKit
import ImageIO

// MARK: - API Formatı
// "Kendi yapay zekanı getir": kullanıcı endpoint + anahtar + model adı girer.
// Piyasadaki neredeyse tüm sağlayıcılar şu iki formattan birini konuşur.

enum APIFormat: String, CaseIterable, Identifiable {
    case gemini
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .openAI: return "OpenAI uyumlu"
        }
    }

    var footnote: String {
        switch self {
        case .gemini:
            return "Google Gemini REST formatı (/v1beta/models/…:generateContent). Gemini proxy'leri de bu formatı kullanır."
        case .openAI:
            return "/chat/completions formatı. OpenAI, OpenRouter, Groq, DeepSeek, Mistral, xAI, Anthropic (uyumluluk katmanı), Ollama ve LM Studio ile çalışır."
        }
    }
}

// MARK: - Hazır Sağlayıcılar (tek dokunuşla endpoint doldurma)

struct ProviderPreset: Identifiable {
    let id: String
    let name: String
    let format: APIFormat
    let baseURL: String
    let modelHint: String
    var keyURL: String? = nil
    var isLocal: Bool { id == "ollama" || id == "lmstudio" }
    var requiresKey: Bool { !isLocal && id != "custom" }

    var helpText: String? {
        switch id {
        case "ollama":
            return AppLanguage.isEnglish
                ? "Start Ollama on your computer accessible over the network (`OLLAMA_HOST=0.0.0.0 ollama serve`). Your phone and computer must be on the same Wi-Fi. Enter your computer's local IP address."
                : "Bilgisayarında Ollama'yı ağdan erişilebilir başlat (`OLLAMA_HOST=0.0.0.0 ollama serve`). Telefonun ve bilgisayarın aynı Wi-Fi'de olmalı. Adrese bilgisayarının yerel IP'sini yaz."
        case "lmstudio":
            return AppLanguage.isEnglish
                ? "Open LM Studio → Developer → Local Server, check 'Serve on Local Network'. Port 1234."
                : "LM Studio → Developer → Local Server'ı aç, 'Serve on Local Network' seçeneğini işaretle. Port 1234."
        default:
            return nil
        }
    }

    static let all: [ProviderPreset] = [
        ProviderPreset(id: "gemini",     name: "Google Gemini",    format: .gemini, baseURL: "https://generativelanguage.googleapis.com", modelHint: "gemini-2.5-flash", keyURL: "https://aistudio.google.com/apikey"),
        ProviderPreset(id: "openai",     name: "OpenAI",           format: .openAI, baseURL: "https://api.openai.com/v1",                modelHint: "gpt-4o-mini", keyURL: "https://platform.openai.com/api-keys"),
        ProviderPreset(id: "anthropic",  name: "Anthropic Claude", format: .openAI, baseURL: "https://api.anthropic.com/v1",             modelHint: "claude-3-5-haiku-20241022", keyURL: "https://console.anthropic.com/settings/keys"),
        ProviderPreset(id: "openrouter", name: "OpenRouter",       format: .openAI, baseURL: "https://openrouter.ai/api/v1",             modelHint: "google/gemini-2.5-flash", keyURL: "https://openrouter.ai/keys"),
        ProviderPreset(id: "nvidia",     name: "NVIDIA",           format: .openAI, baseURL: "https://integrate.api.nvidia.com/v1",       modelHint: "meta/llama-3.3-70b-instruct", keyURL: "https://build.nvidia.com/settings/api-keys"),
        ProviderPreset(id: "groq",       name: "Groq",             format: .openAI, baseURL: "https://api.groq.com/openai/v1",           modelHint: "llama-3.3-70b-versatile", keyURL: "https://console.groq.com/keys"),
        ProviderPreset(id: "deepseek",   name: "DeepSeek",         format: .openAI, baseURL: "https://api.deepseek.com/v1",              modelHint: "deepseek-chat", keyURL: "https://platform.deepseek.com/api_keys"),
        ProviderPreset(id: "mistral",    name: "Mistral",          format: .openAI, baseURL: "https://api.mistral.ai/v1",                modelHint: "mistral-small-latest", keyURL: "https://console.mistral.ai/api-keys"),
        ProviderPreset(id: "xai",        name: "xAI",              format: .openAI, baseURL: "https://api.x.ai/v1",                      modelHint: "grok-2-latest", keyURL: "https://console.x.ai"),
        ProviderPreset(id: "ollama",     name: "Ollama (yerel)",   format: .openAI, baseURL: "http://192.168.1.10:11434/v1",             modelHint: ""),
        ProviderPreset(id: "lmstudio",   name: "LM Studio (yerel)",format: .openAI, baseURL: "http://192.168.1.10:1234/v1",              modelHint: ""),
        ProviderPreset(id: "custom",     name: "Özel sunucu",      format: .openAI, baseURL: "",                                          modelHint: "")
    ]
}

// MARK: - Keychain
// API anahtarları UserDefaults'ta (düz metin plist) değil, Keychain'de tutulur.

enum Keychain {
    private static let service = "com.pufy.PufyAgent"
    /// Bu oturumda yazılanlar: Keychain bir sebeple yazamasa da (Mac) uygulama açık kaldıkça oturum/anahtar kaybolmaz
    private static var cache: [String: String] = [:]

    private static func base(_ key: String, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    /// Mac'te iki Keychain türü var; uygulamaya özel olanı (iPhone'daki gibi) dener, olmazsa klasiğe yazar.
    /// ESKİ HATA (Mac, 20 Ekim 2026): oturum anahtarı kaydedilemiyor → giriş yapılmış görünse de eşitleme hiç başlamıyordu.
    private static var variants: [Bool] {
        #if targetEnvironment(macCatalyst)
        return [true, false]
        #else
        return [false]
        #endif
    }

    static func set(_ value: String, for key: String) {
        cache[key] = value.isEmpty ? nil : value
        for dp in variants { SecItemDelete(base(key, dataProtection: dp) as CFDictionary) }
        guard !value.isEmpty, let data = value.data(using: .utf8) else { MacVault.set(nil, for: key); return }
        for dp in variants {
            var add = base(key, dataProtection: dp)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecSuccess { MacVault.set(nil, for: key); return }
            print("⚠️ Keychain yazılamadı (\(key), korumalı: \(dp)): \(status)")
        }
        MacVault.set(value, for: key)
    }

    static func get(_ key: String) -> String? {
        if let hit = cache[key] { return hit }
        for dp in variants {
            var query = base(key, dataProtection: dp)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let text = String(data: data, encoding: .utf8) {
                cache[key] = text
                return text
            }
        }
        if let text = MacVault.get(key) { cache[key] = text; return text }
        return nil
    }
}

/// Mac'te Keychain hiç yazamazsa son çare: uygulamanın kendi korumalı kabındaki (sandbox) gizli dosya.
/// ESKİ HATA (Mac, 21 Ekim 2026): Keychain yazamadığı için API anahtarı her açılışta siliniyordu.
/// iPhone'da kullanılmaz (orada Keychain her zaman çalışır).
private enum MacVault {
    private static var url: URL? {
        #if targetEnvironment(macCatalyst)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PufyAgent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".vault.json")
        #else
        return nil
        #endif
    }

    private static func load() -> [String: String] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func get(_ key: String) -> String? { load()[key] }

    static func set(_ value: String?, for key: String) {
        guard let url else { return }
        var all = load()
        if all[key] == value { return }
        all[key] = value
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

// MARK: - Ayarların Kalıcılığı

enum AIConfig {
    // UserDefaults anahtarları — eski sürümle uyumlu kalsın diye isimler korundu
    static let endpointKey   = "gemini_endpoint"
    static let modelKey      = "gemini_model"
    static let formatKey     = "pufy_api_format"
    static let imageModelKey = "pufy_image_model"
    static let heavyModelKey = "pufy_heavy_model"
    static let streamingKey  = "pufy_streaming_enabled"
    static let googleSearchKey = "pufy_google_search"
    static let searxngKey    = "searxng_base_url"

    // Keychain hesap adları
    static let apiKeyAccount  = "ai_api_key"
    static let jinaKeyAccount = "jina_api_key"

    static func resetAll() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: endpointKey)
        defaults.removeObject(forKey: modelKey)
        defaults.removeObject(forKey: formatKey)
        defaults.removeObject(forKey: imageModelKey)
        defaults.removeObject(forKey: heavyModelKey)
        defaults.removeObject(forKey: streamingKey)
        defaults.removeObject(forKey: googleSearchKey)
        defaults.removeObject(forKey: searxngKey)
        defaults.removeObject(forKey: "gemini_api_key")
        Keychain.set("", for: apiKeyAccount)
        Keychain.set("", for: jinaKeyAccount)
        let ai = GeminiService.shared
        ai.apiKey = ""
        ai.endpoint = ""
        ai.modelName = ""
        ai.heavyModelName = ""
        ai.imageModelName = ""
        SearXNGService.shared.baseUrl = ""
        JinaReaderService.shared.apiKey = ""
    }

    /// Uygulama açılışında servisleri kayıtlı ayarlarla doldurur.
    /// Eski sürümden kalan düz metin API anahtarını Keychain'e taşır.
    static func loadIntoServices() {
        let defaults = UserDefaults.standard
        let ai = GeminiService.shared

        if let legacyKey = defaults.string(forKey: "gemini_api_key") {
            if Keychain.get(apiKeyAccount) == nil { Keychain.set(legacyKey, for: apiKeyAccount) }
            defaults.removeObject(forKey: "gemini_api_key")
        }

        ai.apiKey = Keychain.get(apiKeyAccount) ?? ""
        if let endpoint = defaults.string(forKey: endpointKey) {
            ai.endpoint = endpoint
        }
        if let model = defaults.string(forKey: modelKey) { ai.modelName = model }
        if let raw = defaults.string(forKey: formatKey), let format = APIFormat(rawValue: raw) { ai.apiFormat = format }
        if let imageModel = defaults.string(forKey: imageModelKey) { ai.imageModelName = imageModel }
        if let heavy = defaults.string(forKey: heavyModelKey) { ai.heavyModelName = heavy }
        if defaults.object(forKey: streamingKey) != nil { ai.streamingEnabled = defaults.bool(forKey: streamingKey) }
        if defaults.object(forKey: googleSearchKey) != nil { ai.googleSearchEnabled = defaults.bool(forKey: googleSearchKey) }

        if let searx = defaults.string(forKey: searxngKey) { SearXNGService.shared.baseUrl = searx }
        JinaReaderService.shared.apiKey = Keychain.get(jinaKeyAccount) ?? ""
    }

    static func save(apiKey: String, endpoint: String, model: String, format: APIFormat,
                     imageModel: String, streaming: Bool, searxngURL: String, jinaKey: String,
                     googleSearch: Bool = true, heavyModel: String? = nil) {
        let ai = GeminiService.shared
        ai.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.apiFormat = format
        ai.imageModelName = imageModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let heavyModel { ai.heavyModelName = heavyModel.trimmingCharacters(in: .whitespacesAndNewlines) }
        ai.streamingEnabled = streaming
        ai.googleSearchEnabled = googleSearch
        UserDefaults.standard.set(googleSearch, forKey: googleSearchKey)
        SearXNGService.shared.baseUrl = searxngURL.trimmingCharacters(in: .whitespacesAndNewlines)
        JinaReaderService.shared.apiKey = jinaKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Keychain.set(ai.apiKey, for: apiKeyAccount)
        Keychain.set(JinaReaderService.shared.apiKey, for: jinaKeyAccount)

        let defaults = UserDefaults.standard
        defaults.set(ai.endpoint, forKey: endpointKey)
        defaults.set(ai.modelName, forKey: modelKey)
        defaults.set(format.rawValue, forKey: formatKey)
        defaults.set(ai.imageModelName, forKey: imageModelKey)
        defaults.set(ai.heavyModelName, forKey: heavyModelKey)
        defaults.set(streaming, forKey: streamingKey)
        defaults.set(SearXNGService.shared.baseUrl, forKey: searxngKey)
    }
}

// MARK: - Görsel Yardımcıları

enum ImageUtils {
    /// Görseli uzun kenarı `maxDimension` olacak şekilde küçültüp JPEG'e çevirir.
    /// 12MP kamera fotoğrafı (~4 MB) → ~250 KB. Hem API isteği hem disk kaydı hızlanır.
    static func preparedJPEG(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))   // yön (EXIF) de düzeltilir
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    static func preparedJPEG(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        if longest <= maxDimension && data.count < 600_000 { return data }
        return preparedJPEG(from: image, maxDimension: maxDimension, quality: quality) ?? data
    }

    /// Bellek dostu küçük resim (ImageIO downsampling — tam boy decode etmez)
    static func thumbnail(from data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Sohbetteki görseller her çizimde yeniden decode edilmesin diye küçük önbellek
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() { cache.countLimit = 120 }

    func image(for data: Data, key: String, maxPixel: CGFloat = 720) -> UIImage? {
        let nsKey = "\(key)-\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: nsKey) { return hit }
        guard let thumb = ImageUtils.thumbnail(from: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(thumb, forKey: nsKey)
        return thumb
    }
}
