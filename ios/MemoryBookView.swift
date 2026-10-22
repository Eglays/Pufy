import SwiftUI

// MARK: - Kişisel Ağ
//
// Eski ekran: koyu mor zemin, eşit halkalara dizilmiş "nöronlar", her düğümde rastgele
// bir sparkle ikonu — bilgiler arasında hiçbir yapı yoktu.
// Yeni ekran: Sen merkezdesin → hayatının alanları (İnsanlar, İlgi Alanları, Beceriler…) →
// her alanın kendi bilgileri. İnsanlar baş harfleriyle, ilişkileriyle görünür. Önemli bilgiler
// merkeze yakın ve daha belirgin. Yanında aranabilir liste görünümü ve öğrenme durumu var.

struct MemoryBookView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var store = MemoryStore.shared
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case graph, list

        var title: LocalizedStringKey {
            switch self {
            case .graph: return "Ağ"
            case .list: return "Liste"
            }
        }
    }

    @State private var mode: Mode = .graph
    @State private var selected: MemoryItem?
    @State private var focus: MemoryCategory?
    @State private var editing: MemoryItem?
    @State private var showAdd = false
    @State private var confirmReset = false
    @State private var query = ""
    @AppStorage("hint_memory_shown") private var hintMemoryShown = false
    @State private var showMemoryHint = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if showMemoryHint {
                    HintBubbleView(text: "Pufy sohbet ettikçe seni tanır. Bir bilgiye dokunup düzenleyebilir ya da silebilirsin.") {
                        hintMemoryShown = true
                        withAnimation(SmoothSpring.standard) { showMemoryHint = false }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !store.items.isEmpty {
                    Picker("Görünüm", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                if store.items.isEmpty {
                    emptyState
                } else if mode == .graph {
                    MemoryGraphView(
                        items: store.items,
                        userName: viewModel.userName,
                        avatarData: viewModel.userProfileImageData,
                        traces: store.traces,
                        onTracesShown: { store.clearTraces() },
                        selected: $selected,
                        focus: $focus
                    )
                    .overlay(alignment: .bottom) {
                        if let item = selected, let live = store.items.first(where: { $0.id == item.id }) {
                            MemoryDetailCard(item: live,
                                             onEdit: { editing = live },
                                             onDelete: {
                                                 withAnimation(SmoothSpring.standard) {
                                                     store.delete(live)
                                                     selected = nil
                                                 }
                                             },
                                             onClose: { withAnimation(SmoothSpring.standard) { selected = nil } })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(SmoothSpring.standard, value: selected?.id)
                } else {
                    listView
                }
            }
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .navigationTitle("Kişisel Ağ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await store.rebuild(from: viewModel.sessions) }
                        } label: {
                            Label("Sohbetlerimden güncelle", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(store.rebuildProgress != nil)
                        Button {
                            showAdd = true
                        } label: {
                            Label("Bilgi ekle", systemImage: "plus")
                        }
                        Divider()
                        Button(role: .destructive) {
                            confirmReset = true
                        } label: {
                            Label("Tümünü sil", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Seçenekler")
                }
            }
            .confirmationDialog("Pufy'nin senin hakkında bildiği her şey silinsin mi?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Tümünü Sil", role: .destructive) {
                    store.resetAll()
                    viewModel.saveMemory(ChatViewModel.emptyMemoryText)
                    selected = nil
                }
            }
            .sheet(item: $editing) { item in
                MemoryEditorView(item: item) { store.update($0) }
            }
            .sheet(isPresented: $showAdd) {
                MemoryEditorView(item: nil) { store.add($0) }
            }
            // Hafızaya işlenmemiş mesaj varsa (ör. cevabı hata vermiş) şimdi öğren — izleri haritada görünür
            .task { await store.catchUp(from: viewModel.sessions) }
            .onAppear {
                if !hintMemoryShown {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !hintMemoryShown {
                            withAnimation(SmoothSpring.standard) { showMemoryHint = true }
                        }
                    }
                }
            }
        }
    }

    // MARK: Başlık + durum

    private var header: some View {
        VStack(spacing: 6) {
            Text(viewModel.userName.isEmpty ? "Seni tanıdıklarım" : "\(viewModel.userName) hakkında bildiklerim")
                .font(.system(.title3, design: .rounded).weight(.bold))
            if !store.items.isEmpty {
                Text(statsText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            statusRow
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var statsText: String {
        let people = store.items.filter { $0.resolvedCategory == .people }.count
        let areas = Set(store.items.map(\.resolvedCategory)).count
        return "\(store.items.count) bilgi · \(people) kişi · \(areas) alan"
    }

    @ViewBuilder
    private var statusRow: some View {
        if let progress = store.rebuildProgress {
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(.pufyPrimary)
                    .frame(maxWidth: 220)
                Text("Sohbetlerin okunuyor… %\(Int(progress * 100))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } else if store.isLearning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Son mesajından öğreniyor…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let error = store.lastError {
            VStack(spacing: 4) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Tekrar dene") {
                    Task { await store.rebuild(from: viewModel.sessions) }
                }
                .font(.caption.weight(.semibold))
            }
        } else if let date = store.lastLearnedAt {
            Text("Son güncelleme \(Self.relative.localizedString(for: date, relativeTo: Date()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = AppLanguage.currentLocale
        f.unitsStyle = .full
        return f
    }()

    // MARK: Boş durum

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text("Henüz seni tanımıyorum")
                .font(.headline)
            Text("Sohbette kendinden bahsettikçe ağın kendiliğinden oluşur. Daha önce anlattıklarından hemen oluşturabilirim.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                PremiumHaptics.medium()
                Task { await store.rebuild(from: viewModel.sessions) }
            } label: {
                Label("Sohbetlerimden oluştur", systemImage: "wand.and.stars")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.pufyOnPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.pufyPrimary))
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .disabled(store.rebuildProgress != nil)
            .opacity(store.rebuildProgress != nil ? 0.5 : 1)
            Button("Kendim ekleyeyim") { showAdd = true }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Liste

    private var listView: some View {
        let filtered = query.isEmpty ? store.items : store.items.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
        let grouped = Dictionary(grouping: filtered, by: \.resolvedCategory)
        return List {
            ForEach(MemoryCategory.allCases) { category in
                if let group = grouped[category], !group.isEmpty {
                    Section {
                        ForEach(group.sorted { $0.resolvedImportance > $1.resolvedImportance }) { item in
                            Button { editing = item } label: { MemoryListRow(item: item) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) { store.delete(item) } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Label("\(category.title) · \(group.count)", systemImage: category.icon)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bilgilerde ara")
    }
}

private struct MemoryListRow: View {
    let item: MemoryItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.text).font(.body.weight(.semibold))
                    if let relation = item.relation {
                        Text(relation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.pufySoft))
                    }
                }
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ImportanceDots(value: item.resolvedImportance)
        }
        .contentShape(Rectangle())
    }
}

private struct ImportanceDots: View {
    let value: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= value ? Color.pufyPrimary : Color.pufyDisabled)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Önem \(value)/5")
    }
}

// MARK: - Ağ Görünümü

/// Yerleşim: her alan, bilgi sayısıyla orantılı bir açı dilimi alır. Alanın merkezi (hub) iç
/// çemberde; bilgileri dilimin içinde, önemliden önemsize doğru dışa açılan sıralarda.
/// Böylece kümeler birbirine karışmaz ve düğümler üst üste binmez.
/// Not: aralıklar bilerek geniş (alan 135, bilgi 245 + sıra×72). Sıkıştırılınca düğümler iç içe giriyordu.
private struct GraphLayout {
    struct Hub { let category: MemoryCategory; let position: CGPoint; let count: Int }
    /// `hub`: düğümün çıktığı nokta (kök bilgide alan, dal bilgide üst bilginin konumu); `parent`: üst bilginin sırası
    struct Leaf { let item: MemoryItem; let position: CGPoint; let hub: CGPoint; let parent: Int? }

    var hubs: [Hub] = []
    var leaves: [Leaf] = []
    /// İlişki çizgileri (leaves sıraları)
    var links: [(Int, Int)] = []
    var extent: CGFloat = 0

    init(items: [MemoryItem]) {
        let grouped = Dictionary(grouping: items, by: \.resolvedCategory)
        let categories = grouped.keys.sorted { $0.order < $1.order }
        guard !categories.isEmpty else { return }

        // 1) Dallanma: kayıtlı üst bilgi (yapay zeka "about") ya da addan çıkarılan (bkz. GraphLinks)
        let parents = GraphLinks.parents(items)
        let roots = items.filter { parents[$0.id] == nil }
        let rootGroups = Dictionary(grouping: roots, by: \.resolvedCategory)

        let totalWeight = categories.reduce(0.0) { $0 + Double(max(rootGroups[$1]?.count ?? 1, 2)) }
        // ESKİ HATA: tek alan varken (ör. yeni kurulumda sadece "Kimlik") alan düğümü tam merkeze, profil fotoğrafının
        // üstüne konuyordu. Alanlar her zaman merkezden uzakta.
        let hubRadius: Double = 135
        let spacing: Double = 108
        var angle = -Double.pi / 2
        var indexOf: [UUID: Int] = [:]

        for category in categories {
            let group = (rootGroups[category] ?? []).sorted { $0.resolvedImportance > $1.resolvedImportance }
            let span = 2 * Double.pi * Double(max(group.count, 2)) / totalWeight
            let mid = angle + span / 2
            let hub = CGPoint(x: cos(mid) * hubRadius, y: sin(mid) * hubRadius)
            hubs.append(Hub(category: category, position: hub, count: grouped[category]?.count ?? 0))

            var index = 0
            var ring = 0
            while index < group.count {
                let radius = 245 + Double(ring) * 72
                let usable = max(span - 0.18, 0.25)            // dilimler arası boşluk
                let perRing = max(1, Int(usable * radius / spacing))
                let count = min(perRing, group.count - index)
                let step = count > 1 ? min(usable / Double(count - 1), spacing / radius) : 0
                for k in 0..<count {
                    let a = mid + (Double(k) - Double(count - 1) / 2) * step
                    let p = CGPoint(x: cos(a) * radius, y: sin(a) * radius)
                    indexOf[group[index + k].id] = leaves.count
                    leaves.append(Leaf(item: group[index + k], position: p, hub: hub, parent: nil))
                    extent = max(extent, CGFloat(radius))
                }
                index += count
                ring += 1
            }
            angle += span
        }

        // 2) Dal bilgileri: üst bilgiden merkezin TERSİNE (dışa) doğru yelpaze gibi açılır, kademe kademe
        var children: [UUID: [MemoryItem]] = [:]
        for item in items { if let p = parents[item.id] { children[p, default: []].append(item) } }
        var queue = leaves.indices.map { $0 }
        var cursor = 0
        while cursor < queue.count {
            let pi = queue[cursor]; cursor += 1
            let parent = leaves[pi]
            guard let kids = children[parent.item.id]?.sorted(by: { $0.resolvedImportance > $1.resolvedImportance }) else { continue }
            let base = atan2(Double(parent.position.y), Double(parent.position.x))
            let n = kids.count
            let distance: Double = n > 3 ? 104 : 92
            let gap = min(0.42, 1.6 / Double(max(n, 1)))
            for (k, kid) in kids.enumerated() where indexOf[kid.id] == nil {
                let a = base + (Double(k) - Double(n - 1) / 2) * gap
                let p = CGPoint(x: parent.position.x + CGFloat(cos(a) * distance), y: parent.position.y + CGFloat(sin(a) * distance))
                indexOf[kid.id] = leaves.count
                queue.append(leaves.count)
                leaves.append(Leaf(item: kid, position: p, hub: parent.position, parent: pi))
                extent = max(extent, hypot(p.x, p.y))
            }
        }

        // 3) İlişki çizgileri
        for (a, b) in GraphLinks.links(items, parents: parents) {
            if let ia = indexOf[a], let ib = indexOf[b] { links.append((ia, ib)) }
        }
    }
}

/// Bilgiler arasındaki bağlar. Yapay zekanın kaydettiği "parent"/"links" önce gelir; olmayanlar addan çıkarılır:
///  • Dallanma: bir bilginin kişisi/adı (entity) başka bir bilginin adıysa ("Nura" → "Nura'nın doğum günü") o bilgiden dallanır.
///  • İlişki: bir bilginin özel adı ("iPad", "Magic Keyboard") başka bir bilgide geçiyorsa ince çizgiyle bağlanır.
enum GraphLinks {
    private static let tr = Locale(identifier: "tr_TR")
    private static func norm(_ s: String) -> String { s.lowercased(with: tr).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func words(_ s: String) -> [String] {
        norm(s).components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted).filter { !$0.isEmpty }
    }
    /// "ipad" → "iPad'e", "ipad'imin" gibi Türkçe eklerle de eşleşsin: kelime bu adla başlıyorsa
    private static func mentions(_ text: String, _ name: [String]) -> Bool {
        let w = words(text)
        guard !name.isEmpty, w.count >= name.count else { return false }
        for start in 0...(w.count - name.count) {
            var ok = true
            for (k, part) in name.enumerated() {
                let word = w[start + k]
                if k == name.count - 1 ? !word.hasPrefix(part) : word != part { ok = false; break }
            }
            if ok { return true }
        }
        return false
    }
    /// Özel ad mı? (büyük harf ya da rakam içeren, 3+ harf, en fazla 3 kelime) — "kahve", "spor" gibi genel kelimeler bağ kurmasın
    private static func isProperName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3, t.split(separator: " ").count <= 3 else { return false }
        return t.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    static func parents(_ items: [MemoryItem]) -> [UUID: UUID] {
        let ids = Set(items.map(\.id))
        var result: [UUID: UUID] = [:]
        // Ad → o adı taşıyan "çapa" bilgi (en önemli olan)
        var anchors: [String: MemoryItem] = [:]
        for item in items.sorted(by: { $0.resolvedImportance > $1.resolvedImportance }) where isProperName(item.text) {
            let key = norm(item.text)
            if anchors[key] == nil { anchors[key] = item }
        }
        for item in items {
            if let p = item.parent, p != item.id, ids.contains(p) { result[item.id] = p; continue }
            guard let entity = item.entity.map(norm), !entity.isEmpty, norm(item.text) != entity,
                  let anchor = anchors[entity], anchor.id != item.id else { continue }
            result[item.id] = anchor.id
        }
        // Döngü ve çok derin dal olmasın (en fazla 3 kademe)
        for id in Array(result.keys) {
            var seen: Set<UUID> = [id]; var cur = result[id]; var depth = 1
            while let c = cur {
                if seen.contains(c) || depth > 3 { result[id] = nil; break }
                seen.insert(c); cur = result[c]; depth += 1
            }
        }
        return result
    }

    static func links(_ items: [MemoryItem], parents: [UUID: UUID]) -> [(UUID, UUID)] {
        let ids = Set(items.map(\.id))
        var pairs = Set<[UUID]>()
        func add(_ a: UUID, _ b: UUID) {
            guard a != b, parents[a] != b, parents[b] != a else { return }
            pairs.insert([a, b].sorted { $0.uuidString < $1.uuidString })
        }
        for item in items { for l in item.links ?? [] where ids.contains(l) { add(item.id, l) } }
        let names = items.filter { isProperName($0.text) }.map { ($0, words($0.text)) }
        var perItem: [UUID: Int] = [:]
        for item in items {
            for (anchor, name) in names where anchor.id != item.id {
                guard (perItem[item.id] ?? 0) < 3, mentions(item.text + " " + item.detail, name) else { continue }
                add(item.id, anchor.id)
                perItem[item.id, default: 0] += 1
            }
        }
        return pairs.map { ($0[0], $0[1]) }
    }
}

/// Düğümlerin hafif "nefes alma" salınımı — her düğüm kendi ritminde, birkaç punto
private func drift(_ id: UUID, _ t: Double, amplitude: CGFloat) -> CGPoint {
    guard amplitude > 0 else { return .zero }
    let seed = Double(id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF })
    let phase = seed.truncatingRemainder(dividingBy: 628) / 100
    let speed = 0.55 + seed.truncatingRemainder(dividingBy: 40) / 100
    return CGPoint(x: CGFloat(sin(t * speed + phase)) * amplitude,
                   y: CGFloat(cos(t * speed * 0.8 + phase * 1.3)) * amplitude)
}

private func hubDrift(_ category: MemoryCategory, _ t: Double) -> CGPoint {
    let phase = Double(category.order) * 1.7
    return CGPoint(x: CGFloat(sin(t * 0.45 + phase)) * 1.6, y: CGFloat(cos(t * 0.38 + phase)) * 1.6)
}

struct MemoryGraphView: View {
    let items: [MemoryItem]
    let userName: String
    let avatarData: Data?
    /// Henüz gösterilmemiş ekleme/silme izleri
    var traces: [MemoryTrace] = []
    var onTracesShown: () -> Void = {}
    @Binding var selected: MemoryItem?
    @Binding var focus: MemoryCategory?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero
    @State private var scale: CGFloat = 0.8
    @GestureState private var pinching: CGFloat = 1
    /// Açılış: düğümler merkezden (senden) dışarı akarak yerlerine oturur
    @State private var openedAt: Date?
    @State private var didFit = false
    @State private var viewSize: CGSize = .zero
    @State private var introDone = false
    /// İz animasyonunun başladığı an ve oynatılan izler
    @State private var traceStart: Date?
    @State private var playing: [MemoryTrace] = []

    private static let traceDuration: Double = 1.6
    private static let traceHold: Double = 4.0

    var body: some View {
        // Silinen bilgiler animasyon bitene kadar eski yerlerinde "hayalet" olarak durur
        let ghosts = playing.filter { trace in trace.kind == .removed && !items.contains { $0.id == trace.item.id } }.map(\.item)
        let layout = GraphLayout(items: items + ghosts)
        let ghostIDs = Set(ghosts.map(\.id))
        let newIDs = Set(playing.filter { $0.kind != .removed }.map(\.item.id))
        let isInteracting = dragging != .zero || pinching != 1

        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            // Açılış akışı 60 fps; sonra hafif salınım 30 fps (çok sayıda cam baloncuk var)
            TimelineView(.animation(minimumInterval: introDone ? 1.0 / 30 : 1.0 / 60, paused: reduceMotion || (isInteracting && traceStart == nil))) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let traceP = tracePhase(at: timeline.date)
                let amp: CGFloat = reduceMotion ? 0 : 2.6
                let since = openedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                let hubOut = Self.emerge(since, delay: 0)
                // Merkezden çıkış: konumlar merkeze göre ölçeklenir (0 = merkezde, 1 = yerinde)
                let leafOut: (Int) -> CGFloat = { index in Self.emerge(since, delay: 0.12 + Double(min(index, 40)) * 0.012) }

                // Cam baloncuklar tek kapsayıcıda: iOS birlikte çizer (performans); spacing 0 → birbirine yapışmazlar
                PufyGlassContainer(spacing: 0) {
                ZStack {
                    // Merkezden yayılan çok hafif dalga
                    if !reduceMotion {
                        let p = CGFloat((t / 3.2).truncatingRemainder(dividingBy: 1))
                        Circle()
                            .stroke(Color.primary.opacity(0.10 * (1 - p)), lineWidth: 1)
                            .frame(width: 84 + 120 * p, height: 84 + 120 * p)
                            .position(center + CGPoint(x: 0, y: -10))
                            .allowsHitTesting(false)
                    }

                    // Bağlantılar
                    // ESKİ HATA (22 Ekim 2026): tuval ekran boyutundaydı; ağ büyüyünce uzak dalların çizgileri kenarda kesiliyordu.
                    // Artık tüm ağı kapsayan kare tuval, merkez aynı noktada.
                    let side = max(geo.size.width, geo.size.height, (layout.extent + 220) * 2)
                    let shift = CGPoint(x: side / 2 - center.x, y: side / 2 - center.y)
                    let leafPoint: (Int) -> CGPoint = { i in
                        let leaf = layout.leaves[i]
                        return center + leaf.hub * hubOut + (leaf.position - leaf.hub) * leafOut(i) + drift(leaf.item.id, t, amplitude: amp)
                    }
                    Canvas { context, _ in
                        context.translateBy(x: shift.x, y: shift.y)
                        // İlişkiler: bilgiler arasında ince eğri
                        for (a, b) in layout.links {
                            guard leafOut(a) > 0.5, leafOut(b) > 0.5 else { continue }
                            let ia = layout.leaves[a].item, ib = layout.leaves[b].item
                            let dim = focus != nil && (focus != ia.resolvedCategory && focus != ib.resolvedCategory)
                            let lit = selected?.id == ia.id || selected?.id == ib.id
                            context.stroke(Self.curve(from: leafPoint(a), to: leafPoint(b)),
                                           with: .color(Color.primary.opacity(lit ? 0.5 : (dim ? 0.02 : 0.07))),
                                           style: StrokeStyle(lineWidth: lit ? 1.4 : 1, dash: lit ? [] : [4, 5]))
                        }
                        for hub in layout.hubs {
                            let dim = focus != nil && focus != hub.category
                            var path = Path()
                            path.move(to: center)
                            path.addLine(to: center + hub.position * hubOut + hubDrift(hub.category, t))
                            context.stroke(path, with: .color(Color.primary.opacity(dim ? 0.05 : 0.18)), lineWidth: 1.4)
                        }
                        for (index, leaf) in layout.leaves.enumerated() {
                            let id = leaf.item.id
                            let dim = focus != nil && focus != leaf.item.resolvedCategory
                            let out = leafOut(index)
                            guard out > 0.02 else { continue }
                            // Kök bilgi alandan, dal bilgi üst bilginin (canlı) konumundan çıkar
                            let hubPoint = leaf.parent.map { leafPoint($0) } ?? (center + leaf.hub * hubOut + hubDrift(leaf.item.resolvedCategory, t))
                            let end = leafPoint(index)
                            let path = Self.curve(from: hubPoint, to: end)
                            let isSelected = selected?.id == id

                            if ghostIDs.contains(id) {
                                // Silinen: kesikli çizgi düğümden alana doğru geri çekilir
                                let remain = 1 - min(1, traceP * 1.2)
                                if remain > 0 {
                                    context.stroke(path.trimmedPath(from: 0, to: remain),
                                                   with: .color(Color.primary.opacity(0.35 * remain)),
                                                   style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                                }
                                continue
                            }

                            context.stroke(path,
                                           with: .color(Color.primary.opacity(isSelected ? 0.6 : (dim ? 0.03 : 0.10))),
                                           lineWidth: isSelected ? 1.6 : 1)

                            if newIDs.contains(id), let traceStart {
                                // Eklenen: merkez → alan → bilgi yolu parlak bir çizgiyle çizilir
                                var full = Path()
                                full.move(to: center)
                                full.addLine(to: hubPoint)
                                full.addPath(path)
                                let drawn = min(1, traceP)
                                let fade = Self.holdFade(since: traceStart, now: timeline.date)
                                if drawn > 0, fade > 0 {
                                    context.stroke(full.trimmedPath(from: 0, to: drawn),
                                                   with: .color(Color.primary.opacity(0.75 * fade)),
                                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    // Yolun ucunda ilerleyen nokta
                                    if drawn < 1, let tip = full.trimmedPath(from: max(0, drawn - 0.001), to: drawn).currentPoint {
                                        context.fill(Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7)),
                                                     with: .color(Color.primary))
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .position(center)
                    .allowsHitTesting(false)

                    // Bilgiler
                    ForEach(Array(layout.leaves.enumerated()), id: \.element.item.id) { index, leaf in
                        let id = leaf.item.id
                        let isGhost = ghostIDs.contains(id)
                        let isNew = newIDs.contains(id)
                        LeafNode(item: leaf.item, isSelected: selected?.id == id)
                            .overlay {
                                if isNew, let traceStart, traceP >= 1 {
                                    NewBadgeRing(fade: Self.holdFade(since: traceStart, now: timeline.date))
                                }
                            }
                            .opacity(isGhost ? max(0, 1 - traceP) * 0.8 : 1)
                            .scaleEffect(isGhost ? 1 - 0.4 * min(1, traceP) : (isNew && traceP < 1 ? 0.55 : 1))
                            .animation(.spring(response: 0.42, dampingFraction: 0.58), value: traceP >= 1)
                            .opacity(focus != nil && focus != leaf.item.resolvedCategory ? 0.2 : 1)
                            .scaleEffect(0.5 + 0.5 * leafOut(index))
                            .opacity(Double(min(1, leafOut(index) * 1.6)))
                            .position(center + leaf.hub * hubOut + (leaf.position - leaf.hub) * leafOut(index) + drift(id, t, amplitude: amp))
                            .allowsHitTesting(!isGhost)
                            .onTapGesture {
                                PremiumHaptics.light()
                                withAnimation(SmoothSpring.standard) {
                                    selected = selected?.id == id ? nil : leaf.item
                                }
                            }
                    }

                    // Alanlar
                    ForEach(layout.hubs, id: \.category) { hub in
                        HubNode(category: hub.category, count: hub.count, isFocused: focus == hub.category)
                            .opacity(focus != nil && focus != hub.category ? 0.35 : 1)
                            .scaleEffect(0.5 + 0.5 * hubOut)
                            .opacity(Double(min(1, hubOut * 2)))
                            .position(center + hub.position * hubOut + hubDrift(hub.category, t))
                            .onTapGesture {
                                PremiumHaptics.light()
                                withAnimation(SmoothSpring.standard) {
                                    focus = focus == hub.category ? nil : hub.category
                                    selected = nil
                                }
                            }
                    }

                }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                // Sen — cam katmanının da ÜSTÜNDE (cam baloncuklar birlikte çizildiği için sıralama garanti olsun)
                .overlay {
                    CenterNode(name: userName, avatarData: avatarData)
                        .position(center)
                        .onTapGesture {
                            withAnimation(SmoothSpring.standard) { focus = nil; selected = nil }
                        }
                }
            }
            .scaleEffect(scale * pinching)
            .offset(x: offset.width + dragging.width, y: offset.height + dragging.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragging) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
                    .simultaneously(with:
                        MagnificationGesture()
                            .updating($pinching) { value, state, _ in state = value }
                            .onEnded { value in scale = min(max(scale * value, 0.35), 2.5) }
                    )
            )
            .onTapGesture(count: 2) {
                withAnimation(SmoothSpring.gentle) { fit(in: geo.size, extent: layout.extent) }
            }
            .onAppear {
                // Açılışta kamera SENİN üzerinde ve yakın (eskiden tüm ağı sığdırıyordu → düğümler minicik
                // ve uzakta görünüyordu). Tüm ağı görmek için iki kez dokun ya da köşedeki düğme.
                viewSize = geo.size
                if !didFit {
                    offset = .zero
                    scale = 1.0
                    didFit = true
                }
                if openedAt == nil { openedAt = reduceMotion ? .distantPast : Date() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { introDone = true }
                playTraces(after: 1.3)
            }
            .onChange(of: traces) { _ in playTraces(after: 0.2) }
        }
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if selected == nil {
                Button {
                    PremiumHaptics.light()
                    withAnimation(SmoothSpring.gentle) {
                        if scale < 0.95 { offset = .zero; scale = 1.0 } else { fit(in: viewSize, extent: layout.extent) }
                    }
                } label: {
                    Image(systemName: scale < 0.95 ? "scope" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .pufyGlass(Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scale < 0.95 ? "Bana odaklan" : "Tüm ağı göster")
                .padding(16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if focus != nil {
                Button {
                    withAnimation(SmoothSpring.standard) { focus = nil }
                } label: {
                    Label("Tümü", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .pufyGlass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
        .overlay(alignment: .top) {
            if traceStart != nil, let summary = traceSummary {
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .pufyGlass(Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(SmoothSpring.standard, value: traceStart)
    }

    // MARK: İzler

    private var traceSummary: String? {
        let added = playing.filter { $0.kind == .added }.count
        let updated = playing.filter { $0.kind == .updated }.count
        let removed = playing.filter { $0.kind == .removed }.count
        var parts: [String] = []
        if added > 0 { parts.append("\(added) yeni") }
        if updated > 0 { parts.append("\(updated) güncellendi") }
        if removed > 0 { parts.append("\(removed) silindi") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func tracePhase(at date: Date) -> Double {
        guard !playing.isEmpty else { return 1 }
        guard let traceStart else { return 0 }      // ekran açıldı, iz birazdan başlayacak
        if reduceMotion { return 1 }
        return max(0, date.timeIntervalSince(traceStart) / Self.traceDuration)
    }

    /// Çizim bittikten sonra iz birkaç saniye kalır, sonra yavaşça söner
    private static func holdFade(since start: Date, now: Date) -> Double {
        let elapsed = now.timeIntervalSince(start) - traceDuration
        guard elapsed > traceHold else { return 1 }
        return max(0, 1 - (elapsed - traceHold) / 1.2)
    }

    private func playTraces(after delay: Double) {
        guard !traces.isEmpty else { return }
        let snapshot = traces
        onTracesShown()     // depodan silinir; bu ekranda kopyası oynatılır
        playing = snapshot
        traceStart = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard playing == snapshot else { return }
            traceStart = Date()
            PremiumHaptics.light()
            let total = Self.traceDuration + Self.traceHold + 1.3
            DispatchQueue.main.asyncAfter(deadline: .now() + total) {
                if playing == snapshot {
                    withAnimation(SmoothSpring.gentle) {
                        traceStart = nil
                        playing = []
                    }
                }
            }
        }
    }

    /// Açılış ilerlemesi: yumuşak, hafif esneyerek yerine oturur (0…~1.04…1)
    private static func emerge(_ since: Double, delay: Double) -> CGFloat {
        let duration = 0.75
        let x = min(max((since - delay) / duration, 0), 1)
        guard x < 1 else { return 1 }
        // easeOutBack: sonda çok hafif taşar ve geri oturur
        let c1 = 1.2, c3 = c1 + 1
        return CGFloat(1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2))
    }

    private static func curve(from start: CGPoint, to end: CGPoint) -> Path {
        let control = CGPoint(x: (start.x + end.x) / 2 + (end.y - start.y) * 0.12,
                              y: (start.y + end.y) / 2 - (end.x - start.x) * 0.12)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// Tüm ağı ekrana sığdır
    private func fit(in size: CGSize, extent: CGFloat) {
        offset = .zero
        let needed = (extent + 64) * 2
        let fitScale = min(size.width, size.height) / max(needed, 1)
        scale = min(max(fitScale, 0.4), 1.15)
    }
}

/// Yeni eklenen bilginin etrafında birkaç saniye duran ince halka + "yeni" işareti
private struct NewBadgeRing: View {
    let fade: Double

    var body: some View {
        Capsule()
            .strokeBorder(Color.primary.opacity(0.7 * fade), lineWidth: 1.5)
            .padding(-4)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 8)
                    .offset(x: 3, y: -5)
                    .opacity(fade)
            }
            .allowsHitTesting(false)
    }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
private func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }

private struct CenterNode: View {
    let name: String
    let avatarData: Data?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let avatarData, let image = ThumbnailCache.shared.image(for: avatarData, key: "memory-avatar-\(avatarData.count)", maxPixel: 240) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.pufyPrimary)
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(UIColor.systemBackground), lineWidth: 3))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)

            Text(name.isEmpty ? "Sen" : name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
        }
    }
}

private struct HubNode: View {
    let category: MemoryCategory
    let count: Int
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Liquid Glass baloncuk (seçiliyse koyu dolgulu cam)
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isFocused ? Color.pufyOnPrimary : Color.primary)
                .frame(width: 50, height: 50)
                .pufyGlass(Circle(), tint: isFocused ? Color.pufyPrimary : nil, interactive: true)
            Text(category.title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.title), \(count) bilgi")
    }
}

private struct LeafNode: View {
    let item: MemoryItem
    let isSelected: Bool

    private var size: CGFloat {
        switch item.resolvedImportance {
        case 5: return 14
        case 4: return 13
        default: return 12
        }
    }

    var body: some View {
        Group {
            if item.resolvedCategory == .people {
                VStack(spacing: 3) {
                    Text(initials)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.pufyOnPrimary : .primary)
                        .frame(width: 36, height: 36)
                        .pufyGlass(Circle(), tint: isSelected ? Color.pufyPrimary : nil, interactive: true)
                    Text(item.text)
                        .font(.system(size: size, weight: .semibold))
                    if let relation = item.relation {
                        Text(relation)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 100)
            } else {
                Text(item.text)
                    .font(.system(size: size, weight: item.resolvedImportance >= 4 ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.pufyOnPrimary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 104)
                    // Liquid Glass baloncuk (seçiliyse koyu dolgulu cam); önemli bilgiler ince bir çizgiyle belirgin
                    .pufyGlass(Capsule(), tint: isSelected ? Color.pufyPrimary : nil, interactive: true)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(item.resolvedImportance >= 4 && !isSelected ? 0.18 : 0), lineWidth: 0.8))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.detail)
    }

    private var initials: String {
        let source = item.entity ?? item.text
        let parts = source.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Bilgi Kartı

private struct MemoryDetailCard: View {
    let item: MemoryItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(item.resolvedCategory.title, systemImage: item.resolvedCategory.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ImportanceDots(value: item.resolvedImportance)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Kapat")
            }
            Text(item.text)
                .font(.title3.weight(.bold))
            if let relation = item.relation {
                Text(relation.capitalized(with: Locale(identifier: "tr_TR")))
                    .font(.subheadline.weight(.medium))
            }
            Text(item.detail)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Label("Düzenle", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.pufySoft))
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Unut", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.red.opacity(0.1)))
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .pufyGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - Düzenleyici

struct MemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: MemoryItem?
    let onSave: (MemoryItem) -> Void

    @State private var label: String
    @State private var detail: String
    @State private var category: MemoryCategory
    @State private var relation: String
    @State private var importance: Int

    init(item: MemoryItem?, onSave: @escaping (MemoryItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _label = State(initialValue: item?.text ?? "")
        _detail = State(initialValue: item?.detail ?? "")
        _category = State(initialValue: item?.resolvedCategory ?? .interests)
        _relation = State(initialValue: item?.relation ?? "")
        _importance = State(initialValue: item?.resolvedImportance ?? 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kısa ad (haritada görünür)", text: $label)
                    TextField("Açıklama", text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Alan", selection: $category) {
                        ForEach(MemoryCategory.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    if category == .people {
                        TextField("İlişki (ör. en yakın arkadaşı)", text: $relation)
                    }
                    Stepper(value: $importance, in: 1...5) {
                        HStack {
                            Text("Önem")
                            Spacer()
                            ImportanceDots(value: importance)
                        }
                    }
                } footer: {
                    Text("Önemli bilgiler haritada merkeze daha yakın ve daha belirgin görünür.")
                }
            }
            .navigationTitle(item == nil ? "Bilgi Ekle" : "Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        var result = item ?? MemoryItem(text: cleanLabel, detail: cleanDetail)
                        result.text = cleanLabel
                        result.detail = cleanDetail.isEmpty ? cleanLabel : cleanDetail
                        result.category = category
                        result.relation = category == .people && !relation.isEmpty ? relation : nil
                        result.entity = category == .people ? cleanLabel : result.entity
                        result.importance = importance
                        onSave(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
