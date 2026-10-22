import Foundation

// MARK: - Planner Agent JSON Model
struct PlannerResponse: Codable {
    let needResearch: Bool
    let needImageGeneration: Bool? // Yeni Eklenti: Görsel oluşturma talebi
    let imagePrompt: String?       // Yeni Eklenti: Çizilecek görselin ingilizce promptu
    let queries: [String]
}

// MARK: - Research Agent JSON Model
struct ResearchResponse: Codable {
    let enoughInformation: Bool
    let additionalQueries: [String]
}

// MARK: - SearXNG Result Model
struct SearXNGResult: Codable, Hashable {
    let url: String
    let title: String
    let snippet: String
}
