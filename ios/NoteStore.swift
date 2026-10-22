import Foundation
import SwiftUI

// MARK: - Notlar
//
// Kullanıcı (15 Ekim 2026): "Yapay zeka benim yerime not alabilsin. Alışveriş listesi bir not, yapılacaklar ayrı bir not;
// başka bir sohbette yeni bir yapılacak çıkarsa hangi nota yazacağını iyi bilsin (kendi kendine sınıflandırsın).
// Menüde hatırlatıcıların altında Notlar başlıklarıyla görünsün; basınca not sayfası tamamen açılsın."
//
// Yapay zeka mevcut notları (kimlik, başlık, içerik) her mesajda görür ve [NOTE: {...}] etiketiyle doğru nota yazar:
//   yeni not:            [NOTE: {"title":"Alışveriş Listesi","content":"- [ ] Süt\n- [ ] Ekmek"}]
//   var olana ekleme:    [NOTE: {"id":"…","append":"- [ ] Yumurta"}]
//   baştan yazma:        [NOTE: {"id":"…","content":"…tam içerik…"}]
//   işaretle / çıkar:    [NOTE: {"id":"…","check":["Süt"]}]  /  {"id":"…","remove":["Ekmek"]}
//   silme:               [DELETE_NOTE: {"id":"…"}]
// Liste maddeleri Markdown işaret kutusu: "- [ ] madde" / "- [x] madde" (not sayfasında dokunarak işaretlenir).

struct Note: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    /// Markdown; listelerde "- [ ] madde"
    var content: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// İşaret kutulu maddeler: (tamamlanan, toplam)
    var checklistProgress: (done: Int, total: Int)? {
        let lines = content.components(separatedBy: "\n").compactMap(NoteLine.checkItem)
        guard !lines.isEmpty else { return nil }
        return (lines.filter(\.done).count, lines.count)
    }

    /// Menüdeki alt satır
    var summary: String {
        if let p = checklistProgress {
            return AppLanguage.isEnglish ? "\(p.done)/\(p.total) completed" : "\(p.done)/\(p.total) tamamlandı"
        }
        let first = content.components(separatedBy: "\n").map { NoteLine.plain($0) }.first { !$0.isEmpty } ?? ""
        return first.isEmpty ? (AppLanguage.isEnglish ? "Empty note" : "Boş not") : first
    }
}

/// Not içeriğinin tek satırı (görüntüleme ve işaretleme için)
enum NoteLine {
    case check(done: Bool, text: String)
    case bullet(String)
    case heading(String)
    case text(String)
    case blank

    init(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if let item = NoteLine.checkItem(line) { self = .check(done: item.done, text: item.text) }
        else if line.isEmpty { self = .blank }
        else if line.hasPrefix("#") { self = .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
        else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") { self = .bullet(String(line.dropFirst(2))) }
        else { self = .text(line) }
    }

    static func checkItem(_ raw: String) -> (done: Bool, text: String)? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        for (prefix, done) in [("- [ ]", false), ("- [x]", true), ("- [X]", true), ("* [ ]", false), ("* [x]", true)]
        where line.hasPrefix(prefix) {
            return (done, line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// İşaretsiz düz metin ("- [ ] Süt" → "Süt")
    static func plain(_ raw: String) -> String {
        switch NoteLine(raw) {
        case .check(_, let t), .bullet(let t), .heading(let t), .text(let t): return t
        case .blank: return ""
        }
    }
}

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [Note] = []
    /// Açılacak not (menü, sohbet rozeti)
    @Published var presented: PresentedNote?

    struct PresentedNote: Identifiable {
        let id: UUID
        var editing = false
    }

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("pufy-notes.json")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }

    /// Son değişen en üstte
    var sorted: [Note] { notes.sorted { $0.updatedAt > $1.updatedAt } }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(notes).write(to: fileURL, options: .atomic)
        SyncService.shared.scheduleSync()
    }

    // MARK: Düzenleme (kullanıcı)

    @discardableResult
    func create(title: String = "Yeni Not", content: String = "") -> Note {
        let note = Note(title: title, content: content)
        notes.append(note)
        save()
        return note
    }

    func update(_ id: UUID, title: String? = nil, content: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { notes[index].title = title.trimmingCharacters(in: .whitespaces) }
        if let content { notes[index].content = content }
        notes[index].updatedAt = Date()
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        notes.removeAll()
        save()
    }

    /// Not sayfasında maddeye dokununca
    func toggle(_ id: UUID, line lineIndex: Int) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var lines = notes[index].content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex), let item = NoteLine.checkItem(lines[lineIndex]) else { return }
        let indent = String(lines[lineIndex].prefix { $0 == " " })
        lines[lineIndex] = indent + (item.done ? "- [ ] " : "- [x] ") + item.text
        notes[index].content = lines.joined(separator: "\n")
        notes[index].updatedAt = Date()
        save()
    }

    // MARK: Eşitleme

    func applyRemote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            guard notes[index] != note else { return }
            notes[index] = note
        } else {
            notes.append(note)
        }
        try? JSONEncoder().encode(notes).write(to: fileURL, options: .atomic)
    }

    func applyRemoteDeletion(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        notes.removeAll { $0.id == id }
        try? JSONEncoder().encode(notes).write(to: fileURL, options: .atomic)
    }

    // MARK: Yapay zeka

    /// Yapay zekaya verilen mevcut notlar (hangi nota yazacağını seçebilsin diye içerikleriyle)
    func promptText() -> String {
        guard !notes.isEmpty else { return "Henüz not yok." }
        var budget = 9000
        var lines: [String] = []
        for note in sorted {
            let body = note.content.count > 1500 ? String(note.content.prefix(1500)) + "\n…(devamı var)" : note.content
            let entry = "- ID: \(note.id.uuidString) | Başlık: \"\(note.title)\"\n" +
                body.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
            budget -= entry.count
            if budget < 0 { lines.append("- ID: \(note.id.uuidString) | Başlık: \"\(note.title)\" (içerik uzun, gösterilmedi)"); continue }
            lines.append(entry)
        }
        return lines.joined(separator: "\n")
    }

    /// Notla ilgisiz mesajlarda sadece başlıklar (yönerge kısa kalsın, cevap hızlı gelsin)
    func titlesText() -> String {
        guard !notes.isEmpty else { return "henüz not yok." }
        return sorted.prefix(30).map { "\"\($0.title)\" (ID: \($0.id.uuidString))" }.joined(separator: ", ")
    }

    /// Mesaj bir notun başlığına ya da maddesine değiniyor mu? ("sütü aldım", "tatil planına bak")
    func isMentioned(in query: String) -> Bool {
        let tr = Locale(identifier: "tr_TR")
        let words = query.lowercased(with: tr)
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
        guard !words.isEmpty else { return false }
        func hit(_ text: String) -> Bool {
            let key = text.lowercased(with: tr)
                .components(separatedBy: CharacterSet.letters.inverted)
                .first { $0.count >= 3 }
            guard let key else { return false }
            return words.contains { $0.hasPrefix(key) }
        }
        for note in notes {
            if note.title.lowercased(with: tr).components(separatedBy: CharacterSet.letters.inverted)
                .contains(where: { $0.count >= 4 && words.contains($0) }) { return true }
            for raw in note.content.components(separatedBy: "\n").prefix(80) {
                switch NoteLine(raw) {
                case .check(_, let text), .bullet(let text): if hit(text) { return true }
                default: break
                }
            }
        }
        return false
    }

    /// Cevaptaki [NOTE]/[DELETE_NOTE] etiketlerini uygular, metinden çıkarır. Dönen: (temiz metin, rozet, açılacak not)
    func applyTags(in text: String) -> (text: String, badges: [String], noteID: UUID?) {
        var text = text
        var badges: [String] = []
        var lastID: UUID?
        for object in Self.takeJSONTags("DELETE_NOTE", from: &text) {
            guard let id = (object["id"] as? String).flatMap(UUID.init(uuidString:)), let note = note(id) else { continue }
            delete(id)
            badges.append("Not silindi: \(note.title)")
        }
        for object in Self.takeJSONTags("NOTE", from: &text) {
            if let (id, badge) = applyNote(object) {
                lastID = id
                badges.append(badge)
            }
        }
        return (text, badges, lastID)
    }

    private func applyNote(_ o: [String: Any]) -> (UUID, String)? {
        let title = (o["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = (o["id"] as? String).flatMap(UUID.init(uuidString:)).flatMap { id in notes.firstIndex { $0.id == id } }
        // Kimlik yoksa ama aynı başlıkta not varsa ona yaz (aynı türde ikinci not açılmasın)
        if index == nil, let title, !title.isEmpty {
            let key = Self.normalize(title)
            index = notes.firstIndex { Self.normalize($0.title) == key }
        }
        guard let i = index else {
            guard let title, !title.isEmpty else { return nil }
            let content = (o["content"] as? String) ?? (o["append"] as? String) ?? ""
            let note = create(title: title, content: content.trimmingCharacters(in: .newlines))
            return (note.id, "Not alındı: \(note.title)")
        }
        var note = notes[i]
        if let title, !title.isEmpty, o["rename"] as? Bool == true || o["content"] != nil { note.title = title }
        if let content = o["content"] as? String {
            note.content = content.trimmingCharacters(in: .newlines)
        }
        if let append = o["append"] as? String {
            // Zaten listede olan maddeyi tekrar ekleme
            let existing = Set(note.content.components(separatedBy: "\n").map { Self.normalize(NoteLine.plain($0)) })
            let fresh = append.components(separatedBy: "\n").filter {
                let key = Self.normalize(NoteLine.plain($0))
                return !key.isEmpty && !existing.contains(key)
            }
            if !fresh.isEmpty {
                note.content = note.content.trimmingCharacters(in: .newlines) + (note.content.isEmpty ? "" : "\n") + fresh.joined(separator: "\n")
            }
        }
        func matches(_ line: String, _ targets: [String]) -> Bool {
            let key = Self.normalize(NoteLine.plain(line))
            return targets.contains { let t = Self.normalize($0); return !t.isEmpty && (key == t || key.contains(t)) }
        }
        if let check = o["check"] as? [String] {
            note.content = note.content.components(separatedBy: "\n").map { line in
                guard let item = NoteLine.checkItem(line), !item.done, matches(line, check) else { return line }
                return "- [x] " + item.text
            }.joined(separator: "\n")
        }
        if let uncheck = o["uncheck"] as? [String] {
            note.content = note.content.components(separatedBy: "\n").map { line in
                guard let item = NoteLine.checkItem(line), item.done, matches(line, uncheck) else { return line }
                return "- [ ] " + item.text
            }.joined(separator: "\n")
        }
        if let remove = o["remove"] as? [String] {
            note.content = note.content.components(separatedBy: "\n").filter { !matches($0, remove) }.joined(separator: "\n")
        }
        note.updatedAt = Date()
        notes[i] = note
        save()
        return (note.id, "Not güncellendi: \(note.title)")
    }

    static func normalize(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "[ETİKET: {json}]" — içerikte "- [ ] madde" gibi köşeli parantezler olduğu için süslü parantez sayılarak ayrıştırılır
    static func takeJSONTags(_ tag: String, from text: inout String) -> [[String: Any]] {
        var results: [[String: Any]] = []
        let pattern = "\\[\(tag)\\s*:\\s*"
        // "[NOTE:" kalıbı "[DELETE_NOTE:" ile eşleşmez ("[" hemen önünde olmalı)
        while let start = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            guard let brace = text[start.upperBound...].firstIndex(of: "{") else { text.removeSubrange(start); continue }
            var depth = 0, inString = false, escaped = false
            var end: String.Index?
            var i = brace
            while i < text.endIndex {
                let c = text[i]
                if inString {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                } else if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
                i = text.index(after: i)
            }
            guard let end else { text.removeSubrange(start.lowerBound..<text.endIndex); break }
            if let data = String(text[brace...end]).data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                results.append(object)
            }
            var close = text.index(after: end)
            while close < text.endIndex, text[close].isWhitespace { close = text.index(after: close) }
            if close < text.endIndex, text[close] == "]" { close = text.index(after: close) }
            text.removeSubrange(start.lowerBound..<close)
        }
        return results
    }
}
