import Foundation

// MARK: - Hava durumu (hızlı yol)
//
// Kullanıcı (15 Ekim 2026): "Hava durumu sorduğumda da uzun bekliyor; basit şeylerde uzun düşünmesin."
// Eskiden "bugün hava nasıl" → Google araması (~5-8 sn). Artık konum Kişisel Ağ'dan (ör. "Ataşehir'de yaşıyor") ya da
// sorudaki şehirden alınır, Open-Meteo'dan anlık + 7 günlük tahmin çekilir (~0,4 sn) ve yönergeye eklenir; yazar aramasız
// ve kısa düşünmeyle cevaplar. Yer bulunamazsa ya da soru başka bir güncel konu da içeriyorsa eski yol (arama) kullanılır.

enum WeatherService {
    struct Place: Codable {
        var name: String
        var region: String?
        var country: String?
        var latitude: Double
        var longitude: Double
    }

    private static let tr = Locale(identifier: "tr_TR")

    private static let weatherCues = [
        "hava durumu", "hava nasıl", "havalar", "havası", "havada ", "hava kaç", "hava ", "yağmur", "kar yağ", "kar var",
        "şemsiye", "kaç derece", "sıcaklık", "rüzgar", "fırtına", "dolu yağ", "güneşli mi", "bulutlu"
    ]
    /// "hava" geçen ama hava durumu olmayan sorular
    private static let notWeatherCues = [
        "hava yolu", "hava yolları", "havayolu", "havaalanı", "hava limanı", "havalimanı", "hava kirliliği", "hava kuvvet",
        "hava fritöz", "airfryer", "klima", "hava atmak", "hava atıyor", "havalı"
    ]

    /// Sorudaki yer olmayan kelimeler (kalan kelimeler yer adı olabilir → coğrafi aramaya gider)
    private static let stopWords: Set<String> = [
        "bugün", "bugünkü", "yarın", "yarınki", "öbür", "ertesi", "gün", "günü", "günler", "hafta", "haftaya", "haftası",
        "sonu", "sonunda", "akşam", "akşamki", "sabah", "sabahki", "öğle", "öğlen", "öğleden", "gece", "geceki", "şimdi",
        "şu", "an", "anda", "bu", "o", "ne", "neler", "nasıl", "olacak", "olur", "oluyor", "mu", "mı", "mü", "mi", "kaç",
        "derece", "hava", "havalar", "havası", "havada", "durumu", "durum", "yağmur", "yağmurlu", "yağacak", "yağar",
        "yağıyor", "kar", "karlı", "şemsiye", "alayım", "almalı", "almalıyım", "lazım", "sıcaklık", "sıcaklığı", "rüzgar",
        "rüzgarlı", "fırtına", "var", "için", "de", "da", "ki", "bana", "söyle", "söyler", "bak", "bakar", "peki", "ya",
        "acaba", "burada", "burda", "evde", "dışarı", "dışarıda", "saat", "saatte", "kaçta", "pazartesi", "salı",
        "çarşamba", "perşembe", "cuma", "cumartesi", "pazar", "ay", "yüzde", "ihtimal", "ihtimali", "olasılık", "soğuk",
        "sıcak", "serin", "ılık", "nem", "nemli", "güneşli", "güneş", "bulutlu", "bulut", "mont", "ceket", "giy",
        "giyeyim", "giymeli", "çıkacağım", "çıkıcam", "gideceğim", "gidicem", "gideceğiz", "dolu", "fazla", "çok", "biraz",
        "durumunu", "verir", "misin", "musun", "lütfen", "bi", "bir", "nedir", "ve", "ile", "sonra", "önce", "kadar",
        "boyunca", "günlük", "haftalık", "tahmin", "tahmini", "nası", "naber", "dün", "dünkü", "hafta", "gelecek",
        "önümüzdeki", "iyi", "kötü", "güzel", "uygun", "mıdır", "midir", "olacakmış", "yağacakmış", "kaçtan", "kaça",
        "benim", "bizim", "orada", "orda", "orası", "burası", "sence", "acil", "şemsiyeye", "gerek", "dışarda", "evden"
    ]

    static func isWeatherQuery(_ query: String) -> Bool {
        let q = query.lowercased(with: tr) + " "
        return has(q, weatherCues) && !has(q, notWeatherCues)
    }

    /// Hava verisi bloğu (yer bulunamazsa nil → normal yol)
    static func promptBlock(for query: String, history: [Message]) async -> String? {
        var weatherQuery = isWeatherQuery(query)
        // "peki yarın?" gibi kısa devam soruları
        if !weatherQuery, query.split(separator: " ").count <= 4,
           let lastUser = history.last(where: { $0.role == .user })?.content, isWeatherQuery(lastUser) {
            weatherQuery = true
        }
        guard weatherQuery else { return nil }

        let place: Place?
        let candidates = placeCandidates(in: query)
        if candidates.isEmpty {
            place = await homePlace()
        } else {
            // Soruda başka bir yer adı var: bulunamazsa tahmin etme, normal yola (aramaya) bırak
            var found: Place?
            search: for variants in candidates.prefix(2) {
                for word in variants {
                    if let p = await geocode(word) { found = p; break search }
                }
            }
            guard let found else { return nil }
            place = found
        }
        guard let place, let forecast = await fetchForecast(place) else { return nil }
        return forecast
    }

    // MARK: Konum

    /// Kişisel Ağ'daki yaşadığı yer ("Ataşehir'de yaşıyor")
    private static func homePlace() async -> Place? {
        let items = await MainActor.run { MemoryStore.shared.items }
        let homeWords = ["yaşıyor", "yaşar", "oturuyor", "ikamet", "evi ", "evim", "yaşadığı", "oturduğu", "konum"]
        let ranked = items.filter { item in
            let all = (item.text + " " + item.detail).lowercased(with: tr) + " "
            return homeWords.contains { all.contains($0) }
        } + items.filter { $0.resolvedCategory == .places }
        var tried = Set<String>()
        for item in ranked {
            for name in placeNames(in: item) where tried.insert(name.lowercased(with: tr)).inserted {
                if let p = await geocode(name) { return p }
                if tried.count >= 4 { return nil }
            }
        }
        return nil
    }

    /// "İstanbul Ataşehir'de yaşıyor" → ["Ataşehir", "İstanbul"]
    private static func placeNames(in item: MemoryItem) -> [String] {
        var names: [String] = []
        for source in [item.entity ?? "", item.detail, item.text] {
            let words = source.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’"))))
            for raw in words where !raw.isEmpty {
                let word: String
                if let apostrophe = raw.firstIndex(where: { $0 == "'" || $0 == "’" }) {
                    word = String(raw[..<apostrophe])
                } else {
                    word = raw
                }
                guard let first = word.first, first.isUppercase, word.count >= 3,
                      !["Kullanıcı", "Kullanıcının", "Kendisi", "Ev", "Evi"].contains(word) else { continue }
                // Yer adı genelde "'de/'da" ile yazılır → öne al
                if raw.contains("'") || raw.contains("’") { names.insert(word, at: 0) } else { names.append(word) }
            }
        }
        return names
    }

    /// Sorudaki muhtemel yer adları, her biri için denenecek yazımlarla ("izmirde hava nasıl" → [["izmirde", "izmir"]])
    private static func placeCandidates(in query: String) -> [[String]] {
        let words = query.lowercased(with: tr)
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'’")).inverted)
            .filter { !$0.isEmpty }
        var result: [[String]] = []
        for raw in words {
            var word = raw
            let hadApostrophe = word.contains("'") || word.contains("’")
            if let apostrophe = word.firstIndex(where: { $0 == "'" || $0 == "’" }) {
                word = String(word[..<apostrophe])
            }
            guard word.count >= 3, !stopWords.contains(word), !stopWords.contains(raw) else { continue }
            var variants = [word]
            if !hadApostrophe {
                // Kesme işaretsiz yazılan ekler: izmirde, ankarada, bodruma değil ama kadıköydeki, antalyaya
                for suffix in ["deki", "daki", "teki", "taki", "de", "da", "te", "ta", "ya", "ye"] where word.hasSuffix(suffix) {
                    let stem = String(word.dropLast(suffix.count))
                    if stem.count >= 3, !stopWords.contains(stem) { variants.append(stem) }
                    break
                }
            }
            result.append(variants)
        }
        return result
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased(with: tr).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: tr)
            .replacingOccurrences(of: "ı", with: "i")
    }

    private static let cacheKey = "pufy_geocode_cache_v1"

    /// Open-Meteo yer arama. Sadece adı birebir tutan ve önemli yerler (il/ilçe/başkent ya da ≥10 bin nüfus) kabul edilir —
    /// "maç" → "Maçka" ya da küçük bir köy gibi yanlış eşleşmeler olmasın.
    private static func geocode(_ name: String) async -> Place? {
        let key = normalized(name)
        var cache = (UserDefaults.standard.data(forKey: cacheKey))
            .flatMap { try? JSONDecoder().decode([String: Place].self, from: $0) } ?? [:]
        if let hit = cache[key] { return hit }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "10"),
                                 URLQueryItem(name: "language", value: "tr"), URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        let important: Set<String> = ["PPLC", "PPLA", "PPLA2", "PPLA3", "ADM1", "ADM2", "ADM3"]
        let best = results.filter { r in
            guard let n = r["name"] as? String, normalized(n) == key else { return false }
            let population = r["population"] as? Int ?? 0
            return important.contains(r["feature_code"] as? String ?? "") || population >= 10_000
        }.max { ($0["population"] as? Int ?? 0) < ($1["population"] as? Int ?? 0) }

        guard let best, let lat = best["latitude"] as? Double, let lon = best["longitude"] as? Double,
              let placeName = best["name"] as? String else { return nil }
        let place = Place(name: placeName, region: best["admin1"] as? String, country: best["country"] as? String,
                          latitude: lat, longitude: lon)
        cache[key] = place
        if let encoded = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(encoded, forKey: cacheKey) }
        return place
    }

    // MARK: Tahmin

    private static func fetchForecast(_ place: Place) async -> String? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "forecast_hours", value: "36")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let daily = json["daily"] as? [String: Any] else { return nil }

        func num(_ v: Any?) -> String {
            guard let d = v as? Double ?? (v as? Int).map(Double.init) else { return "?" }
            return String(Int(d.rounded()))
        }
        func array(_ dict: [String: Any], _ key: String) -> [Any] { dict[key] as? [Any] ?? [] }

        let timezone = json["timezone"] as? String ?? "Europe/Istanbul"
        let isTurkey = timezone == "Europe/Istanbul"
        let where_ = [place.name, place.region == place.name ? nil : place.region, isTurkey ? nil : place.country]
            .compactMap { $0 }.joined(separator: ", ")

        var lines: [String] = []
        lines.append("HAVA DURUMU VERİSİ — \(where_) için Open-Meteo'dan ŞU AN çekildi (saatler \(isTurkey ? "TSİ" : "oranın yerel saati, \(timezone)")). Hava sorusunu BUNA göre cevapla, web araması gerekmez:")
        lines.append("- Şu an: \(num(current["temperature_2m"]))°C (hissedilen \(num(current["apparent_temperature"]))°C), \(describe(current["weather_code"])), nem %\(num(current["relative_humidity_2m"])), rüzgar \(num(current["wind_speed_10m"])) km/s, yağış \(current["precipitation"] as? Double ?? 0) mm")

        // Önümüzdeki saatler (3 saatte bir, ~30 saat)
        if let hourly = json["hourly"] as? [String: Any] {
            let times = array(hourly, "time"), temps = array(hourly, "temperature_2m")
            let rain = array(hourly, "precipitation_probability"), codes = array(hourly, "weather_code")
            var parts: [String] = []
            for i in stride(from: 0, to: times.count, by: 3) {
                guard let t = times[i] as? String, i < temps.count else { continue }
                let clock = t.split(separator: "T").last.map(String.init) ?? t
                let day = t.prefix(10)
                parts.append("\(day == (times.first as? String)?.prefix(10) ? "" : "ertesi gün ")\(clock) \(num(temps[i]))°C \(describe(i < codes.count ? codes[i] : nil)) yağış %\(num(i < rain.count ? rain[i] : nil))")
            }
            if !parts.isEmpty { lines.append("- Saatlik: " + parts.joined(separator: " · ")) }
        }

        // Günlük (7 gün)
        let days = array(daily, "time")
        let dayFormatter = DateFormatter()
        dayFormatter.locale = tr
        dayFormatter.dateFormat = "d MMMM EEEE"
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: timezone)
        dayFormatter.timeZone = parser.timeZone
        for (i, d) in days.enumerated() {
            guard let s = d as? String else { continue }
            let label = parser.date(from: s).map { dayFormatter.string(from: $0) } ?? s
            let prefix = i == 0 ? "Bugün" : i == 1 ? "Yarın" : label
            let sunrise = (array(daily, "sunrise")[safe: i] as? String)?.split(separator: "T").last.map(String.init)
            let sunset = (array(daily, "sunset")[safe: i] as? String)?.split(separator: "T").last.map(String.init)
            var line = "- \(prefix)\(i <= 1 ? " (\(label))" : ""): \(describe(array(daily, "weather_code")[safe: i])), \(num(array(daily, "temperature_2m_min")[safe: i]))–\(num(array(daily, "temperature_2m_max")[safe: i]))°C, yağış olasılığı %\(num(array(daily, "precipitation_probability_max")[safe: i])) (\(num(array(daily, "precipitation_sum")[safe: i])) mm), rüzgar en fazla \(num(array(daily, "wind_speed_10m_max")[safe: i])) km/s"
            if i == 0, let sunrise, let sunset { line += ", gün doğumu \(sunrise), gün batımı \(sunset)" }
            lines.append(line)
        }
        lines.append("Cevap: kısa ve doğal (2-4 cümle); sorulan zamana odaklan, gerekiyorsa pratik öneri ver (şemsiye, mont). Konumu bir kez söyle. Kart, görsel ya da kaynak listesi ekleme.")
        return lines.joined(separator: "\n")
    }

    /// WMO hava kodu → Türkçe
    private static func describe(_ value: Any?) -> String {
        guard let code = value as? Int ?? (value as? Double).map({ Int($0) }) else { return "?" }
        switch code {
        case 0: return "açık"
        case 1: return "çoğunlukla açık"
        case 2: return "parçalı bulutlu"
        case 3: return "kapalı"
        case 45, 48: return "sisli"
        case 51, 53, 55: return "çisenti"
        case 56, 57: return "dondurucu çisenti"
        case 61: return "hafif yağmurlu"
        case 63: return "yağmurlu"
        case 65: return "kuvvetli yağmurlu"
        case 66, 67: return "dondurucu yağmur"
        case 71: return "hafif kar yağışlı"
        case 73: return "kar yağışlı"
        case 75: return "yoğun kar yağışlı"
        case 77: return "kar taneli"
        case 80: return "hafif sağanak"
        case 81: return "sağanak yağışlı"
        case 82: return "şiddetli sağanak"
        case 85, 86: return "kar sağanaklı"
        case 95: return "gök gürültülü fırtına"
        case 96, 99: return "dolulu fırtına"
        default: return "değişken"
        }
    }

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
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
