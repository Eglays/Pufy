import Foundation

// MARK: - Canlı Skorlar
//
// Kullanıcı geri bildirimi (13 Ekim 2026): "Sarıyer-Bodrum 27. dakikada 3-0'dı; dakikayı doğru buldu ama skoru 0-0,
// sonra 1-0 dedi." Sebep: web aramasının bulduğu sayfalar farklı anlardan (maç önü yazıları, eski önbellekler);
// dakika bir sayfadan, skor başka bir sayfadan geliyordu.
// Çözüm: maç/skor sorularında flashscore'un hafif mobil sayfasından (şu an oynanan ve bugünkü tüm maçlar) o anda
// çekilen veri modele "en güvenilir kaynak" olarak verilir; maç kartı da buradan saniyeler içinde yenilenir.
// Not: resmi bir API değil (kullanıcının spor API anahtarı bağlanınca o kullanılabilir).

enum LiveScores {
    // SAAT DİLİMİ (14 Ekim 2026, kullanıcı: "Şampiyonlar Ligi maçlarını 21'de dedi, 1 saat yanlış"):
    // flashscore.mobi başlama saatlerini ORTA AVRUPA saatiyle (CET/CEST, Prag) yazar; Türkiye saati değil.
    // Doğrulama: 20:24 TSİ'de 40. dakikada olan maçlar 18:45 CEST'te (19:45 TSİ) başlamıştı; akşam maçları listede
    // "21:00" görünüyordu (= 22:00 TSİ).
    // Saatler artık gerçek ana çevrilip modele "TSİ" etiketiyle verilir (yaz saati farkı da TimeZone ile otomatik).
    static let sourceZone = TimeZone(identifier: "Europe/Prague") ?? TimeZone(secondsFromGMT: 3600)!
    static let turkeyZone = TimeZone(identifier: "Europe/Istanbul") ?? TimeZone(secondsFromGMT: 3 * 3600)!

    struct Match: Hashable {
        let league: String
        /// Ham durum: "27'", "Half Time", "21:00" (ORTA AVRUPA saati — modele doğrudan verme) …
        let status: String
        let home: String
        let away: String
        /// "1-4" ya da "" (başlamadı)
        let score: String
        let isLive: Bool
        /// Gerçek başlama anı (flashscore saati CET/CEST'ten çevrildi)
        var kickoff: Date? = nil
        /// "ertelendi", "iptal", "yarıda kaldı"
        var note: String? = nil

        /// Türkiye saatiyle "22:00" (gece yarısını geçiyorsa "00:30 (ertesi gün)")
        var kickoffTR: String? {
            guard let kickoff else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = LiveScores.turkeyZone
            let nextDay = !cal.isDate(kickoff, inSameDayAs: Date()) && kickoff > Date()
            return LiveScores.turkeyClock(kickoff) + (nextDay ? " (ertesi gün)" : "")
        }

        var line: String {
            let start = kickoffTR.map { "başlama \($0) TSİ" } ?? ""
            let state: String
            if isLive {
                state = status == "Half Time" ? "DEVRE ARASI" : "CANLI \(status)"
            } else if let note {
                state = [start, note.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
            } else if !score.isEmpty {
                state = ["MAÇ SONU", start].filter { !$0.isEmpty }.joined(separator: " · ")
            } else {
                state = [start, "henüz başlamadı"].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return "\(league) | \(state) | \(home) - \(away)\(score.isEmpty ? "" : " | \(score)")"
        }
    }

    /// flashscore saatini ("21:00", "21:00Postponed") gerçek ana çevirir. Sayfa "bugün"ü Prag takvimine göre listeler.
    static func kickoffDate(fromStatus status: String, on day: Date = Date()) -> Date? {
        guard let r = status.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) else { return nil }
        let parts = status[r].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = sourceZone
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = parts[0]
        comps.minute = parts[1]
        return cal.date(from: comps)
    }

    static func turkeyClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = turkeyZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    private static var cache: (date: Date, matches: [Match])?

    // MARK: Soru algılama

    /// Maç / skor sorusu mu? ("Sarıyer Bodrum maçı kaç kaç", "GS skor", "canlı maçlar")
    static func isScoreQuery(_ query: String) -> Bool {
        let q = normalize(query)
        let cues = ["mac", "skor", "kac kac", "canli", "gol", "dakika", "devre", "ilk yari", "ikinci yari",
                    "kazandi", "bitti", "oynuyor", "lig", "score", "match", "live"]
        return cues.contains { q.contains($0) }
    }

    // MARK: Veri

    /// Bugünkü tüm maçlar + şu an oynananlar (60 sn önbellek)
    static func todaysMatches() async -> [Match] {
        if let cache, Date().timeIntervalSince(cache.date) < 60 { return cache.matches }
        async let livePage = fetch("https://www.flashscore.mobi/?d=0&s=2")
        async let allPage = fetch("https://www.flashscore.mobi/?d=0")
        let live = parse(await livePage ?? "", live: true)
        let all = parse(await allPage ?? "", live: false)
        // Canlı listedekiler canlı durumuyla, diğerleri bugünkü listeden
        let liveKeys = Set(live.map { normalize($0.home + "|" + $0.away) })
        let merged = live + all.filter { !liveKeys.contains(normalize($0.home + "|" + $0.away)) }
        if !merged.isEmpty { cache = (Date(), merged) }
        return merged
    }

    /// Sorudaki takımlara ya da lige uyan maçlar
    static func relevant(to query: String, in matches: [Match]) -> [Match] {
        let q = normalize(query)
        let words = q.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 }
        let stop: Set<String> = ["maci", "macin", "maclar", "maclari", "skor", "skoru", "kac", "canli", "dakika", "bugun", "simdi",
                                 "durum", "durumu", "nedir", "neydi", "oldu", "bitti", "kazandi", "takim", "lige", "ligi",
                                 "hangi", "hangileri", "saat", "saati", "saatte", "kacta", "oynanacak", "oynuyor", "aksam",
                                 "sampiyonlar", "avrupa", "konferans", "super", "premier", "listele", "goster", "fikstur",
                                 "liginde", "liginin", "ligde", "macta", "maclarda"]
        let tokens = words.filter { !stop.contains($0) }
        let byTeam = matches.filter { match in
            let teams = [normalize(match.home), normalize(match.away)]
            return tokens.contains { token in
                teams.contains { team in
                    team.contains(token) || team.split(separator: " ").contains { $0.count >= 4 && token.hasPrefix($0) }
                }
            }
        }
        if !byTeam.isEmpty {
            // En çok kelimesi eşleşen maç önce ("Roma Real Madrid" → önce AS Roma - Real Madrid, sonra diğer "Real"ler)
            func score(_ m: Match) -> Int {
                let teams = normalize(m.home + " " + m.away)
                return tokens.filter { teams.contains($0) }.count
            }
            return Array(byTeam.sorted { score($0) > score($1) }.prefix(15))
        }
        // Lig adıyla ("1. lig", "super lig", "premier league", "sampiyonlar ligi")
        // "Champions League" AFC/Körfez liglerini de içerir: Avrupa kupaları "EUROPE:" önekiyle aranır
        let leagueHints: [(String, String)] = [("super lig", "TURKEY: Super Lig"), ("1. lig", "TURKEY: 1. Lig"),
                                               ("premier", "ENGLAND: Premier League"), ("sampiyonlar", "EUROPE: Champions League"),
                                               ("champions", "EUROPE: Champions League"), ("avrupa ligi", "EUROPE: Europa League"),
                                               ("europa", "EUROPE: Europa League"), ("konferans", "EUROPE: Conference League"),
                                               ("conference", "EUROPE: Conference League"),
                                               ("dunya kupasi", "World Cup"), ("uluslar ligi", "Nations League"),
                                               ("la liga", "SPAIN: LaLiga"), ("serie a", "ITALY: Serie A"), ("bundesliga", "GERMANY: Bundesliga"),
                                               ("ligue 1", "FRANCE: Ligue 1"), ("eredivisie", "NETHERLANDS: Eredivisie")]
        for (hint, league) in leagueHints where q.contains(hint) {
            let hits = matches.filter { $0.league.localizedCaseInsensitiveContains(league) }
            if !hits.isEmpty { return Array(hits.prefix(20)) }
        }
        return []
    }

    /// Modele eklenecek blok (ilgili maç yoksa nil)
    static func promptBlock(for query: String) async -> String? {
        guard isScoreQuery(query) else { return nil }
        let all = await todaysMatches()
        let hits = relevant(to: query, in: all)
        guard !hits.isEmpty else { return nil }
        // Lig sorusu ("bugün Şampiyonlar Ligi'nde hangi maçlar var"): liste o ligin bugünkü TAMAMI — model başka günün/ligin
        // maçlarını eklemesin (testte Konferans Ligi maçlarını Şampiyonlar Ligi'ne katmıştı)
        let isLeagueList = Set(hits.map(\.league)).count == 1 && hits.count == all.filter { $0.league == hits[0].league }.count
            && hits.count > 1
        // Sayfa "bugün"ü Prag takvimine göre listeler: gece 00:00-01:00 TSİ arasında hâlâ dünün listesidir
        let day = DateFormatter()
        day.locale = Locale(identifier: "tr_TR")
        day.timeZone = sourceZone
        day.dateFormat = "d MMMM"
        return """
        CANLI SKOR VERİSİ — flashscore'un \(day.string(from: Date())) listesi, \(turkeyClock(Date())) TSİ'de ŞU AN çekildi. Skor, dakika ve başlama saati için EN GÜVENİLİR \
        kaynak budur; web aramasında farklı bir skor görürsen o sayfa eskidir, BUNU kullan. Saatler TÜRKİYE SAATİNE (TSİ) çevrilmiştir, \
        olduğu gibi kullan (tekrar çevirme). Listede olmayan maçlar için web aramasına bak:
        \(hits.map { "- " + $0.line }.joined(separator: "\n"))\(isLeagueList ? "\nBu liste \(hits[0].league) için o günün TAM listesidir; başka maç ekleme (başka gün/lig maçlarını karıştırma)." : "")
        """
    }

    /// Maç kartı için: iki takım adıyla maçı bul
    static func find(home: String, away: String) async -> Match? {
        let h = normalize(home), a = normalize(away)
        func same(_ x: String, _ y: String) -> Bool {
            let firstX = x.split(separator: " ").first.map(String.init) ?? x
            let firstY = y.split(separator: " ").first.map(String.init) ?? y
            return x.contains(y) || y.contains(x) || (firstX.count >= 4 && firstX == firstY)
                || (firstX.count >= 4 && y.hasPrefix(firstX)) || (firstY.count >= 4 && x.hasPrefix(firstY))
        }
        return await todaysMatches().first { same(normalize($0.home), h) && same(normalize($0.away), a) }
    }

    // MARK: Ayrıştırma

    private static func fetch(_ url: String) async -> String? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// <div id="score-data"><h4>LİG</h4><span>DURUM</span>Ev - Deplasman <a>SKOR</a><br/>…
    static func parse(_ html: String, live: Bool) -> [Match] {
        guard let start = html.range(of: "id=\"score-data\"") else { return [] }
        var body = String(html[start.upperBound...])
        if let end = body.range(of: "</div>") { body = String(body[..<end.lowerBound]) }
        var matches: [Match] = []
        var league = ""
        for raw in body.components(separatedBy: "<br") {
            var segment = raw
            if let h4 = segment.range(of: "<h4>"), let h4End = segment.range(of: "</h4>", range: h4.upperBound..<segment.endIndex) {
                league = strip(String(segment[h4.upperBound..<h4End.lowerBound])).replacingOccurrences(of: "Standings", with: "")
                    .trimmingCharacters(in: .whitespaces)
                segment = String(segment[h4End.upperBound...])
            }
            guard let spanOpen = segment.range(of: "<span"), let spanClose = segment.range(of: "</span>"),
                  let anchorOpen = segment.range(of: "<a ", range: spanClose.upperBound..<segment.endIndex),
                  let anchorClose = segment.range(of: "</a>", range: anchorOpen.upperBound..<segment.endIndex) else { continue }
            let statusHTML = String(segment[spanOpen.lowerBound..<spanClose.lowerBound])
            let status = strip(statusHTML).trimmingCharacters(in: .whitespaces)
            let teams = strip(String(segment[spanClose.upperBound..<anchorOpen.lowerBound]))
            let scoreText = strip(String(segment[anchorOpen.lowerBound..<anchorClose.lowerBound]))
                .replacingOccurrences(of: "&nbsp;", with: "").trimmingCharacters(in: .whitespaces)
            let parts = teams.components(separatedBy: " - ")
            guard parts.count >= 2 else { continue }
            let score = scoreText.range(of: "^\\d+\\s*-\\s*\\d+$", options: .regularExpression) != nil
                ? scoreText.replacingOccurrences(of: " ", with: "") : ""
            let isLive = live || statusHTML.contains("class=\"live\"")
            let lower = status.lowercased()
            let note: String? = lower.contains("postp") ? "ertelendi" : lower.contains("cancel") ? "iptal"
                : lower.contains("abandon") ? "yarıda kaldı" : lower.contains("awarded") ? "hükmen" : nil
            matches.append(Match(league: league, status: status,
                                 home: parts[0].trimmingCharacters(in: .whitespaces),
                                 away: parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces),
                                 score: score, isLive: isLive,
                                 kickoff: isLive ? nil : kickoffDate(fromStatus: status), note: note))
        }
        return matches
    }

    private static func strip(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Türkçe harfleri sadeleştir, küçük harf ("Sarıyer" → "sariyer")
    static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }
}
