import Foundation

class JinaReaderService {
    static let shared = JinaReaderService()

    /// Ayarlar'dan (Keychain) gelir. Boşsa Jina'nın ücretsiz/limitli modu kullanılır.
    /// Not: Anahtar artık kaynak koda gömülü değil — IPA'dan okunup sızdırılamaz.
    var apiKey: String = ""

    private init() {}

    /// Jina AI Reader kullanarak URL içeriğini okur
    func read(url: String) async throws -> String {
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let jinaUrl = URL(string: "https://r.jina.ai/\(encodedUrl)") else {
            throw NSError(domain: "JinaReaderService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz Jina URL'si"])
        }

        var request = URLRequest(url: jinaUrl)
        request.httpMethod = "GET"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Jina AI Maksimum Verimlilik Header Ayarları
        request.setValue("markdown", forHTTPHeaderField: "X-Respond-With")
        request.setValue("none", forHTTPHeaderField: "X-Retain-Links") // Tüm menü ve yönlendirme linklerini atar
        request.setValue("none", forHTTPHeaderField: "X-Retain-Images") // Gereksiz görsel veya Base64 kodlarını atar
        request.setValue("mutation-idle", forHTTPHeaderField: "X-Respond-Timing") // JavaScript'in tam olarak yüklenmesini (skorlar vb.) bekler
        request.setValue("agent", forHTTPHeaderField: "X-Preset") // AI Ajanlarına özel formatlı sayfa düzeni
        request.setValue("true", forHTTPHeaderField: "X-Remove-Overlay") // Çerez onay ve reklam popuplarını siler

        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        let responseString = String(data: data, encoding: .utf8) ?? ""
        if responseString.contains("InsufficientBalanceError") {
            throw NSError(domain: "JinaReaderService", code: 402, userInfo: [NSLocalizedDescriptionKey: "Jina AI bakiyesi yetersiz."])
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "JinaReaderService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Jina okuma hatası"])
        }

        return responseString.isEmpty ? "Okunan içerik boş veya hatalı." : responseString
    }
}
