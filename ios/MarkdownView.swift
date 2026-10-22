import SwiftUI
import UIKit

// MARK: - Markdown Blokları
// Eski yöntem başlıkları/listeleri silip sadece **kalın** gösteriyordu; kod blokları ve tablolar
// ham ``` ve | karakterleriyle görünüyordu. ChatGPT/Gemini'deki gibi blok bazlı çizim.

struct MarkdownListItem {
    let indent: Int
    let marker: String
    let text: AttributedString
}

enum MarkdownBlock {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case list([MarkdownListItem])
    case quote(AttributedString)
    case code(language: String, code: String)
    case table(header: [AttributedString], rows: [[AttributedString]])
    case rule
    /// [IMG: konu | açıklama] — akış içi görsel
    case image(topic: String, caption: String?)
    /// [IMGS: konu = açıklama | konu = açıklama …] — her öğenin kendi görseli (ör. elma çeşitleri yan yana)
    case gallery([(topic: String, caption: String?)])
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ``` kod bloğu (akış sırasında kapanış henüz gelmemiş olabilir → sona kadar al)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(language: language, code: code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Görsel galerisi: [IMGS: Red Delicious = Kırmızı | Granny Smith = Yeşil]
            if trimmed.uppercased().hasPrefix("[IMGS") {
                flushParagraph()
                if trimmed.hasSuffix("]"), let colon = trimmed.firstIndex(of: ":") {
                    let inner = trimmed[trimmed.index(after: colon)..<trimmed.index(before: trimmed.endIndex)]
                    let items: [(topic: String, caption: String?)] = inner.split(separator: "|").compactMap { raw in
                        let parts = raw.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        guard let topic = parts.first, !topic.isEmpty else { return nil }
                        return (topic, parts.count > 1 ? parts[1] : nil)
                    }
                    if !items.isEmpty { blocks.append(.gallery(Array(items.prefix(6)))) }
                }
                i += 1
                continue
            }

            // Akış içi görsel: [IMG: konu | açıklama]
            if trimmed.uppercased().hasPrefix("[IMG") {
                flushParagraph()
                if trimmed.hasSuffix("]"), let colon = trimmed.firstIndex(of: ":") {
                    let inner = trimmed[trimmed.index(after: colon)..<trimmed.index(before: trimmed.endIndex)]
                    let parts = inner.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if let topic = parts.first, !topic.isEmpty {
                        blocks.append(.image(topic: topic, caption: parts.count > 1 ? parts[1] : nil))
                    }
                }
                // Kapanmamışsa (akış sürüyor) hiç gösterme
                i += 1
                continue
            }

            // Başlık
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(level)
                if level <= 6, rest.first == " " {
                    flushParagraph()
                    blocks.append(.heading(level: level, text: inline(rest.trimmingCharacters(in: .whitespaces))))
                    i += 1
                    continue
                }
            }

            // Yatay çizgi
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            // Tablo: | a | b |  +  |---|---|
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let header = tableCells(trimmed).map(inline)
                var rows: [[AttributedString]] = []
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") else { break }
                    var cells = tableCells(row).map(inline)
                    if cells.count < header.count {
                        cells += Array(repeating: AttributedString(""), count: header.count - cells.count)
                    }
                    rows.append(Array(cells.prefix(header.count)))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Liste (madde veya numaralı)
            if listMarker(for: line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while i < lines.count, let item = listMarker(for: lines[i]) {
                    items.append(MarkdownListItem(indent: item.0, marker: item.1, text: inline(item.2)))
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }

            // Alıntı
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    quoted.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(inline(quoted.joined(separator: "\n"))))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    /// **kalın**, *italik*, `kod`, [link](url)
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func listMarker(for line: String) -> (Int, String, String)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = min(leading / 2, 3)
        let body = line.dropFirst(leading)
        if let first = body.first, "-*•+".contains(first), body.dropFirst().first == " " {
            return (indent, indent == 0 ? "•" : "◦", String(body.dropFirst(2)))
        }
        let digits = body.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 3 {
            let after = body.dropFirst(digits.count)
            if let sep = after.first, sep == "." || sep == ")", after.dropFirst().first == " " {
                return (indent, "\(digits).", String(after.dropFirst(2)))
            }
        }
        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.hasPrefix("-") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func tableCells(_ row: String) -> [String] {
        var t = row
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Aynı metin her çizimde yeniden ayrıştırılmasın
final class MarkdownCache {
    static let shared = MarkdownCache()
    private final class Box { let blocks: [MarkdownBlock]; init(_ b: [MarkdownBlock]) { blocks = b } }
    private let cache = NSCache<NSString, Box>()

    private init() { cache.countLimit = 300 }

    func blocks(for text: String) -> [MarkdownBlock] {
        let key = text as NSString
        if let hit = cache.object(forKey: key) { return hit.blocks }
        let parsed = MarkdownParser.parse(text)
        cache.setObject(Box(parsed), forKey: key)
        return parsed
    }
}

// MARK: - Görünüm

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let blocks = MarkdownCache.shared.blocks(for: text)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            SelectableText(text: text)

        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? .title3.weight(.bold) : (level == 2 ? .headline : .subheadline.weight(.semibold)))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

        case .list(let items):
            if items.count >= 2 {
                ListCard(items: items)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker).font(.body.weight(.semibold))
                        Text(item.text).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .quote(let text):
            CalloutBox(text: text)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .rule:
            Divider().padding(.vertical, 4)

        case .image(let topic, let caption):
            InlineTopicImage(topic: topic, caption: caption)

        case .gallery(let items):
            TopicGallery(items: items)
        }
    }
}

/// Madde/numaralı listeler: ChatGPT'deki gibi ayrı bir kutu, numaralar rozet içinde
private struct ListCard: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    marker(item)
                    SelectableText(text: item.text, lineSpacing: 3)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(item.indent) * 22)
                .padding(.vertical, 10)
                if index < items.count - 1 && items[index + 1].indent == 0 {
                    Divider().padding(.leading, 34)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
    }

    @ViewBuilder
    private func marker(_ item: MarkdownListItem) -> some View {
        if item.marker.hasSuffix(".") {
            Text(String(item.marker.dropLast()))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.pufyOnPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.pufyPrimary))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        } else {
            Circle()
                .fill(item.indent == 0 ? Color.primary.opacity(0.75) : Color.secondary)
                .frame(width: 6, height: 6)
                .frame(width: 22)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
    }
}

/// "> **İpucu:** …" / "> **Dikkat:** …" → ikonlu vurgu kutusu
private struct CalloutBox: View {
    let text: AttributedString

    private var plain: String { String(text.characters).lowercased(with: Locale(identifier: "tr_TR")) }

    private var icon: String {
        if plain.hasPrefix("dikkat") || plain.hasPrefix("uyarı") || plain.hasPrefix("önemli") { return "exclamationmark.triangle.fill" }
        if plain.hasPrefix("ipucu") || plain.hasPrefix("öneri") { return "lightbulb.fill" }
        return "info.circle.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(icon == "exclamationmark.triangle.fill" ? Color.orange : Color.primary)
                .padding(.top, 2)
            SelectableText(text: text, style: .callout, lineSpacing: 3)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.pufySoft))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "kod" : language.lowercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    PremiumHaptics.light()
                    withAnimation(SmoothSpring.quick) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(SmoothSpring.quick) { copied = false }
                    }
                } label: {
                    Label(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.pufyPrimary : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().opacity(0.6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }
}

struct MarkdownTableView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]

    /// 5+ sütunda daha küçük yazı ve dar boşluk (puan durumu gibi tablolar telefona sığsın)
    private var compact: Bool { header.count >= 5 }

    // ESKİ HATA (22 Ekim 2026): tablo her zaman yatay kaydırılan, sütun başına en az 70pt'lik bir ızgaraydı; puan durumu
    // gibi tablolar ekrana hiç sığmıyor, sağa kaydırmak gerekiyordu. Artık önce ekran genişliğine sığdırılır (uzun hücreler
    // alt satıra iner, kısa sayı sütunları dar kalır); en dar hali bile sığmıyorsa yatay kaydırmaya düşülür.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            table
            ScrollView(.horizontal, showsIndicators: false) { table }
        }
    }

    private var table: some View {
        FitTableLayout(columns: header.count) {
            ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                cellView(cell, bold: true, background: Color.pufySoft)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                ForEach(0..<header.count, id: \.self) { col in
                    cellView(col < row.count ? row[col] : AttributedString(""), bold: false,
                             background: index % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    private func cellView(_ text: AttributedString, bold: Bool, background: Color) -> some View {
        Text(text)
            .font(compact ? (bold ? .footnote.weight(.semibold) : .footnote) : (bold ? .subheadline.weight(.semibold) : .subheadline))
            .padding(.horizontal, compact ? 7 : 12)
            .padding(.vertical, compact ? 7 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
    }
}

/// Tabloyu verilen genişliğe sığdıran düzen: her sütun önce doğal genişliğini ister; toplam sığmazsa uzun sütunlar
/// (en uzun kelimesinin genişliğine kadar) daraltılır ve metin alt satıra iner. Satır yüksekliği o satırın en uzun hücresidir.
/// En dar hali de sığmıyorsa gereken genişliği bildirir → ViewThatFits yatay kaydırmalı sürüme geçer.
struct FitTableLayout: Layout {
    let columns: Int

    struct Cache { var widths: [CGFloat] = []; var heights: [CGFloat] = []; var key: CGFloat = -1 }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func compute(_ proposal: ProposedViewSize, _ subviews: Subviews, _ cache: inout Cache) {
        let available = proposal.width ?? .infinity
        if cache.key == available, !cache.widths.isEmpty { return }
        let n = max(columns, 1)
        var ideal = [CGFloat](repeating: 0, count: n)
        var minimum = [CGFloat](repeating: 0, count: n)
        for (i, view) in subviews.enumerated() {
            let c = i % n
            ideal[c] = max(ideal[c], view.sizeThatFits(.unspecified).width)
        }
        // En dar hal: sütun kendi içeriğinden geniş olmaz, ama 64pt'den dar da olmaz (metin harf harf bölünmesin)
        for c in 0..<n { minimum[c] = min(ideal[c], 64) }
        // Genişlik verilmeden sorulursa (ViewThatFits'in "sığar mı" ölçümü, yatay kaydırma) en dar hali bildirilir:
        // böylece daraltılınca sığan tablolar kaydırmaya düşmez.
        var widths = available.isFinite ? ideal : minimum
        let idealSum = ideal.reduce(0, +)
        if available.isFinite {
            if idealSum <= available {
                // Boşluğu en geniş sütuna ver (genelde isim/takım sütunu)
                if let widest = ideal.indices.max(by: { ideal[$0] < ideal[$1] }) { widths[widest] += available - idealSum }
            } else {
                let minSum = minimum.reduce(0, +)
                if minSum >= available {
                    widths = minimum
                } else {
                    let flex = zip(ideal, minimum).map { $0 - $1 }
                    let flexSum = max(flex.reduce(0, +), 1)
                    let room = available - minSum
                    widths = zip(minimum, flex).map { $0 + room * $1 / flexSum }
                }
            }
        }
        let rowCount = (subviews.count + n - 1) / n
        var heights = [CGFloat](repeating: 0, count: rowCount)
        for (i, view) in subviews.enumerated() {
            let h = view.sizeThatFits(ProposedViewSize(width: widths[i % n], height: nil)).height
            heights[i / n] = max(heights[i / n], h)
        }
        cache = Cache(widths: widths, heights: heights, key: available)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        compute(proposal, subviews, &cache)
        return CGSize(width: cache.widths.reduce(0, +), height: cache.heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        compute(ProposedViewSize(width: bounds.width, height: nil), subviews, &cache)
        let n = max(columns, 1)
        var y = bounds.minY
        for row in 0..<cache.heights.count {
            var x = bounds.minX
            for c in 0..<n {
                let i = row * n + c
                guard i < subviews.count else { break }
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: cache.widths[c], height: cache.heights[row]))
                x += cache.widths[c]
            }
            y += cache.heights[row]
        }
    }
}

// MARK: - Seçilebilir metin
//
// SwiftUI Text'in .textSelection'ı iOS'ta sadece bloğun TAMAMINI kopyalatır; kelime seçilemez.
// Eskiden uzun basınca tüm mesajı küçülten bir önizleme + "Kopyala" menüsü açılıyordu.
// Bu görünüm Notlar/Safari gibi: uzun bas → kelime seçilir, tutamaçlarla genişletilir, Kopyala.

struct SelectableText: UIViewRepresentable {
    let text: AttributedString
    var style: UIFont.TextStyle = .body
    var color: UIColor = .label
    var lineSpacing: CGFloat = 4
    /// true: kısa metinde sadece gerektiği kadar genişler (mesaj balonu)
    var hugs = false

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [.foregroundColor: UIColor.label,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let attributed = Self.convert(text, style: style, color: color, lineSpacing: lineSpacing)
        if !(view.attributedText?.isEqual(to: attributed) ?? false) {
            view.attributedText = attributed
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        var usedWidth = width
        if hugs, let attributed = uiView.attributedText {
            let rect = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            usedWidth = min(width, ceil(rect.width) + 1)
        }
        let fitted = uiView.sizeThatFits(CGSize(width: usedWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: usedWidth, height: ceil(fitted.height))
    }

    /// Markdown (kalın, italik, kod, link) → UIKit metin özellikleri
    static func convert(_ text: AttributedString, style: UIFont.TextStyle, color: UIColor, lineSpacing: CGFloat) -> NSAttributedString {
        let base = UIFont.preferredFont(forTextStyle: style)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let result = NSMutableAttributedString()
        for run in text.runs {
            let piece = String(text[run.range].characters)
            var font = base
            if let intent = run.inlinePresentationIntent {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if intent.contains(.code) {
                    font = UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular)
                } else if !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                    font = UIFont(descriptor: descriptor, size: base.pointSize)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if let link = run.link { attributes[.link] = link }
            if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
    }
}
