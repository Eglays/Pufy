import Foundation
import UIKit

/// Yapay zeka istemcisi. Adı tarihsel olarak "Gemini" ama artık iki formatı konuşur:
/// - Gemini REST (/v1beta/models/{model}:generateContent)
/// - OpenAI uyumlu (/chat/completions) → OpenAI, OpenRouter, Groq, DeepSeek, Anthropic, Ollama…
/// Ayarlar `AIConfig` tarafından yüklenir/kaydedilir.
/// Akışta gelen parça: cevabın kendisi ya da modelin düşünce süreci
enum StreamChunk {
    case text(String)
    case thought(String)
    /// Google aramasında kullanılan kaynaklar (sunucu iletiyorsa)
    case sources([WebSource])
}

class GeminiService {
    static let shared = GeminiService()

    var apiKey: String = ""
    var endpoint: String = ""
    var modelName: String = ""
    /// Zor işler için ikinci model (boşsa temel model kullanılır)
    var heavyModelName: String = ""
    var apiFormat: APIFormat = .gemini
    /// Görsel üretimi için model (boşsa görsel üretimi kapalı)
    var imageModelName: String = ""
    /// Cevabı parça parça göster
    var streamingEnabled: Bool = true
    /// Gemini formatında Google araması (grounding)
    var googleSearchEnabled: Bool = true

    var isConfigured: Bool {
        let ep = endpoint.trimmingCharacters(in: .whitespaces)
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        let isLocal = ep.contains("192.168.") || ep.contains("10.") || ep.contains("172.") || ep.contains("localhost") || ep.contains("127.0.0.1")
        if isLocal {
            return !ep.isEmpty
        }
        return !key.isEmpty && !ep.isEmpty
    }

    /// Bu yapılandırmada yerleşik Google araması kullanılabilir mi?
    var canUseGoogleSearch: Bool { apiFormat == .gemini && googleSearchEnabled }

    var canGenerateImages: Bool { apiFormat == .gemini && !imageModelName.isEmpty }

    /// Zor işlerde kullanılacak model adı
    var deepModel: String {
        let heavy = heavyModelName.trimmingCharacters(in: .whitespaces)
        return heavy.isEmpty ? modelName : heavy
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // İstek: sunucudan hiç veri gelmeden beklenecek en uzun süre (düşünen modeller sessiz kalabiliyor)
        config.timeoutIntervalForRequest = 150
        // Kaynak: tüm cevabın en uzun süresi. Eskiden 5 dk'ydı → büyük uygulama üretimi yarıda kesiliyordu
        config.timeoutIntervalForResource = 1200
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Tek Seferlik Cevap

    /// - Parameters:
    ///   - prompt: Kullanıcının son mesajı
    ///   - history: Önceki mesajlar
    ///   - imageDatas: Son mesaja eklenen görseller (JPEG)
    ///   - responseMimeType: "application/json" → yalnızca Gemini'de JSON modu açar
    func generateContent(
        prompt: String,
        history: [Message] = [],
        imageDatas: [Data] = [],
        mimeType: String? = "image/jpeg",
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 8192,
        modelOverride: String? = nil,
        responseMimeType: String? = nil,
        timeout: TimeInterval? = nil,
        useSearch: Bool = false,
        thinking: String? = nil
    ) async throws -> String {
        var request = try buildRequest(prompt: prompt, history: history, imageDatas: imageDatas,
                                       mimeType: mimeType ?? "image/jpeg", systemPrompt: systemPrompt,
                                       maxOutputTokens: maxOutputTokens, model: modelOverride ?? modelName,
                                       responseMimeType: responseMimeType, stream: false, useSearch: useSearch,
                                       thinking: thinking)
        if let timeout { request.timeoutInterval = timeout }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw friendlyNetworkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw serviceError(500, "Sunucudan geçersiz yanıt alındı.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw httpError(status: http.statusCode, body: data)
        }

        switch apiFormat {
        case .gemini: return try parseGeminiResponse(data)
        case .openAI: return try parseOpenAIResponse(data)
        }
    }

    // MARK: - Akış (Streaming)

    /// Cevabı geldikçe parça parça verir (Server-Sent Events).
    /// Tüketen Task iptal edilirse ağ isteği de iptal olur.
    func streamContent(
        prompt: String,
        history: [Message] = [],
        imageDatas: [Data] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 8192,
        modelOverride: String? = nil,
        useSearch: Bool = false,
        thinking: String? = nil
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(prompt: prompt, history: history, imageDatas: imageDatas,
                                                   mimeType: "image/jpeg", systemPrompt: systemPrompt,
                                                   maxOutputTokens: maxOutputTokens, model: modelOverride ?? modelName,
                                                   responseMimeType: nil, stream: true, useSearch: useSearch,
                                                   thinking: thinking)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw serviceError(500, "Sunucudan geçersiz yanıt alındı.")
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 20_000 { break } }
                        throw httpError(status: http.statusCode, body: body)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let chunk = payload.data(using: .utf8) else { continue }
                        for piece in parseStreamDelta(chunk) {
                            continuation.yield(piece)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: self.friendlyNetworkError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Bağlantı Testi (Ayarlar ekranı)

    enum ConnectionError: LocalizedError {
        case invalidKey
        case modelNotFound
        case rateLimit
        case noInternet
        case custom(String)

        var errorDescription: String? {
            switch self {
            case .invalidKey: return "Anahtar geçersiz"
            case .modelNotFound: return "Model bulunamadı"
            case .rateLimit: return "Kota doldu ya da çok sık istek"
            case .noInternet: return "İnternete ulaşılamadı"
            case .custom(let msg): return msg
            }
        }
    }

    func testConnection() async -> Result<String, Error> {
        do {
            // Kısa zaman aşımı: port kapalıysa (ör. AWS güvenlik grubu) 90 sn beklemesin
            let reply = try await generateContent(prompt: "Sadece 'Tamam' yaz.", maxOutputTokens: 64, timeout: 15)
            return .success(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(error)
        }
    }

    /// Yeni kurulum veya Ayarlar için model listesi çeker
    func fetchModels(endpoint: String, format: APIFormat, apiKey: String) async throws -> [String] {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty && !base.contains("://") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        if format == .gemini, base.hasSuffix("/v1beta") { base.removeLast("/v1beta".count) }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Bearer ", with: "")

        let url: URL
        var request: URLRequest
        if format == .gemini {
            var components = URLComponents(string: "\(base)/v1beta/models")
            if !cleanKey.isEmpty { components?.queryItems = [URLQueryItem(name: "key", value: cleanKey)] }
            guard let u = components?.url else { throw serviceError(400, "Geçersiz adres") }
            url = u
            request = URLRequest(url: url)
            if !cleanKey.isEmpty, !base.contains("googleapis.com") {
                request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
            }
        } else {
            guard let u = URL(string: "\(base)/models") else { throw serviceError(400, "Geçersiz adres") }
            url = u
            request = URLRequest(url: url)
            if !cleanKey.isEmpty {
                request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
            }
        }
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw serviceError(500, "Geçersiz yanıt") }
        guard (200...299).contains(http.statusCode) else {
            throw httpError(status: http.statusCode, body: data)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw serviceError(500, "JSON okunamadı")
        }

        if format == .gemini {
            guard let models = json["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { dict in
                if let methods = dict["supportedGenerationMethods"] as? [String], !methods.contains("generateContent") {
                    return nil
                }
                guard let name = dict["name"] as? String else { return nil }
                return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            }
        } else {
            guard let dataList = json["data"] as? [[String: Any]] else { return [] }
            return dataList.compactMap { $0["id"] as? String }
        }
    }

    /// İlk kurulum için küçük bir istekle bağlantıyı sınar (20 token max)
    func testConnectionDetailed(endpoint: String, format: APIFormat, apiKey: String, model: String) async -> Result<String, ConnectionError> {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty && !base.contains("://") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        if format == .gemini, base.hasSuffix("/v1beta") { base.removeLast("/v1beta".count) }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Bearer ", with: "")
        guard !base.isEmpty else { return .failure(.noInternet) }
        guard !model.isEmpty else { return .failure(.modelNotFound) }

        let request: URLRequest
        do {
            switch format {
            case .gemini:
                var components = URLComponents(string: "\(base)/v1beta/models/\(model):generateContent")
                if !cleanKey.isEmpty { components?.queryItems = [URLQueryItem(name: "key", value: cleanKey)] }
                guard let url = components?.url else { return .failure(.noInternet) }
                var req = URLRequest(url: url)
                if !cleanKey.isEmpty, !base.contains("googleapis.com") {
                    req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
                }
                req.httpMethod = "POST"
                req.timeoutInterval = 15
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "contents": [["role": "user", "parts": [["text": "Merhaba"]]]],
                    "generationConfig": ["maxOutputTokens": 20]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                request = req
            case .openAI:
                let path = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
                guard let url = URL(string: path) else { return .failure(.noInternet) }
                var req = URLRequest(url: url)
                if !cleanKey.isEmpty { req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization") }
                req.httpMethod = "POST"
                req.timeoutInterval = 15
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "model": model,
                    "messages": [["role": "user", "content": "Merhaba"]],
                    "max_tokens": 20
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                request = req
            }
        } catch {
            return .failure(.noInternet)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.noInternet)
            }
            if (200...299).contains(http.statusCode) {
                return .success("Bağlandı")
            }
            switch http.statusCode {
            case 401, 403: return .failure(.invalidKey)
            case 404:      return .failure(.modelNotFound)
            case 429:      return .failure(.rateLimit)
            default:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                    return .failure(.custom(msg))
                }
                return .failure(.custom("Hata: HTTP \(http.statusCode)"))
            }
        } catch {
            return .failure(.noInternet)
        }
    }

    /// Düşünme seviyesi ayarı sadece Gemini 3 modellerinde var (eskilerde 400 hatası verir)
    static func supportsThinkingLevel(_ model: String) -> Bool {
        model.lowercased().contains("gemini-3")
    }

    /// Gönderilecek düşünme seviyesi. "minimal" en hızlısı (basit işler); Pro modeller "minimal" bilmez → "low".
    static func thinkingLevel(_ level: String?, for model: String) -> String? {
        guard let level, supportsThinkingLevel(model) else { return nil }
        if level == "minimal", model.lowercased().contains("pro") { return "low" }
        return level
    }

    // MARK: - Dikte (ses → metin)

    static let dictationPrompt = """
    Sen bir dikte motorusun. Sesi kelimesi kelimesine yazıya dök. Türkçe ve İngilizce karışık olabilir; \
    her kelimeyi söylendiği dilde ve doğru yazımıyla yaz (meeting, deadline, feedback gibi). \
    Noktalama ve büyük harf kullan. "ııı", "eee" gibi dolgu seslerini ve tekrarları at. \
    Kişi cümlenin ortasında kendini düzeltirse ("yarın, yok pazartesi") son halini yaz. \
    Sadece metni yaz: açıklama, tırnak, başlık yok. Ses boşsa ya da konuşma yoksa hiçbir şey yazma.
    """

    /// Kaydedilen sesi kullanıcının yapay zekasıyla yazıya döker.
    /// - Gemini formatı: ses doğrudan modele gider (düşünme "low" → ~2-3 sn, TR/EN karışık konuşmada çok iyi)
    /// - OpenAI uyumlu: /audio/transcriptions (Groq'ta whisper-large-v3-turbo — SuperWhisper'ın "Ultra v3 turbo"su)
    func transcribe(audio: Data, mimeType: String = "audio/mp4", fileName: String = "dikte.m4a") async throws -> String {
        let base = normalizedBase()
        guard !base.isEmpty else { throw serviceError(400, "API adresi boş. Ayarlar'dan bir endpoint gir.") }

        switch apiFormat {
        case .gemini:
            func body(thinking: Bool) throws -> Data {
                var config: [String: Any] = ["temperature": 0, "maxOutputTokens": 4096]
                if thinking { config["thinkingConfig"] = ["thinkingLevel": "low"] }
                return try JSONSerialization.data(withJSONObject: [
                    "systemInstruction": ["parts": [["text": Self.dictationPrompt]]],
                    "contents": [["role": "user", "parts": [
                        ["inlineData": ["mimeType": mimeType, "data": audio.base64EncodedString()]],
                        ["text": "Bu sesi yazıya dök."]
                    ]]],
                    "generationConfig": config
                ])
            }
            var components = URLComponents(string: "\(base)/v1beta/models/\(modelName):generateContent")
            if !apiKey.isEmpty { components?.queryItems = [URLQueryItem(name: "key", value: apiKey)] }
            guard let url = components?.url else { throw serviceError(400, "Geçersiz API adresi.") }
            var request = URLRequest(url: url)
            addProxyAuthorization(&request, base: base)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try body(thinking: modelName.contains("gemini-3"))
            do {
                return try clean(try await send(request))
            } catch {
                // Eski modeller "thinkingLevel" bilmez → düşünme ayarı olmadan tekrar
                let ns = error as NSError
                guard ns.code == 400, ns.localizedDescription.lowercased().contains("think") else { throw error }
                request.httpBody = try body(thinking: false)
                return try clean(try await send(request))
            }

        case .openAI:
            var root = base
            if root.hasSuffix("/chat/completions") { root.removeLast("/chat/completions".count) }
            guard let url = URL(string: "\(root)/audio/transcriptions") else { throw serviceError(400, "Geçersiz API adresi.") }
            let model: String
            if root.contains("api.openai.com") { model = "gpt-4o-mini-transcribe" }
            else { model = "whisper-large-v3-turbo" }
            let boundary = "pufy-\(UUID().uuidString)"
            var data = Data()
            func field(_ name: String, _ value: String) {
                data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
            }
            field("model", model)
            field("response_format", "json")
            field("temperature", "0")
            // İpucu: karışık dil ve yazım (Whisper "prompt" alanını üslup için kullanır)
            field("prompt", "Türkçe ve İngilizce karışık konuşma. Meeting, deadline, feedback.")
            data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            data.append(audio)
            data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = data
            let (responseData, response) = try await perform(request)
            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let text = json["text"] as? String else {
                _ = response
                throw serviceError(500, "Ses yazıya dökülemedi.")
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func send(_ request: URLRequest) async throws -> String {
            let (data, _) = try await perform(request)
            return try parseGeminiResponse(data)
        }
        func clean(_ text: String) -> String {
            var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("\""), t.hasSuffix("\""), t.count > 1 { t = String(t.dropFirst().dropLast()) }
            return t
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw friendlyNetworkError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw serviceError(500, "Sunucudan geçersiz yanıt alındı.") }
        guard (200...299).contains(http.statusCode) else { throw httpError(status: http.statusCode, body: data) }
        return (data, response)
    }

    // MARK: - İstek Oluşturma

    private func buildRequest(prompt: String, history: [Message], imageDatas: [Data], mimeType: String,
                              systemPrompt: String?, maxOutputTokens: Int, model: String,
                              responseMimeType: String?, stream: Bool, useSearch: Bool = false,
                              thinking: String? = nil) throws -> URLRequest {
        let base = normalizedBase()
        guard !base.isEmpty else {
            throw serviceError(400, "API adresi boş. Ayarlar'dan bir endpoint gir.")
        }
        guard !model.isEmpty else {
            throw serviceError(400, "Model adı boş. Ayarlar'dan bir model adı gir.")
        }

        var request: URLRequest
        switch apiFormat {
        case .gemini:
            let method = stream ? "streamGenerateContent" : "generateContent"
            var components = URLComponents(string: "\(base)/v1beta/models/\(model):\(method)")
            var items: [URLQueryItem] = []
            if !apiKey.isEmpty { items.append(URLQueryItem(name: "key", value: apiKey)) }
            if stream { items.append(URLQueryItem(name: "alt", value: "sse")) }
            components?.queryItems = items.isEmpty ? nil : items
            guard let url = components?.url else { throw serviceError(400, "Geçersiz API adresi.") }
            request = URLRequest(url: url)
            addProxyAuthorization(&request, base: base)
            request.httpBody = try encoder.encode(geminiBody(prompt: prompt, history: history, imageDatas: imageDatas,
                                                             mimeType: mimeType, systemPrompt: systemPrompt,
                                                             maxOutputTokens: maxOutputTokens,
                                                             responseMimeType: responseMimeType,
                                                             useSearch: useSearch && googleSearchEnabled,
                                                             thinking: Self.thinkingLevel(thinking, for: model)))
        case .openAI:
            let path = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
            guard let url = URL(string: path) else { throw serviceError(400, "Geçersiz API adresi.") }
            request = URLRequest(url: url)
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: openAIBody(
                prompt: prompt, history: history, imageDatas: imageDatas, mimeType: mimeType,
                systemPrompt: systemPrompt, model: model, stream: stream))
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        return request
    }

    /// Kendi yapay zeka sunucusu (proxy) anahtarı "Authorization: Bearer …" başlığında ister. Kullanıcı (15 Ekim 2026) proxy'de
    /// doğrulamayı açınca anahtar sadece adreste (?key=) gittiği için "yetki yok" hatası alındı. Google'ın kendi adresine bu
    /// başlık GÖNDERİLMEZ (Google onu OAuth jetonu sanıp isteği reddeder); orada ?key= yeterli.
    private func addProxyAuthorization(_ request: inout URLRequest, base: String) {
        guard !apiKey.isEmpty, !base.contains("googleapis.com") else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    /// Kullanıcının girdiği adresi toparlar: sondaki "/" ve Gemini için fazladan "/v1beta" atılır.
    /// "3.95.12.34:8045" gibi şemasız yazılan adreslere "http://" eklenir — yoksa URL geçersiz sayılıyordu.
    private func normalizedBase() -> String {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty && !base.contains("://") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        if apiFormat == .gemini, base.hasSuffix("/v1beta") { base.removeLast("/v1beta".count) }
        return base
    }

    // MARK: Gemini gövdesi

    private func geminiBody(prompt: String, history: [Message], imageDatas: [Data], mimeType: String,
                            systemPrompt: String?, maxOutputTokens: Int, responseMimeType: String?,
                            useSearch: Bool, thinking: String? = nil) -> GeminiRequest {
        var contents: [GeminiContent] = []

        func append(role: String, parts: [GeminiPart]) {
            guard !parts.isEmpty else { return }   // API boş part kabul etmez
            // Gemini ardışık aynı rolü kabul etmez → birleştir
            if let last = contents.last, last.role == role {
                contents[contents.count - 1] = GeminiContent(role: role, parts: last.parts + parts)
            } else {
                contents.append(GeminiContent(role: role, parts: parts))
            }
        }

        for msg in history {
            var parts = msg.imageDatas.map {
                GeminiPart(text: nil, inlineData: GeminiInlineData(mimeType: mimeType, data: $0.base64EncodedString()))
            }
            if !msg.content.isEmpty { parts.append(GeminiPart(text: msg.content, inlineData: nil)) }
            append(role: msg.role == .user ? "user" : "model", parts: parts)
        }

        var current = imageDatas.map {
            GeminiPart(text: nil, inlineData: GeminiInlineData(mimeType: mimeType, data: $0.base64EncodedString()))
        }
        if !prompt.isEmpty { current.append(GeminiPart(text: prompt, inlineData: nil)) }
        append(role: "user", parts: current)

        var system: GeminiSystemInstruction? = nil
        if let systemPrompt, !systemPrompt.isEmpty {
            system = GeminiSystemInstruction(parts: [GeminiPart(text: systemPrompt, inlineData: nil)])
        }

        return GeminiRequest(
            contents: contents,
            systemInstruction: system,
            generationConfig: GeminiGenerationConfig(temperature: 0.7, maxOutputTokens: maxOutputTokens,
                                                     responseMimeType: responseMimeType,
                                                     thinkingConfig: thinking.map { GeminiThinkingConfig(thinkingLevel: $0) }),
            // JSON modu ile araç birlikte kullanılamıyor
            tools: (useSearch && responseMimeType == nil) ? [GeminiTool()] : nil
        )
    }

    // MARK: OpenAI gövdesi

    private func openAIBody(prompt: String, history: [Message], imageDatas: [Data], mimeType: String,
                            systemPrompt: String?, model: String, stream: Bool) -> [String: Any] {
        func content(text: String, images: [Data]) -> Any {
            guard !images.isEmpty else { return text }
            var parts: [[String: Any]] = images.map {
                ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\($0.base64EncodedString())"]]
            }
            if !text.isEmpty { parts.append(["type": "text", "text": text]) }
            return parts
        }

        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        for msg in history where !(msg.content.isEmpty && msg.imageDatas.isEmpty) {
            messages.append(["role": msg.role == .user ? "user" : "assistant",
                             "content": content(text: msg.content, images: msg.imageDatas)])
        }
        messages.append(["role": "user", "content": content(text: prompt, images: imageDatas)])

        // max_tokens / temperature bilinçli olarak gönderilmiyor: bazı yeni modeller
        // (ör. akıl yürütme modelleri) bu parametreleri reddediyor. Sağlayıcı varsayılanı kullanılır.
        return ["model": model, "messages": messages, "stream": stream]
    }

    // MARK: - Cevap Ayrıştırma

    /// Görsel modelinden ham görüntü (uygulama yapımında oyun/uygulama görselleri için; dosyaya kaydetmez)
    func generateImageData(prompt: String, imageDatas: [Data] = [], timeout: TimeInterval = 180) async throws -> Data {
        var request = try buildRequest(prompt: prompt, history: [], imageDatas: imageDatas, mimeType: "image/jpeg",
                                       systemPrompt: nil, maxOutputTokens: 8192, model: imageModelName,
                                       responseMimeType: nil, stream: false)
        request.timeoutInterval = timeout
        let (data, _) = try await perform(request)
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = raw["candidates"] as? [[String: Any]],
              let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] else {
            throw serviceError(500, "Görsel modeli boş döndü.")
        }
        for part in parts {
            if let inline = part["inlineData"] as? [String: Any], let b64 = inline["data"] as? String,
               let image = Data(base64Encoded: b64) { return image }
            // Bazı proxy'ler görseli standart dışı alanda döndürüyor
            if let signature = part["thoughtSignature"] as? String, let image = Data(base64Encoded: signature),
               UIImage(data: image) != nil { return image }
        }
        throw serviceError(500, "Görsel modeli görsel üretmedi.")
    }

    private func parseGeminiResponse(_ data: Data) throws -> String {
        let result = try decoder.decode(GeminiResponse.self, from: data)
        guard let content = result.candidates?.first?.content else {
            throw serviceError(500, "Modelden boş yanıt veya beklenmeyen veri yapısı alındı.")
        }

        let text = content.parts.compactMap { part -> String? in
            if part.thought == true { return nil }   // modelin iç düşüncesi
            if let text = part.text { return text }
            if let inline = part.inlineData, let image = Data(base64Encoded: inline.data) {
                return saveGeneratedImage(image)
            }
            return nil
        }.joined(separator: "\n")

        if !text.isEmpty { return text }

        // Bazı proxy'ler görseli "thoughtSignature" gibi standart dışı alanlarda döndürüyor
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = raw["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let first = parts.first {
            if let signature = first["thoughtSignature"] as? String, let image = Data(base64Encoded: signature) {
                return saveGeneratedImage(image)
            }
            if let inline = first["inlineData"] as? [String: Any], let b64 = inline["data"] as? String,
               let image = Data(base64Encoded: b64) {
                return saveGeneratedImage(image)
            }
        }
        throw serviceError(500, "Modelden boş metin yanıtı alındı.")
    }

    private func parseOpenAIResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw serviceError(500, "Sunucu cevabı okunamadı.")
        }
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            if let text = message["content"] as? String, !text.isEmpty { return text }
            // Bazı sağlayıcılar içerik dizisi döndürür
            if let parts = message["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty { return text }
            }
        }
        throw serviceError(500, "Modelden boş yanıt alındı.")
    }

    /// SSE satırındaki JSON'dan yeni metin parçasını çıkarır
    /// SSE satırındaki JSON'dan yeni parçaları çıkarır: cevap metni ve (varsa) modelin düşüncesi.
    /// Gemini 3.x düşünceleri `thought: true` parçası olarak, DeepSeek/OpenRouter ise
    /// `reasoning_content` / `reasoning` alanında gönderir.
    private func parseStreamDelta(_ chunk: Data) -> [StreamChunk] {
        switch apiFormat {
        case .gemini:
            guard let response = try? decoder.decode(GeminiResponse.self, from: chunk),
                  let candidate = response.candidates?.first else { return [] }
            var result: [StreamChunk] = (candidate.content?.parts ?? []).compactMap { part in
                guard let text = part.text, !text.isEmpty else { return nil }
                return part.thought == true ? .thought(text) : .text(text)
            }
            // Google aramasının kaynakları (doğrudan Gemini API'de gelir; bazı proxy'ler iletmez)
            let sources = (candidate.groundingMetadata?.groundingChunks ?? []).compactMap { chunk -> WebSource? in
                guard let uri = chunk.web?.uri else { return nil }
                return WebSource(title: chunk.web?.title ?? uri, url: uri)
            }
            if !sources.isEmpty { result.append(.sources(sources)) }
            return result
        case .openAI:
            guard let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return [] }
            var result: [StreamChunk] = []
            if let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String), !reasoning.isEmpty {
                result.append(.thought(reasoning))
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                result.append(.text(content))
            }
            return result
        }
    }

    /// Üretilen görselleri tutan kalıcı klasör (Documents/GeneratedImages)
    static var generatedImagesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeneratedImages", isDirectory: true)
    }

    /// Mesajdaki görsel adresini bugünkü konuma çevirir.
    /// ESKİ HATA: mesajda TAM dosya yolu saklanıyordu (…/Application/<KİMLİK>/Documents/…). Uygulama yeniden
    /// kurulunca iOS bu klasör kimliğini değiştiriyor → dosya duruyor ama eski yol geçersiz → "Görsel artık cihazda
    /// bulunmuyor". Artık dosya adıyla bugünkü klasörde aranıyor (eski mesajlar da düzelir).
    static func resolveGeneratedImageURL(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let current = generatedImagesDirectory.appendingPathComponent(url.lastPathComponent)
        return FileManager.default.fileExists(atPath: current.path) ? current : url
    }

    /// Üretilen görseli kalıcı klasöre yazar (eskiden tmp'ye yazılıyordu → iOS silince geçmişte kayboluyordu)
    private func saveGeneratedImage(_ data: Data) -> String {
        let dir = Self.generatedImagesDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: file, options: .atomic)
            return "![Görsel](\(file.absoluteString))"
        } catch {
            return "Görsel kaydedilemedi."
        }
    }

    // MARK: - Hatalar

    /// iOS'un ağ hatalarını (URLError) "neyi kontrol etmeliyim?" sorusunu cevaplayan Türkçe mesajlara çevirir.
    /// Kendi sunucunu (ör. AWS) bağlarken en sık karşılaşılan durumlar burada.
    /// iOS'un ağ hatalarını sade, kullanıcıya uygun Türkçe mesajlara çevirir.
    /// Teknik ayrıntı (IP, port, sunucu kurulumu) sohbette gösterilmez; Ayarlar'daki
    /// "Bağlantıyı test et" ekranı kendi ipuçlarını ekler (bkz. SettingsView).
    private func friendlyNetworkError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        let message: String
        switch urlError.code {
        case .cancelled:
            return error   // iptal ayrı ele alınıyor
        case .timedOut:
            message = "Yapay zeka sunucusu zamanında yanıt vermedi. Biraz sonra tekrar dene."
        case .cannotConnectToHost:
            message = "Yapay zeka sunucusuna bağlanılamadı. Sunucunun açık olduğundan emin ol."
        case .cannotFindHost, .dnsLookupFailed:
            message = "Yapay zeka sunucusunun adresi bulunamadı. Ayarlar'daki adresi kontrol et."
        case .notConnectedToInternet:
            message = "İnternet bağlantısı yok."
        case .networkConnectionLost:
            message = "Bağlantı yarıda kesildi. Tekrar dene."
        case .badURL, .unsupportedURL:
            message = "Ayarlar'daki sunucu adresi geçersiz."
        case .appTransportSecurityRequiresSecureConnection:
            message = "Bu adrese güvenli olmayan (http) bağlantıya izin verilmiyor. Adresi https:// ile dene."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            message = "Sunucuyla güvenli bağlantı kurulamadı."
        default:
            return error
        }
        return serviceError(urlError.errorCode, message)
    }

    private func serviceError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "AIService", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func httpError(status: Int, body: Data) -> NSError {
        // Gemini: {"error":{"message":...}}  OpenAI: {"error":{"message":...}}
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return serviceError(status, "API hatası (\(status)): \(message)")
            }
            if let message = json["message"] as? String {
                return serviceError(status, "API hatası (\(status)): \(message)")
            }
        }
        let raw = String(data: body, encoding: .utf8) ?? ""
        let isHTML = raw.contains("<!DOCTYPE") || raw.contains("<html")
        let message: String
        switch status {
        case 401, 403: message = "API anahtarı geçersiz veya yetki yok (\(status))."
        case 404:      message = "Endpoint ya da model bulunamadı (404). Adresi, formatı ve model adını kontrol et."
        case 429:      message = "API limiti aşıldı, biraz bekleyip tekrar dene (429)."
        case 502, 503, 530: message = "API sunucusuna ulaşılamıyor (\(status)). Sunucunun çalıştığından emin ol."
        default:
            message = (raw.isEmpty || isHTML) ? "Sunucu hatası: HTTP \(status)" : String(raw.prefix(200))
        }
        return serviceError(status, message)
    }
}

