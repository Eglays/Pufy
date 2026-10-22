import Foundation

/// Araştırma hattının kullanıcıya gösterilen adımları (ChatGPT'deki "Web'de aranıyor…" satırı gibi)
enum ResearchProgress {
    case planning
    case searching([String])
    case reading(Int)
    case analyzing
    case writing
    case drawing
    case note(String)

    /// Arayüzde gösterilecek metin (kullanıcının seçili diline göre)
    var displayText: String {
        switch self {
        case .planning:              return String(localized: "Düşünüyor…")
        case .searching(let q):      return q.isEmpty ? String(localized: "Web'de aranıyor…") : String(localized: "Web'de aranıyor: \(q.prefix(2).joined(separator: ", "))")
        case .reading(let count):    return String(localized: "\(count) kaynak okunuyor…")
        case .analyzing:             return String(localized: "Bilgiler değerlendiriliyor…")
        case .writing:               return String(localized: "Düşünüyor…")
        case .drawing:               return String(localized: "Görsel çiziliyor…")
        case .note(let text):        return text
        }
    }
}

class DeepResearchManager {
    static let shared = DeepResearchManager()

    private init() {}

    /// Web araması yapılabilir mi? (SearXNG adresi girilmemişse arama hattı boşuna çalışmasın)
    var isSearxAvailable: Bool {
        !SearXNGService.shared.baseUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Herhangi bir yolla (Google araması ya da SearXNG) web'de arama yapılabilir mi?
    var isSearchAvailable: Bool {
        GeminiService.shared.canUseGoogleSearch || isSearxAvailable
    }

    // MARK: - İleri zamanlı istekler
    //
    // Denge (13 Ekim 2026, kullanıcı geri bildirimi):
    //  • ZAMANI BELLİ görev ("5 dk sonra BTC", "yarın 9'da", "her 5 dakikada", sayaç) → şimdi arama YOK, hemen kurulur.
    //  • OLAYA BAĞLI görev ("ilk 11 açıklanınca yaz", "maç bitince haber ver") → arama VAR: önce hangi maç,
    //    saat kaç bulunur, görev o saate kurulur. (Arama tamamen kapatılınca model saati tahmin ediyordu.)

    private static func regexes(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    private static let timedPatterns = regexes([
        // "5 dk sonra", "10 dakika içinde", "2 saat sonra"
        "\\b\\d+\\s*(sn|saniye|dk|dak|dakika|sa|saat|gün|hafta)\\s*(sonra|içinde)",
        // "yarım saat sonra", "bir saat sonra"
        "\\b(yarım|bir|iki|üç|beş|on|on beş|yirmi|otuz)\\s*(dakika|saat|gün)\\s*sonra",
        // "her 5 dakikada", "her sabah", "her pazartesi"
        "\\bher\\s+(\\d+\\s*)?(sn|saniye|dk|dakika|saat|gün|sabah|akşam|gece|hafta|pazartesi|salı|çarşamba|perşembe|cuma|cumartesi|pazar)",
        // "yarın sabah bana … söyle", "akşam 8'de bak"
        "(yarın|bu akşam|bu gece|bu sabah|haftaya|akşam|sabah|öğlen|saat\\s*\\d{1,2}([:.]\\d{2})?'?\\s*(da|de|ta|te))\\b.*\\b(söyle|yaz|bak|haber ver|bildir|hatırlat|gönder|araştır|kontrol et|özetle)",
        "(sayaç|zamanlayıcı|timer|hatırlat|alarm|geri sayım|kronometre|uyandır)"
    ])

    /// "-ınca/-ince/-dığında" + istek fiili: "açıklanınca yaz", "bitince haber ver" (yazım hatalarına da dayanıklı)
    private static let eventPatterns = regexes([
        "\\b\\p{L}+(ınca|ince|unca|ünce|dığında|diğinde|duğunda|düğünde|tığında|tiğinde|tuğunda|tüğünde)\\b.*\\b(yaz|söyle|haber ver|bildir|bak|gönder|hatırlat|uyar)"
    ])

    private static func matches(_ list: [NSRegularExpression], _ query: String) -> Bool {
        let text = query.lowercased(with: Locale(identifier: "tr_TR"))
        let range = NSRange(text.startIndex..., in: text)
        return list.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// Olaya bağlı görev mi? (zamanını bulmak için arama gerekir)
    static func isEventRequest(_ query: String) -> Bool { matches(eventPatterns, query) }

    /// Kullanıcı bir şeyi ŞİMDİ değil İLERİDE istiyor mu? (zamanlayıcı, hatırlatıcı, zamanlanmış görev)
    static func isSchedulingRequest(_ query: String) -> Bool {
        matches(timedPatterns, query) || isEventRequest(query)
    }

    /// Şimdi arama gereksiz mi? Sadece zamanı belli görevlerde (olaya bağlı olanlarda arama lazım)
    static func skipsSearchNow(_ query: String) -> Bool {
        matches(timedPatterns, query) && !isEventRequest(query)
    }

    // MARK: - Core Execution

    /// - Parameters:
    ///   - forceSearch: Kullanıcı "Web'de Ara" modunu açtıysa planlayıcı beklenmeden arama yapılır
    ///   - progress: Adım bildirimi (ana thread'de çağrılır)
    ///   - onPartialText: Akış açıksa o ana kadarki cevap ve modelin düşünce metni (ana thread'de çağrılır)
    func executeDeepResearch(
        query: String,
        history: [Message],
        imageDatas: [Data] = [],
        hasFiles: Bool = false,
        systemPrompt: String,
        forceSearch: Bool = false,
        progress: @escaping @MainActor (ResearchProgress) -> Void = { _ in },
        onPartialText: (@MainActor (_ text: String, _ reasoning: String) -> Void)? = nil,
        onSources: (@MainActor ([WebSource]) -> Void)? = nil
    ) async throws -> String {
        let startTime = Date()
        let ai = GeminiService.shared
        // Maç/skor sorularında o anki canlı skor verisi (web aramasındaki eski sayfalardan daha güvenilir)
        var systemPrompt = systemPrompt
        if !Self.skipsSearchNow(query), let liveBlock = await LiveScores.promptBlock(for: query) {
            systemPrompt += "\n\n" + liveBlock
        }
        // Hava durumu: konum Kişisel Ağ'dan/sorudan, veri Open-Meteo'dan (~0,4 sn) → arama yok (bkz. WeatherService)
        var weatherReady = false
        if !Self.skipsSearchNow(query), let weather = await WeatherService.promptBlock(for: query, history: history) {
            systemPrompt += "\n\n" + weather
            weatherReady = true
        }

        // ── Hızlı yol: Gemini'nin yerleşik Google araması ──
        // Model, güncel bilgi gerektiğinde tek istekte kendisi arar (13 Ekim 2026 testi: ~15 sn,
        // planlayıcı + SearXNG + Jina hattının ~yarısı; sohbet mesajlarında ek gecikme yok).
        // Görsel istekleri de bu yoldan: görsel üretilip üretilmeyeceğine cevabı yazan model karar verir ([DRAW: …]).
        // ESKİ HATA: sadece belirli kelimeler ("çiz", "görsel üret") tanınıyordu; "kedi resmi oluştur" gibi istekler
        // yazı modeline gidip "görsel üretemem" cevabı alıyordu.
        if ai.canUseGoogleSearch {
            // Zamanlayıcı/hatırlatıcı/İLERİ ZAMANLI görev isteklerinde arama aracı hiç verilmez:
            // "5 dk sonra bana BTC fiyatını söyle" → eskiden ŞİMDİ 20 sn web'de arıyordu; arama görevin vaktinde yapılır.
            let isDeviceAction = Self.skipsSearchNow(query) && !forceSearch
            let canDraw = ai.canGenerateImages
            let basePrompt = systemPrompt + (canDraw ? Self.drawRules : "")

            // [DRAW] akışta görününce: "yazıyor" yerine görsel kartı; sonraki "web'de araştırıyor" notları kartı bozmasın
            let drawSignal = DrawSignal()
            let guardedProgress: @MainActor (ResearchProgress) -> Void = { @MainActor step in
                if drawSignal.active, case .drawing = step { return }
                if drawSignal.active { return }
                progress(step)
            }
            let watchedPartial: (@MainActor (String, String) -> Void)? = onPartialText.map { handler in
                { @MainActor text, reasoning in
                    if canDraw, !drawSignal.active, text.contains("[DRAW") {
                        progress(.drawing)
                        drawSignal.active = true
                    }
                    handler(text, reasoning)
                }
            }

            await progress(.writing)
            // Hakem: arama gerekir mi, ne kadar düşünsün? (bkz. QueryRouter)
            let context = QueryRouter.Context(history: history)
            let route: QueryRouter.Route = {
                var r = QueryRouter.quickRoute(query, hasImages: !imageDatas.isEmpty, hasFiles: hasFiles, forceSearch: forceSearch, context: context)
                if isDeviceAction {
                    r.search = .no
                    r.reason = "zamanlanmış istek (arama görev vaktinde)"
                    if r.thinking == "low" { r.thinking = "minimal" }
                } else if weatherReady, !forceSearch, !r.deep, imageDatas.isEmpty, QueryRouter.isOnlyWeather(query) {
                    r.search = .no
                    r.thinking = "minimal"
                    r.reason = "hava verisi hazır"
                }
                return r
            }()
            print("🧭 Hakem: \(route.search) · düşünme \(route.thinking) · \(route.reason)")

            func write(_ mode: WriterMode, _ partial: (@MainActor (String, String) -> Void)?) async throws -> String {
                try await runWriter(contents: [], query: query, history: history, imageDatas: imageDatas,
                                    systemPrompt: basePrompt + Self.searchDirective(mode), onPartialText: partial,
                                    useSearch: mode.usesSearch, onSources: onSources,
                                    thinking: route.thinking, progress: guardedProgress)
            }

            var written: String
            switch route.search {
            case .yes where route.deep:
                written = try await deepResearch(query: query, history: history, basePrompt: basePrompt,
                                                 partial: watchedPartial, onSources: onSources, progress: guardedProgress)
            case .yes:
                written = try await write(.mustSearch, watchedPartial)
            case .optional:
                written = try await write(.maySearch, watchedPartial)
            case .no where isDeviceAction:
                written = try await write(.deviceAction, watchedPartial)
            case .no, .unknown:
                // Aramasız yazar hemen başlar. İlk harfleri "[ARA]" olabilir diye ekrana verilmeden tutulur (ikinci şans);
                // kararsızsa hakem kararı gelene kadar da tutulur ("gerek yok" çıkarsa hazır cevap bekletmeden gösterilir).
                let probe = await MainActor.run { EscalationProbe(gateOpen: route.search == .no) }
                let probedPartial: (@MainActor (String, String) -> Void)? = watchedPartial.map { forward in
                    { @MainActor text, reasoning in probe.receive(text, reasoning, forward: forward) }
                }
                let fast = Task { try await write(.noSearch, probedPartial) }
                await MainActor.run {
                    probe.onEscalate = { fast.cancel() }
                    if probe.escalated { fast.cancel() }
                }
                var needSearch = false
                if route.search == .unknown, await QueryRouter.llmNeedsSearch(query, context: context) {
                    needSearch = true
                    fast.cancel()
                    print("🧭 Hakem (yapay zeka): arama gerekli")
                }
                var fastText: String?
                if !needSearch {
                    if let forward = watchedPartial { await MainActor.run { probe.openGate(forward: forward) } }
                    do {
                        let text = try await withTaskCancellationHandler {
                            try await fast.value
                        } onCancel: {
                            fast.cancel()
                        }
                        if Self.isEscalation(text) { needSearch = true } else { fastText = text }
                    } catch {
                        try Task.checkCancellation()        // kullanıcı durdurduysa
                        guard await MainActor.run(body: { probe.escalated }) else { throw error }
                        needSearch = true
                    }
                    if needSearch { print("🧭 Yazar [ARA] dedi: aramalıya geçiliyor") }
                }
                if let fastText {
                    written = fastText
                } else {
                    written = try await write(.mustSearch, watchedPartial)
                }
            }
            written = Self.removingEscalation(written)

            guard canDraw, let draw = Self.extractDraw(from: written) else { return written }
            if !drawSignal.active {
                await progress(.drawing)
                drawSignal.active = true
            }
            do {
                // Fotoğraf eklendiyse görsel modeline o da gider (düzenleme: "bunu anime yap")
                let image = try await ai.generateContent(prompt: draw.prompt, imageDatas: imageDatas,
                                                         modelOverride: ai.imageModelName, timeout: 180)
                guard image.contains("![") else {
                    return "Görseli oluşturamadım; görsel modeli boş döndü. Biraz sonra tekrar dene."
                }
                return draw.rest.isEmpty ? image : image + "\n\n" + draw.rest
            } catch {
                if Task.isCancelled { throw CancellationError() }
                return "Görseli şu an oluşturamadım: \(error.localizedDescription)"
            }
        }

        // Planlayıcıya görsel göndermiyoruz: sadece "araştırma lazım mı" kararı veriyor,
        // her istekte base64 görsel yüklemek gereksiz bant genişliği ve gecikme.
        let textHistory = history.map { msg -> Message in
            var m = msg
            m.imageDatas = []
            return m
        }

        var queries: [String] = []

        if forceSearch && isSearxAvailable {
            // Kullanıcı açıkça arama istedi → planlayıcı turunu atla (bir API çağrısı + ~1-3 sn kazanç)
            queries = [query]
        } else if !Self.skipsSearchNow(query),
                  isSearxAvailable || (GeminiService.shared.canGenerateImages && looksLikeImageRequest(query)) {
            await progress(.planning)
            let plan = try await runPlanner(query: query, history: textHistory, hasImages: !imageDatas.isEmpty)

            if plan.needImageGeneration == true, let imagePrompt = plan.imagePrompt,
               GeminiService.shared.canGenerateImages {
                await progress(.drawing)
                do {
                    return try await GeminiService.shared.generateContent(
                        prompt: imagePrompt,
                        modelOverride: GeminiService.shared.imageModelName
                    )
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    return "Üzgünüm, görsel oluşturulurken bir hata oluştu: \(error.localizedDescription)"
                }
            }
            if plan.needResearch && isSearxAvailable {
                queries = plan.queries
            }
        }
        // Arama mümkün değilse planlayıcı hiç çağrılmaz → doğrudan cevap (yarı yarıya daha hızlı)

        var allReadContents: [String] = []

        if !queries.isEmpty {
            var currentQueries = queries
            var round = 0
            let maxRounds = 3
            let maxUrlsToRead = 15
            var totalUrlsRead = 0
            var readUrlSet = Set<String>()

            while round < maxRounds && totalUrlsRead < maxUrlsToRead {
                try Task.checkCancellation()
                round += 1
                if Date().timeIntervalSince(startTime) > 30 {
                    await progress(.note("Zaman sınırına ulaşıldı, mevcut bilgilerle yanıtlanıyor…"))
                    break
                }

                await progress(.searching(currentQueries))

                // 1. SearXNG (paralel arama)
                var allResults: [SearXNGResult] = []
                await withTaskGroup(of: [SearXNGResult].self) { group in
                    for q in currentQueries {
                        group.addTask {
                            (try? await SearXNGService.shared.searchRaw(query: q)) ?? []
                        }
                    }
                    for await list in group { allResults.append(contentsOf: list) }
                }

                // 2. URL seçimi
                let fresh = deduplicate(results: allResults.filter { !readUrlSet.contains($0.url) })
                let selected = Array(scoreAndSelectURLs(results: fresh, limit: 5)
                    .prefix(maxUrlsToRead - totalUrlsRead))
                guard !selected.isEmpty else { break }

                // 3. Jina Reader (paralel okuma)
                await progress(.reading(selected.count))
                totalUrlsRead += selected.count
                selected.forEach { readUrlSet.insert($0.url) }

                await withTaskGroup(of: String?.self) { group in
                    for result in selected {
                        group.addTask {
                            do {
                                let text = try await JinaReaderService.shared.read(url: result.url)
                                return "Kaynak: \(result.url)\nBaşlık: \(result.title)\n\nİçerik:\n\(String(text.prefix(15000)))"
                            } catch {
                                // Okunamayan sayfa için en azından arama özetini kullan
                                return "Kaynak: \(result.url)\nBaşlık: \(result.title)\n\nÖzet:\n\(result.snippet)"
                            }
                        }
                    }
                    for await content in group {
                        if let content { allReadContents.append(content) }
                    }
                }

                // 4. Yeterlilik kontrolü
                await progress(.analyzing)
                let research = try await runResearch(contents: allReadContents, query: query)
                if research.enoughInformation || research.additionalQueries.isEmpty { break }
                currentQueries = Array(research.additionalQueries.prefix(3))
            }
        }

        // 5. Cevabı yaz
        await progress(.writing)
        return try await runWriter(contents: allReadContents, query: query, history: history,
                                   imageDatas: imageDatas, systemPrompt: systemPrompt,
                                   onPartialText: onPartialText)
    }

    /// Planlayıcıyı yalnızca gerçekten görsel isteniyor olabilecekse çağırmak için basit sezgi
    /// [DRAW: …] etiketi: görsel açıklaması + etiketsiz kalan metin
    // MARK: - Derin araştırma (çok adımlı, paralel)
    //
    // Kullanıcı (15 Ekim 2026): "Normal sohbette tek bir yapay zeka bir kere çalışmasına gerek yok; gerekiyorsa iki üç kere
    // çalışacak, bir şeyi doğrulamak ya da öğrenmek için; gerekirse aynı anda."
    //   1) Plan: soru 2-4 alt soruya bölünür; kolay yanlış olabilecek bilgiler (skor, saat, fiyat…) "kritik" işaretlenir.
    //   2) Araştırma: alt sorular AYNI ANDA aranır; kritik olanlar ikinci, bağımsız bir aramayla çapraz kontrol edilir.
    //   3) Yazım: notlar zor işler modeline verilir; çelişkileri çözer, eksik kalanı kendisi arar, cevabı yazar.
    // Basit güncel sorular (kur, tek maç saati) bu yola girmez (hakem karar verir).

    private struct SubQuery: Decodable {
        let q: String
        let critical: Bool?
    }

    /// Aşamalı gösterimde araştırma planı ve bulgu satırlarının önekleri (ChatView bunlara bakıp listeyi çizer)
    static let planPrefix = "Araştırıyorum: "
    static let findingPrefix = "✓ "

    /// Araştırma notundan tek satırlık bulgu: "Konu — ilk somut cümle"
    static func findingSnippet(label: String, note: String) -> String {
        let lines = note.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("###") }
        var first = lines.first ?? ""
        for mark in ["**", "__", "`"] { first = first.replacingOccurrences(of: mark, with: "") }
        while let c = first.first, "-*•#> ".contains(c) { first.removeFirst() }
        if first.count > 110 { first = String(first.prefix(107)) + "…" }
        let topic = label.count > 48 ? String(label.prefix(46)) + "…" : label
        return first.isEmpty ? topic : "\(topic) — \(first)"
    }

    private func deepResearch(query: String, history: [Message], basePrompt: String,
                              partial: (@MainActor (String, String) -> Void)?,
                              onSources: (@MainActor ([WebSource]) -> Void)?,
                              progress: @escaping @MainActor (ResearchProgress) -> Void) async throws -> String {
        let ai = GeminiService.shared
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = LiveScores.turkeyZone
        f.dateFormat = "d MMMM yyyy EEEE, HH:mm"
        let now = f.string(from: Date())
        let context = history.suffix(4).map { "\($0.role == .user ? "Kullanıcı" : "Pufy"): \($0.content.prefix(400))" }.joined(separator: "\n")

        // 1) Plan
        await progress(.note(String(localized: "Araştırma planlanıyor…")))
        var subqueries: [SubQuery] = [SubQuery(q: query, critical: true)]
        let planSystem = """
        Sen bir araştırma planlayıcısısın. Şu an \(now) (Türkiye saati). Kullanıcının son mesajını doğru ve eksiksiz cevaplamak
        için web'de AYRI AYRI araştırılması gereken 2-4 alt soru çıkar (her biri tek başına anlaşılır, tarih/kişi/takım adı içeren
        arama cümlesi). Kolay yanlış olabilecek bilgileri (skor, saat, tarih, fiyat, kadro, istatistik, kim/ne zaman) içeren alt
        soruları "critical": true işaretle. SADECE JSON: {"subqueries":[{"q":"…","critical":true}]}
        """
        if let raw = try? await ai.generateContent(prompt: (context.isEmpty ? "" : "Önceki konuşma:\n\(context)\n\n") + "Son mesaj: \(query)",
                                                   systemPrompt: planSystem, maxOutputTokens: 1500,
                                                   responseMimeType: "application/json", timeout: 20, thinking: "low"),
           let data = extractJSON(from: raw).data(using: .utf8),
           let plan = try? JSONDecoder().decode([String: [SubQuery]].self, from: data),
           let list = plan["subqueries"], !list.isEmpty {
            subqueries = Array(list.prefix(4))
        }
        try Task.checkCancellation()
        // Aşamalı gösterim: önce ne araştırılacağı görünür (uzun sürenlerde kullanıcı neyin yapıldığını görsün)
        await progress(.note(Self.planPrefix + subqueries.map(\.q).joined(separator: " · ")))

        // 2) Paralel araştırma (+ kritik olanlar için bağımsız çapraz kontrol)
        let critical = subqueries.filter { $0.critical == true }.count
        await progress(.note(critical > 0
            ? "\(subqueries.count) konu aynı anda araştırılıyor, \(critical) bilgi çapraz kontrol ediliyor…"
            : "\(subqueries.count) konu aynı anda araştırılıyor…"))
        let researchSystem = """
        Sen bir araştırmacısın. Şu an \(now) (Türkiye saati). Verilen konuyu web'de ARA ve bulduklarını kısa notlar halinde yaz:
        somut bilgiler (sayılar, tarihler, saatler, isimler), her birinin kaynağı (site adı) ve sayfanın tarihi. Saatleri Türkiye
        saatine (TSİ) çevir. Eski sezon/yıl sayfalarını güncel sanma. Emin olmadığını ya da kaynakların çeliştiğini açıkça yaz.
        Sohbet cümlesi kurma, sadece not.
        """
        var jobs: [(label: String, prompt: String)] = subqueries.map { ($0.q, "Konu: \($0.q)") }
        for sub in subqueries where sub.critical == true {
            jobs.append(("Çapraz kontrol: \(sub.q)", "Bu bilgiyi FARKLI kaynaklardan bağımsız olarak doğrula (resmi site, canlı skor/fiyat siteleri, büyük haber ajansları): \(sub.q)"))
        }
        // Her arama bitince kısa bulgusu görünür. En yavaş arama herkesi bekletmesin: 35 sn sonra eldekiyle devam edilir
        // (eskiden her biri 90 sn'ye kadar bekleniyordu → bazı sorular 1 dakikayı geçiyordu).
        let deadline: UInt64 = 35_000_000_000
        let notes: [String] = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    let text = try? await ai.generateContent(prompt: job.prompt, systemPrompt: researchSystem, maxOutputTokens: 3000,
                                                             timeout: 60, useSearch: true, thinking: "low")
                    return (index, text.map { "### \(job.label)\n\($0.trimmingCharacters(in: .whitespacesAndNewlines))" })
                }
            }
            group.addTask { try? await Task.sleep(nanoseconds: deadline); return (-1, nil) }
            var results: [(Int, String)] = []
            var finished = 0
            for await (index, text) in group {
                if index == -1 {                       // süre doldu
                    if !results.isEmpty { group.cancelAll(); break }
                    continue
                }
                finished += 1
                if let text, !text.isEmpty {
                    results.append((index, text))
                    if !jobs[index].label.hasPrefix("Çapraz kontrol") {
                        await progress(.note(Self.findingPrefix + Self.findingSnippet(label: jobs[index].label, note: text)))
                    }
                }
                if finished == jobs.count { group.cancelAll(); break }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        try Task.checkCancellation()

        // 3) Yazım (zor işler modeli): notları birleştirir, çelişkiyi çözer, eksik kalanı kendisi arar
        await progress(.note(notes.isEmpty ? "Yazıyor…" : "Bilgiler karşılaştırılıp yazılıyor…"))
        let directive = """


        HAKEM KARARI — DERİN ARAŞTIRMA: Bu soru için birden çok bağımsız arama yapıldı; notlar aşağıda (ARAŞTIRMA SONUÇLARI).
        Notları birleştir. Aynı bilgi için notlar ÇELİŞİYORSA daha güncel ve resmi kaynağı seç, önemliyse belirsizliği kısaca söyle.
        Eksik kalan nokta varsa kendin Google'da ara. Saatleri TSİ ver. Kullandığın sitelerin alan adlarını sonda [SOURCES: …] ile yaz.
        """
        return try await runWriter(contents: notes, query: query, history: history, imageDatas: [],
                                   systemPrompt: basePrompt + directive, onPartialText: partial,
                                   useSearch: true, onSources: onSources, thinking: "high",
                                   model: ai.deepModel, progress: progress)
    }

    // MARK: - Hakem kararı → yazara talimat

    /// Aramasız yazarın "bu soru güncel bilgi istiyor, beni aramayla çalıştır" işareti
    static let escalationToken = "[ARA]"

    enum WriterMode {
        case mustSearch, maySearch, noSearch, deviceAction
        var usesSearch: Bool { self == .mustSearch || self == .maySearch }
    }

    /// ESKİ HATA (22 Ekim 2026): sadece ilk 4 harfe ("[ARA") bakılıyordu → "[ARAYUZ]" ile başlayan dinamik arayüz cevabı
    /// arama isteği sanılıyor, etiketi siliniyor (sohbete çıplak HTML düşüyordu) ve gereksiz yere web araması yapılıyordu.
    /// Artık işaret tam "[ARA]" olmalı.
    static func isEscalation(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix(escalationToken)
    }

    /// Yanlışlıkla aramalı cevapta da yazılmışsa temizle
    static func removingEscalation(_ text: String) -> String {
        guard isEscalation(text) else { return text }
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let close = rest.firstIndex(of: "]") { rest = String(rest[rest.index(after: close)...]) }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchDirective(_ mode: WriterMode) -> String {
        switch mode {
        case .mustSearch:
            return """


            HAKEM KARARI — WEB ARAMASI ZORUNLU: Bu mesaj güncel ya da doğrulanması gereken bilgi istiyor. Cevabı yazmadan ÖNCE \
            Google'da ara (gerekirse birkaç sorguyla; Türkçe ve İngilizce). Eğitim bilgini güncel gerçek gibi sunma; aramayla \
            çelişiyorsa aramayı esas al, önceki cevabın yanlışsa açıkça düzelt. Saatleri TSİ'ye çevir. Kullandığın siteleri \
            sonda [SOURCES: …] ile yaz.
            """
        case .maySearch:
            return """


            HAKEM KARARI — ARAMA SERBEST (kullanıcı görsel gönderdi): Önce görseli dikkatle oku. Görselde gerçek dünyaya ait GÜNCEL \
            bir şey varsa (fikstür, maç listesi, skor, bilet, etkinlik, haber, sosyal medya gönderisi, fiyat, ürün, kişi) Google'da \
            ara; bilgileri doğrula ve tamamla (ör. maç saatlerini TSİ olarak). Bulamasan da "gerçek değil" deme. Görsel güncel bir \
            şey içermiyorsa (yemek, hayvan, nesne, çeviri, ödev, kod) aramadan cevapla.
            """
        case .noSearch:
            return """


            HAKEM KARARI — ARAMASIZ: Hakem bu mesajın bilginle cevaplanabileceğine karar verdi; hemen cevapla.
            İKİNCİ ŞANS: Cevabın, eğitim bilginden SONRA değişmiş ya da ortaya çıkmış olabilecek bir bilgiye dayandığını fark \
            edersen (bugünkü/yaklaşan maç, fikstür, skor, kadro, fiyat, kur, haber, hava, yeni ürün/sürüm, bir kişinin ya da \
            kurumun şu anki durumu, tanımadığın bir isim/olay/ürün) ya da kullanıcı önceki güncel bir bilgiye itiraz ediyorsa: \
            HİÇBİR ŞEY yazmadan cevabın en başına sadece \(escalationToken) yaz ve dur; uygulama seni web aramasıyla yeniden \
            çalıştırır. Genel bilgi, tarif, matematik, kod, çeviri, tavsiye, sohbet ve hatırlatıcı/görev isteklerinde \(escalationToken) KULLANMA.
            """
        case .deviceAction:
            return """


            HAKEM KARARI — ARAMASIZ (zamanlanmış istek): Bu bir hatırlatıcı/sayaç/zamanlanmış görev isteği. Şimdi arama yapma, \
            şimdiki değeri verme; uygun etiketi yaz ve tek cümleyle onayla. Arama, görev vakti gelince yapılır.
            """
        }
    }

    static let drawRules = """


    GÖRSEL ÜRETME ([DRAW]) — bu uygulama görsel üretebilir ve düzenleyebilir:
    - KULLAN: kullanıcı bir görsel/resim/çizim/fotoğraf/logo/illüstrasyon/duvar kağıdı/avatar OLUŞTURMANI ya da gönderdiği \
      fotoğrafı DEĞİŞTİRMENİ istiyorsa ("bunu anime yap", "arka planı değiştir"): cevabın EN BAŞINA tek satır \
      [DRAW: ayrıntılı İngilizce görsel açıklaması — konu, stil, ışık, renkler, kompozisyon] yaz, altına en fazla bir kısa \
      Türkçe cümle ekle. Web araması yapma, "görsel üretemem" deme.
    - KULLANMA: kullanıcı bilgi soruyorsa (gerçek fotoğraf için [IMG] kullan), bir görseli yorumlatıyorsa ya da sadece \
      fotoğraf gönderip soru soruyorsa.
    """

    static func extractDraw(from text: String) -> (prompt: String, rest: String)? {
        guard let regex = try? NSRegularExpression(pattern: "\\[DRAW\\s*:\\s*([\\s\\S]+?)\\]", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let promptRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else { return nil }
        let prompt = text[promptRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count > 3 else { return nil }
        var rest = text
        rest.removeSubrange(fullRange)
        return (prompt, rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func looksLikeImageRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        let keys = ["çiz", "görsel oluştur", "görsel üret", "resim yap", "resmini yap", "resim oluştur",
                    "fotoğraf oluştur", "illüstrasyon", "logo tasarla", "draw", "generate an image", "image of"]
        return keys.contains { t.contains($0) }
    }

    // MARK: - Agent Operations

    private func runPlanner(query: String, history: [Message], hasImages: Bool) async throws -> PlannerResponse {
        let canDraw = GeminiService.shared.canGenerateImages
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short)
        let systemPrompt = """
        Sen bir planlayıcısın. Kullanıcının mesajı için web araştırması gerekip gerekmediğine karar ver.
        Cevap verme, SADECE JSON üret. Bugün: \(today)

        KURALLAR:
        1. Yalnızca güncel/doğrulanması gereken bilgi isteniyorsa "needResearch": true yap (maç skorları, kadrolar, hava durumu, haberler, fiyatlar, "kim kazandı" vb.). Sorguları tarih odaklı yaz; gerekirse İngilizce sorgu da ekle. En fazla 3 sorgu.
        2. Hatırlatıcı, alarm, uygulama içi görev, selamlaşma, sohbet, genel bilgi, kod, çeviri, matematik → "needResearch": false.
        \(hasImages ? "3. Kullanıcı bir görsel gönderdi. Görselde güncel dünya bilgisi (fikstür, maç, haber, fiyat, ürün, etkinlik) varsa araştır; yemek/hayvan/nesne/metin gibi içerikler için araştırma gerekmez." : "")
        \(canDraw ? "4. Kullanıcı bir görsel/resim/çizim oluşturulmasını istiyorsa \"needImageGeneration\": true yap ve İngilizce ayrıntılı açıklamayı \"imagePrompt\" alanına yaz; bu durumda \"needResearch\": false." : "")

        Örnek: {"needResearch": true, "queries": ["Galatasaray ilk 11 bugün"]}
        Örnek: {"needResearch": false, "queries": []}
        """

        let jsonStr = try await GeminiService.shared.generateContent(
            prompt: query,
            history: Array(history.suffix(4)),
            systemPrompt: systemPrompt,
            // Düşünen modellerde düşünce de bu bütçeden yer: 512'de JSON yarım kalabiliyordu
            maxOutputTokens: 2048,
            responseMimeType: "application/json"
        )

        if let data = extractJSON(from: jsonStr).data(using: .utf8),
           let response = try? JSONDecoder().decode(PlannerResponse.self, from: data) {
            return response
        }
        return PlannerResponse(needResearch: false, needImageGeneration: false, imagePrompt: nil, queries: [])
    }

    private func runResearch(contents: [String], query: String) async throws -> ResearchResponse {
        let joinedContents = contents.joined(separator: "\n\n---\n\n")
        let prompt = """
        Kullanıcının sorusu: "\(query)"

        Şu ana kadar toplanan bilgiler:
        \(joinedContents)

        Bu bilgiler soruyu güvenilir şekilde cevaplamaya yetiyor mu? Yetmiyorsa eksik kısmı tamamlayacak en fazla 3 yeni arama sorgusu öner.
        Format: {"enoughInformation": true/false, "additionalQueries": ["..."]}
        """

        let jsonStr = try await GeminiService.shared.generateContent(
            prompt: prompt,
            systemPrompt: "Sen bir araştırma analiz ajanısın. Sadece JSON formatında cevap ver.",
            maxOutputTokens: 512,
            responseMimeType: "application/json"
        )

        if let data = extractJSON(from: jsonStr).data(using: .utf8),
           let response = try? JSONDecoder().decode(ResearchResponse.self, from: data) {
            return response
        }
        return ResearchResponse(enoughInformation: true, additionalQueries: [])
    }

    private func runWriter(contents: [String], query: String, history: [Message], imageDatas: [Data],
                           systemPrompt: String, onPartialText: (@MainActor (_ text: String, _ reasoning: String) -> Void)?,
                           useSearch: Bool = false,
                           onSources: (@MainActor ([WebSource]) -> Void)? = nil,
                           thinking: String? = nil,
                           model: String? = nil,
                           progress: @escaping @MainActor (ResearchProgress) -> Void = { _ in }) async throws -> String {
        var finalSystemPrompt = systemPrompt
        if !contents.isEmpty {
            let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short)
            finalSystemPrompt += """


            ARAŞTIRMA SENTEZİ — Bugün: \(today)
            - Aşağıdaki araştırma sonuçlarını sentezle; uydurma bilgi üretme.
            - Kesin olmayan bilgiyi kesinmiş gibi sunma, tarihleri belirt.
            - Kaynakları doğal bir dille an (ör. "ESPN'e göre…"); çelişki varsa açıkla.
            - Yeterli veri yoksa: "Bu konuda yeterli güncel bilgiye ulaşamadım." de.

            [ARAŞTIRMA SONUÇLARI]
            \(contents.joined(separator: "\n\n---\n\n"))
            """
        }

        let ai = GeminiService.shared
        guard let onPartialText, ai.streamingEnabled else {
            return try await ai.generateContent(prompt: query, history: history, imageDatas: imageDatas,
                                                systemPrompt: finalSystemPrompt, modelOverride: model, useSearch: useSearch, thinking: thinking)
        }

        // Model aramaya gidince birkaç saniye sessiz kalır: kullanıcı ne olduğunu görsün
        let searchHint: Task<Void, Never>? = useSearch ? Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled { await progress(.note("Web'de araştırıyor…")) }
        } : nil
        defer { searchHint?.cancel() }

        // Akış: cevap geldikçe ekrana yansıt. Arayüzü boğmamak için ~25 fps ile sınırlı.
        var full = ""
        var reasoning = ""
        var sources: [WebSource] = []
        var lastPush = Date.distantPast
        do {
            for try await chunk in ai.streamContent(prompt: query, history: history, imageDatas: imageDatas,
                                                    systemPrompt: finalSystemPrompt, modelOverride: model,
                                                    useSearch: useSearch, thinking: thinking) {
                switch chunk {
                case .text(let t):
                    full += t
                    searchHint?.cancel()
                case .thought(let t):
                    reasoning += t
                case .sources(let list):
                    for item in list where !sources.contains(item) { sources.append(item) }
                }
                if Date().timeIntervalSince(lastPush) > 0.04 {
                    lastPush = Date()
                    let (text, thought) = (full, reasoning)
                    await onPartialText(text, thought)
                }
            }
            let (text, thought) = (full, reasoning)
            await onPartialText(text, thought)
            if !sources.isEmpty, let onSources {
                let found = sources
                await onSources(found)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Sunucu akışı desteklemiyorsa ve henüz hiçbir şey gelmediyse normal isteğe düş
            guard full.isEmpty else { throw error }
            return try await ai.generateContent(prompt: query, history: history, imageDatas: imageDatas,
                                                systemPrompt: finalSystemPrompt, modelOverride: model, useSearch: useSearch, thinking: thinking)
        }

        if full.isEmpty {
            return try await ai.generateContent(prompt: query, history: history, imageDatas: imageDatas,
                                                systemPrompt: finalSystemPrompt, modelOverride: model, useSearch: useSearch, thinking: thinking)
        }
        return full
    }

    // MARK: - URL Selection Logic

    private func deduplicate(results: [SearXNGResult]) -> [SearXNGResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.url).inserted }
    }

    private func scoreAndSelectURLs(results: [SearXNGResult], limit: Int) -> [SearXNGResult] {
        let trustedDomains = ["espn.com", "bbc.co.uk", "bbc.com", "reuters.com", "flashscore", "transfermarkt",
                              "wikipedia.org", "goal.com", "theguardian", "nytimes", "bloomberg", "sofascore",
                              "mackolik", "trtspor", "ntvspor", "aa.com.tr"]

        let scored = results.map { res -> (SearXNGResult, Int) in
            var score = 0
            let urlLower = res.url.lowercased()
            if trustedDomains.contains(where: { urlLower.contains($0) }) { score += 10 }
            if res.snippet.count < 50 { score -= 5 }
            return (res, score)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    // MARK: - Utility

    /// Model JSON'un etrafına açıklama/kod bloğu eklese bile ilk {...} bloğunu çıkarır
    private func extractJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[start...end])
    }
}

/// Akış sırasında "[DRAW" görüldü mü? (erişimler sıralı: akış bitince okunur)
private final class DrawSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var active: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// Aramasız yazarın akışını süzer:
///  • Cevap "[ARA]" ile başlıyorsa (model güncel bilgi gerektiğini fark etti) hiçbir şey gösterilmez, yazar durdurulur.
///  • Kararsız sorularda hakem kararı gelene kadar akış ekrana verilmez, son hali saklanır.
@MainActor
private final class EscalationProbe {
    var gateOpen: Bool
    private var decided = false
    private(set) var escalated = false
    private var pending: (String, String)?
    var onEscalate: (() -> Void)?

    init(gateOpen: Bool) { self.gateOpen = gateOpen }

    func receive(_ text: String, _ reasoning: String, forward: (String, String) -> Void) {
        guard !escalated else { return }
        if !decided {
            let head = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(5).uppercased()
            // Tam "[ARA]" olmalı ("[ARAYUZ]" bir yükseltme değil, dinamik arayüz etiketi)
            if head.hasPrefix(DeepResearchManager.escalationToken) {
                escalated = true
                pending = nil
                onEscalate?()
                return
            }
            // "[", "[A", "[AR", "[ARA" henüz belirsiz: bekle (düşünce metni boş cevapla gösterilebilir)
            if head.count < 5 && DeepResearchManager.escalationToken.hasPrefix(head) {
                if gateOpen { forward("", reasoning) } else { pending = ("", reasoning) }
                return
            }
            decided = true
        }
        if gateOpen { forward(text, reasoning) } else { pending = (text, reasoning) }
    }

    func openGate(forward: (String, String) -> Void) {
        gateOpen = true
        if !escalated, let pending { forward(pending.0, pending.1) }
        pending = nil
    }
}
