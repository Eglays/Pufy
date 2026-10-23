import SwiftUI

// MARK: - Uygulama Değiştirici
//
// ESKİSİ: Kartlar elle yazılmış bir sürükleme hesabıyla kaydırılıyordu (görünmez dokunma katmanı,
// eşik değerleri, ±2 kart çizimi) → takılan, "yapay" bir his. Silmek için kartı yukarı itip
// havada bekletip ayrıca çöp kutusuna basmak gerekiyordu.
// YENİSİ: iOS'un yerel sayfalı kaydırması (gerçek ivme ve mıknatıs oturma), kartın üstünde ikon + ad,
// komşu kartlar kaydırma oranında küçülüp soluklaşır. Yukarı fırlat → uygulama silinir,
// 4 sn boyunca "Geri al" ile kurtarılabilir (silme dosyaları da kaldırdığı için).

struct TabSwitcherView: View {
    @EnvironmentObject var tabManager:    TabManager
    @EnvironmentObject var chatViewModel: ChatViewModel
    @Environment(\.colorScheme) var scheme

    @State private var showCreator = false
    @State private var editingAppForCreator: MiniApp? = nil
    /// Her açılışta ikon ızgarası; kartlı görünüme üstteki düğmeyle geçilir
    @State private var isListMode = true
    /// Izgara sayfası (ana ekran gibi yana kayan sayfalar)
    @State private var gridPage = 0

    @State private var scrolledID: UUID?
    @State private var pageIndex = 0
    /// Kartlar ilk karede doğru konuma oturana kadar görünmez (bkz. carousel)
    @State private var carouselReady = false

    /// Açılışta hangi kartın ortada olacağı — İLK değer olarak verilir. Eskiden onAppear'da sonradan
    /// atanıyordu → kartlar her açılışta soldan ortaya kayarak geliyordu.
    init(initialTabID: UUID? = nil, initialIndex: Int = 0) {
        _scrolledID = State(initialValue: initialTabID)
        _pageIndex = State(initialValue: initialIndex)
        // Düğmeyle/kenardan açılınca ızgara; iki parmakla kıstırınca pencereli kartlar
        let cards = TabManager.shared.switcherOpensInCards
        _isListMode = State(initialValue: !cards)
        TabManager.shared.switcherOpensInCards = false
    }
    /// Yukarı fırlatılıp silinmeyi bekleyen uygulama (Geri al süresi)
    @State private var pendingDelete: MiniApp?
    @State private var commitTask: Task<Void, Never>?
    @AppStorage("hint_new_app_shown") private var hintNewAppShown = false

    private static let newCardID = UUID()

    // Görünen kartlar: silinmeyi bekleyen gizli
    private var visibleTabs: [AppTab] {
        tabManager.tabs.filter { tab in
            if case .miniApp(let a) = tab.type, a.id == pendingDelete?.id { return false }
            return true
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(scheme == .dark ? 0.35 : 0.08))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    if isListMode {
                        listView
                            .transition(.opacity)
                    } else {
                        // Kartlar, başlık ve alt çubuk çıktıktan sonra KALAN alana göre boyutlanır
                        GeometryReader { area in
                            carousel(size: geo.size, available: area.size)
                        }
                        .transition(.opacity)
                    }
                    bottomBar
                }

                if let app = pendingDelete {
                    VStack {
                        Spacer()
                        UndoToast(name: app.name) { undoDelete() }
                            .padding(.bottom, 110)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(SmoothSpring.standard, value: isListMode)
        .animation(SmoothSpring.standard, value: pendingDelete?.id)
        .onAppear {
            // Sohbette açık kalan klavye uygulamalar ekranının üstünde kalmasın
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onDisappear { commitPendingDelete() }
        .sheet(isPresented: $showCreator) {
            AppCreatorView(editingApp: editingAppForCreator) { updated in
                tabManager.updateMiniApp(updated)
            }
            .environmentObject(tabManager)
        }
    }

    // MARK: Başlık

    private var header: some View {
        HStack {
            Text("Uygulamalar")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Spacer()
            GlassIconButton(systemImage: isListMode ? "rectangle.on.rectangle" : "square.grid.3x3",
                            size: 40, iconSize: 15,
                            accessibilityLabel: isListMode ? "Kart görünümü" : "Izgara görünümü") {
                isListMode.toggle()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Kartlar

    /// ESKİ HATA: kart, ekranın TAMAMINA göre boyutlanıyordu (yüksekliğin %64'ü); başlık + alt çubuk + sayfa noktaları
    /// eklenince toplam ekranı aşıyor, kartlar taşıyordu. Artık kartlar için kalan alana sığar, ekran oranı korunur.
    private func cardSize(screen: CGSize, available: CGSize) -> CGSize {
        let aspect = screen.height / max(screen.width, 1)
        // iPad'de kartlar büyük: ortadaki uygulama ekranın yarısına yakın
        // iPad'de ortadaki uygulama büyük (ekranın ~%62'si), yanlardakiler kenarlardan görünür
        var width = screen.width > 700 ? min(available.width * 0.62, 760) : min(available.width * 0.70, 360)
        // Kalan yükseklik: kaydırma alanı payı (44) + aralıklar (3×18) + sayfa noktaları + kart başlığı payı
        let maxHeight = max(available.height - 44 - 54 - 20, 160)
        var height = width * aspect
        if height > maxHeight {
            height = maxHeight
            width = height / aspect          // oran korunur (basık görünmesin)
        }
        return CGSize(width: width, height: height)
    }

    @ViewBuilder
    private func carousel(size: CGSize, available: CGSize) -> some View {
        let card = cardSize(screen: size, available: available)
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if #available(iOS 17, *) {
                // ESKİ HATA: iki parmakla kıstırınca kartlı görünüm bir animasyonun içinde açılıyordu ve
                // tembel (Lazy) dizide hedef kart ilk karede hazır olmadığından kaydırma ilk karttan hedef karta
                // ANİMASYONLA gidiyordu (Pufy sohbeti ve diğer kartlar bir an önünden geçiyordu).
                // Şimdi: normal HStack (hedef kart ilk karede var), konum animasyonsuz kurulur, hazır olunca görünür.
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(visibleTabs) { tab in
                            switcherCard(tab: tab, card: card, screen: size)
                                .id(tab.id)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(1 - min(abs(phase.value), 1) * 0.10)
                                        .opacity(1 - min(abs(phase.value), 1) * 0.45)
                                }
                        }
                        newAppCard(card: card)
                            .id(Self.newCardID)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(1 - min(abs(phase.value), 1) * 0.10)
                                    .opacity(1 - min(abs(phase.value), 1) * 0.45)
                            }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (size.width - card.width) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledID)
                .scrollClipDisabled()
                .frame(height: card.height + 44)
                .transaction { if !carouselReady { $0.animation = nil; $0.disablesAnimations = true } }
                .opacity(carouselReady ? 1 : 0)
                .onAppear {
                    // ESKİ HATA (2): scrolledID zaten hedefteyken tekrar atamak kaydırmıyordu → kartlar en baştan
                    // (Pufy sohbeti) açılıyordu. Şimdi yerleşim bittikten sonra hedef karta animasyonsuz kaydırılıyor,
                    // kartlar ancak doğru yerdeyken beliriyor.
                    let target = tabManager.activeTab.id
                    DispatchQueue.main.async {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            proxy.scrollTo(target, anchor: .center)
                            scrolledID = target
                        }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.18)) { carouselReady = true }
                        }
                    }
                }
                .onDisappear { carouselReady = false }
                .onChange(of: scrolledID) { _ in if carouselReady { PremiumHaptics.light() } }
                }
            } else {
                // iOS 16: yerel sayfalı TabView
                TabView(selection: $pageIndex) {
                    ForEach(Array(visibleTabs.enumerated()), id: \.element.id) { index, tab in
                        switcherCard(tab: tab, card: card, screen: size).tag(index)
                    }
                    newAppCard(card: card).tag(visibleTabs.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: card.height + 44)
            }
            pageDots
            Spacer(minLength: 0)
        }
    }

    private var currentPage: Int {
        if #available(iOS 17, *) {
            if scrolledID == Self.newCardID { return visibleTabs.count }
            return visibleTabs.firstIndex { $0.id == scrolledID } ?? 0
        }
        return pageIndex
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<(visibleTabs.count + 1), id: \.self) { i in
                Capsule()
                    .fill(i == currentPage ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: i == currentPage ? 18 : 6, height: 6)
            }
        }
        .animation(SmoothSpring.quick, value: currentPage)
    }

    @ViewBuilder
    private func switcherCard(tab: AppTab, card: CGSize, screen: CGSize) -> some View {
        let deletable: Bool = { if case .miniApp = tab.type { return true }; return false }()
        SwitcherCard(
            title: tab.title,
            isActive: tabManager.activeTab.id == tab.id,
            deletable: deletable,
            cardSize: card,
            icon: { cardIcon(tab: tab) },
            preview: { cardPreview(tab: tab, screen: screen, card: card) },
            onOpen: {
                if let index = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) {
                    PremiumHaptics.medium()
                    tabManager.selectTab(at: index)
                }
            },
            onDelete: {
                if case .miniApp(let app) = tab.type { scheduleDelete(app) }
            }
        )
    }

    @ViewBuilder
    private func cardIcon(tab: AppTab) -> some View {
        switch tab.type {
        case .chat:
            Image("chat_pp").resizable().scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .nativeApp(let n):
            if let img = n.imageName, UIImage(named: img) != nil {
                Image(img).resizable().scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                MiniAppIconTile(icon: n.icon, colorHex: nil, size: 26)
            }
        case .miniApp(let app):
            MiniAppIconTile(icon: app.icon, colorHex: app.colorHex, size: 26)
        }
    }

    /// Kart önizlemesi. Mini uygulamalar: son ekran görüntüsü ya da tasarlanmış kapak.
    /// Sohbet ve yerleşikler: gerçek ekran boyutunda çizilip karta küçültülür.
    @ViewBuilder
    private func cardPreview(tab: AppTab, screen: CGSize, card: CGSize) -> some View {
        if case .miniApp(let app) = tab.type {
            MiniAppCover(app: app, size: card)
        } else {
            let scale = card.width / max(screen.width, 1)
            Group {
                switch tab.type {
                case .chat:
                    ChatView(viewModel: chatViewModel, showSideMenu: .constant(false))
                        .environmentObject(tabManager)
                case .nativeApp(let n):
                    nativePreview(n)
                case .miniApp:
                    EmptyView()
                }
            }
            .frame(width: screen.width, height: card.height / scale)
            .scaleEffect(scale)
            .frame(width: card.width, height: card.height)
            .allowsHitTesting(false)
        }
    }

    private func nativePreview(_ n: NativeBuiltinApp) -> some View {
        VStack(spacing: 18) {
            if let imgName = n.imageName, UIImage(named: imgName) != nil {
                Image(imgName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                MiniAppIconTile(icon: n.icon, colorHex: nil, size: 120)
            }
            Text(n.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(n.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    private func newAppCard(card: CGSize) -> some View {
        Button {
            hintNewAppShown = true
            PremiumHaptics.medium()
            editingAppForCreator = nil
            showCreator = true
        } label: {
            VStack(spacing: 10) {
                Color.clear.frame(height: 26)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.primary.opacity(0.03)))
                    .overlay {
                        VStack(spacing: 14) {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .medium))
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(Color.pufySoft))
                            Text("Yeni uygulama")
                                .font(.system(.headline, design: .rounded))
                            Text("Anlat, yapay zeka yazsın")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .frame(width: card.width, height: card.height)
            }
        }
        .buttonStyle(PremiumCardButtonStyle())
        .overlay(alignment: .top) {
            if !hintNewAppShown {
                newAppHint
                    .frame(maxWidth: card.width)
                    .offset(y: -30)
            }
        }
    }

    /// "Yeni uygulama" ipucu: bir kez, birkaç saniye görünür; dokununca ya da "+"ya basınca kapanır
    private var newAppHint: some View {
        HintBubbleView(text: "Ne istediğini yaz, Pufy senin için uygulamayı yazsın.") {
            withAnimation(SmoothSpring.standard) { hintNewAppShown = true }
        }
        .transition(.scale.combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation(SmoothSpring.standard) { hintNewAppShown = true }
        }
    }

    // MARK: Silme (Geri al ile)

    private func scheduleDelete(_ app: MiniApp) {
        commitPendingDelete()            // önceki bekleyen varsa kesinleştir
        PremiumHaptics.success()
        pendingDelete = app
        commitTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { commitPendingDelete() }
        }
    }

    private func undoDelete() {
        commitTask?.cancel()
        PremiumHaptics.light()
        if let app = pendingDelete { scrolledID = tabManager.tabs.first { if case .miniApp(let a) = $0.type { return a.id == app.id }; return false }?.id }
        pendingDelete = nil
    }

    private func commitPendingDelete() {
        commitTask?.cancel()
        guard let app = pendingDelete else { return }
        pendingDelete = nil
        if let index = tabManager.tabs.firstIndex(where: { if case .miniApp(let a) = $0.type { return a.id == app.id }; return false }) {
            tabManager.deleteTab(at: index)
        }
    }

    // MARK: Alt bar

    private var bottomBar: some View {
        PufyGlassContainer(spacing: 8) {
            HStack(spacing: 14) {
                Button {
                    withAnimation(SmoothSpring.standard) { tabManager.isTabSwitcherVisible = false }
                } label: {
                    Text("Kapat")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .pufyGlass(Capsule(), interactive: true)
                }
                .buttonStyle(PufyPressStyle())

                Button {
                    PremiumHaptics.medium()
                    editingAppForCreator = nil
                    showCreator = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.pufyPrimary))
                }
                .buttonStyle(PremiumScaleButtonStyle())
                .accessibilityLabel("Yeni uygulama")
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Ana Ekran (ikon ızgarası)
    // Eskiden sürükle-bırak listesiydi. Artık iOS ana ekranı gibi: dokun → aç,
    // uzun bas → Düzenle / Paylaş (tek HTML dosyası) / Sil.

    @State private var deleteCandidate: MiniApp?

    /// Izgaradaki bir öğe: sekme ya da "Yeni" kutusu
    private enum GridEntry: Identifiable {
        case tab(AppTab, index: Int)
        case newApp
        var id: String {
            switch self {
            case .tab(let tab, _): return tab.id.uuidString
            case .newApp: return "new"
            }
        }
    }

    /// iPhone ana ekranı gibi: dikey kaydırma yok; sayfa dolunca (en fazla 24 = 4×6) yan sayfaya geçer.
    /// İkonlar biraz daha büyük ve ilk satır biraz aşağıda (en üste uzanmak zordu).
    private var listView: some View {
        GeometryReader { geo in
            // iPad: satır başına 5-6 uygulama (iPhone'da 4)
            let columns = geo.size.width > 950 ? 6 : (geo.size.width > 650 ? 5 : 4)
            let rowHeight: CGFloat = 112
            let rows = max(3, min(6, Int((geo.size.height - 60) / rowHeight)))
            let perPage = rows * columns
            let entries: [GridEntry] = tabManager.tabs.enumerated().map { GridEntry.tab($0.element, index: $0.offset) } + [.newApp]
            let pages: [[GridEntry]] = stride(from: 0, to: entries.count, by: perPage).map {
                Array(entries[$0..<min($0 + perPage, entries.count)])
            }

            VStack(spacing: 10) {
                TabView(selection: $gridPage) {
                    ForEach(pages.indices, id: \.self) { page in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 24) {
                            ForEach(pages[page]) { entry in
                                switch entry {
                                case .tab(let tab, let index): homeIcon(tab: tab, index: index)
                                case .newApp: newAppIcon
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 30)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if !hintNewAppShown {
                    newAppHint
                        .padding(.horizontal, 24)
                }

                if pages.count > 1 {
                    HStack(spacing: 7) {
                        ForEach(pages.indices, id: \.self) { page in
                            Circle()
                                .fill(Color.primary.opacity(page == gridPage ? 0.85 : 0.22))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.bottom, 6)
                    .animation(SmoothSpring.quick, value: gridPage)
                }
            }
        }
        .confirmationDialog("\(deleteCandidate?.name ?? "Uygulama") silinsin mi?",
                            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let app = deleteCandidate,
                   let index = tabManager.tabs.firstIndex(where: { if case .miniApp(let a) = $0.type { return a.id == app.id }; return false }) {
                    withAnimation(SmoothSpring.standard) { tabManager.deleteTab(at: index) }
                }
                deleteCandidate = nil
            }
        } message: {
            Text("Uygulama, sürümleri ve kaydettiği veriler silinir.")
        }
    }

    private var newAppIcon: some View {
        Button {
            hintNewAppShown = true
            editingAppForCreator = nil
            showCreator = true
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .overlay(Image(systemName: "plus").font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary))
                Text("Yeni")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .buttonStyle(PremiumScaleButtonStyle())
    }

    private static let iconSize: CGFloat = 68

    @ViewBuilder
    private func homeIcon(tab: AppTab, index: Int) -> some View {
        let label = VStack(spacing: 7) {
            Group {
                switch tab.type {
                case .chat:
                    Image("pufy_logo").resizable().scaledToFill()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                case .nativeApp(let n):
                    if let img = n.imageName, UIImage(named: img) != nil {
                        Image(img).resizable().scaledToFill()
                            .frame(width: Self.iconSize, height: Self.iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        MiniAppIconTile(icon: n.icon, colorHex: nil, size: Self.iconSize)
                    }
                case .miniApp(let app):
                    MiniAppIconTile(icon: app.icon, colorHex: app.colorHex, size: Self.iconSize)
                }
            }
            .overlay(alignment: .bottom) {
                if tabManager.activeTab.id == tab.id {
                    Circle().fill(Color.primary).frame(width: 5, height: 5).offset(y: 9)
                }
            }
            Text(tab.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.top, 2)
        }

        if case .miniApp(let app) = tab.type {
            Button { tabManager.selectTab(at: index) } label: { label }
                .buttonStyle(PremiumScaleButtonStyle())
                .contextMenu {
                    Button {
                        editingAppForCreator = app
                        showCreator = true
                    } label: { Label("Düzenle", systemImage: "pencil") }
                    Button {
                        if let folder = app.folderName, let url = MiniAppFiles.exportSingleHTML(folder: folder, name: app.name) {
                            presentShareSheet([url])
                        }
                    } label: { Label("HTML dosyası olarak", systemImage: "doc") }
                    Divider()
                    Button(role: .destructive) { deleteCandidate = app } label: { Label("Sil", systemImage: "trash") }
                }
        } else {
            Button { tabManager.selectTab(at: index) } label: { label }
                .buttonStyle(PremiumScaleButtonStyle())
        }
    }

}

// MARK: - Kart (yukarı fırlatarak silme)

private struct SwitcherCard<Icon: View, Preview: View>: View {
    let title: String
    let isActive: Bool
    let deletable: Bool
    let cardSize: CGSize
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let preview: () -> Preview
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var dragY: CGFloat = 0
    @State private var flying = false

    var body: some View {
        // 0 → 1: kart yukarı çekildikçe küçülür, başlık kaybolur
        let progress = min(max(-dragY / (cardSize.height * 0.6), 0), 1)

        VStack(spacing: 10) {
            HStack(spacing: 8) {
                icon()
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if isActive {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                        .accessibilityLabel("Açık")
                }
                Spacer(minLength: 0)
            }
            .frame(width: cardSize.width, height: 26)
            .opacity(1 - progress)

            preview()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                // Açık uygulama çerçeveyle değil başlıktaki küçük noktayla belirtilir
                // (koyu temada beyaz kalın çerçeve kötü görünüyordu)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .scaleEffect(1 - progress * 0.08)
        .offset(y: dragY)
        .opacity(flying ? 0 : 1 - progress * 0.35)
        .onTapGesture(perform: onOpen)
        .modifier(VerticalSwipe(
            onChange: { dy in
                // Silinemeyenler (sohbet, yerleşik) ve aşağı çekme: lastik gibi direnç
                dragY = (dy < 0 && deletable) ? dy : dy * 0.22
            },
            onEnd: { dy, velocity in
                let flick = dy + velocity * 0.25
                if deletable && (dy < -cardSize.height * 0.28 || flick < -cardSize.height * 0.8) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        dragY = -cardSize.height * 1.5
                        flying = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDelete()
                        dragY = 0
                        flying = false
                    }
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { dragY = 0 }
                }
            }
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Aç", onOpen)
    }
}

private struct UndoToast: View {
    let name: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("\(name) silindi")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Button(action: onUndo) {
                Text("Geri al")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.pufyOnPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.pufyPrimary))
            }
            .buttonStyle(PremiumScaleButtonStyle())
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .pufyGlass(Capsule())
    }
}

// MARK: - Sadece dikey kaydırma tanıyıcı
//
// ESKİ HATA: Kartlardaki SwiftUI DragGesture, yatay kaydırma görünümünün hareketini zaman zaman
// "çalıyordu" → bazen sağa sola kayıyor, bazen ekran sabit kalıyordu.
// Çözüm: UIKit pan tanıyıcısı, hareket DİKEY başlamıyorsa hiç başlamaz (gestureRecognizerShouldBegin);
// yatay hareketler tamamen kaydırmaya kalır.

private struct VerticalSwipe: ViewModifier {
    let onChange: (CGFloat) -> Void
    let onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.gesture(VerticalPanRecognizer(onChange: onChange, onEnd: onEnd))
        } else {
            content   // iOS 17 ve öncesi: silme ızgaradaki basılı tutma menüsünden
        }
    }
}

@available(iOS 18, *)
private struct VerticalPanRecognizer: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dy = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .changed:
            onChange(dy)
        case .ended, .cancelled, .failed:
            onEnd(dy, recognizer.velocity(in: recognizer.view).y)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > abs(v.x) * 1.3
        }
    }
}

// MARK: - Mini uygulama kapağı

/// Uygulama kapağı: kimlik rengiyle tema, büyük soluk ikon deseni, altta logo + ad + slogan.
/// (Ekran görüntüsü ve yapay zekanın HTML kartı denendi; kullanıcı bu tasarımı tercih etti, 13 Ekim 2026.)
struct MiniAppCover: View {
    let app: MiniApp
    let size: CGSize

    var body: some View {
        designedCover
            .frame(width: size.width, height: size.height)
    }

    private var tint: Color { Color(hex: app.colorHex) ?? .pufyPrimary }

    /// ESKİ HATA: arkadaki dev soluk ikon yerleşime dahildi; kart büyüyünce (iPad yatay) kapağı görünen alandan büyütüp
    /// başlık ve sloganı kartın DIŞINA itiyordu (iPad'de "yazısı yok, sadece arka plan"). Desen artık yerleşimi etkilemeyen
    /// bir katman; ikon, başlık ve slogan kart boyutuyla ölçeklenir (iPhone'da sığar, iPad'de büyür).
    private var designedCover: some View {
        let s = min(size.width, size.height * 0.9)
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: max(8, s * 0.03)) {
                MiniAppIconTile(icon: app.icon, colorHex: app.colorHex, size: min(max(s * 0.19, 44), 96))
                    .overlay(RoundedRectangle(cornerRadius: min(max(s * 0.19, 44), 96) * 0.26, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1))
                Text(app.name)
                    .font(.system(size: min(max(s * 0.085, 20), 40), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if !app.description.isEmpty {
                    Text(app.description)
                        .font(.system(size: min(max(s * 0.048, 13), 20)))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(max(16, s * 0.07))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topTrailing) {
            // Büyük, soluk ikon deseni — yerleşimi etkilemez
            Image(systemName: UIImage(systemName: app.icon) != nil ? app.icon : "app.dashed")
                .font(.system(size: s * 0.9, weight: .bold))
                .foregroundStyle(.white.opacity(0.10))
                .rotationEffect(.degrees(-14))
                .offset(x: s * 0.25, y: -s * 0.05)
                .allowsHitTesting(false)
        }
        .clipShape(Rectangle())
    }
}
