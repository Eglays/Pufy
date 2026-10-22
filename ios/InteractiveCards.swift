import SwiftUI
import UIKit

// MARK: - Etkileşimli sohbet parçaları
//
// Kullanıcı (15 Ekim 2026): "Sohbet arayüzünde buton, anket, soru, sunum, slayt gibi şeyleri arttıralım, daha interaktif
// olsun. Mesela iPhone 17 Pro Max ile 18 Pro Max farkını sorunca gereken yerde tatlı bir sunum hazırlasın — süreden çok
// feragat etmeden."
//  • [SLIDES: başlık]  → cevap BİTTİKTEN SONRA ayrı bir istekle 5-8 slaytlık sunum hazırlanır (cevap hiç gecikmez);
//                        sohbette kapak kartı, dokununca tam ekran slaytlar, PDF olarak paylaşma
//  • [COMPARE: {json}] → görselli karşılaştırma kartı (daha iyi olan işaretli, sonuç cümlesi)
//  • [QUIZ: {json}]    → sohbetin içinde çözülen test (anında doğru/yanlış, açıklama, puan, yanlışları sorma)
//  • [ACTIONS: a | b]  → cevabın altında, dokununca mesaj olarak giden eylem butonları

// MARK: - Modeller

/// Modelden gelen değerler bazen sayı bazen yazı: hepsini yazıya çevir
private struct LooseString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else if let b = try? c.decode(Bool.self) { value = b ? "Var" : "Yok" }
        else { value = "" }
    }
}

struct SlideRow: Codable, Hashable {
    var label: String
    var values: [String]
    /// Daha iyi olan sütun (0'dan başlar); eşitse ya da kıyaslanamıyorsa yok
    var better: Int? = nil

    enum CodingKeys: String, CodingKey { case label, values, better }

    init(label: String, values: [String], better: Int? = nil) {
        self.label = label
        self.values = values
        self.better = better
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(LooseString.self, forKey: .label).value) ?? ""
        values = ((try? c.decode([LooseString].self, forKey: .values)) ?? []).map(\.value)
        if let b = try? c.decode(Int.self, forKey: .better) { better = b }
        else if let s = try? c.decode(String.self, forKey: .better) { better = Int(s) }
    }
}

struct Slide: Codable, Hashable {
    struct Item: Codable, Hashable {
        var label: String
        var value: String? = nil
        var text: String? = nil

        enum CodingKeys: String, CodingKey { case label, value, text }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = (try? c.decode(LooseString.self, forKey: .label).value) ?? ""
            value = try? c.decode(LooseString.self, forKey: .value).value
            text = try? c.decode(LooseString.self, forKey: .text).value
        }
    }

    /// cover | bullets | compare | stats | timeline | verdict | section | quote | image | proscons
    var kind: String
    var title: String? = nil
    var subtitle: String? = nil
    var bullets: [String]? = nil
    /// İngilizce Wikipedia başlığı (gerçek fotoğraf)
    var image: String? = nil
    var columns: [String]? = nil
    var rows: [SlideRow]? = nil
    var items: [Item]? = nil
    var text: String? = nil
    var pros: [String]? = nil
    var cons: [String]? = nil

    enum CodingKeys: String, CodingKey { case kind, title, subtitle, bullets, image, columns, rows, items, text, pros, cons }

    init(kind: String, title: String? = nil, subtitle: String? = nil, image: String? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.image = image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = ((try? c.decode(String.self, forKey: .kind)) ?? "bullets").lowercased()
        title = try? c.decode(String.self, forKey: .title)
        subtitle = try? c.decode(String.self, forKey: .subtitle)
        bullets = (try? c.decode([LooseString].self, forKey: .bullets))?.map(\.value).filter { !$0.isEmpty }
        image = (try? c.decode(String.self, forKey: .image)).flatMap { $0.isEmpty ? nil : $0 }
        columns = (try? c.decode([LooseString].self, forKey: .columns))?.map(\.value)
        rows = try? c.decode([SlideRow].self, forKey: .rows)
        items = try? c.decode([Item].self, forKey: .items)
        text = try? c.decode(String.self, forKey: .text)
        pros = (try? c.decode([LooseString].self, forKey: .pros))?.map(\.value).filter { !$0.isEmpty }
        cons = (try? c.decode([LooseString].self, forKey: .cons))?.map(\.value).filter { !$0.isEmpty }
    }
}

struct SlideDeck: Codable, Hashable {
    enum Status: String, Codable { case generating, ready, failed }
    var title: String
    var subtitle: String? = nil
    var slides: [Slide] = []
    var status: Status = .generating
    /// Hazırlığın başladığı an (uygulama kapanınca yarım kalanı "tekrar dene"ye çevirmek için)
    var startedAt: Date? = Date()
    /// Renk teması (bkz. SlideTheme), desen ve isteğe bağlı marka/takım rengi
    var theme: String? = nil
    var pattern: String? = nil
    var accent: String? = nil
}

struct QuizData: Codable, Hashable {
    struct Question: Codable, Hashable {
        var q: String
        var options: [String]
        var answer: Int
        var explain: String? = nil

        enum CodingKeys: String, CodingKey { case q, options, answer, explain }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            q = (try? c.decode(String.self, forKey: .q)) ?? ""
            options = ((try? c.decode([LooseString].self, forKey: .options)) ?? []).map(\.value)
            explain = try? c.decode(String.self, forKey: .explain)
            // Doğru cevap: sıra (0'dan), "B" gibi harf ya da seçeneğin kendisi olabilir
            if let i = try? c.decode(Int.self, forKey: .answer) {
                answer = i
            } else if let s = try? c.decode(String.self, forKey: .answer) {
                let t = s.trimmingCharacters(in: .whitespaces)
                if let i = Int(t) { answer = i }
                else if t.count == 1, let ascii = t.uppercased().unicodeScalars.first?.value, (65...70).contains(ascii) {
                    answer = Int(ascii) - 65
                } else {
                    answer = options.firstIndex { $0.caseInsensitiveCompare(t) == .orderedSame } ?? 0
                }
            } else {
                answer = 0
            }
        }
    }
    var title: String? = nil
    var questions: [Question]

    var isValid: Bool {
        !questions.isEmpty && questions.allSatisfy { $0.options.count >= 2 && $0.options.indices.contains($0.answer) && !$0.q.isEmpty }
    }
}

struct CompareData: Codable, Hashable {
    struct Item: Codable, Hashable {
        var name: String
        var wiki: String? = nil
        var subtitle: String? = nil
    }
    var title: String? = nil
    var items: [Item]
    var rows: [SlideRow]
    var verdict: String? = nil

    var isValid: Bool { (2...4).contains(items.count) && !rows.isEmpty }
}

extension JSONTag {
    /// [NAME: {json}] etiketini çıkarıp çözer (yarım etiket akış sırasında gizlenir)
    static func decode<T: Decodable>(_ name: String, as type: T.Type, from input: String) -> (text: String, value: T?) {
        let (text, payloads) = extract(name, from: input)
        let value = payloads.lazy.compactMap { try? JSONDecoder().decode(T.self, from: $0) }.first
        return (text, value)
    }
}

// MARK: - Sunum hazırlayıcı

enum SlideMaker {
    static let system = """
    Sen usta bir sunum tasarımcısısın. Sana bir sohbet ve asistanın cevabı verilecek. Bu bilgilerden Türkçe, akıcı, sade ama \
    göze hoş gelen bir sunum hazırla. SADECE JSON yaz:
    {"title":"Kısa sunum başlığı","subtitle":"Bir cümlelik alt başlık","theme":"…","pattern":"…","accent":"#RRGGBB (isteğe bağlı)","slides":[ … ]}

    SLAYT SAYISI içeriğe göre: kısa/basit konu 3-4, normal 5-8, kapsamlı (gezi planı, uzun araştırma, çok başlıklı konu) 9-15. \
    Her sunumda aynı sayıyı kullanma; içerik ne kadarsa o kadar. Bir slayta çok şey sıkıştırma, boş slayt da açma.

    TEMA (konuya uygun olanı seç; renkli temaları tercih et): mono (sadece kullanıcı sade/siyah-beyaz isterse), ocean (bilim, \
    teknoloji, telefon, deniz, seyahat), forest (doğa, sağlık, bitki, çevre), sunset (yemek, gezi, enerji, yaz), sand (tarih, kültür, kitap, sanat), \
    slate (iş, finans, ekonomi, kariyer), crimson (futbol, spor, otomobil, tutku), teal (eğitim, psikoloji, sağlıklı yaşam), \
    gold (başarı, ödül, lüks, Fenerbahçe gibi sarı-lacivert konular), midnight (uzay, astronomi, gece, oyun, sinema).
    "accent": konunun bilinen bir markası/takımı varsa onun rengi (Galatasaray #C8102E, Beşiktaş #111111, Trabzonspor #7A1F3D, \
    Spotify #1DB954); yoksa yazma. Mor ve pembe kullanma.
    DESEN (kapak ve bölüm slaytlarında): rings, dots, grid, waves, diagonal, blobs, arcs, none — konunun havasına göre seç, hep aynısını seçme.

    Slayt türleri:
    - {"kind":"cover","title":"…","subtitle":"…","image":"İngilizce Wikipedia başlığı"} — İLK slayt, her zaman.
    - {"kind":"section","title":"Bölüm adı","subtitle":"kısa açıklama"} — uzun sunumlarda bölüm ayırıcı (9+ slaytta 1-3 tane).
    - {"kind":"bullets","title":"…","bullets":["…","…"],"image":"İngilizce Wikipedia başlığı (isteğe bağlı)"} — 2-5 madde, her biri en fazla 12 kelime.
    - {"kind":"image","title":"…","text":"1-2 cümle açıklama","image":"İngilizce Wikipedia başlığı"} — gözle görülür bir şeyi büyük fotoğrafla göster (yer, yemek, ürün, hayvan).
    - {"kind":"compare","title":"…","columns":["A","B"],"rows":[{"label":"Ekran","values":["6,9 inç","6,9 inç"]},{"label":"Pil","values":["4.832 mAh","5.100 mAh"],"better":1}]} — 2-3 sütun, 3-7 satır; "better" daha iyi olanın sırası (0'dan), eşitse yazma.
    - {"kind":"proscons","title":"…","pros":["…"],"cons":["…"]} — artılar/eksiler (2-4'er madde).
    - {"kind":"stats","title":"…","items":[{"value":"48 MP","label":"Ana kamera"},{"value":"%20","label":"Daha uzun pil"}]} — 1-4 çarpıcı sayı.
    - {"kind":"timeline","title":"…","items":[{"label":"Eylül 2026","text":"Tanıtım"}]} — tarih/gün/adım sırası, 3-5 öğe.
    - {"kind":"quote","text":"Akılda kalan tek cümle","subtitle":"kaynak (varsa)"} — öne çıkan bir söz ya da ana fikir.
    - {"kind":"verdict","title":"Sonuç","text":"1-2 cümlelik net hüküm","bullets":["kime uygun…"]} — SON slayt, her zaman.

    Kurallar:
    - SADECE verilen metindeki bilgileri kullan; yeni sayı, tarih, özellik UYDURMA.
    - Türleri karıştır ve konuya göre seç: karşılaştırmada compare/proscons, sayılarda stats, sırada timeline, yerlerde image.
    - "image" yalnızca gerçek, gözle görülebilir bir şey için ve İngilizce Wikipedia sayfa başlığı olarak \
    ("iPhone 17 Pro", "Cappadocia", "Lasagna"); soyut konularda yazma. En fazla 4 slaytta görsel.
    - Başlıklar kısa (en fazla 6 kelime). Emoji yok. Türkçe sayı biçimi (6,9 inç; 1.299 $). Türkçe karakterleri doğru yaz.
    """

    /// - contentLength: sunuma dönüşecek cevabın uzunluğu (slayt sayısını içeriğe göre seçsin diye modele söylenir)
    static func make(title: String, conversation: String, contentLength: Int) async throws -> SlideDeck {
        let size = contentLength < 1300 ? "KISA (3-4 slayt)" : contentLength < 3500 ? "NORMAL (5-8 slayt)" : "UZUN (9-15 slayt)"
        let prompt = "Sunum konusu: \(title)\nİçerik: ~\(contentLength) karakter → \(size)\n\n\(conversation)"
        let raw = try await GeminiService.shared.generateContent(
            prompt: prompt, systemPrompt: system, maxOutputTokens: 8192,
            responseMimeType: "application/json", timeout: 90, thinking: "low")
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8) else {
            throw NSError(domain: "Pufy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Sunum boş döndü."])
        }
        struct Raw: Decodable {
            var title: String?; var subtitle: String?; var slides: [Slide]?
            var theme: String?; var pattern: String?; var accent: String?
        }
        let decoded = try JSONDecoder().decode(Raw.self, from: data)
        let known: Set<String> = ["cover", "bullets", "compare", "stats", "timeline", "verdict", "section", "quote", "image", "proscons"]
        var slides = (decoded.slides ?? []).filter { known.contains($0.kind) && isUsable($0) }
        let deckTitle = decoded.title?.isEmpty == false ? decoded.title! : title
        if slides.first?.kind != "cover" {
            slides.insert(Slide(kind: "cover", title: deckTitle, subtitle: decoded.subtitle), at: 0)
        }
        guard slides.count >= 3 else {
            throw NSError(domain: "Pufy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Sunum çok kısa çıktı."])
        }
        let patterns: Set<String> = ["rings", "dots", "grid", "waves", "diagonal", "blobs", "arcs", "none"]
        let theme = decoded.theme.map { $0.lowercased() }.flatMap { SlideTheme.names.contains($0) ? $0 : nil }
        let pattern = decoded.pattern.map { $0.lowercased() }.flatMap { patterns.contains($0) ? $0 : nil }
        return SlideDeck(title: deckTitle, subtitle: decoded.subtitle, slides: Array(slides.prefix(15)), status: .ready,
                         theme: theme ?? SlideTheme.names[deckTitle.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % SlideTheme.names.count],
                         pattern: pattern ?? "rings", accent: decoded.accent)
    }

    private static func isUsable(_ s: Slide) -> Bool {
        switch s.kind {
        case "cover": return s.title != nil
        case "bullets": return !(s.bullets ?? []).isEmpty
        case "compare": return (s.columns?.count ?? 0) >= 2 && !(s.rows ?? []).isEmpty
        case "stats", "timeline": return !(s.items ?? []).isEmpty
        case "verdict": return s.text != nil || !(s.bullets ?? []).isEmpty
        case "section": return s.title != nil
        case "quote": return s.text != nil || s.title != nil
        case "image": return s.image != nil || s.text != nil
        case "proscons": return !(s.pros ?? s.bullets ?? []).isEmpty
        default: return false
        }
    }
}

// MARK: - Görseller (slayt ve karşılaştırma kartı)

@MainActor
final class TopicImageCache {
    static let shared = TopicImageCache()
    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []

    func cached(_ topic: String) -> UIImage? { images[topic] }

    func load(_ topic: String) async -> UIImage? {
        if let hit = images[topic] { return hit }
        if missing.contains(topic) { return nil }
        for url in await WikiImageLoader.shared.imageURLs(for: topic) {
            var request = URLRequest(url: url)
            request.setValue("PufyAgent/1.1 (iOS)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) {
                let scaled = image.pufyScaled(maxSide: 1200)
                images[topic] = scaled
                return scaled
            }
        }
        missing.insert(topic)
        return nil
    }

    func loadAll(_ topics: [String]) async -> [String: UIImage] {
        var result: [String: UIImage] = [:]
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for topic in Set(topics) { group.addTask { (topic, await self.load(topic)) } }
            for await (topic, image) in group { if let image { result[topic] = image } }
        }
        return result
    }
}

/// Wikipedia'daki ürün görselleri çoğunlukla arka planı şeffaf "kesik" PNG (ör. iPhone): bunlar kırpılarak doldurulursa
/// telefonun simsiyah bir köşesi görünüyor. Kesikler sığdırılır, fotoğraflar doldurulur.
@MainActor
enum CutoutCheck {
    private static var cache: [ObjectIdentifier: Bool] = [:]

    static func isCutout(_ image: UIImage) -> Bool {
        let key = ObjectIdentifier(image)
        if let hit = cache[key] { return hit }
        let value = transparentCorner(image)
        cache[key] = value
        return value
    }

    private static func transparentCorner(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        // Sol üst piksel 1×1'lik tuvale düşsün
        context.draw(cg, in: CGRect(x: 0, y: -CGFloat(cg.height - 1), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return pixel[3] < 24
    }
}

// MARK: - Ortam: sohbete mesaj gönderme, sunumu yeniden deneme

private struct ChatActionKey: EnvironmentKey { static let defaultValue: ((String) -> Void)? = nil }
private struct DeckRetryKey: EnvironmentKey { static let defaultValue: ((UUID) -> Void)? = nil }

extension EnvironmentValues {
    /// Eylem butonu / test sonucu → mesaj olarak gönder
    var pufyChatAction: ((String) -> Void)? {
        get { self[ChatActionKey.self] }
        set { self[ChatActionKey.self] = newValue }
    }
    var pufyDeckRetry: ((UUID) -> Void)? {
        get { self[DeckRetryKey.self] }
        set { self[DeckRetryKey.self] = newValue }
    }
}

// MARK: - Slayt teması
//
// Kullanıcı (15 Ekim 2026): "Sunumlar şablon gibi; hep siyah beyaz. Sadelik ön planda ama renk de kullanabilsin, arka planı
// sunuma göre değişsin, desenler değişsin; her seferinde 5 sayfa yapıyor gibi, gerekirse 3 gerekirse 15 yapsın."
// Model konuya göre tema + desen seçer (futbol → kırmızı/lacivert, uzay → gece mavisi, yemek → gün batımı…).
// Temalar sade ve elle seçilmiş; marka/takım rengi için "accent" verilebilir (mor/pembe tonları ve okunmayan açık renkler elenir).

struct SlideTheme {
    let bg: Color
    let surface: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let onAccent: Color
    let hero: Color
    let heroInk: Color
    let heroAccent: Color

    /// (zemin, kutu, yazı, vurgu, kapak zemini, kapak yazısı)
    private static let palettes: [String: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)] = [
        "mono":     (0xF2F2F4, 0xFFFFFF, 0x111111, 0x111111, 0x111111, 0xFFFFFF),
        "ocean":    (0xEDF3FA, 0xFFFFFF, 0x0F2238, 0x1F6FD1, 0x0E2A47, 0xFFFFFF),
        "forest":   (0xEEF5EE, 0xFFFFFF, 0x15291A, 0x2E7D4F, 0x173B26, 0xF3F8F1),
        "sunset":   (0xFBF0E7, 0xFFFFFF, 0x2B1A10, 0xE0622A, 0x6E2A12, 0xFFF4EC),
        "sand":     (0xF6EFE2, 0xFFFDF8, 0x2E2618, 0xA87A2C, 0x3A2F1D, 0xF8F1E2),
        "slate":    (0xEDF0F3, 0xFFFFFF, 0x1B2430, 0x3E6385, 0x1B2430, 0xF1F4F7),
        "crimson":  (0xF8EDED, 0xFFFFFF, 0x2A1214, 0xC2272D, 0x5E1216, 0xFFF1F1),
        "teal":     (0xEBF5F4, 0xFFFFFF, 0x0F2A2A, 0x128A82, 0x0D3B39, 0xEFFAF9),
        "gold":     (0xFFF8E3, 0xFFFFFF, 0x1F2A44, 0xD49A00, 0x1F2A44, 0xFFE27A),
        "midnight": (0x111624, 0x1B2233, 0xEEF1F7, 0xF2B53C, 0x070A12, 0xFFFFFF)
    ]

    static let names = ["mono", "ocean", "forest", "sunset", "sand", "slate", "crimson", "teal", "gold", "midnight"]

    static func resolve(_ deck: SlideDeck) -> SlideTheme {
        let key = (deck.theme ?? "").lowercased()
        let p = palettes[key] ?? palettes["mono"]!
        var accent = Color(rgb: p.3)
        var accentHex = p.3
        // Marka/takım rengi (okunabilir ve mor/pembe değilse)
        if let raw = deck.accent, let hex = Self.hex(raw), Self.usable(hex, onDark: key == "midnight") {
            accent = Color(rgb: hex)
            accentHex = hex
        }
        // Kapak/sonuç zemininde vurgu rengi ancak yeterince ayrışıyorsa (lacivert üstünde mavi okunmuyordu)
        let contrast = abs(Self.luminance(accentHex) - Self.luminance(p.4))
        let heroAccent: Color = key != "mono" && contrast > 0.28 ? accent : Color(rgb: p.5).opacity(0.75)
        return SlideTheme(bg: Color(rgb: p.0), surface: Color(rgb: p.1), ink: Color(rgb: p.2),
                          muted: Color(rgb: p.2).opacity(0.6), accent: accent,
                          onAccent: Self.luminance(accentHex) > 0.55 ? Color(rgb: 0x111111) : .white,
                          hero: Color(rgb: p.4), heroInk: Color(rgb: p.5), heroAccent: heroAccent)
    }

    private static func hex(_ s: String) -> UInt32? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard t.count == 6 else { return nil }
        return UInt32(t, radix: 16)
    }

    private static func components(_ v: UInt32) -> (Double, Double, Double) {
        (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    static func luminance(_ v: UInt32) -> Double {
        let (r, g, b) = components(v)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Mor/pembe (kullanıcı sevmiyor) ve zemin üstünde okunmayacak kadar açık renkler elenir
    private static func usable(_ v: UInt32, onDark: Bool) -> Bool {
        let (r, g, b) = components(v)
        let maxC = max(r, g, b), minC = min(r, g, b)
        if maxC - minC > 0.15 {
            var hue: Double
            if maxC == r { hue = (g - b) / (maxC - minC) }
            else if maxC == g { hue = 2 + (b - r) / (maxC - minC) }
            else { hue = 4 + (r - g) / (maxC - minC) }
            hue *= 60
            if hue < 0 { hue += 360 }
            if hue >= 255 && hue <= 345 { return false }
        }
        let lum = luminance(v)
        return onDark ? lum > 0.35 : lum < 0.72
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}

/// Kapak ve bölüm slaytlarının deseni (sunumdan sunuma değişir)
struct SlidePattern: View {
    let kind: String
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            switch kind {
            case "dots":
                let step: CGFloat = 16
                var y: CGFloat = 10
                while y < h {
                    var x: CGFloat = 10
                    while x < w {
                        // Sağ üstten sola alta doğru solar
                        let fade = max(0, 1 - hypot(w - x, y) / (w * 0.95))
                        if fade > 0.02 {
                            let r = 1.2 + 1.6 * fade
                            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                         with: .color(color.opacity(0.10 + 0.35 * fade)))
                        }
                        x += step
                    }
                    y += step
                }
            case "grid":
                var path = Path()
                stride(from: CGFloat(0), through: w, by: 30).forEach { path.move(to: CGPoint(x: $0, y: 0)); path.addLine(to: CGPoint(x: $0, y: h)) }
                stride(from: CGFloat(0), through: h, by: 30).forEach { path.move(to: CGPoint(x: 0, y: $0)); path.addLine(to: CGPoint(x: w, y: $0)) }
                context.stroke(path, with: .color(color.opacity(0.09)), lineWidth: 1)
                context.fill(Path(ellipseIn: CGRect(x: w * 0.55, y: -h * 0.12, width: w * 0.7, height: w * 0.7)),
                             with: .color(color.opacity(0.06)))
            case "waves":
                for i in 0..<7 {
                    var path = Path()
                    let base = h * 0.18 + CGFloat(i) * 15
                    path.move(to: CGPoint(x: 0, y: base))
                    for x in stride(from: CGFloat(0), through: w, by: 6) {
                        path.addLine(to: CGPoint(x: x, y: base + sin(x / 42 + CGFloat(i) * 0.6) * 12))
                    }
                    context.stroke(path, with: .color(color.opacity(0.07 + Double(i) * 0.015)), lineWidth: 1.5)
                }
            case "diagonal":
                var path = Path()
                for offset in stride(from: -h, through: w, by: 22) {
                    path.move(to: CGPoint(x: offset + h * 0.0, y: 0))
                    path.addLine(to: CGPoint(x: offset + h * 0.45, y: h * 0.45))
                }
                context.stroke(path, with: .color(color.opacity(0.08)), lineWidth: 7)
            case "blobs":
                context.addFilter(.blur(radius: 40))
                context.fill(Path(ellipseIn: CGRect(x: w * 0.45, y: -h * 0.15, width: w * 0.8, height: w * 0.8)), with: .color(color.opacity(0.22)))
                context.fill(Path(ellipseIn: CGRect(x: -w * 0.3, y: h * 0.25, width: w * 0.6, height: w * 0.6)), with: .color(color.opacity(0.14)))
            case "arcs":
                for i in 1...6 {
                    let r = CGFloat(i) * 46
                    context.stroke(Path(ellipseIn: CGRect(x: w - r, y: -r, width: r * 2, height: r * 2)),
                                   with: .color(color.opacity(0.13 - Double(i) * 0.012)), lineWidth: 1.5)
                }
            case "none":
                break
            default:   // rings
                let big = w * 0.42, small = w * 0.25
                context.stroke(Path(ellipseIn: CGRect(x: w * 0.92 - big, y: h * 0.17 - big, width: big * 2, height: big * 2)),
                               with: .color(color.opacity(0.08)), lineWidth: 46)
                context.stroke(Path(ellipseIn: CGRect(x: w * 0.08 - small, y: h * 0.88 - small, width: small * 2, height: small * 2)),
                               with: .color(color.opacity(0.05)), lineWidth: 30)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Slayt

struct SlideView: View {
    let slide: Slide
    let index: Int
    let total: Int
    let deckTitle: String
    let images: [String: UIImage]
    var theme: SlideTheme = SlideTheme.resolve(SlideDeck(title: ""))
    var pattern: String = "rings"
    /// PDF'te köşeler düz
    var rounded = true

    static let size = CGSize(width: 360, height: 450)

    private var isHero: Bool { ["cover", "verdict", "section"].contains(slide.kind) }
    private var ink: Color { isHero ? theme.heroInk : theme.ink }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? 30 : 0, style: .continuous))
    }

    // MARK: Zemin

    private var mainImage: UIImage? { slide.image.flatMap { images[$0] } }
    private var imageIsCutout: Bool { mainImage.map(CutoutCheck.isCutout) ?? false }
    /// Fotoğraf tüm slaytı kaplıyor mu? (kapak ve görsel slaytı; kesik ürün görseli kaplamaz)
    private var fullBleedPhoto: Bool {
        (slide.kind == "cover" || slide.kind == "image") && mainImage != nil && !imageIsCutout
    }

    @ViewBuilder
    private var background: some View {
        if fullBleedPhoto, let image = mainImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.3), .black.opacity(0.85)],
                                        startPoint: .top, endPoint: .bottom))
        } else if isHero {
            ZStack {
                theme.hero
                SlidePattern(kind: pattern, color: theme.heroInk)
            }
        } else {
            ZStack(alignment: .topTrailing) {
                theme.bg
                // İçerik slaytlarında desen sadece sağ üst köşede, çok hafif
                SlidePattern(kind: pattern == "none" ? "none" : "dots", color: theme.accent)
                    .frame(width: 150, height: 150)
                    .opacity(0.55)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(fullBleedPhoto ? Color.white : (isHero ? theme.heroAccent : theme.accent))
            Rectangle().frame(width: 18, height: 1.5).opacity(0.5)
            Text("\(total)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .opacity(0.5)
            Spacer()
            if index > 0 {
                Text(deckTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .opacity(0.5)
            }
        }
        .foregroundStyle(fullBleedPhoto ? Color.white : ink)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch slide.kind {
        case "cover": cover
        case "compare": compare
        case "stats": stats
        case "timeline": timeline
        case "verdict": verdict
        case "section": section
        case "quote": quote
        case "image": imageSlide
        case "proscons": prosCons
        default: bullets
        }
    }

    private func title(_ text: String?, size: CGFloat = 25) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text ?? "")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .tracking(-0.3)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .foregroundStyle(ink)
            Capsule().fill(theme.accent).frame(width: 34, height: 4)
        }
        .padding(.bottom, 16)
    }

    // MARK: Türler

    private var cover: some View {
        let color: Color = fullBleedPhoto ? .white : ink
        return VStack(alignment: .leading, spacing: 10) {
            if imageIsCutout, let image = mainImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 170)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                    .background(Circle().fill(theme.heroAccent.opacity(0.18)).frame(width: 190, height: 190).blur(radius: 28))
            }
            Spacer(minLength: 0)
            Text("SUNUM")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(fullBleedPhoto ? Color.white.opacity(0.75) : theme.heroAccent)
            Text(slide.title ?? deckTitle)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .lineLimit(4)
                .minimumScaleFactor(0.5)
            if let subtitle = slide.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(3)
                    .opacity(0.8)
            }
            HStack(spacing: 6) {
                Image("chat_pp").resizable().scaledToFill().frame(width: 18, height: 18).clipShape(Circle())
                Text("Pufy · \(Self.dateText)")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.7)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(color)
    }

    private static var dateText: String {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: Date())
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.heroAccent)
            Text(slide.title ?? "")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            if let subtitle = slide.subtitle ?? slide.text, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(3)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "quote.opening")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(slide.text ?? slide.title ?? "")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .lineLimit(7)
                .minimumScaleFactor(0.55)
                .foregroundStyle(theme.ink)
            if let source = slide.subtitle, !source.isEmpty {
                Text("— \(source)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var imageSlide: some View {
        if fullBleedPhoto {
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                Text(slide.title ?? "")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let caption = slide.text ?? slide.subtitle, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(4)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                title(slide.title)
                if let image = mainImage {
                    Image(uiImage: image).resizable().scaledToFit().padding(12)
                        .frame(maxWidth: .infinity).frame(height: 200)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surface))
                        .padding(.bottom, 12)
                }
                if let caption = slide.text ?? slide.subtitle {
                    Text(caption)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .lineLimit(5)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(slide.title)
            if let image = mainImage {
                Group {
                    if imageIsCutout {
                        Image(uiImage: image).resizable().scaledToFit().padding(10)
                            .frame(maxWidth: .infinity).frame(height: 110)
                            .background(theme.surface)
                    } else {
                        // Panorama görseller slaytı genişletmesin: yerleşime girmeyen katman
                        Color.clear.frame(maxWidth: .infinity).frame(height: 110)
                            .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 14)
            }
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array((slide.bullets ?? []).prefix(5).enumerated()), id: \.offset) { i, text in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(theme.accent))
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        Text(text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var prosCons: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(slide.title, size: 23)
            VStack(alignment: .leading, spacing: 12) {
                listBlock(String(localized: "Artıları"), icon: "plus", items: slide.pros ?? slide.bullets ?? [], strong: true)
                listBlock(String(localized: "Eksileri"), icon: "minus", items: slide.cons ?? [], strong: false)
            }
        }
    }

    private func listBlock(_ label: String, icon: String, items: [String], strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased(with: AppLanguage.currentLocale))
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(strong ? theme.accent : theme.muted)
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(strong ? theme.onAccent : theme.ink)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(strong ? theme.accent : theme.ink.opacity(0.12)))
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(item)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.surface))
    }

    private var compare: some View {
        let columns = Array((slide.columns ?? []).prefix(3))
        let rows = Array((slide.rows ?? []).prefix(7))
        return VStack(alignment: .leading, spacing: 0) {
            title(slide.title, size: 23)
            HStack(spacing: 8) {
                Color.clear.frame(width: 78, height: 1)
                ForEach(Array(columns.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 12, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.bottom, 8)
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 8) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(width: 78, alignment: .leading)
                        ForEach(0..<columns.count, id: \.self) { c in
                            let value = row.values.indices.contains(c) ? row.values[c] : "—"
                            let best = row.better == c
                            HStack(spacing: 3) {
                                Text(value)
                                    .font(.system(size: 12, weight: best ? .bold : .regular))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                if best {
                                    Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(i.isMultiple(of: 2) ? theme.surface.opacity(0.85) : Color.clear))
                }
            }
        }
    }

    private var stats: some View {
        let items = Array((slide.items ?? []).prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            title(slide.title)
            if items.count == 1, let item = items.first {
                Spacer(minLength: 0)
                Text(item.value ?? item.label)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(theme.accent)
                Text(item.value == nil ? (item.text ?? "") : item.label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.muted)
                Spacer(minLength: 0)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.value ?? "—")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.45)
                                .foregroundStyle(i == 0 ? theme.onAccent : theme.accent)
                            Text(item.label)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(3)
                                .foregroundStyle(i == 0 ? theme.onAccent.opacity(0.8) : theme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(i == 0 ? theme.accent : theme.surface))
                    }
                }
            }
        }
    }

    private var timeline: some View {
        let items = Array((slide.items ?? []).prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            title(slide.title)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle().fill(theme.accent).frame(width: 11, height: 11).padding(.top, 3)
                            if i < items.count - 1 {
                                Rectangle().fill(theme.accent.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.ink)
                            Text(item.text ?? item.value ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.muted)
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.bottom, 14)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((slide.title ?? String(localized: "Sonuç")).uppercased(with: AppLanguage.currentLocale))
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(theme.heroAccent)
            Image(systemName: "quote.opening")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(theme.heroAccent.opacity(0.7))
            if let text = slide.text {
                Text(text)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(6)
                    .minimumScaleFactor(0.6)
            }
            ForEach(Array((slide.bullets ?? []).prefix(4).enumerated()), id: \.offset) { _, b in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.heroAccent)
                    Text(b).font(.system(size: 14, weight: .medium)).lineLimit(2).minimumScaleFactor(0.8)
                }
                .opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
    }
}

// MARK: - Tam ekran sunum

final class SlideDeckPresenter: ObservableObject {
    static let shared = SlideDeckPresenter()
    struct Presented: Identifiable {
        let id = UUID()
        let deck: SlideDeck
    }
    @Published var presented: Presented?
}

struct SlideDeckViewer: View {
    let deck: SlideDeck
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var images: [String: UIImage] = [:]
    @State private var shareFile: ShareFile?
    @State private var exporting = false
    private var theme: SlideTheme { SlideTheme.resolve(deck) }

    struct ShareFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        GeometryReader { geo in
            let scale = max(0.5, min((geo.size.width - 36) / SlideView.size.width,
                                     (geo.size.height - 150) / SlideView.size.height))
            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    ForEach(Array(deck.slides.enumerated()), id: \.offset) { index, slide in
                        SlideView(slide: slide, index: index, total: deck.slides.count, deckTitle: deck.title, images: images,
                                  theme: theme, pattern: deck.pattern ?? "rings")
                            .scaleEffect(scale)
                            .frame(width: SlideView.size.width * scale, height: SlideView.size.height * scale)
                            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                pageDots
                    .padding(.bottom, 14)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task {
            let topics = deck.slides.compactMap(\.image)
            images = topics.reduce(into: [:]) { result, topic in
                if let hit = TopicImageCache.shared.cached(topic) { result[topic] = hit }
            }
            let loaded = await TopicImageCache.shared.loadAll(topics)
            withAnimation(SmoothSpring.fade) { images.merge(loaded) { a, _ in a } }
        }
        .onChange(of: page) { _ in PremiumHaptics.light() }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url]).ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .pufyGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(deck.slides.count) slayt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { exportPDF() } label: {
                Group {
                    if exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .pufyGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(exporting)
            .accessibilityLabel(String(localized: "PDF olarak paylaş"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<deck.slides.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.pufyPrimary : Color.pufyPrimary.opacity(0.2))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .onTapGesture { withAnimation(SmoothSpring.standard) { page = i } }
            }
        }
        .animation(SmoothSpring.quick, value: page)
    }

    @MainActor
    private func exportPDF() {
        exporting = true
        Task { @MainActor in
            let loaded = await TopicImageCache.shared.loadAll(deck.slides.compactMap(\.image))
            images.merge(loaded) { a, _ in a }
            if let url = Self.renderPDF(deck: deck, images: images) { shareFile = ShareFile(url: url) }
            exporting = false
        }
    }

    @MainActor
    static func renderPDF(deck: SlideDeck, images: [String: UIImage]) -> URL? {
        let safe = deck.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.prefix(60)).pdf")
        var box = CGRect(origin: .zero, size: SlideView.size)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for (index, slide) in deck.slides.enumerated() {
            let renderer = ImageRenderer(content:
                SlideView(slide: slide, index: index, total: deck.slides.count, deckTitle: deck.title,
                          images: images, theme: SlideTheme.resolve(deck), pattern: deck.pattern ?? "rings", rounded: false)
                    .environment(\.colorScheme, .light))
            renderer.render { size, draw in
                var page = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &page)
                draw(context)
                context.endPage()
            }
        }
        context.closePDF()
        return url
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Sohbetteki sunum kartı

struct SlideDeckCard: View {
    let deck: SlideDeck
    let messageID: UUID
    let createdAt: Date
    @Environment(\.pufyDeckRetry) private var retry
    @State private var coverImage: UIImage?

    /// Uygulama kapanınca yarım kalan hazırlık takılı görünmesin
    private var isStale: Bool {
        deck.status == .generating && Date().timeIntervalSince(deck.startedAt ?? createdAt) > 180
    }

    var body: some View {
        Group {
            if deck.status == .ready, !deck.slides.isEmpty {
                ready
            } else if deck.status == .failed || isStale {
                failed
            } else {
                generating
            }
        }
        .animation(SmoothSpring.standard, value: deck.status)
    }

    private var generating: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.pufySoft)
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .pulseSymbol()
            }
            .frame(width: 64, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                ShimmerText(text: String(localized: "Sunum hazırlanıyor…"), font: .subheadline.weight(.semibold))
                Text(deck.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        .transition(.opacity)
    }

    private var failed: some View {
        Button {
            PremiumHaptics.light()
            retry?(messageID)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.pufySoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Sunum hazırlanamadı"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Tekrar denemek için dokun"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        }
        .buttonStyle(PremiumCardButtonStyle())
    }

    private var ready: some View {
        Button {
            PremiumHaptics.medium()
            SlideDeckPresenter.shared.presented = .init(deck: deck)
        } label: {
            HStack(spacing: 14) {
                let thumbScale: CGFloat = 0.24
                SlideView(slide: deck.slides[0], index: 0, total: deck.slides.count, deckTitle: deck.title,
                          images: coverImage.flatMap { img in deck.slides[0].image.map { [$0: img] } } ?? [:],
                          theme: SlideTheme.resolve(deck), pattern: deck.pattern ?? "rings")
                    .scaleEffect(thumbScale)
                    .frame(width: SlideView.size.width * thumbScale, height: SlideView.size.height * thumbScale)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguage.isEnglish ? "PRESENTATION" : "SUNUM")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    Text(deck.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text("\(deck.slides.count) " + (AppLanguage.isEnglish ? "slides" : "slayt"))
                        Text("·")
                        Text(String(localized: "Aç"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(PremiumCardButtonStyle())
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .task(id: deck.slides.first?.image) {
            guard let topic = deck.slides.first?.image else { return }
            coverImage = TopicImageCache.shared.cached(topic)
            if coverImage == nil { coverImage = await TopicImageCache.shared.load(topic) }
        }
    }
}

private extension View {
    @ViewBuilder
    func pulseSymbol() -> some View {
        if #available(iOS 17, *) {
            self.symbolEffect(.pulse)
        } else {
            self
        }
    }
}

// MARK: - Karşılaştırma kartı

struct CompareCard: View {
    let data: CompareData
    @State private var images: [String: UIImage] = [:]

    private var items: [CompareData.Item] { Array(data.items.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = data.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 8) {
                        thumbnail(item, index: index)
                        Text(item.name)
                            .font(.footnote.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(data.rows.prefix(10).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(0..<items.count, id: \.self) { c in
                                let best = row.better == c
                                HStack(spacing: 4) {
                                    Text(row.values.indices.contains(c) ? row.values[c] : "—")
                                        .font(.subheadline.weight(best ? .bold : .regular))
                                        .multilineTextAlignment(.center)
                                    if best {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 11))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(best ? Color.pufyPrimary.opacity(0.08) : Color.clear))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    if i < min(data.rows.count, 10) - 1 {
                        Divider().opacity(0.6)
                    }
                }
            }

            if let verdict = data.verdict, !verdict.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verdict)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.pufyOnPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.pufyPrimary))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .task(id: items.map(\.name).joined()) {
            let topics = items.compactMap(\.wiki).filter { !$0.isEmpty }
            guard !topics.isEmpty else { return }
            let loaded = await TopicImageCache.shared.loadAll(topics)
            withAnimation(SmoothSpring.fade) { images = loaded }
        }
    }

    @ViewBuilder
    private func thumbnail(_ item: CompareData.Item, index: Int) -> some View {
        if let wiki = item.wiki, let image = images[wiki] {
            Group {
                if CutoutCheck.isCutout(image) {
                    Image(uiImage: image).resizable().scaledToFit().padding(6)
                        .frame(width: 72, height: 72)
                        .background(Color(UIColor.systemBackground))
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 72, height: 72)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.opacity)
        } else {
            Text(String(item.name.prefix(1)).uppercased())
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(index == 0 ? Color.pufyOnPrimary : Color.pufyPrimary)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(index == 0 ? Color.pufyPrimary : Color(UIColor.systemBackground)))
        }
    }
}

// MARK: - Test

/// Kaydırınca satır yeniden oluşsa da testin ilerleyişi kaybolmasın (oturum boyunca)
@MainActor
final class QuizProgressStore: ObservableObject {
    static let shared = QuizProgressStore()
    @Published var picks: [UUID: [Int: Int]] = [:]
    @Published var current: [UUID: Int] = [:]
}

struct QuizCard: View {
    let quiz: QuizData
    let messageID: UUID
    @ObservedObject private var progress = QuizProgressStore.shared
    @Environment(\.pufyChatAction) private var sendToChat

    private var picks: [Int: Int] { progress.picks[messageID] ?? [:] }
    private var index: Int { progress.current[messageID] ?? 0 }
    private var finished: Bool { index >= quiz.questions.count }
    private var score: Int { quiz.questions.indices.filter { picks[$0] == quiz.questions[$0].answer }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(quiz.title?.isEmpty == false ? quiz.title! : "Test", systemImage: "checklist")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(finished ? "Bitti" : "\(index + 1)/\(quiz.questions.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.pufyPrimary)
                        .frame(width: geo.size.width * CGFloat(min(index, quiz.questions.count)) / CGFloat(max(quiz.questions.count, 1)))
                }
            }
            .frame(height: 5)

            if finished {
                result
            } else {
                question(quiz.questions[index], number: index)
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .clipped()
        .animation(SmoothSpring.standard, value: index)
        .animation(SmoothSpring.quick, value: picks)
    }

    private func question(_ q: QuizData.Question, number: Int) -> some View {
        let picked = picks[number]
        return VStack(alignment: .leading, spacing: 10) {
            Text(q.q)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                optionButton(option, letter: i, question: q, number: number, picked: picked)
            }
            if let picked {
                let correct = picked == q.answer
                VStack(alignment: .leading, spacing: 6) {
                    Text(correct ? String(localized: "Doğru!") : (AppLanguage.isEnglish ? "Correct: \(q.options[q.answer])" : "Doğrusu: \(q.options[q.answer])"))
                        .font(.subheadline.weight(.bold))
                    if let explain = q.explain, !explain.isEmpty {
                        Text(explain)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                Button {
                    PremiumHaptics.light()
                    progress.current[messageID] = number + 1
                } label: {
                    Text(number + 1 < quiz.questions.count ? String(localized: "Sonraki soru") : String(localized: "Sonucu gör"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.pufyPrimary))
                }
                .buttonStyle(PremiumScaleButtonStyle())
                .padding(.top, 2)
            }
        }
    }

    private func optionButton(_ option: String, letter: Int, question q: QuizData.Question, number: Int, picked: Int?) -> some View {
        let answered = picked != nil
        let isCorrect = letter == q.answer
        let isPicked = picked == letter
        let highlight = answered && isCorrect
        let wrong = answered && isPicked && !isCorrect
        return Button {
            guard !answered else { return }
            var current = picks
            current[number] = letter
            progress.picks[messageID] = current
            if isCorrect { PremiumHaptics.success() } else { PremiumHaptics.error() }
        } label: {
            HStack(spacing: 12) {
                Text(String(UnicodeScalar(65 + letter).map(Character.init) ?? "?"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(highlight ? Color.pufyOnPrimary.opacity(0.18) : Color.pufySoft))
                Text(option)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(wrong)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if highlight {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                } else if wrong {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(highlight ? Color.pufyOnPrimary : (wrong ? Color.secondary : Color.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlight ? Color.pufyPrimary : Color(UIColor.systemBackground)))
            .opacity(answered && !highlight && !isPicked ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PremiumScaleButtonStyle())
        .disabled(answered)
    }

    private var result: some View {
        let total = quiz.questions.count
        let ratio = Double(score) / Double(max(total, 1))
        let message = ratio == 1 ? String(localized: "Kusursuz!") : ratio >= 0.7 ? String(localized: "Çok iyi!") : ratio >= 0.4 ? String(localized: "Fena değil.") : String(localized: "Biraz daha çalışalım.")
        let wrongs = quiz.questions.indices.filter { picks[$0] != quiz.questions[$0].answer }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(score)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                Text("/ \(total)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(message)
                    .font(.headline)
            }
            HStack(spacing: 10) {
                Button {
                    PremiumHaptics.light()
                    progress.picks[messageID] = [:]
                    progress.current[messageID] = 0
                } label: {
                    Label(String(localized: "Tekrar çöz"), systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color(UIColor.systemBackground)))
                }
                .buttonStyle(PremiumScaleButtonStyle())
                if !wrongs.isEmpty, let sendToChat {
                    Button {
                        PremiumHaptics.light()
                        let list = wrongs.map { "\"\(quiz.questions[$0].q)\"" }.joined(separator: ", ")
                        let prompt = AppLanguage.isEnglish
                            ? "I answered these questions incorrectly in the test: \(list). Can you briefly explain the correct answers?"
                            : "Testte şu soruları yanlış yaptım: \(list). Doğrularını kısaca anlatır mısın?"
                        sendToChat(prompt)
                    } label: {
                        Label(String(localized: "Yanlışlarımı anlat"), systemImage: "lightbulb")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.pufyOnPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Color.pufyPrimary))
                    }
                    .buttonStyle(PremiumScaleButtonStyle())
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Eylem butonları

struct ActionChips: View {
    let actions: [String]
    @Environment(\.pufyChatAction) private var sendToChat

    var body: some View {
        if let sendToChat {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        Button {
                            PremiumHaptics.light()
                            sendToChat(action)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: Self.icon(for: action))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(action)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color(UIColor.secondarySystemBackground)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(PremiumScaleButtonStyle())
                    }
                }
            }
            .scrollClipDisabledIfAvailable()
        }
    }

    static func icon(for action: String) -> String {
        let a = action.lowercased(with: Locale(identifier: "tr_TR"))
        if a.contains("sunum") || a.contains("slayt") { return "rectangle.on.rectangle.angled" }
        if a.contains("test") || a.contains("quiz") || a.contains("soru sor") || a.contains("sına") { return "checklist" }
        if a.contains("liste") || a.contains("not") { return "note.text.badge.plus" }
        if a.contains("hatırlat") || a.contains("haber ver") { return "bell" }
        if a.contains("karşılaştır") { return "square.split.2x1" }
        if a.contains("tarif") { return "fork.knife" }
        if a.contains("rota") || a.contains("yol") || a.contains("harita") { return "map" }
        if a.contains("görsel") || a.contains("çiz") { return "photo" }
        if a.contains("uygulama") || a.contains("oyun") { return "app.badge" }
        return "arrow.up.right"
    }
}

private extension View {
    @ViewBuilder
    func scrollClipDisabledIfAvailable() -> some View {
        if #available(iOS 17, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
}
