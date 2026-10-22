import Foundation

// MARK: - Hakem (Baş Sorumlu / Soru Yönlendirici)
//
// Kullanıcı geri bildirimi (13 Ekim 2026): "İki kere iki kaç yapar dedim, webde araştırıyor. Saçmalık. Bir baş sorumlu
// olmalı: bu soru web araması gerektiriyor mu?"
// Ölçüm (gerçek sunucu): aynı soru — eski hal 6,0 sn; düşük düşünme 3,2 sn; düşük düşünme + aramasız 2,0 sn.
//
// Kullanıcı geri bildirimi (14 Ekim 2026): "Fikstür ekran görüntüsü attım, 'Roma–Real Madrid gerçekte yok' dedi; maç bir
// saat sonra oynandı." Sebep: görsel gelince hakem aramayı KAPATIYORDU ve modelin eski bilgisiyle reddetmesini engelleyen
// bir kural yoktu. Artık:
//
//  1) Anında karar (0 sn):
//     • ZORUNLU ARA  → güncel ipucu (bugün, maç, fiyat, kur, haber…), açık arama isteği ("araştır", "internette bak"),
//                      önceki güncel cevaba itiraz ("emin misin", "yanlış").
//     • SERBEST      → görsel gönderildi: araç verilir, görselde güncel dünya bilgisi (fikstür, haber, fiyat…) varsa
//                      model kendisi arar ve doğrular.
//     • ARAMA YOK    → matematik, tarif, kod, çeviri, selam/teşekkür, kısa sohbet.
//     • KARARSIZ     → aşağıdaki 2. katman.
//  2) Kararsız soruda aramasız cevap ZATEN hazırlanmaya başlar (ekrana verilmez); aynı anda yapay zekaya, sohbetin son
//     turuyla birlikte "arama gerekir mi?" sorulur (~1,5 sn). Gerek yoksa hazır cevap gösterilir, gerekirse aramalıya geçilir.
//  3) İkinci şans: aramasız yazan model cevabın güncel bilgi gerektirdiğini fark ederse cevaba "[ARA]" ile başlar;
//     uygulama o cevabı göstermeden aramalı yazara geçer (bkz. DeepResearchManager.escalationToken).
//  4) Düşünme seviyesi: varsayılan düşük; kod, analiz, uzun/çok adımlı sorular ve kullanıcının itirazları yüksek.

enum QueryRouter {
    enum SearchDecision: Equatable {
        /// Arama zorunlu: model cevaptan önce arar
        case yes
        /// Araç verilir, gerekirse model kendisi arar (görsel gönderildiğinde)
        case optional
        /// Aramasız; model gerekirse "[ARA]" ile yükseltir
        case no
        /// Yapay zeka hakemi karar verir
        case unknown
    }

    struct Route {
        var search: SearchDecision
        /// "minimal" | "low" | "high"
        var thinking: String
        /// Kayıt/teşhis için kısa gerekçe
        var reason: String
        /// Derin araştırma: alt sorulara bölünüp paralel aranır, kritik bilgiler çapraz kontrol edilir,
        /// zor işler modeli yazar (bkz. DeepResearchManager.deepResearch)
        var deep: Bool = false
    }

    /// Sohbetin son turu: kısa takip sorularını ("emin misin?", "saat kaçta?") doğru yönlendirmek için
    struct Context {
        var lastUser: String?
        var lastAssistant: String?
        /// Önceki cevap web aramasıyla mı yazıldı? (kaynak çipi var)
        var lastAnswerWasSearched: Bool

        static let empty = Context(lastUser: nil, lastAssistant: nil, lastAnswerWasSearched: false)

        init(lastUser: String?, lastAssistant: String?, lastAnswerWasSearched: Bool) {
            self.lastUser = lastUser
            self.lastAssistant = lastAssistant
            self.lastAnswerWasSearched = lastAnswerWasSearched
        }

        init(history: [Message]) {
            let assistant = history.last { $0.role == .model }
            lastAssistant = assistant?.content
            lastUser = history.last { $0.role == .user }?.content
            lastAnswerWasSearched = !(assistant?.sources ?? []).isEmpty
        }
    }

    static func quickRoute(_ query: String, hasImages: Bool, hasFiles: Bool = false, forceSearch: Bool, context: Context = .empty) -> Route {
        if hasFiles && !forceSearch {
            let q = query.lowercased(with: Locale(identifier: "tr_TR")) + " "
            let deep = needsDeepThinking(q)
            return Route(search: .no, thinking: deep ? "high" : "low", reason: "dosyalı mesaj (arama kapalı)")
        }
        // Sona boşluk: "kuru " gibi tam kelime ipuçları cümle sonunda da eşleşsin
        let q = query.lowercased(with: Locale(identifier: "tr_TR")) + " "
        let (search, reason) = forceSearch ? (.yes, "kullanıcı web araması modunu açtı")
            : quickSearch(q, hasImages: hasImages, context: context)
        let deep = needsDeepThinking(q) || has(q, challengeCues)
        // Hız (kullanıcı, 15 Ekim 2026: "not alsana dedim 5 saniye bekledi"): aramasız basit işlerde (not, sohbet,
        // matematik, tarif) düşünme "minimal" — ölçüm: ilk kelime ~2 sn (düşük: 3,5-7 sn). Aramalı/kararsız sorular "low",
        // kod/analiz/itiraz "high".
        let thinking = deep ? "high" : (search == .no ? "minimal" : "low")
        var route = Route(search: search, thinking: thinking, reason: reason)
        route.deep = search == .yes && !hasImages && needsDeepResearch(q, context: context)
        return route
    }

    // MARK: Yönergenin hangi ayrıntıları gerekli? (bkz. ChatViewModel.buildAgentSystemPrompt)

    private static let noteDetailCues = noteCues + [
        "not ", "notu", "notlar", "notum", "liste", "aldım", "işaretle", "çıkar", "ekle", "sil"
    ]

    /// Not içerikleri ve ayrıntılı not kuralları gerekli mi?
    static func isNoteRequest(_ query: String) -> Bool {
        has(query.lowercased(with: Locale(identifier: "tr_TR")) + " ", noteDetailCues)
    }

    private static let schedulingCues = [
        "hatırlat", "görev", "haber ver", "bildir", "alarm", "sayaç", "zamanlayıcı", "kur ", "sonra ", "yarın", "her gün",
        "her sabah", "her akşam", "her hafta", "her ay", "dakikada", "saatte", "açıklanınca", "başlayınca", "bitince",
        "olunca", "gelince", "çıkınca"
    ]

    /// Ayrıntılı zamanlanmış görev kuralları gerekli mi?
    static func mentionsScheduling(_ query: String) -> Bool {
        has(query.lowercased(with: Locale(identifier: "tr_TR")) + " ", schedulingCues)
    }

    /// Soru sadece hava durumu mu? (başka güncel konu ya da açık arama isteği yoksa hava verisi yeter)
    static func isOnlyWeather(_ query: String) -> Bool {
        let q = query.lowercased(with: Locale(identifier: "tr_TR")) + " "
        let weatherWords: Set<String> = ["hava durumu", "hava nasıl", "yağmur"]
        return !has(q, topicFreshCues.filter { !weatherWords.contains($0) }) && !has(q, explicitSearchCues)
            && !has(q, challengeCues)
    }

    // MARK: Derin araştırma (çok adımlı) gerekir mi?
    // Kullanıcı (15 Ekim 2026): "Tek bir yapay zeka bir kere çalışmasın; gerekiyorsa iki üç kere çalışsın, doğrulasın,
    // gerekirse aynı anda." Basit güncel sorular (kur, tek maç saati) hızlı yolda kalır.

    private static let deepResearchCues = [
        "karşılaştır", "kıyasla", "analiz", "detaylı", "ayrıntılı", "artıları", "eksileri", "hangisi daha", "farkları",
        "fark nedir", "rapor", "değerlendir", "son durum", "neler oldu", "neden oldu", "nasıl oldu", "araştır", "incele",
        "geçmişi", "istatistik", "tahmin", "senaryo", "tüm detay", "her şeyi"
    ]

    static func needsDeepResearch(_ q: String, context: Context) -> Bool {
        if has(q, deepResearchCues) { return true }
        if q.count > 160 { return true }
        // Birden çok soru ("X ne zaman? Y kaç?") ya da birden çok konu
        if q.filter({ $0 == "?" }).count >= 2 { return true }
        // Aramayla verilmiş cevaba itiraz → bağımsız doğrulama
        if context.lastAnswerWasSearched && has(q, challengeCues) { return true }
        return false
    }

    // MARK: Arama kararı (anında)

    private static let freshCues = [
        "bugün", "bu gün", "şu an", "şimdi", "güncel", "son dakika", "bu hafta", "bu akşam", "bu gece", "dünkü", "dün ", "yarın",
        "bu sezon", "bu yıl", "geçen hafta", "hafta sonu",
        "fiyat", "kaç tl", "kaç lira", "kaç dolar", "kaç para", "döviz", "kuru ", "dolar", "euro", "sterlin", "bitcoin", "btc",
        // "altın" tek başına "altında"yı, "hisse" "hissediyorum"u yakalardı: boşluklu/ekli yazılır
        "altın ", "altının ", "gram altın", "çeyrek altın", "kripto", "borsa", "hisse ", "hissesi", "hisseleri", "bist",
        "faiz", "enflasyon", "asgari ücret",
        "skor", "maç", "kadro", "ilk 11", "puan durumu", "fikstür", "transfer", "kim kazandı", "kazandı mı", "kura çekimi",
        "şampiyonlar ligi", "avrupa ligi", "konferans ligi", "süper lig", "premier lig", "milli takım",
        "hava durumu", "hava nasıl", "yağmur", "sıcaklık",
        "haber", "gündem", "seçim ", "seçimi", "seçimler", "deprem", "trafik", "konser", "etkinlik", "vizyon", "bilet",
        "ne zaman çıkacak", "çıktı mı", "yeni çıkan", "vizyondaki", "açıklandı mı", "en son", "son sürüm", "en yeni",
        "teknik direktör", "başkanı kim", "ceo'su", "şu anki", "şimdiki", "2025", "2026", "2027"
    ]

    /// Not alma / liste işleri (bkz. NoteStore)
    private static let noteCues = [
        "not al", "not et", "notlarım", "notuma", "notlara", "notumu", "notlarımı", "listeye", "listeme", "listemde", "listemden",
        "listemi", "alışveriş listesi", "yapılacaklar", "yapılacak listesi", "kaydet bunu", "unutmayayım"
    ]

    /// Kullanıcının kendisiyle ilgili duygu/durum cümleleri
    private static let personalCues = [
        "hissediyorum", "kendimi", "canım", "moralim", "yorgunum", "yoruldum", "üzgünüm", "mutluyum", "sıkıldım",
        "uykum", "başım ağrıyor", "hastayım", "aşık", "sevgilim", "annem", "babam"
    ]

    /// Zaman kelimesi dışındaki güncel konu ipuçları (kişisel cümlede bunlar varsa yine aranır: "bugün annemle maça gideceğiz, kaçta?")
    private static let topicFreshCues = [
        "fiyat", "kaç tl", "döviz", "kuru ", "dolar", "euro", "altın ", "bitcoin", "borsa", "skor", "maç", "kadro", "ilk 11",
        "puan durumu", "fikstür", "transfer", "hava durumu", "hava nasıl", "yağmur", "haber", "deprem", "trafik", "konser", "bilet"
    ]

    /// Kullanıcı açıkça arama istiyor
    private static let explicitSearchCues = [
        "araştır", "internette", "internetten", "webde", "web'de", "google", "ara bak", "bir bak", "kontrol et",
        "doğrula", "teyit", "kaynak ver", "kaynağı ne", "kaynakla"
    ]

    /// Önceki cevaba itiraz: güncel bir konuda ise mutlaka doğrulanır, düşünme yükseltilir
    private static let challengeCues = [
        "emin misin", "emin değilim", "yanlış", "hatalı", "gerçekten mi", "öyle değil", "öyle bir şey", "saçmala",
        "uyduruyorsun", "uydurma", "yalan", "var böyle", "doğru mu", "tekrar bak"
    ]

    private static let staticCues = [
        "tarif", "nasıl yapılır", "nedir", "ne demek", "anlamı", "çevir", "translate", "tanımı", "formül",
        "kod", "swift", "python", "javascript", "html", "css", "fonksiyon", "hata veriyor", "algoritma",
        "şiir", "hikaye", "masal", "yaz bana", "özetle", "düzelt", "fikir ver", "öneri", "tavsiye",
        "merhaba", "selam", "nasılsın", "teşekkür", "sağ ol", "eyw", "tamam", "günaydın", "iyi geceler"
    ]

    /// Görselle birlikte gelince aramayı gereksiz kılan istekler ("bu ne yazıyor", "çevir", "tarifini ver")
    private static let imageStaticCues = [
        "çevir", "translate", "ne yazıyor", "oku", "tarif", "kod", "hata", "düzelt", "matematik", "soru", "çöz",
        "nasıl görünüyor", "yakışmış", "güzel mi", "renk", "kombin"
    ]

    /// İpucu kelimenin BAŞINDA mı? ("maç" ✓ "amaç" ✗, "dün " ✓ "dünya" ✗)
    private static func has(_ q: String, _ cues: [String]) -> Bool {
        cues.contains { cue in
            var searchRange = q.startIndex..<q.endIndex
            while let r = q.range(of: cue, range: searchRange) {
                if r.lowerBound == q.startIndex || !q[q.index(before: r.lowerBound)].isLetter { return true }
                searchRange = r.upperBound..<q.endIndex
            }
            return false
        }
    }

    private static func quickSearch(_ q: String, hasImages: Bool, context: Context) -> (SearchDecision, String) {
        // Matematik: "2*2", "iki kere iki", "15 artı 7", "%20'si"
        if !hasImages, q.range(of: #"^[\d\s\.\,\+\-\*\/x×÷\(\)\^%=?]+$"#, options: .regularExpression) != nil {
            return (.no, "matematik")
        }
        if has(q, explicitSearchCues) { return (.yes, "açık arama isteği") }
        let mathWords = ["kere", "çarpı", "artı", "eksi", "bölü", "karekök", "kaç eder", "kaç yapar", "yüzde kaç", "toplamı"]
        if !hasImages, has(q, mathWords), !has(q, freshCues) { return (.no, "matematik") }

        // Not işleri ("bu hafta yapılacaklar listeme ekle", "alışveriş listemde ne var") → arama yok
        if has(q, noteCues), !has(q, topicFreshCues) { return (.no, "not işlemi") }
        // "Bugün kendimi yorgun hissediyorum": zaman kelimesi var ama konu kullanıcının kendisi → arama yok
        if has(q, personalCues), !has(q, topicFreshCues) { return (.no, "kişisel sohbet") }
        if has(q, freshCues) { return (.yes, "güncel bilgi ipucu") }
        // İtiraz: önceki cevap güncel bir konudaysa (aramayla yazıldıysa) doğrula; değilse hakem bağlamla karar versin
        if has(q, challengeCues) {
            return context.lastAnswerWasSearched ? (.yes, "güncel cevaba itiraz") : (.unknown, "itiraz (bağlama bakılacak)")
        }
        // Görsel: fikstür/haber/fiyat ekran görüntüsü olabilir → araç verilir, model görsele bakıp gerekirse arar
        if hasImages {
            return has(q, imageStaticCues) ? (.no, "görsel + statik istek") : (.optional, "görsel (içerik güncel olabilir)")
        }
        if has(q, staticCues) { return (.no, "statik konu") }
        // Çok kısa mesajlar: güncel bir konunun devamıysa ("saat kaçta", "peki ya Fener") hakem bağlamla karar verir
        if q.split(separator: " ").count <= 3 && !q.contains("?") {
            return context.lastAnswerWasSearched ? (.unknown, "güncel konunun kısa devamı") : (.no, "kısa sohbet")
        }
        return (.unknown, "belirsiz")
    }

    // MARK: Düşünme seviyesi

    private static let deepCues = [
        "kod", "swift", "python", "javascript", "hata ayıkla", "debug", "algoritma", "fonksiyon yaz", "uygulama yaz",
        "analiz", "karşılaştır", "strateji", "plan yap", "planla", "adım adım", "ispat", "kanıtla", "optimize",
        "neden olur", "nasıl çalışır", "detaylı", "ayrıntılı", "makale", "rapor", "denklem", "olasılık"
    ]

    private static func needsDeepThinking(_ q: String) -> Bool {
        if q.count > 400 { return true }
        if q.contains("```") { return true }
        return has(q, deepCues)
    }

    // MARK: Kararsız sorular için yapay zeka hakemi

    /// ~1,5 sn; hata ya da 4 sn'yi aşarsa "arama yok" (aramasız yazar yine de "[ARA]" ile yükseltebilir)
    static func llmNeedsSearch(_ query: String, context: Context = .empty) async -> Bool {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = LiveScores.turkeyZone
        f.dateFormat = "d MMMM yyyy EEEE"
        let system = """
        Sen bir hakemsin. Bugün \(f.string(from: Date())). Bir yapay zeka asistanının kullanıcının SON mesajını cevaplamak için \
        web araması yapması gerekip gerekmediğine karar ver. Asistanın bilgisi aylar/yıllar öncesine ait; o tarihten sonraki \
        olayları, maçları, ürünleri, görev değişikliklerini bilmez.
        SADECE JSON yaz: {"search": true} ya da {"search": false}

        true:
        - Cevap zamanla değişiyorsa: bugünkü/yaklaşan/yakın geçmişteki olaylar, maç, fikstür, skor, kadro, fiyat, kur, haber, hava.
        - Gerçek bir kişinin/kurumun/takımın/ürünün ŞU ANKİ durumu (kim yönetiyor, hangi sürüm, ne zaman çıkıyor, hâlâ var mı).
        - Asistanın tanımayabileceği yeni bir isim, ürün, oyun, dizi, olay, uygulama geçiyorsa.
        - Kullanıcı, önceki turdaki güncel bir bilgiye itiraz ediyor ya da onun devamını soruyorsa ("emin misin", "saat kaçta").
        false:
        - Genel bilgi, tanım, bilim, tarih, coğrafya, doğa, tarif, dil, çeviri, matematik, kod, tavsiye, yaratıcı yazı, sohbet.
        - Kullanıcının kendisiyle ilgili sohbet ya da asistana verdiği bir görev/hatırlatıcı.
        """
        var prompt = ""
        if let lastUser = context.lastUser, !lastUser.isEmpty {
            prompt += "Önceki kullanıcı mesajı: \"\(lastUser.prefix(300))\"\n"
        }
        if let lastAssistant = context.lastAssistant, !lastAssistant.isEmpty {
            prompt += "Asistanın önceki cevabı\(context.lastAnswerWasSearched ? " (web aramasıyla yazılmıştı)" : ""): \"\(lastAssistant.prefix(400))\"\n"
        }
        prompt += "SON MESAJ: \"\(query.prefix(1000))\""
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                guard let raw = try? await GeminiService.shared.generateContent(
                    prompt: prompt, systemPrompt: system, maxOutputTokens: 300,
                    responseMimeType: "application/json", timeout: 6, thinking: "minimal") else { return false }
                return raw.replacingOccurrences(of: " ", with: "").contains("\"search\":true")
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return nil      // süre doldu
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
    }
}
