import Foundation
import SwiftUI

// MARK: - App Data Models

enum MessageRole: String, Codable {
    case user = "user"
    case model = "model"
    case system = "system"
}

struct FileAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: String // "pdf" | "text" | "docx" | "code"
    var size: Int
    var text: String
    var truncated: Bool
    var pageCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case name, kind, size, text, truncated, pageCount
    }

    init(id: UUID = UUID(), name: String, kind: String, size: Int, text: String, truncated: Bool, pageCount: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.text = text
        self.truncated = truncated
        self.pageCount = pageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.size = try container.decode(Int.self, forKey: .size)
        self.text = try container.decode(String.self, forKey: .text)
        self.truncated = try container.decode(Bool.self, forKey: .truncated)
        self.pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(size, forKey: .size)
        try container.encode(text, forKey: .text)
        try container.encode(truncated, forKey: .truncated)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
    }
}

struct Message: Identifiable, Codable, Hashable {
    var id = UUID()
    var content: String
    var role: MessageRole
    var timestamp = Date()
    var imageDatas: [Data] = []  // Çoklu görsel desteği
    var searchQuery: String?
    var searchResults: String?
    var isSearching: Bool = false
    var thinkingSteps: [String] = [] // Yapay zekanın Agentic reasoning adımları
    var reminderTitle: String? // Hatırlatıcı eklendiyse başlığı
    var isVoiceInitiated: Bool = false // Sesli mesaj ile başlatıldıysa true
    var reasoning: String? = nil // Modelin düşünce süreci (destekleyen modellerde) — "Düşünce sürecini göster"
    var sources: [WebSource]? = nil       // Web aramasında kullanılan kaynaklar (kaynak çipleri)
    var imageTopics: [String]? = nil      // Cevaba eşlik eden görseller için konu adları (Wikipedia görselleri)
    var choices: ChoicePrompt? = nil      // Yapay zekanın sorduğu seçenekli sorular (yazma çubuğunun üstünde)
    var widgets: [ChatWidget]? = nil      // Cevabın başındaki kartlar (maç, logolu kurum) — bkz. ChatWidgets.swift
    var noteTitle: String? = nil          // Yapay zeka not aldıysa/güncellediyse rozet ("Not güncellendi: Alışveriş Listesi")
    var noteID: UUID? = nil               // Rozete dokununca açılacak not
    var compare: CompareData? = nil       // [COMPARE] görselli karşılaştırma kartı (cevabın başında)
    var quiz: QuizData? = nil             // [QUIZ] sohbet içinde çözülen test
    var deck: SlideDeck? = nil            // [SLIDES] cevaptan sonra hazırlanan sunum
    var pendingDeckTitle: String? = nil   // Soru sorulduğu için ertelenen sunum (cevaplanınca son cevapta hazırlanır)
    var actions: [String]? = nil          // [ACTIONS] cevabın altındaki eylem butonları
    var canvas: String? = nil             // [ARAYUZ] dinamik HTML arayüz alanı
    var files: [FileAttachment]? = nil    // Eklenen dosyalar ([FileAttachment])
    var appRequest: AppRequestData? = nil // [UYGULAMA_YAP] sohbetten mini uygulama oluşturma isteği
    
    // Geriye dönük uyumluluk: tek görsel
    var imageData: Data? {
        get { imageDatas.first }
        set {
            if let d = newValue {
                imageDatas = [d]
            } else {
                imageDatas = []
            }
        }
    }
    
    // Conforming to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// DİKKAT: Sadece `id` karşılaştırılırsa SwiftUI, içeriği değişen mesajı "aynı" sanıp
    /// satırı yeniden çizmeyebilir (akış sırasında metnin takılı kalması). Bu yüzden
    /// ekranda görünen alanlar da karşılaştırılıyor. Görsel verisi pahalı olduğu için sadece sayısı.
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
            && lhs.content == rhs.content
            && lhs.isSearching == rhs.isSearching
            && lhs.searchQuery == rhs.searchQuery
            && lhs.reminderTitle == rhs.reminderTitle
            && lhs.thinkingSteps == rhs.thinkingSteps
            && lhs.reasoning == rhs.reasoning
            && lhs.sources == rhs.sources
            && lhs.imageTopics == rhs.imageTopics
            && lhs.choices == rhs.choices
            && lhs.widgets == rhs.widgets
            && lhs.compare == rhs.compare
            && lhs.quiz == rhs.quiz
            && lhs.deck == rhs.deck
            && lhs.actions == rhs.actions
            && lhs.canvas == rhs.canvas
            && lhs.noteTitle == rhs.noteTitle
            && lhs.files == rhs.files
            && lhs.appRequest == rhs.appRequest
            && lhs.imageDatas.count == rhs.imageDatas.count
    }
}

struct ChatSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var messages: [Message]
    var createdAt = Date()
    var isPinned: Bool = false
    var isSpaceChat: Bool? = false // Uzay sohbeti (Ajan görevleri)
    /// Sohbetin sonunda yapay zekanın önerdiği tek devam sorusu — yeni sohbet ekranında gösterilir
    var followUp: String? = nil
    
    var isSpaceChatValue: Bool {
        isSpaceChat ?? false
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.isPinned == rhs.isPinned
            && lhs.messages == rhs.messages
    }
}

/// Web kaynağı (kaynak çipi)
struct WebSource: Codable, Hashable {
    var title: String
    var url: String

    var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? title
    }
}

/// Yapay zekanın kullanıcıya seçenekli sorduğu sorular (anket benzeri hızlı cevap)
struct ChoicePrompt: Codable, Hashable {
    struct Question: Codable, Hashable {
        var q: String
        var options: [String]
        var multi: Bool? = nil
    }
    var questions: [Question]
}

// MARK: - Gemini REST API Models

struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let generationConfig: GeminiGenerationConfig?
    /// Google araması (grounding) — model gerekirse kendisi arar
    var tools: [GeminiTool]? = nil
    
    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "systemInstruction"
        case generationConfig = "generationConfig"
        case tools
    }
}

/// {"google_search": {}}
struct GeminiTool: Encodable {
    private struct Empty: Encodable {}
    enum CodingKeys: String, CodingKey { case googleSearch = "google_search" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Empty(), forKey: .googleSearch)
    }
}

struct GeminiSystemInstruction: Codable {
    let parts: [GeminiPart]
}

struct GeminiContent: Codable {
    let role: String // "user" or "model"
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?
    /// Düşünen modellerde (Gemini 3.x) iç düşünce parçaları `thought: true` ile gelir — kullanıcıya gösterilmez
    var thought: Bool? = nil
    
    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inlineData"
        case thought
    }
}

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String // Base64 String
}

struct GeminiGenerationConfig: Codable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let responseMimeType: String?
    /// Gemini 3: düşünme seviyesi ("low" / "high"). nil → modelin varsayılanı (yüksek, yavaş)
    var thinkingConfig: GeminiThinkingConfig? = nil

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "maxOutputTokens"
        case responseMimeType = "responseMimeType"
        case thinkingConfig
    }
}

struct GeminiThinkingConfig: Codable {
    let thinkingLevel: String
}

struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
    let error: GeminiErrorDetails?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent?
    let finishReason: String?
    let index: Int?
    let groundingMetadata: GeminiGroundingMetadata?
}

struct GeminiGroundingMetadata: Codable {
    struct Chunk: Codable {
        struct Web: Codable { let uri: String?; let title: String? }
        let web: Web?
    }
    let groundingChunks: [Chunk]?
}

struct GeminiErrorDetails: Codable {
    let code: Int?
    let message: String?
    let status: String?
}

// MARK: - AI Native App Specification Models

struct AppSpecification: Codable, Hashable {
    var appName: String?
    var appIcon: String?
    var appType: String // "browser", "notes", "todo", "chat", "calculator", "camera", "weather", "gallery" vb.
    var configuration: [String: String]?
}

struct AppRequestData: Codable, Hashable {
    var name: String
    var prompt: String
}
