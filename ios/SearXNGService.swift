import Foundation

/// SearXNG — Meta Arama Motoru Entegrasyonu
/// Arama endpointi: /search?q={query}&format=json
class SearXNGService {
    static let shared = SearXNGService()
    
    var baseUrl: String = "" // Örn: http://127.0.0.1:4000
    
    private init() {}
    
    /// Web araması yapar — SearXNG JSON API
    /// - Parameter query: Arama sorgusu
    /// - Returns: Yapılandırılmış arama sonuçları listesi
    func searchRaw(query: String) async throws -> [SearXNGResult] {
        guard !baseUrl.isEmpty else {
            throw NSError(domain: "SearXNGService", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "SearXNG Base URL konfigürasyonu eksik."])
        }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NSError(domain: "SearXNGService", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Geçersiz arama sorgusu."])
        }
        
        let cleanBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(cleanBaseUrl)/search?q=\(encodedQuery)&format=json"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "SearXNGService", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Geçersiz SearXNG URL'si."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tr", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 25
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SearXNGService", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "SearXNG'den geçersiz yanıt."])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let rawError = String(data: data, encoding: .utf8) ?? "Bilinmeyen hata"
            throw NSError(domain: "SearXNGService", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "SearXNG Arama Hatası (\(httpResponse.statusCode)): \(rawError)"])
        }
        
        return parseSearchResponseRaw(data: data)
    }
    
    private func parseSearchResponseRaw(data: Data) -> [SearXNGResult] {
        var results: [SearXNGResult] = []
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["results"] as? [[String: Any]] else {
            return []
        }
        
        for item in dataArray.prefix(10) {
            let title = item["title"] as? String ?? "Başlık Yok"
            let url = item["url"] as? String ?? ""
            
            var contentStr = ""
            if let content = item["content"] as? String, !content.isEmpty {
                contentStr = content
            } else if let snippet = item["snippet"] as? String, !snippet.isEmpty {
                contentStr = snippet
            }
            
            if !url.isEmpty && !contentStr.isEmpty {
                results.append(SearXNGResult(url: url, title: title, snippet: contentStr))
            }
        }
        
        return results
    }
}
