import Foundation
import SwiftUI

// MARK: - Kategori

enum MemoryCategory: String, Codable, CaseIterable, Identifiable {
    case identity, people, work, skills, interests, preferences, traits, places, goals, health, other

    var id: String { rawValue }

    var title: String {
        if AppLanguage.isEnglish {
            switch self {
            case .identity:    return "Identity"
            case .people:      return "People"
            case .work:        return "Work & School"
            case .skills:      return "Skills"
            case .interests:   return "Interests"
            case .preferences: return "Preferences"
            case .traits:      return "Personality"
            case .places:      return "Places"
            case .goals:       return "Goals"
            case .health:      return "Health"
            case .other:       return "Other"
            }
        }
        switch self {
        case .identity:    return "Kimlik"
        case .people:      return "İnsanlar"
        case .work:        return "İş & Okul"
        case .skills:      return "Beceriler"
        case .interests:   return "İlgi Alanları"
        case .preferences: return "Tercihler"
        case .traits:      return "Kişilik"
        case .places:      return "Yerler"
        case .goals:       return "Hedefler"
        case .health:      return "Sağlık"
        case .other:       return "Diğer"
        }
    }

    var icon: String {
        switch self {
        case .identity:    return "person.text.rectangle"
        case .people:      return "person.2"
        case .work:        return "briefcase"
        case .skills:      return "hammer"
        case .interests:   return "sparkles"
        case .preferences: return "heart"
        case .traits:      return "brain.head.profile"
        case .places:      return "mappin.and.ellipse"
        case .goals:       return "flag"
        case .health:      return "cross.case"
        case .other:       return "circle.grid.2x2"
        }
    }

    /// Haritada merkeze yakınlık sırası
    var order: Int { MemoryCategory.allCases.firstIndex(of: self) ?? 99 }
}

// MARK: - Bilgi (harita düğümü)

struct MemoryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Haritada görünen kısa etiket ("Sema", "n8n", "Gece insanı")
    var text: String
    /// Tam cümle ("En yakın arkadaşı Sema")
    var detail: String
    var category: MemoryCategory? = nil
    /// İnsanlar için kişinin adı, ilişki
    var entity: String? = nil
    var relation: String? = nil
    /// 1–5 (5 = kimlik/aile gibi çok temel)
    var importance: Int? = nil
    var isManual: Bool = false
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    /// Bu bilgiyi hangi kelimeler "çağırır" (ör. iPhone bilgisi → telefon, cihaz, iphone)
    var keywords: [String]? = nil
    /// Bu bilgi hangi bilgiden dallanıyor (ör. "Nura doğum günü" → "Nura"). Ağda o düğümden çıkar.
    var parent: UUID? = nil
    /// İlişkili bilgiler (ör. "iPad" ↔ "iPad'e uygulama geliştirmek"); ağda ince çizgiyle bağlanır.
    var links: [UUID]? = nil

    // Eski sürüm alanları (çözümleme uyumu için)
    var weight: Double = 0.5
    var angle: Double = 0
    var icon: String = "sparkle"

    var resolvedCategory: MemoryCategory { category ?? .other }
    var resolvedImportance: Int { min(max(importance ?? 3, 1), 5) }

    /// Sohbetin her mesajında okunan temel bilgiler: kimlik (ad, yaşadığı yer, doğum günü…)
    var isCore: Bool { resolvedCategory == .identity || (resolvedImportance == 5 && resolvedCategory == .people) }
}

/// Yapay zekanın önerdiği hafıza değişikliği
struct MemoryChange {
    var label: String?
    var detail: String?
    var category: MemoryCategory?
    var entity: String?
    var relation: String?
    var importance: Int?
    var keywords: [String]?
    /// Bilinen bir kayda bağlı ("about": "m12") ve ilişkili kayıtlar ("related": ["m3"])
    var parentID: UUID? = nil
    var linkIDs: [UUID]? = nil
}

/// Haritada gösterilecek "iz": yapay zekanın kendiliğinden eklediği / sildiği / güncellediği bilgi.
/// Kişisel Ağ açılınca merkezden o düğüme giden yol çizilir (eklendi) ya da düğüm sönerek kaybolur (silindi).
struct MemoryTrace: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case added, removed, updated }
    var id: UUID { item.id }
    let kind: Kind
    let item: MemoryItem
    let date: Date
}

// MARK: - Hafıza Deposu
//
// 13 Ekim 2026 (2. tur) — kullanıcı geri bildirimiyle:
//  • "Nerede yaşıyorsun?" → "İstanbul" gibi KISA cevaplar 15 karakter sınırına takılıp hiç öğrenilmiyordu;
//    üstelik sorulan soru bağlam olarak verilmiyordu. Artık asistanın son sorusu da okunuyor.
//  • Bilgiler sadece ekleniyordu. Artık yapay zeka ekle / güncelle / sil kararı veriyor
//    ("Ankara'ya taşındım" → yaşadığı yer güncellenir, "artık oynamıyorum" → silinir).
//  • Her mesajda tüm hafıza okunuyordu. Artık sadece temel kimlik bilgileri + o mesajla ilgili
//    birkaç bilgi (anahtar kelime eşleşmesiyle) sohbete gider: "telefonum bozuldu" → sadece telefon bilgisi.

@MainActor
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()

    @Published var items: [MemoryItem] = []
    @Published private(set) var isLearning = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastLearnedAt: Date?
    /// "Sohbetlerimden oluştur" ilerlemesi (0…1), çalışmıyorsa nil
    @Published private(set) var rebuildProgress: Double?
    /// Henüz haritada gösterilmemiş değişiklikler (ekleme/silme izleri)
    @Published private(set) var traces: [MemoryTrace] = []

    private let storageKey = "pufy_memory_v4"
    private let legacyStorageKey = "pufy_memory_nodes_v3"
    private let blockedKey = "pufy_memory_blocked_v1"
    private let tracesKey = "pufy_memory_traces_v1"
    private let processedKey = "pufy_memory_processed_v1"
    private var blocked: Set<String> = []
    private var pending: [(text: String, ids: [UUID])] = []
    private var keywordBackfillStarted = false
    /// Hafızaya işlenmiş kullanıcı mesajları — işlenmeyenler (ör. cevap hata verdiği için) telafi taramasında öğrenilir
    private var processed: [String] = []
    private lazy var processedSet = Set(processed)
    private var catchUpRunning = false

    private init() {
        load()
        blocked = Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
        lastLearnedAt = UserDefaults.standard.object(forKey: "pufy_memory_last_learned") as? Date
        processed = UserDefaults.standard.stringArray(forKey: processedKey) ?? []
        if let data = UserDefaults.standard.data(forKey: tracesKey),
           let decoded = try? JSONDecoder().decode([MemoryTrace].self, from: data) {
            traces = decoded.filter { $0.date > Date().addingTimeInterval(-7 * 86_400) }
        }
    }

    private func saveTraces() {
        if let data = try? JSONEncoder().encode(traces) { UserDefaults.standard.set(data, forKey: tracesKey) }
    }

    /// Harita izleri gösterdi → temizle
    func clearTraces() {
        guard !traces.isEmpty else { return }
        traces.removeAll()
        saveTraces()
    }

    private func record(_ kind: MemoryTrace.Kind, _ item: MemoryItem) {
        traces.removeAll { $0.item.id == item.id }
        // Aynı oturumda eklenip silinen bilgi için iz bırakma
        traces.append(MemoryTrace(kind: kind, item: item, date: Date()))
        if traces.count > 30 { traces.removeFirst(traces.count - 30) }
    }

    private func markProcessed(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids.map(\.uuidString) where !processedSet.contains(id) {
            processed.append(id)
            processedSet.insert(id)
        }
        if processed.count > 4000 {
            processed.removeFirst(processed.count - 4000)
            processedSet = Set(processed)
        }
        UserDefaults.standard.set(processed, forKey: processedKey)
    }

    // MARK: Kalıcılık

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            items = decoded
            return
        }
        if let data = defaults.data(forKey: legacyStorageKey),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            items = decoded
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        SyncService.shared.scheduleSync()
    }

    // MARK: Eşitleme (diğer cihazdan gelen)

    func applyRemote(_ item: MemoryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.append(item) }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func applyRemoteDeletion(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func persistBlocked() {
        UserDefaults.standard.set(Array(blocked), forKey: blockedKey)
    }

    // MARK: Elle düzenleme (Kişisel Ağ ekranı)

    func add(_ item: MemoryItem) {
        var new = item
        new.isManual = true
        new.createdAt = Date()
        new.updatedAt = Date()
        items.append(new)
        save()
    }

    func update(_ item: MemoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var edited = item
        edited.isManual = true
        edited.updatedAt = Date()
        items[index] = edited
        save()
    }

    /// Kullanıcı sildi: bir daha otomatik eklenmesin
    func delete(_ item: MemoryItem) {
        items.removeAll { $0.id == item.id }
        blocked.insert(Self.normalize(item.detail))
        blocked.insert(Self.normalize(item.text))
        persistBlocked()
        save()
    }

    func resetAll() {
        items.removeAll()
        blocked.removeAll()
        pending.removeAll()
        lastError = nil
        traces.removeAll()
        saveTraces()
        persistBlocked()
        save()
    }

    // MARK: Hatırlama (sohbete giden bilgiler)

    /// Tüm hafıza (Kişisel Ağ özeti vb.)
    var promptText: String {
        guard !items.isEmpty else { return "Henüz bir bilgi yok." }
        return items.map { "- \($0.detail)" }.joined(separator: "\n")
    }

    /// Bu mesaj için sohbete gidecek bilgiler: temel kimlik + ilgili birkaç bilgi + hafızanın içindekiler listesi.
    /// Böylece model her seferinde uzun bir profil okumaz, sadece "gerekli nöronu" görür.
    /// Yapay zekaya verilen Kişisel Ağ: TAMAMI (kategoriye göre, önemliler önce) + bu mesajla en ilgili olanlar ayrıca.
    /// ESKİ HATA (kullanıcı, 15 Ekim 2026: "Ataşehir'de yaşıyor yazmasına rağmen 'bugün hava nasıl' deyince nerede diye
    /// soruyor"): sadece "Kimlik" kategorisi + sorudaki kelimelerle eşleşen bilgiler gidiyordu. "İstanbul'da yaşıyor"
    /// (Yerler) "hava" kelimesiyle eşleşmediği için hiç gitmiyor, üstüne "listelenmeyenleri bildiğini varsayma" notu
    /// yapay zekayı sormaya itiyordu. Bilgiler kısa (100 bilgi ≈ 1.200 token): hepsi verilir, ilgisini model seçer.
    func promptText(for query: String) -> String {
        guard !items.isEmpty else { return "Henüz bir bilgi yok." }
        let related = relevantFacts(for: query, limit: 8)
        let relatedIDs = Set(related.map(\.id))
        let sorted = items.sorted {
            ($0.resolvedCategory.order, -$0.resolvedImportance) < ($1.resolvedCategory.order, -$1.resolvedImportance)
        }
        // Çok büyürse önemsiz ayrıntılar (ilgili değilse) dışarıda kalır
        let shown = sorted.count <= 150 ? sorted
            : Array(sorted.filter { $0.resolvedImportance >= 3 || relatedIDs.contains($0.id) }.prefix(150))
        var lines: [String] = []
        var category: MemoryCategory?
        for item in shown {
            if item.resolvedCategory != category {
                category = item.resolvedCategory
                lines.append("\(item.resolvedCategory.title):")
            }
            lines.append("  - \(item.detail)")
        }
        if !related.isEmpty {
            lines.append("Bu mesajla en ilgili görünenler: " + related.map(\.detail).joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    /// Anahtar kelime + kök eşleşmesiyle ilgili bilgileri bulur (Türkçe ekleri tolere eder: "telefonum" → "telefon")
    func relevantFacts(for query: String, excluding: Set<UUID> = [], limit: Int = 8) -> [MemoryItem] {
        let tokens = Self.tokens(query)
        guard !tokens.isEmpty else { return [] }
        let scored = items.filter { !excluding.contains($0.id) }.compactMap { item -> (MemoryItem, Double)? in
            let keywordWords = (item.keywords ?? []).flatMap { Self.tokens($0) }
            let textWords = Self.tokens([item.text, item.detail, item.entity ?? "", item.relation ?? ""].joined(separator: " "))
            var score = 0.0
            for token in tokens {
                if keywordWords.contains(where: { Self.matches(token, $0) }) { score += 2 }
                else if textWords.contains(where: { Self.matches(token, $0) }) { score += 1 }
            }
            guard score > 0 else { return nil }
            return (item, score + Double(item.resolvedImportance) * 0.05)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static let stopWords: Set<String> = ["bir", "bu", "şu", "ve", "ile", "için", "ama", "gibi", "çok", "daha", "nasıl",
                                                  "ne", "neden", "mi", "mı", "mu", "mü", "da", "de", "ben", "sen", "benim",
                                                  "bana", "beni", "var", "yok", "olur", "oldu", "olan", "kadar", "sonra", "the", "and"]

    static func tokens(_ text: String) -> [String] {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// "telefonum" ~ "telefon", "kedilerim" ~ "kedi", "istanbul'da" ~ "istanbul"
    static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        return short.count >= 3 && long.hasPrefix(short)
    }

    // MARK: Öğrenme

    /// Her kullanıcı mesajından sonra çağrılır.
    /// - context: Asistanın bir önceki mesajı. Soru içeriyorsa ("Nerede yaşıyorsun?") kısa cevaplar da öğrenilir.
    func learn(from userText: String, context: String? = nil, messageID: UUID? = nil) {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let askedQuestion = context.map { $0.contains("?") } ?? false
        // "iPad'imi unut", "kedim yok" gibi kısa düzeltme/silme istekleri de işlenir
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        let isCorrection = ["unut", "sil", "hatırlama", "yanlış", "değilim", "yok artık", "artık"].contains { lowered.contains($0) }
        guard text.count >= 15 || isCorrection || (askedQuestion && text.count >= 2) else {   // "tamam", "eyw" vb.
            if let messageID { markProcessed([messageID]) }
            return
        }
        let ids = messageID.map { [$0] } ?? []
        if let context, askedQuestion {
            pending.append(("Asistanın sorusu: \"\(context.suffix(400))\"\nKullanıcının cevabı: \"\(text)\"", ids))
        } else {
            pending.append(("Kullanıcı: \"\(text)\"", ids))
        }
        guard !isLearning else { return }
        Task { await drainQueue() }
    }

    private func drainQueue() async {
        isLearning = true
        defer { isLearning = false }
        while !pending.isEmpty {
            let batch = pending.map(\.text).joined(separator: "\n\n---\n\n")
            let ids = pending.flatMap(\.ids)
            pending.removeAll()
            if await learnBatch(batch) { markProcessed(ids) }
        }
    }

    @discardableResult
    private func learnBatch(_ text: String) async -> Bool {
        do {
            let result = try await MemoryExtractor.extract(from: text, known: items)
            apply(result)
            lastError = nil
            lastLearnedAt = Date()
            UserDefaults.standard.set(lastLearnedAt, forKey: "pufy_memory_last_learned")
            return true
        } catch {
            if Task.isCancelled { return false }
            lastError = error.localizedDescription
            print("⚠️ Hafıza güncellenemedi: \(error.localizedDescription)")
            return false
        }
    }

    /// Telafi taraması: hafızaya hiç işlenmemiş kullanıcı mesajlarını öğrenir.
    /// ESKİ SORUN: öğrenme sadece cevap başarıyla bitince tetikleniyordu; bağlantı hatası alan
    /// "İstanbul'da yaşıyorum" gibi mesajlar hiç öğrenilmiyordu. Açılışta ve Kişisel Ağ açılınca çalışır.
    func catchUp(from sessions: [ChatSession]) async {
        guard !catchUpRunning, rebuildProgress == nil, !isLearning else { return }
        let firstRun = UserDefaults.standard.object(forKey: processedKey) == nil
        let cutoff = Date().addingTimeInterval(firstRun ? -14 * 86_400 : -60 * 86_400)
        var exchanges: [(text: String, ids: [UUID], date: Date)] = []
        var skipped: [UUID] = []
        for session in sessions {
            var lastAssistant: String?
            for message in session.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
                if message.role == .model { lastAssistant = message.content; continue }
                guard message.role == .user, !processedSet.contains(message.id.uuidString) else { continue }
                guard message.timestamp > cutoff else { skipped.append(message.id); continue }
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let q = lastAssistant, q.contains("?"), text.count >= 2, text.count < 15 {
                    exchanges.append(("Asistanın sorusu: \"\(q.suffix(300))\"\nKullanıcının cevabı: \"\(text)\"", [message.id], message.timestamp))
                } else if text.count >= 15 {
                    exchanges.append(("Kullanıcı: \"\(text.prefix(4000))\"", [message.id], message.timestamp))
                } else {
                    skipped.append(message.id)
                }
            }
        }
        markProcessed(skipped)
        guard !exchanges.isEmpty else { return }

        catchUpRunning = true
        isLearning = true
        defer { catchUpRunning = false; isLearning = false }
        // En yeniler önce; tek seferde en fazla 6 paket (gerisi sonraki açılışta)
        let ordered = exchanges.sorted { $0.date > $1.date }
        var batches: [(text: String, ids: [UUID])] = []
        var current = (text: "", ids: [UUID]())
        for item in ordered {
            if current.text.count + item.text.count > 6000, !current.text.isEmpty {
                batches.append(current)
                current = ("", [])
            }
            current.text += (current.text.isEmpty ? "" : "\n\n---\n\n") + item.text
            current.ids += item.ids
        }
        if !current.text.isEmpty { batches.append(current) }
        for batch in batches.prefix(6) {
            guard await learnBatch(batch.text) else { break }
            markProcessed(batch.ids)
        }
    }

    /// Tüm sohbetlerdeki kullanıcı mesajlarını baştan tarar
    func rebuild(from sessions: [ChatSession]) async {
        guard rebuildProgress == nil else { return }
        var exchanges: [String] = []
        for session in sessions {
            var lastAssistant: String?
            for message in session.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
                if message.role == .model { lastAssistant = message.content; continue }
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let q = lastAssistant, q.contains("?"), text.count >= 2, text.count < 15 {
                    exchanges.append("Asistanın sorusu: \"\(q.suffix(300))\"\nKullanıcının cevabı: \"\(text)\"")
                } else if text.count >= 15 {
                    exchanges.append("Kullanıcı: \"\(text.prefix(8000))\"")
                }
            }
        }
        guard !exchanges.isEmpty else {
            lastError = "Sohbetlerinde kendinden bahsettiğin bir mesaj bulunamadı."
            return
        }

        var batches: [String] = []
        var current = ""
        for item in exchanges {
            if current.count + item.count > 6000, !current.isEmpty {
                batches.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n---\n\n") + item
        }
        if !current.isEmpty { batches.append(current) }

        rebuildProgress = 0
        isLearning = true
        for (index, batch) in batches.enumerated() {
            await learnBatch(batch)
            rebuildProgress = Double(index + 1) / Double(batches.count)
        }
        markProcessed(sessions.flatMap { $0.messages.filter { $0.role == .user }.map(\.id) })
        isLearning = false
        rebuildProgress = nil
        PremiumHaptics.success()
    }

    /// Anahtar kelimesi olmayan eski bilgilere (önceki sürümden) bir kez anahtar kelime ekletir
    func backfillKeywordsIfNeeded() {
        let missing = items.filter { ($0.keywords ?? []).isEmpty }
        guard !keywordBackfillStarted, !missing.isEmpty else { return }
        keywordBackfillStarted = true
        Task {
            let list = missing.prefix(60).enumerated().map { "k\($0.offset): \($0.element.detail)" }.joined(separator: "\n")
            let prompt = """
            Her bilgi için, kullanıcı ileride bu bilgiyle ilgili bir şey söylediğinde geçebilecek 3-6 Türkçe anahtar kelime yaz
            (eş anlamlılar ve üst kavramlar dahil; ör. "iPhone 15 Pro Max kullanıyor" → telefon, iphone, cihaz, apple, mobil).
            Sadece JSON: {"k0":["…"],"k1":["…"]}

            \(list)
            """
            guard let raw = try? await GeminiService.shared.generateContent(prompt: prompt, maxOutputTokens: 6000,
                                                                            responseMimeType: "application/json"),
                  let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}"), s < e,
                  let data = String(raw[s...e]).data(using: .utf8),
                  let map = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }
            for (offset, item) in missing.prefix(60).enumerated() {
                guard let words = map["k\(offset)"], let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
                items[index].keywords = words
            }
            save()
        }
    }

    // MARK: Değişiklikleri uygulama

    private func apply(_ result: MemoryExtractor.Result) {
        var changed = false
        // Silinenler (taşındı, artık yapmıyor, yanlışmış…)
        for id in result.removeIDs {
            if let index = items.firstIndex(where: { $0.id == id }) {
                let removed = items.remove(at: index)
                // Bu turda eklenip hemen silinen bilginin izi kalmasın; değilse "silindi" izi
                if traces.contains(where: { $0.item.id == id && $0.kind == .added }) {
                    traces.removeAll { $0.item.id == id }
                } else {
                    record(.removed, removed)
                }
                changed = true
            }
        }
        // Güncellenenler
        for (id, change) in result.updates {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            var item = items[index]
            if let v = change.label, !v.isEmpty { item.text = v }
            if let v = change.detail, !v.isEmpty { item.detail = v }
            if let v = change.category { item.category = v }
            if let v = change.entity { item.entity = v }
            if let v = change.relation { item.relation = v }
            if let v = change.importance { item.importance = v }
            if let v = change.keywords, !v.isEmpty { item.keywords = v }
            if let v = change.parentID, v != item.id { item.parent = v }
            if let v = change.linkIDs, !v.isEmpty { item.links = Array(Set((item.links ?? []) + v).subtracting([item.id])) }
            item.updatedAt = Date()
            items[index] = item
            if !traces.contains(where: { $0.item.id == id && $0.kind == .added }) { record(.updated, item) }
            changed = true
        }
        // Yeniler (kullanıcının sildikleri ve neredeyse aynı olanlar hariç)
        for fact in result.additions {
            guard let detail = fact.detail, !detail.isEmpty else { continue }
            let normDetail = Self.normalize(detail)
            let label = fact.label?.isEmpty == false ? fact.label! : String(detail.prefix(24))
            if blocked.contains(normDetail) || blocked.contains(Self.normalize(label)) { continue }
            if items.contains(where: { Self.similarity(Self.normalize($0.detail), normDetail) > 0.7 }) { continue }
            var item = MemoryItem(
                text: label, detail: detail, category: fact.category ?? .other,
                entity: fact.entity, relation: fact.relation, importance: fact.importance ?? 3,
                createdAt: Date(), updatedAt: Date(), keywords: fact.keywords
            )
            item.parent = fact.parentID
            item.links = fact.linkIDs
            items.append(item)
            record(.added, item)
            changed = true
        }
        if changed { save(); saveTraces() }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// Kelime kümesi benzerliği (Jaccard)
    static func similarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.split(separator: " ").filter { $0.count > 2 })
        let setB = Set(b.split(separator: " ").filter { $0.count > 2 })
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        return Double(setA.intersection(setB).count) / Double(setA.union(setB).count)
    }
}

// MARK: - Çıkarıcı

enum MemoryExtractor {
    struct Result {
        var additions: [MemoryChange] = []
        var updates: [(UUID, MemoryChange)] = []
        var removeIDs: [UUID] = []
    }

    static func extract(from text: String, known: [MemoryItem]) async throws -> Result {
        // Bilinenler kısa kimliklerle (m0, m1…) verilir; model bunlarla güncelleme/silme yapar
        let idMap = Dictionary(uniqueKeysWithValues: known.enumerated().map { ("m\($0.offset)", $0.element.id) })
        let knownText = known.isEmpty
            ? "(henüz yok)"
            : known.enumerated().map { "m\($0.offset) [\($0.element.resolvedCategory.rawValue)] \($0.element.detail)" }.joined(separator: "\n")
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        let prompt = """
        Bugün: \(today)

        BİLİNENLER:
        \(knownText)

        YENİ KONUŞMA:
        \"\"\"
        \(text.prefix(12000))
        \"\"\"
        """

        // NÖRON KURALLARI (14 Ekim 2026 netleştirildi; ayrıntı: YAPAY_ZEKA_ANAYASASI.md §5)
        // Sadece KULLANICININ kendi sözleri işlenir (asistanın cevapları değil) → asistanın tahminleri hafızaya girmez.
        let system = """
        Sen Pufy'nin kişisel hafıza motorusun ("Kişisel Ağ"). Konuşmadan kullanıcının KENDİSİ hakkındaki KALICI bilgileri çıkarır, \
        bilinenleri günceller ya da silersin. Sadece JSON üret.

        1) EKLE ("add") — HEPSİ sağlanmalı:
           a) Bilgi kullanıcının KENDİSİ (ya da kendi yakınları, eşyaları, işi) hakkında ve kullanıcı bunu AÇIKÇA söyledi \
              ya da cümlesinden kesin anlaşılıyor ("iPad'imin şarjı bitiyor" → iPad'i var).
           b) KALICI: haftalar/aylar boyunca doğru kalacak (kimlik, yaşadığı yer, aile ve arkadaşlar, evcil hayvan, iş/okul, \
              cihaz ve araçlar, sürekli ilgi alanları, tuttuğu takım, beslenme tercihi, alerji/kronik sağlık durumu, hedef, önemli tarih).
           c) BİLİNENLERDE yok (aynısı ya da aynı şeyin eski hali varsa EKLEME, "update" yap).
           Asistan bir soru sorup kullanıcı kısaca cevap verdiyse ("iPad modelin hangisi?" → "Air") bunu tam bilgi olarak kaydet \
           ("iPad Air kullanıyor") — gerekirse var olan kaydı güncelle.
        2) EKLEME:
           - Sadece SORULAN ya da merak edilen şeyler: "iPhone 17 ne zaman çıkıyor?" ≠ iPhone 17'si var; "Roma maçı kaç kaç?" ≠ Roma taraftarı.
           - Tek seferlik istek ve görevler (tarif istedi, hatırlatıcı kurdu, çeviri yaptırdı), haberler, genel bilgi, başkaları hakkındaki genel sorular.
           - Anlık durum ve ruh hali ("bugün yorgunum", "şu an otobüsteyim", "acıktım"), varsayımlar ("diyelim ki…"), şakalar, rol yapma, alıntılar.
           - Asistanın söylediği ya da tahmin ettiği hiçbir şey.
           - GİZLİ bilgiler: şifre, kart/hesap numarası, TC kimlik, API anahtarı, tam adres — ASLA kaydetme.
           Tek bir sorudan ilgi alanı çıkarma; kullanıcı açıkça söylerse ("Galatasaray'lıyım", "her hafta izlerim", "satranç oynarım") kaydet.
        3) GÜNCELLE ("update"): Aynı konu hakkında yeni ya da daha ayrıntılı bilgi gelince eski kaydı DEĞİŞTİR, yeni kayıt açma:
           taşındı (İstanbul → Ankara), telefon/araba değiştirdi, iş değiştirdi, ayrıntı netleşti ("iPad" → "iPad Pro M4"), yaşı/rolü değişti.
           Önem değişirse importance'ı da güncelle (tekrar tekrar bahsedilen bilgi daha önemlidir).
        4) SİL ("remove") — sadece şu durumlarda:
           - Kullanıcı açıkça unutmanı/silmeni istedi ("bunu unut", "hafızandan sil", "beni X olarak hatırlama").
           - Kullanıcı bir bilginin YANLIŞ olduğunu söyledi ("ben İzmir'de yaşamıyorum", "kedim yok").
           - Bilgi artık geçerli değil ve yerine yenisi gelmedi ("artık sigara içmiyorum", "ayrıldık", "arabamı sattım", "köpeğimiz öldü").
           Konuşmada geçmemesi, silme sebebi DEĞİLDİR. Emin değilsen silme.

        Her kayıt TEK bir gerçek; Türkçe, üçüncü şahıs, kısa.
        - label: 1-3 kelime ("Sema", "İstanbul", "iPhone 15 Pro Max")
        - detail: tam cümle ("İstanbul'da yaşıyor")
        - category: identity | people | work | skills | interests | preferences | traits | places | goals | health
        - entity: kişi/yer/şeyin adı; relation: sadece insanlar için ("en yakın arkadaşı")
        - importance: 1-5 (5 = isim, yaşadığı yer, yakın aile; 4 = iş/okul, sürekli kullandığı cihaz, sağlık; 3 = ilgi alanı, tercih; 1-2 = küçük ayrıntı)
        - keywords: kullanıcı ileride bu bilgiyle ilgili bir şey söylerse geçebilecek 3-6 kelime, eş anlamlı ve üst kavramlar dahil
          (iPhone → ["telefon","iphone","cihaz","apple"]; İstanbul'da yaşıyor → ["ev","şehir","yaşadığı yer","konum","istanbul"])

        - about: Bu bilgi BİLİNENLER'deki bir kişi/şey HAKKINDAYSA onun kimliği ("m12"). Ör. "Nura" zaten m12 ise
          "Nura'nın doğum günü 3 Mayıs" → about: "m12". Kişi/şey bilinenlerde yoksa yazma.
        - related: Bilinenlerden bu bilgiyle DOĞRUDAN ilişkili en fazla 3 kimlik (ör. "iPad'e uygulama geliştirmek istiyor" ↔ "iPad kullanıyor").
          Zayıf/genel benzerlikler için yazma.

        Format: {"add":[{...}], "update":[{"id":"m3", ...sadece değişen alanlar}], "remove":["m7"]}
        Değişiklik yoksa: {"add":[],"update":[],"remove":[]}
        """

        let raw = try await GeminiService.shared.generateContent(
            prompt: prompt,
            systemPrompt: system,
            maxOutputTokens: 8192,
            responseMimeType: "application/json",
            thinking: "low"
        )
        return parse(raw, idMap: idMap)
    }

    static func parse(_ raw: String, idMap: [String: UUID]) -> Result {
        var result = Result()
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return result }

        func change(_ f: [String: Any]) -> MemoryChange {
            func str(_ k: String) -> String? {
                guard let v = (f[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
                return v
            }
            let importance = (f["importance"] as? Int) ?? (f["importance"] as? String).flatMap(Int.init)
            return MemoryChange(
                label: str("label"), detail: str("detail"),
                category: str("category").flatMap { MemoryCategory(rawValue: $0.lowercased()) },
                entity: str("entity"), relation: str("relation"),
                importance: importance.map { min(max($0, 1), 5) },
                keywords: (f["keywords"] as? [String])?.filter { !$0.isEmpty },
                parentID: str("about").flatMap { idMap[$0] },
                linkIDs: ((f["related"] as? [String]) ?? []).compactMap { idMap[$0] }.nilIfEmptyArray
            )
        }

        result.additions = ((json["add"] as? [[String: Any]]) ?? (json["facts"] as? [[String: Any]]) ?? []).map(change)
        result.updates = ((json["update"] as? [[String: Any]]) ?? []).compactMap { f in
            guard let key = f["id"] as? String, let id = idMap[key] else { return nil }
            return (id, change(f))
        }
        result.removeIDs = ((json["remove"] as? [String]) ?? []).compactMap { idMap[$0] }
        return result
    }
}

private extension Array {
    var nilIfEmptyArray: [Element]? { isEmpty ? nil : self }
}
