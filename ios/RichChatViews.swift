import SwiftUI

// MARK: - Zengin Sohbet Parçaları
//
// Cevaplar sadece düz metin değil: konuya ait gerçek görseller (Wikipedia), web kaynakları,
// seçenekli sorular (yazma çubuğunun üstünde anket gibi) ve yeni sohbette devam önerileri.

// MARK: Konu görselleri (Wikipedia)

/// Yapay zekanın [IMAGES: …] ile verdiği konu adlarından gerçek fotoğraf bulur.
/// Modelin uydurduğu adresler değil, Wikipedia'nın sayfa özetindeki görsel kullanılır → kırık görsel yok.
actor WikiImageLoader {
    static let shared = WikiImageLoader()
    private var cache: [String: URL?] = [:]

    /// Denenecek adresler: önce 960 px (net), olmazsa Wikipedia'nın verdiği küçük boy
    /// (orijinali 960 px'ten küçük görsellerde büyük boy hata veriyor ve görsel sessizce düşüyordu)
    func imageURLs(for topic: String) async -> [URL] {
        guard let first = await imageURL(for: topic) else { return [] }
        var urls = [first]
        if let original = originals[topic], original != first { urls.append(original) }
        return urls
    }

    private var originals: [String: URL] = [:]

    func imageURL(for topic: String) async -> URL? {
        if let hit = cache[topic] { return hit }
        var found: URL?
        // Konular İngilizce Wikipedia başlığı olarak istenir (ör. "Granny Smith"); Türkçe başlıklar için tr de denenir.
        // (ESKİ: önce tr deneniyordu → "Apple" Türkçe'de şirket sayfası → elma yerine Apple Park fotoğrafı)
        for lang in ["en", "tr"] {
            let title = topic.replacingOccurrences(of: " ", with: "_")
            guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)?redirect=true") else { continue }
            var request = URLRequest(url: url)
            request.setValue("PufyAgent/1.1 (iOS)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 8
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // Küçük resmi 960px'e büyüt (orijinal birkaç MB olabilir; Wikimedia sadece standart boyutları kabul eder: 800 → 400 hatası, 960 → çalışıyor)
            var source = (json["thumbnail"] as? [String: Any])?["source"] as? String
            if let thumb = source {
                if !thumb.lowercased().contains(".svg"), let original = URL(string: thumb) { originals[topic] = original }
                source = thumb.replacingOccurrences(of: "/\\d+px-", with: "/960px-", options: .regularExpression)
            } else {
                source = (json["originalimage"] as? [String: Any])?["source"] as? String
            }
            if let source, let imageURL = URL(string: source),
               !source.lowercased().hasSuffix(".svg") {          // logolar/haritalar (svg) atlanır
                found = imageURL
                break
            }
        }
        if found == nil { found = await commonsSearch(topic) }
        cache[topic] = found
        return found
    }

    /// Wikipedia'da sayfası olmayan özel konular için ("orange tabby cat") Wikimedia Commons görsel araması
    private func commonsSearch(_ query: String) async -> URL? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrlimit=6&gsrsearch=\(q)&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=960") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("PufyAgent/1.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (json["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] else { return nil }
        let ordered = pages.values.sorted { ($0["index"] as? Int ?? 99) < ($1["index"] as? Int ?? 99) }
        for page in ordered {
            guard let info = (page["imageinfo"] as? [[String: Any]])?.first,
                  let mime = info["mime"] as? String, ["image/jpeg", "image/png", "image/webp"].contains(mime),
                  let thumb = (info["thumburl"] as? String) ?? (info["url"] as? String) else { continue }
            return URL(string: thumb)
        }
        return nil
    }
}

// MARK: Akış içi görsel ([IMG: konu | açıklama])

private struct ImageTapKey: EnvironmentKey {
    static let defaultValue: ((UIImage) -> Void)? = nil
}

extension EnvironmentValues {
    /// Cevap içindeki görsele dokununca tam ekran açmak için
    var pufyImageTap: ((UIImage) -> Void)? {
        get { self[ImageTapKey.self] }
        set { self[ImageTapKey.self] = newValue }
    }
}

/// Cevabın tam ilgili yerinde gösterilen görsel (ör. "erkek kedi" paragrafından hemen sonra)
struct InlineTopicImage: View {
    let topic: String
    let caption: String?
    var height: CGFloat = 210
    @Environment(\.pufyImageTap) private var onTap
    @State private var image: UIImage?
    /// Görselin adresi bulundu mu? Bulunana kadar HİÇBİR ŞEY gösterilmez (eskiden iskelet çıkıp sonra kayboluyordu)
    @State private var resolved = false
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                VStack(alignment: .leading, spacing: 6) {
                    // ESKİ HATA (kullanıcı, 15 Ekim 2026: "Fuji Dağı görseli sağdan taşmış, sığmamış"): doldurma ölçekli
                    // görsel çerçeveyi kendi genişliğine büyütüyordu; panoramalarda (4:1) kutu ekranın dışına taşıyordu.
                    // Görsel artık yerleşime girmeyen bir katman olarak çiziliyor, kutu her zaman ekran genişliğinde.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onTapGesture { onTap?(image) }
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            } else if resolved && !failed {
                ImageSkeleton(height: height)
                    .transition(.opacity)
            } else {
                // ESKİ HATA: burası boştu → SwiftUI boş görünümü ekrana hiç koymadığı için aşağıdaki .task HİÇ
                // çalışmıyor, görsel hiç istenmiyordu (sohbet görselleri bu yüzden kaybolmuştu). Görünmez 1 pt yer tutucu.
                Color.clear.frame(height: 1)
            }
        }
        .animation(SmoothSpring.fade, value: image != nil)
        .animation(SmoothSpring.fade, value: resolved)
        .task(id: topic) {
            guard image == nil else { return }
            let urls = await WikiImageLoader.shared.imageURLs(for: topic)
            if Task.isCancelled { return }      // akış sırasında görünüm yenilendi: başarısız sayma, tekrar denenir
            guard !urls.isEmpty else {
                failed = true   // bulunamazsa hiç yer kaplamaz
                return
            }
            resolved = true
            for url in urls {
                var request = URLRequest(url: url)
                request.setValue("PufyAgent/1.1 (iOS)", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200, let loaded = UIImage(data: data) {
                    image = loaded
                    return
                }
                if Task.isCancelled { return }
            }
            failed = true
        }
    }
}

/// [IMGS] galerisi: her öğenin kendi görseli, eşit kutularda (2-3 sütun; fazlası yatay kaydırılır)
struct TopicGallery: View {
    let items: [(topic: String, caption: String?)]

    var body: some View {
        if items.count <= 3 {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    InlineTopicImage(topic: item.topic, caption: item.caption, height: items.count == 1 ? 210 : (items.count == 2 ? 150 : 112))
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        InlineTopicImage(topic: item.topic, caption: item.caption, height: 120)
                            .frame(width: 130, alignment: .top)
                    }
                }
            }
            .scrollClipDisabled18()
        }
    }
}

struct TopicImagesView: View {
    let topics: [String]
    let onTap: (UIImage) -> Void

    @State private var images: [(topic: String, image: UIImage)] = []

    var body: some View {
        Group {
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(images, id: \.topic) { item in
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: images.count == 1 ? 280 : 190, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Text(item.topic)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(.black.opacity(0.45)))
                                        .padding(8)
                                }
                                .onTapGesture { onTap(item.image) }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
                .scrollClipDisabled18()
            }
        }
        .animation(SmoothSpring.standard, value: images.count)
        .task(id: topics) { await load() }
    }

    private func load() async {
        for topic in topics where !images.contains(where: { $0.topic == topic }) {
            guard let url = await WikiImageLoader.shared.imageURL(for: topic),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { continue }
            images.append((topic, image))
        }
    }
}

private extension View {
    @ViewBuilder
    func scrollClipDisabled18() -> some View {
        if #available(iOS 17, *) { self.scrollClipDisabled() } else { self }
    }
}

// MARK: Kaynak çipleri

struct SourceChips: View {
    let sources: [WebSource]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources.prefix(8), id: \.self) { source in
                    Button {
                        if let url = URL(string: source.url) { openURL(url) }
                    } label: {
                        HStack(spacing: 6) {
                            AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(source.host)&sz=64")) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit()
                                } else {
                                    Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(source.host)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(UIColor.secondarySystemBackground)))
                    }
                    .buttonStyle(PremiumScaleButtonStyle())
                }
            }
        }
    }
}

// MARK: Seçenekli sorular (anket)

/// Yapay zeka birden fazla soru sorduğunda: yazma çubuğunun üstünde dokunulabilir seçenekler.
/// Tek seçimli tek soru → seçeneğe dokununca hemen gönderilir. Çoklu seçim ya da birden fazla soru → seç, "Gönder".
/// Çoklu seçim: model "multi": true dediğinde YA DA soru birden fazla cevap gerektiriyorsa
/// ("Evde nelerin var?", "Hangi malzemeler…") — model işaretlemeyi unutsa da çoklu seçim açılır.
struct ChoicePanel: View {
    let prompt: ChoicePrompt
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void
    var onCollapse: (() -> Void)? = nil
    /// Panel en fazla bu kadar uzar; fazlası kendi içinde kayar (mesajın üstünü kapatmasın)
    var maxQuestionsHeight: CGFloat = UIScreen.main.bounds.height * 0.36

    @State private var answers: [Int: [String]] = [:]
    @State private var questionsHeight: CGFloat = 0

    private var isSingleQuick: Bool {
        prompt.questions.count == 1 && !Self.isMulti(prompt.questions[0])
    }

    /// Soru birden fazla cevaba açık mı?
    static func isMulti(_ question: ChoicePrompt.Question) -> Bool {
        if let multi = question.multi, multi { return true }
        let q = question.q.lowercased(with: Locale(identifier: "tr_TR"))
        let cues = ["neler", "hangileri", "birden fazla", "birden çok", "seçebilirsin", "hepsini", "which ones", "select all"]
        if cues.contains(where: { q.contains($0) }) { return true }
        // "hangi malzemeler", "hangi günler" → çoğul isim
        if let regex = try? NSRegularExpression(pattern: "hangi\\s+\\p{L}+(ler|lar)\\b"),
           regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                questions
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ChoiceHeightKey.self, value: geo.size.height)
                    })
            }
            .frame(height: min(max(questionsHeight, 1), maxQuestionsHeight))
            .onPreferenceChange(ChoiceHeightKey.self) { questionsHeight = $0 }
            .scrollIndicators(questionsHeight > maxQuestionsHeight ? .automatic : .hidden)

            submitButton
        }
        .padding(16)
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(prompt.questions.prefix(3).enumerated()), id: \.offset) { index, question in
                let multi = Self.isMulti(question)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(question.q)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if multi {
                                Text("Birden fazla seçebilirsin")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if index == 0 {
                            if let onCollapse {
                                Button(action: onCollapse) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 26, height: 26)
                                }
                                .accessibilityLabel(String(localized: "Seçenekleri küçült"))
                            }
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, height: 26)
                            }
                            .accessibilityLabel(String(localized: "Seçenekleri kapat"))
                        }
                    }
                    // Simetrik ızgara: kısa seçenekler eşit genişlikte yan yana (3 → tek satır, 4 → 2x2),
                    // uzun seçenekler alt alta tam genişlik. (Eskiden akış düzeni 2+1 diziyor, sağda boşluk kalıyordu.)
                    let options = Array(question.options.prefix(multi ? 9 : 6))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns(for: options)), spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            let selected = answers[index]?.contains(option) ?? false
                            Button {
                                PremiumHaptics.light()
                                toggle(option, at: index, multi: multi)
                            } label: {
                                HStack(spacing: 5) {
                                    if multi && selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    Text(option)
                                        .font(.subheadline.weight(.medium))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                }
                                    .foregroundStyle(selected ? Color.pufyOnPrimary : .primary)
                                    .animation(SmoothSpring.quick, value: selected)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .padding(.horizontal, 8)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selected ? Color.pufyPrimary : Color(UIColor.secondarySystemBackground)))
                            }
                            .buttonStyle(PremiumScaleButtonStyle())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var submitButton: some View {
        if !isSingleQuick {
            Button {
                PremiumHaptics.medium()
                onSubmit(composedAnswer)
            } label: {
                Text("Gönder")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.pufyOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(answers.isEmpty ? Color.pufyDisabled : Color.pufyPrimary))
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .disabled(answers.isEmpty)
        }
    }

    /// Satıra kaç seçenek: hepsi kısaysa 2-3 sütun (boşluk bırakmayacak şekilde), uzunsa tek sütun
    static func columns(for options: [String]) -> Int {
        let longest = options.map(\.count).max() ?? 0
        let count = options.count
        guard count > 1 else { return 1 }
        if count == 2 { return longest <= 22 ? 2 : 1 }
        // Satırlar hep dolu kalsın: sadece tam bölünen sütun sayıları (3 → 3, 4 → 2x2, 6 → 3x2, 8 → 2x4, 9 → 3x3)
        if count % 3 == 0, longest <= 11 { return 3 }
        if count % 2 == 0, longest <= 18 { return 2 }
        return 1   // 5, 7 gibi: 3+2 asimetrik kalmasın, alt alta
    }

    private func toggle(_ option: String, at index: Int, multi: Bool) {
        if isSingleQuick {
            onSubmit(option)
            return
        }
        var current = answers[index] ?? []
        if multi {
            if current.contains(option) { current.removeAll { $0 == option } } else { current.append(option) }
        } else {
            current = current == [option] ? [] : [option]
        }
        answers[index] = current.isEmpty ? nil : current
    }

    private var composedAnswer: String {
        prompt.questions.prefix(3).enumerated().compactMap { index, q in
            guard let picked = answers[index], !picked.isEmpty else { return nil }
            return "\(q.q) \(picked.joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}

/// Satıra sığmayanı alta kaydıran basit akış yerleşimi (seçenek çipleri için)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: Yeni sohbet önerileri

/// Son sohbetlerin sonunda yapay zekanın kaydettiği devam soruları (en fazla 3)
struct FollowUpSuggestions: View {
    let items: [(title: String, question: String)]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kaldığın yerden")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    PremiumHaptics.light()
                    onPick(item.question)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.question)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
                }
                .buttonStyle(PremiumCardButtonStyle())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

/// Görsel yüklenirken: yazısız, üzerinden ışık geçen iskelet + nefes alan küçük görsel simgesi
struct ImageSkeleton: View {
    var height: CGFloat = 210
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date()

    // ESKİ: onAppear içinde repeatForever animasyonu, kaydırılan listede bütün görünümü kaydırabiliyordu
    // (bozuk hüzme). Şimdi zamanla çizilen, kenarsız bir parıltı.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay {
                    SweepGlow(phase: (t / 1.6).truncatingRemainder(dividingBy: 1),
                              intensity: scheme == .dark ? 0.08 : 0.45)
                }
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .opacity(0.55 + 0.35 * sin(t * 3))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(height: height)
        .accessibilityLabel(String(localized: "Görsel yükleniyor"))
    }
}

/// Kenarsız parıltı: görünümün tamamını kaplayan çapraz degrade, parlak bant `phase` (0…1) ile kayar
struct SweepGlow: View {
    let phase: Double
    var intensity: Double = 0.2

    var body: some View {
        let center = -0.3 + phase * 1.6      // bant görünümün dışından girip dışından çıkar
        let width = 0.22
        LinearGradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: max(0, min(1, center - width))),
            .init(color: .white.opacity(intensity), location: max(0, min(1, center))),
            .init(color: .white.opacity(0), location: max(0, min(1, center + width))),
            .init(color: .white.opacity(0), location: 1)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Görsel üretiliyor kartı
//
// Kullanıcı isteği (13 Ekim 2026): görsel oluşturulurken "yazıyor" göstergesi değil, ChatGPT/Gemini'deki gibi
// içinde desen animasyonu olan bir kart. Tek renkli (siyah-beyaz) tasarım:
//  • nokta ızgarası, köşegen bir dalgayla nefes alır
//  • yumuşak bir ışık lekesi kartın içinde gezinir, zamanla büyür ("görsel oluşuyor" hissi)
//  • üstünden ince bir parıltı geçer; altta durum yazısı ve geçen süre

struct ImageGeneratingCard: View {
    var width: CGFloat = 280

    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static var phrases: [String] {
        [
            String(localized: "Görsel oluşturuluyor…"),
            String(localized: "Ayrıntılar ekleniyor…"),
            String(localized: "Son rötuşlar yapılıyor…")
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            let phraseIndex = t < 8 ? 0 : (t < 18 ? 1 : 2)

            ZStack(alignment: .bottomLeading) {
                Color(UIColor.secondarySystemBackground)

                Canvas { context, size in
                    // Gezinen, zamanla büyüyen ışık
                    let grow = min(1, t / 20)
                    let light = CGPoint(x: size.width * (0.5 + 0.28 * cos(t * 0.55)),
                                        y: size.height * (0.45 + 0.22 * sin(t * 0.75)))
                    let radius = size.width * (0.45 + 0.35 * grow)
                    context.fill(
                        Path(ellipseIn: CGRect(x: light.x - radius, y: light.y - radius, width: radius * 2, height: radius * 2)),
                        // Açık modda ışık gölge gibi kirli görünmesin diye daha hafif
                        with: .radialGradient(Gradient(colors: [Color.primary.opacity(scheme == .dark ? 0.16 : 0.06), Color.primary.opacity(0)]),
                                              center: light, startRadius: 0, endRadius: radius))

                    // Nokta ızgarası: köşegen dalga + ışığa yakın noktalar daha belirgin
                    let spacing: CGFloat = 14
                    let cols = Int(size.width / spacing) + 1
                    let rows = Int(size.height / spacing) + 1
                    for row in 0..<rows {
                        for col in 0..<cols {
                            let x = CGFloat(col) * spacing + spacing / 2
                            let y = CGFloat(row) * spacing + spacing / 2
                            let diagonal = Double(x + y) / Double(size.width + size.height)
                            let wave = 0.5 + 0.5 * sin(t * 2.4 - diagonal * 10)
                            let distance = hypot(x - light.x, y - light.y) / radius
                            let near = max(0, 1 - Double(distance))
                            let r = 0.8 + 1.9 * CGFloat(wave * 0.6 + near * 0.4)
                            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                         with: .color(Color.primary.opacity(0.07 + 0.28 * (wave * 0.5 + near * 0.5))))
                        }
                    }
                }

                // Kartın üstünden geçen ince parıltı — kartın tamamını kaplayan, durakları kayan bir degrade
                // (ESKİ: döndürülmüş dar bir şerit kaydırılıyordu; kenarları görünüp "bozuk hüzme" gibi duruyordu)
                SweepGlow(phase: (t / 2.8).truncatingRemainder(dividingBy: 1),
                          intensity: scheme == .dark ? 0.14 : 0.5)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    ShimmerText(text: Self.phrases[phraseIndex], font: .footnote.weight(.semibold))
                        .id(phraseIndex)
                        .transition(.opacity)
                    Spacer(minLength: 6)
                    Text("\(Int(t)) " + (AppLanguage.isEnglish ? "s" : "sn"))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
                .animation(SmoothSpring.standard, value: phraseIndex)
            }
        }
        .frame(width: width, height: width)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Görsel oluşturuluyor"))
    }
}

private struct ChoiceHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
