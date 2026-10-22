import SwiftUI

// MARK: - Sohbet İçi Widget Kartları
//
// Kullanıcı isteği (13 Ekim 2026): "GS maçını sordum; sohbette iki takımın logosu, saati çıksa, canlıysa skoru verse.
// Sadece maç değil, logosu olan şeylerde de."
// Yapay zeka cevabın başına [WIDGET: {json}] yazar; uygulama bunu bir bakışta okunan bir karta çevirir.
//  • match  → iki takımın arması, başlama saati + geri sayım ya da canlı skor/dakika, maç sonu
//  • entity → logolu kurum/ürün kartı (şirket, hisse, kripto, uygulama, marka) + birkaç güncel değer
// Logolar: İngilizce Wikipedia sayfasının görseli (armalar/logolar), olmazsa resmi sitenin simgesi.
// Kartlar kalıcı bir ana ekran widget'ı değil; sohbetin içinde durur. Canlı maçta ve fiyatlarda "yenile" ile güncellenir.

struct ChatWidget: Codable, Hashable {
    struct Side: Codable, Hashable {
        var name: String
        var short: String? = nil
        var wiki: String? = nil
        var domain: String? = nil
    }

    struct Fact: Codable, Hashable {
        var label: String
        var value: String
        var trend: String? = nil   // up | down | flat
    }

    var type: String
    // Maç
    var league: String? = nil
    var home: Side? = nil
    var away: Side? = nil
    var kickoff: String? = nil
    var status: String? = nil
    var minute: String? = nil
    var homeScore: Int? = nil
    var awayScore: Int? = nil
    var venue: String? = nil
    // Kurum / ürün
    var name: String? = nil
    var subtitle: String? = nil
    var wiki: String? = nil
    var domain: String? = nil
    var facts: [Fact]? = nil
    /// Uygulamanın son yenilediği an
    var updatedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case type, league, home, away, kickoff, status, minute, homeScore, awayScore, venue
        case name, subtitle, wiki, domain, facts, updatedAt
    }

    init(type: String) { self.type = type }

    /// Modelden gelen JSON'a hoşgörülü: skor "2" ya da 2, dakika 67 ya da "67'" olabilir
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type))?.lowercased() ?? "entity"
        league = try? c.decode(String.self, forKey: .league)
        home = try? c.decode(Side.self, forKey: .home)
        away = try? c.decode(Side.self, forKey: .away)
        kickoff = try? c.decode(String.self, forKey: .kickoff)
        status = (try? c.decode(String.self, forKey: .status))?.lowercased()
        if let m = try? c.decode(String.self, forKey: .minute) { minute = m }
        else if let m = try? c.decode(Int.self, forKey: .minute) { minute = String(m) }
        homeScore = Self.flexibleInt(c, .homeScore)
        awayScore = Self.flexibleInt(c, .awayScore)
        venue = try? c.decode(String.self, forKey: .venue)
        name = try? c.decode(String.self, forKey: .name)
        subtitle = try? c.decode(String.self, forKey: .subtitle)
        wiki = try? c.decode(String.self, forKey: .wiki)
        domain = try? c.decode(String.self, forKey: .domain)
        facts = try? c.decode([Fact].self, forKey: .facts)
        updatedAt = try? c.decode(Date.self, forKey: .updatedAt)
    }

    private static func flexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    var isMatch: Bool { type == "match" && home != nil && away != nil }
    var isLive: Bool { status == "live" || status == "halftime" }

    var kickoffDate: Date? {
        guard let kickoff else { return nil }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = LiveScores.turkeyZone      // kart saatleri her zaman Türkiye saatiyle yazılır
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let d = local.date(from: kickoff) { return d }
        }
        return ISO8601DateFormatter().date(from: kickoff)
    }

    /// Kart yenilenmeye değer mi? (canlı maç, başlamış olması gereken maç, fiyat kartı)
    var isRefreshable: Bool {
        if isMatch {
            if isLive { return true }
            if status == "finished" { return false }
            if let date = kickoffDate { return date.timeIntervalSinceNow < 3 * 3600 }
            return true
        }
        return !(facts ?? []).isEmpty
    }
}

// MARK: - [NAME: {json}] etiketleri (süslü parantez sayarak)

enum JSONTag {
    /// Metindeki tüm [NAME: {…}] etiketlerini çıkarır. Yarım kalan etiket (akış sırasında) sona kadar silinir.
    static func extract(_ name: String, from input: String) -> (text: String, payloads: [Data]) {
        var text = input
        var payloads: [Data] = []
        while let start = text.range(of: "[\(name)", options: .caseInsensitive) {
            guard let brace = text[start.upperBound...].firstIndex(of: "{") else {
                text.removeSubrange(start.lowerBound...)
                break
            }
            var depth = 0, inString = false, escaped = false
            var end: String.Index?
            var i = brace
            while i < text.endIndex {
                let c = text[i]
                if escaped { escaped = false }
                else if c == "\\" { escaped = inString }
                else if c == "\"" { inString.toggle() }
                else if !inString {
                    if c == "{" { depth += 1 }
                    if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
                }
                i = text.index(after: i)
            }
            guard let end else {
                text.removeSubrange(start.lowerBound...)   // yarım: kalanını gizle
                break
            }
            if let data = String(text[brace...end]).data(using: .utf8) { payloads.append(data) }
            var tail = text.index(after: end)
            while tail < text.endIndex, text[tail] == " " || text[tail] == "]" { tail = text.index(after: tail) }
            text.removeSubrange(start.lowerBound..<tail)
        }
        return (text, payloads)
    }

    static func widgets(in input: String) -> (text: String, widgets: [ChatWidget]) {
        let (text, payloads) = extract("WIDGET", from: input)
        let widgets = payloads.compactMap { try? JSONDecoder().decode(ChatWidget.self, from: $0) }
            .filter { $0.isMatch || $0.name != nil }
        return (text, widgets)
    }
}

// MARK: - Logo bulucu

actor LogoLoader {
    static let shared = LogoLoader()
    private var cache: [String: URL?] = [:]

    func logoURL(wiki: String?, domain: String?, name: String) async -> URL? {
        let key = "\(wiki ?? "")|\(domain ?? "")|\(name)"
        if let hit = cache[key] { return hit }
        var found: URL?
        // 1) Wikipedia sayfasının görseli — sadece logo/arma gibi görünenler (fotoğraf değil)
        for title in [wiki, name].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            for lang in ["en", "tr"] {
                if let url = await wikiLogo(title: title, lang: lang) { found = url; break }
            }
            if found != nil { break }
        }
        // 2) Resmi sitenin simgesi
        if found == nil, let domain, !domain.isEmpty {
            let host = domain.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                .split(separator: "/").first.map(String.init) ?? domain
            found = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
        }
        cache[key] = found
        return found
    }

    private func wikiLogo(title: String, lang: String) async -> URL? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)?redirect=true") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("PufyAgent/1.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let source = (json["thumbnail"] as? [String: Any])?["source"] as? String else { return nil }
        let lower = source.lowercased()
        // Armalar/logolar genelde svg'den üretilmiş png'dir; .jpg çoğunlukla fotoğraf (ör. Apple Park)
        let looksLikeLogo = lower.contains(".svg") || lower.contains("logo") || lower.contains("crest")
            || lower.contains("emblem") || lower.contains(".png")
        return looksLikeLogo ? URL(string: source) : nil
    }
}

/// Logo kutusu: logolar her temada beyaz zeminde (siyah logolar koyu temada kaybolmasın)
struct LogoTile: View {
    let name: String
    var wiki: String? = nil
    var domain: String? = nil
    var size: CGFloat = 52

    @State private var url: URL?
    @State private var resolved = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: SmoothSpring.fade)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(size * 0.12)
                            .transition(.opacity)
                    case .failure:
                        initials
                    default:
                        ProgressView().controlSize(.mini).tint(.black.opacity(0.4))
                    }
                }
            } else if resolved {
                initials
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(wiki ?? "")|\(domain ?? "")|\(name)") {
            url = await LogoLoader.shared.logoURL(wiki: wiki, domain: domain, name: name)
            resolved = true
        }
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased())
            .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.75))
    }
}

// MARK: - Kart

/// Kart yenilenince sohbete kaydetmek için (mesaj kimliği, kart sırası, yeni kart)
private struct WidgetUpdateKey: EnvironmentKey {
    static let defaultValue: ((UUID, Int, ChatWidget) -> Void)? = nil
}

extension EnvironmentValues {
    var pufyWidgetUpdate: ((UUID, Int, ChatWidget) -> Void)? {
        get { self[WidgetUpdateKey.self] }
        set { self[WidgetUpdateKey.self] = newValue }
    }
}

struct ChatWidgetCard: View {
    let widget: ChatWidget
    let messageID: UUID
    let index: Int
    /// Akış sırasında yenileme yok
    var isStatic: Bool = false

    @Environment(\.pufyWidgetUpdate) private var onUpdate
    @State private var current: ChatWidget?
    @State private var refreshing = false
    @State private var autoRefreshes = 0

    private var shown: ChatWidget { current ?? widget }

    var body: some View {
        Group {
            if shown.isMatch {
                MatchCard(widget: shown, refreshing: refreshing, canRefresh: !isStatic && shown.isRefreshable, onRefresh: refresh,
                          isTracking: isTracking, onTrack: (!isStatic && shown.status != "finished") ? toggleTracking : nil)
            } else {
                EntityCard(widget: shown, refreshing: refreshing, canRefresh: !isStatic && shown.isRefreshable, onRefresh: refresh)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        // Canlı maç: ekrandayken 90 sn'de bir kendiliğinden güncellenir (en fazla 20 kez)
        .onAppear { isTracking = LiveActivityCenter.activity(id: activityID) != nil }
        .task(id: shown.isLive && !isStatic) {
            guard !isStatic, shown.isMatch else { return }
            let stale = (shown.updatedAt ?? .distantPast).timeIntervalSinceNow < -90
            let shouldHaveStarted = shown.status == "upcoming" && (shown.kickoffDate.map { $0 < Date() } ?? false)
            if (shown.isLive || shouldHaveStarted) && stale { await performRefresh() }
            while shown.isLive && autoRefreshes < 20 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                if Task.isCancelled { break }
                autoRefreshes += 1
                await performRefresh()
            }
        }
    }

    private func refresh() {
        PremiumHaptics.light()
        Task { await performRefresh() }
    }

    // MARK: Kilit ekranında takip (skor şablonlu canlı etkinlik)

    @State private var isTracking = false

    private var activityID: String {
        "pufymatch.\(shown.home?.name ?? "")-\(shown.away?.name ?? "")"
    }

    private func liveState(_ w: ChatWidget) -> PufyLiveActivityAttributes.ContentState {
        func side(_ s: ChatWidget.Side?) -> PufyLiveActivityAttributes.ContentState.Side {
            let name = s?.short ?? s?.name ?? ""
            return .init(name: s?.name ?? "", short: s?.short, color: Self.teamColor(name))
        }
        var state = PufyLiveActivityAttributes.ContentState(title: w.league ?? String(localized: "Maç"), status: w.status == "halftime" ? String(localized: "Devre arası") : nil)
        state.style = "score"
        state.home = side(w.home)
        state.away = side(w.away)
        state.homeScore = w.homeScore ?? 0
        state.awayScore = w.awayScore ?? 0
        state.minute = w.status == "halftime" ? "İY" : (w.minute.map { $0.hasSuffix("'") ? $0 : $0 + "'" } ?? (w.kickoffDate.map { Self.clock.string(from: $0) }))
        state.isFinished = w.status == "finished"
        return state
    }

    private func toggleTracking() {
        PremiumHaptics.medium()
        if isTracking {
            LiveActivityCenter.end(id: activityID)
            isTracking = false
        } else {
            isTracking = LiveActivityCenter.start(id: activityID, kind: .task, state: liveState(shown), symbol: "sportscourt.fill")
            if isTracking { Task { await performRefresh() } }
        }
    }

    /// Logo indirilemediği için takım adına göre sabit bir renk (her açılışta aynı)
    private static func teamColor(_ name: String) -> String {
        let palette = ["#A90432", "#0D2F6E", "#1B7A3E", "#E2A400", "#5B2C83", "#C2410C", "#0E7490", "#374151"]
        let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count
        return palette[index]
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func performRefresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard let updated = await ChatWidgetRefresher.refresh(shown) else { return }
        withAnimation(SmoothSpring.standard) { current = updated }
        onUpdate?(messageID, index, updated)
        // Kilit ekranındaki takip de güncellensin (uygulama açıkken)
        if LiveActivityCenter.activity(id: activityID) != nil {
            let state = liveState(updated)
            LiveActivityCenter.update(id: activityID) { $0 = state }
            if updated.status == "finished" {
                LiveActivityCenter.end(id: activityID, dismissAfter: 60 * 30)
                isTracking = false
            }
        }
    }
}

private struct RefreshButton: View {
    let refreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(refreshing ? 360 : 0))
                .animation(refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: refreshing)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(refreshing)
        .accessibilityLabel(String(localized: "Güncelle"))
    }
}

// MARK: Maç kartı

private struct MatchCard: View {
    let widget: ChatWidget
    let refreshing: Bool
    let canRefresh: Bool
    let onRefresh: () -> Void
    var isTracking: Bool = false
    var onTrack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                if let league = widget.league, !league.isEmpty {
                    Text(league)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                statusChip
                if let onTrack {
                    // Kilit ekranında / Dinamik Ada'da skor takibi
                    Button(action: onTrack) {
                        Image(systemName: isTracking ? "lock.iphone" : "rectangle.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isTracking ? Color.primary : Color.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isTracking ? String(localized: "Kilit ekranı takibini durdur") : String(localized: "Kilit ekranında takip et"))
                }
                if canRefresh { RefreshButton(refreshing: refreshing, action: onRefresh) }
            }

            HStack(alignment: .center, spacing: 8) {
                team(widget.home!)
                center
                    .frame(minWidth: 96)
                team(widget.away!)
            }

            if let venue = widget.venue, !venue.isEmpty {
                Label(venue, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func team(_ side: ChatWidget.Side) -> some View {
        VStack(spacing: 8) {
            LogoTile(name: side.name, wiki: side.wiki, domain: side.domain, size: 56)
            Text(side.short ?? side.name)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var center: some View {
        let hasScore = widget.homeScore != nil && widget.awayScore != nil
        if (widget.isLive || widget.status == "finished"), hasScore {
            VStack(spacing: 4) {
                Text("\(widget.homeScore ?? 0) - \(widget.awayScore ?? 0)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(scoreCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else if let date = widget.kickoffDate {
            VStack(spacing: 3) {
                Text(Self.time.string(from: date))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(Self.dayLabel(date))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if date > Date() {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        } else {
            Text("vs")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var scoreCaption: String {
        switch widget.status {
        case "halftime": return String(localized: "Devre arası")
        case "finished": return String(localized: "Maç sonu")
        default:
            if let minute = widget.minute, !minute.isEmpty {
                return minute.hasSuffix("'") ? minute : "\(minute)'"
            }
            return String(localized: "Canlı")
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch widget.status {
        case "live", "halftime":
            HStack(spacing: 5) {
                LiveDot()
                Text(widget.status == "halftime" ? String(localized: "DEVRE ARASI") : String(localized: "CANLI"))
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
            }
        case "finished":
            Text(String(localized: "MAÇ SONU"))
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        case "postponed":
            Text(String(localized: "ERTELENDİ"))
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Bugün") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Yarın") }
        if calendar.isDateInYesterday(date) { return String(localized: "Dün") }
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "d MMMM EEE"
        return f.string(from: date)
    }
}

/// Canlı göstergesi: hafifçe nefes alan nokta
private struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: Kurum / ürün kartı

private struct EntityCard: View {
    let widget: ChatWidget
    let refreshing: Bool
    let canRefresh: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoTile(name: widget.name ?? "", wiki: widget.wiki, domain: widget.domain, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.name ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = widget.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if canRefresh { RefreshButton(refreshing: refreshing, action: onRefresh) }
            }

            let facts = Array((widget.facts ?? []).prefix(6))
            if !facts.isEmpty {
                // Satırlar hep dolu: 3 ya da 6 → 3 sütun, diğerleri 2 sütun
                let columns = facts.count % 3 == 0 ? 3 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .leading), count: columns),
                          alignment: .leading, spacing: 12) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(fact.value)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .contentTransition(.numericText())
                                if let icon = trendIcon(fact.trend) {
                                    Image(systemName: icon)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(fact.trend == "up" ? Color.green : Color.red)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func trendIcon(_ trend: String?) -> String? {
        switch trend {
        case "up": return "arrow.up.right"
        case "down": return "arrow.down.right"
        default: return nil
        }
    }
}

// MARK: - Yenileme (web aramasıyla güncel durum)

enum ChatWidgetRefresher {
    static func refresh(_ widget: ChatWidget) async -> ChatWidget? {
        // Maç: önce canlı skor kaynağından (saniyeler içinde, yapay zeka çağrısı yok)
        if widget.isMatch, let home = widget.home?.name, let away = widget.away?.name,
           let match = await LiveScores.find(home: home, away: away) {
            var updated = widget
            let parts = match.score.split(separator: "-").compactMap { Int($0) }
            if match.isLive {
                updated.status = match.status == "Half Time" ? "halftime" : "live"
                updated.minute = match.status.replacingOccurrences(of: "'", with: "")
            } else if parts.count == 2 {
                updated.status = "finished"
                updated.minute = nil
            } else if let kickoff = match.kickoff {
                // Başlamadı: saati canlı kaynaktan düzelt (model saati yanlış dilimle yazmış olabilir)
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = LiveScores.turkeyZone
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                updated.kickoff = f.string(from: kickoff)
            }
            if parts.count == 2 {
                updated.homeScore = parts[0]
                updated.awayScore = parts[1]
            }
            updated.updatedAt = Date()
            return updated
        }

        let now = DateFormatter()
        now.locale = Locale(identifier: "tr_TR")
        now.dateFormat = "d MMMM yyyy EEEE HH:mm"
        let system = "Şu an: \(now.string(from: Date())) (Türkiye saati). Web'de ara ve SADECE istenen JSON'u yaz; açıklama, kod bloğu ya da başka metin yazma."

        let prompt: String
        if widget.isMatch, let home = widget.home?.name, let away = widget.away?.name {
            prompt = """
            \(home) - \(away) maçının (\(widget.league ?? ""), başlama: \(widget.kickoff ?? "bilinmiyor")) ŞU ANKİ durumunu bul.
            JSON: {"status":"upcoming|live|halftime|finished|postponed","minute":"67","homeScore":0,"awayScore":0,"kickoff":"YYYY-MM-DDTHH:mm:ss"}
            Maç başlamadıysa skorları yazma.
            """
        } else if let name = widget.name, let facts = widget.facts, !facts.isEmpty {
            prompt = """
            \(name) (\(widget.subtitle ?? "")) için şu bilgilerin ŞU ANKİ değerlerini bul: \(facts.map(\.label).joined(separator: ", ")).
            JSON: {"facts":[{"label":"…","value":"…","trend":"up|down|flat"}]} — etiketler aynı kalsın.
            """
        } else {
            return nil
        }

        guard let raw = try? await GeminiService.shared.generateContent(
            prompt: prompt, systemPrompt: system, maxOutputTokens: 1024, timeout: 60,
            useSearch: GeminiService.shared.canUseGoogleSearch, thinking: "low"),
              let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let patch = try? JSONDecoder().decode(ChatWidget.self, from: data) else { return nil }

        var updated = widget
        if widget.isMatch {
            if let s = patch.status, !s.isEmpty { updated.status = s }
            updated.minute = patch.minute ?? (patch.status == "live" ? updated.minute : nil)
            if let h = patch.homeScore { updated.homeScore = h }
            if let a = patch.awayScore { updated.awayScore = a }
            if let k = patch.kickoff, !k.isEmpty { updated.kickoff = k }
        } else if let facts = patch.facts, !facts.isEmpty {
            updated.facts = facts
        }
        updated.updatedAt = Date()
        return updated
    }
}
