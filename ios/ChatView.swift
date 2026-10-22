import SwiftUI
import PhotosUI
import Photos
import CoreImage

// MARK: - Sohbet Ekranı
//
// Yerleşim (ChatGPT / Gemini / iOS 26 Mesajlar mantığı):
//  • Mesajlar tam ekran kayar; üst bar ve mesaj kutusu içeriğin ÜZERİNDE yüzer.
//    Liquid Glass ancak altından içerik geçince "cam" gibi görünür — eskiden barlar
//    ayrı bir VStack satırındaydı, cam düz beyaz zemin üstünde gri bir daire gibi duruyordu.
//  • Yakın cam elemanlar GlassEffectContainer içinde: "+" menüsü butondan akarak açılır (morph).
//  • Cam yalnızca kontrol katmanında; mesaj balonları cam değil.

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showSideMenu: Bool
    /// Uygulamalar (Tab Switcher) ekranını açar — ContentView sağlar
    var onOpenApps: () -> Void = {}
    /// Uygulama açılışında klavyeyi aç (uygulama değiştiricideki önizleme kopyasında kapalı)
    var autoFocusOnLaunch: Bool = false
    private static var didAutoFocus = false

    @StateObject private var photoManager = PhotoManager.shared
    /// Yapay zeka destekli dikte (yazı kutusu boşken gönder düğmesi mikrofona dönüşür)
    @StateObject private var dictation = DictationManager()
    @State private var showAttachMenu = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var showFilePicker = false
    @State private var previewFile: FileAttachment? = nil
    @State private var fullscreenImage: UIImage?
    /// Fotoğraf menüsünden seçilenler: asset id → gönderilecek veri
    @State private var trayData: [String: Data] = [:]
    @State private var loadingAssetID: String?
    @State private var isNearBottom = true
    @State private var scrollViewHeight: CGFloat = 0
    /// Kullanıcının kapattığı seçenek panelleri (mesaj kimliği)
    @State private var dismissedChoices: Set<UUID> = []
    /// Küçültülmüş seçenek panelleri (elle ya da mesajı okumak için yukarı kaydırınca)
    @State private var collapsedChoices: Set<UUID> = []
    @FocusState private var composerFocused: Bool
    @Namespace private var glassNS

    private let bottomID = "bottom_anchor"

    private var messages: [Message] { viewModel.currentSession?.messages ?? [] }

    /// Zamanlanmış görevin sohbeti: farklı arayüz, yazma kutusu yok (bkz. TaskSessionView)
    private var taskSession: ChatSession? {
        guard let session = viewModel.currentSession, session.isSpaceChatValue else { return nil }
        return session
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            Group {
                if let taskSession {
                    TaskSessionView(viewModel: viewModel, session: taskSession, onImageTap: { image in
                        withAnimation(SmoothSpring.fade) { fullscreenImage = image }
                    })
                    .id(taskSession.id)
                } else if messages.isEmpty {
                    welcomeView
                } else {
                    messageList
                }
            }
            .pufyBar(edge: .top) { headerBar }
            .pufyBar(edge: .bottom) {
                if taskSession == nil { composer }
            }

            if let image = fullscreenImage {
                ImageViewer(image: image, onClose: {
                    withAnimation(SmoothSpring.fade) { fullscreenImage = nil }
                }, onAsk: taskSession == nil ? { picked in
                    // "Sor": görseli yazı kutusuna ekle, klavyeyi aç
                    if let data = ImageUtils.preparedJPEG(from: picked), !viewModel.selectedImages.contains(data) {
                        viewModel.selectedImages.append(data)
                    }
                    withAnimation(SmoothSpring.fade) { fullscreenImage = nil }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { composerFocused = true }
                } : nil)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CustomCameraView { data in
                let prepared = ImageUtils.preparedJPEG(from: data)
                if !viewModel.selectedImages.contains(prepared) {
                    viewModel.selectedImages.append(prepared)
                }
            }
        }
        .sheet(isPresented: $showLibraryPicker) {
            MultiImagePicker(selectedImages: $viewModel.selectedImages)
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedDocTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await viewModel.addFiles(urls: urls)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $previewFile) { file in
            FilePreviewSheet(file: file)
        }
        .onAppear {
            // Açılışta klavye hazır olsun (açılış animasyonu ~1,2 sn — bitince)
            // İlk açılış rehberi gösterilirken klavye açılmasın
            guard autoFocusOnLaunch, !Self.didAutoFocus,
                  UserDefaults.standard.bool(forKey: "pufy_onboarding_done") else { return }
            Self.didAutoFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if !showSideMenu { composerFocused = true }
            }
        }
        .onChange(of: composerFocused) { focused in
            if focused && showAttachMenu {
                withAnimation(SmoothSpring.standard) { showAttachMenu = false }
            }
        }
    }

    // MARK: - Üst Bar

    private var headerBar: some View {
        PufyGlassContainer(spacing: 8) {
            HStack(spacing: 12) {
                GlassIconButton(systemImage: "text.alignleft", accessibilityLabel: String(localized: "Menü")) {
                    composerFocused = false
                    withAnimation(SmoothSpring.standard) { showSideMenu = true }
                }

                Spacer()

                // iOS 26 araç çubukları gibi: ilgili iki eylem tek cam kapsülde
                HStack(spacing: 0) {
                    Button {
                        PremiumHaptics.light()
                        composerFocused = false
                        onOpenApps()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .frame(width: 46, height: 44)
                    }
                    .accessibilityLabel(String(localized: "Uygulamalar"))

                    Button {
                        PremiumHaptics.light()
                        withAnimation(SmoothSpring.standard) { viewModel.startNewSession() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .frame(width: 46, height: 44)
                    }
                    .accessibilityLabel(String(localized: "Yeni sohbet"))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .buttonStyle(PufyPressStyle())
                .pufyGlass(Capsule(), interactive: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Karşılama

    /// Sabah, akşam ve gece selam; gün ortasında hiçbir şey yazmaz
    static func greeting(name: String, date: Date = Date()) -> String? {
        let hour = Calendar.current.component(.hour, from: date)
        let base: String
        switch hour {
        case 5..<11: base = String(localized: "Günaydın")
        case 18..<22: base = String(localized: "İyi akşamlar")
        case 22..<24, 0..<5: base = String(localized: "İyi geceler")
        default: return nil
        }
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? base : "\(base), \(first)"
    }

    private var welcomeView: some View {
        let followUps = viewModel.recentFollowUps
        return VStack(spacing: 28) {
            Spacer()
            // "Hoş geldin <ad>" yazma; sadece belli anlarda selam (Günaydın / İyi akşamlar / İyi geceler)
            if let greeting = Self.greeting(name: viewModel.userName) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.pufyGradient)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            // Son sohbetlerinden kaldığın yer: her sohbetin sonunda yapay zekanın kaydettiği soru (en fazla 3)
            if !followUps.isEmpty && !composerFocused {
                FollowUpSuggestions(items: followUps) { question in
                    viewModel.searchText = question
                    send()
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(composerFocused ? 0.45 : 1)
        .scaleEffect(composerFocused ? 0.94 : 1)
        .animation(SmoothSpring.gentle, value: composerFocused)
        .contentShape(Rectangle())
        .onTapGesture { dismissTransientUI() }
    }

    // MARK: - Mesaj Listesi

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    let generatingID = viewModel.isLoading ? messages.last?.id : nil
                    let lastModelID = messages.last(where: { $0.role == .model })?.id

                    ForEach(messages) { message in
                        MessageRowView(
                            message: message,
                            isLastResponse: message.id == lastModelID,
                            isGenerating: message.id == generatingID,
                            onImageTap: { image in
                                withAnimation(SmoothSpring.fade) { fullscreenImage = image }
                            },
                            onFileTap: { file in
                                previewFile = file
                            },
                            onRegenerate: { viewModel.regenerateLastResponse() }
                        )
                        .equatable()
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: BottomMarkerKey.self,
                                                       value: geo.frame(in: .named("chatScroll")).minY)
                            }
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .coordinateSpace(name: "chatScroll")
            // Her sohbet kendi kaydırma görünümüyle açılır → alttaki çapa sayesinde SON mesajdan başlar
            // (eskiden geçmiş sohbet ilk mesajdan açılıyordu, her seferinde aşağı kaydırmak gerekiyordu)
            .id(viewModel.currentSessionID)
            // Kart yenilenince (canlı skor/fiyat) sohbete kaydet
            .environment(\.pufyWidgetUpdate, { [weak viewModel] messageID, index, widget in
                viewModel?.updateWidget(messageID: messageID, index: index, widget: widget)
            })
            // Eylem butonu / test → mesaj olarak gönder; sunum kartı → tekrar dene
            .environment(\.pufyChatAction, { text in
                guard !viewModel.isLoading else { return }
                viewModel.searchText = text
                send()
            })
            .environment(\.pufyDeckRetry, { [weak viewModel] messageID in
                viewModel?.retryDeck(messageID: messageID)
            })
            // Klavye açılınca/kapanınca ve cevap uzadıkça içerik alta yapışık kalır — sistem bunu
            // klavye animasyonuyla AYNI karede yapar (eskiden 0,3 sn sonra ayrıca kaydırılıyordu → kopukluk)
            .pufyChatScrollAnchor(followBottom: isNearBottom)
            // Mesajı okumak için parmakla yukarı kaydırınca seçenek paneli kendiliğinden küçülür.
            // ESKİ HATA: bunun için listeye eklenen sürükleme hareketi, soldan kaydırınca menü açılmasını engelliyordu
            // (iç içe hareketlerde içteki kazanır). Şimdi iOS'un kendi kaydırma olayları dinleniyor (iOS 18+).
            .modifier(UserScrollUpDetector {
                guard let pending = pendingChoices, !collapsedChoices.contains(pending.id) else { return }
                withAnimation(SmoothSpring.standard) { _ = collapsedChoices.insert(pending.id) }
            })
            .scrollDismissesKeyboard(.interactively)
            .pufySoftScrollEdges()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollViewHeight = geo.size.height }
                        .onChange(of: geo.size.height) { scrollViewHeight = $0 }
                }
            )
            .onPreferenceChange(BottomMarkerKey.self) { minY in
                let near = minY < scrollViewHeight + 120
                if near != isNearBottom { isNearBottom = near }
            }
            .simultaneousGesture(TapGesture().onEnded { dismissTransientUI() })
            .overlay(alignment: .bottom) {
                if !isNearBottom {
                    GlassIconButton(systemImage: "arrow.down", size: 38, iconSize: 15, accessibilityLabel: "En alta git") {
                        withAnimation(SmoothSpring.standard) { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                    .padding(.bottom, 10)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(SmoothSpring.quick, value: isNearBottom)
            .onAppear {
                if !Self.hasNativeBottomAnchor { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: viewModel.currentSessionID) { _ in
                DispatchQueue.main.async { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: messages.count) { _ in
                withAnimation(SmoothSpring.standard) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: messages.last?.content) { _ in
                // iOS 18 öncesi yedek: akış sırasında, kullanıcı yukarı kaydırmadıysa cevabı takip et
                if !Self.hasNativeBottomAnchor && isNearBottom { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: composerFocused) { focused in
                guard !Self.hasNativeBottomAnchor, focused, isNearBottom else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(SmoothSpring.standard) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
            }
        }
    }

    /// iOS 18+: sistemin "alta yapışık kaydırma" özelliği var (klavyeyle senkron)
    private static var hasNativeBottomAnchor: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }

    private func dismissTransientUI() {
        composerFocused = false
        if showAttachMenu {
            withAnimation(SmoothSpring.standard) { showAttachMenu = false }
        }
    }

    // MARK: - Mesaj Kutusu (Composer)

    /// Son cevap seçenekli soru sorduysa ve kullanıcı henüz cevaplamadıysa: panel gösterilir
    private var pendingChoices: (id: UUID, prompt: ChoicePrompt)? {
        guard !viewModel.isLoading, !showAttachMenu,
              let last = messages.last, last.role == .model,
              let prompt = last.choices, !prompt.questions.isEmpty,
              !dismissedChoices.contains(last.id) else { return nil }
        return (last.id, prompt)
    }

    private var canSend: Bool {
        GeminiService.shared.isConfigured && !viewModel.isLoading && (
            !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.selectedImages.isEmpty
            || !viewModel.selectedFiles.isEmpty
        )
    }

    private var placeholder: String {
        if viewModel.isReminderMode { return String(localized: "Neyi, ne zaman hatırlatayım?") }
        if viewModel.isSearchingWeb { return String(localized: "Web'de ne arayayım?") }
        return String(localized: "Pufy'ye sor")
    }

    private var composer: some View {
        // spacing (6) < elemanlar arası boşluk (10): cam parçalar dururken birbirine yapışmaz,
        // "+" menüsü açılırken ise aynı konteyner içinde butondan akarak çıkar
        PufyGlassContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                // Menü açıkken eklenen görseller/dosyalar menünün ÜSTÜNDE (menü yerinden oynamasın);
                // menü kapanınca yazı kutusunun içine geçer
                if showAttachMenu && (!viewModel.selectedImages.isEmpty || !viewModel.selectedFiles.isEmpty || viewModel.isExtractingFiles) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !viewModel.selectedImages.isEmpty {
                            selectedImagesStrip(size: 72)
                        }
                        if !viewModel.selectedFiles.isEmpty || viewModel.isExtractingFiles {
                            selectedFilesStrip
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showAttachMenu {
                    attachMenu
                        .pufyGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .pufyGlassID("attach", in: glassNS)
                        .transition(attachMenuTransition)
                }

                if let pending = pendingChoices {
                    if collapsedChoices.contains(pending.id) {
                        // Küçük hali: tek satır, dokununca açılır
                        Button {
                            PremiumHaptics.light()
                            withAnimation(SmoothSpring.standard) { _ = collapsedChoices.remove(pending.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(pending.prompt.questions.first?.q ?? String(localized: "Seçenekler"))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if pending.prompt.questions.count > 1 {
                                    Text("+\(pending.prompt.questions.count - 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .pufyGlass(Capsule(), interactive: true)
                        .pufyGlassID("choices", in: glassNS)
                        .transition(.opacity)
                        .accessibilityLabel(String(localized: "Seçenekleri aç"))
                    } else {
                        ChoicePanel(prompt: pending.prompt, onSubmit: { answer in
                            withAnimation(SmoothSpring.standard) { _ = dismissedChoices.insert(pending.id) }
                            viewModel.searchText = answer
                            send()
                        }, onDismiss: {
                            withAnimation(SmoothSpring.standard) { _ = dismissedChoices.insert(pending.id) }
                        }, onCollapse: {
                            withAnimation(SmoothSpring.standard) { _ = collapsedChoices.insert(pending.id) }
                        })
                        .pufyGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .pufyGlassID("choices", in: glassNS)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if !GeminiService.shared.isConfigured {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.pufyPrimary)
                        Text(AppLanguage.isEnglish ? "Connect your AI to get started" : "Başlamak için yapay zekanı bağla")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Button {
                            PremiumHaptics.light()
                            NotificationCenter.default.post(name: NSNotification.Name("pufy_open_ai_connect"), object: nil)
                        } label: {
                            Text(AppLanguage.isEnglish ? "Connect" : "Bağla")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.pufyOnPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.pufyPrimary))
                        }
                        .buttonStyle(PremiumScaleButtonStyle())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .pufyGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
                }

                inputField
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .animation(SmoothSpring.standard, value: showAttachMenu)
        .animation(SmoothSpring.quick, value: viewModel.selectedImages.count)
        .animation(SmoothSpring.quick, value: viewModel.isSearchingWeb)
        .animation(SmoothSpring.quick, value: viewModel.isReminderMode)
        .animation(SmoothSpring.standard, value: dictation.phase)
        .onChange(of: dictation.errorMessage) { message in
            guard let message else { return }
            withAnimation(SmoothSpring.standard) { viewModel.errorMessage = message }
            dictation.errorMessage = nil
        }
    }

    /// iOS 26'da cam, "+" butonundan akarak (morph) büyür; içerik sadece belirir.
    /// Eski sürümlerde cam morph olmadığı için butondan büyüme animasyonu taklit edilir.
    private var attachMenuTransition: AnyTransition {
        if #available(iOS 26, *) {
            return .opacity
        }
        return .scale(scale: 0.2, anchor: .bottomLeading).combined(with: .opacity)
    }

    private var plusButton: some View {
        Button {
            PremiumHaptics.light()
            if !showAttachMenu {
                composerFocused = false
                photoManager.checkAuthorization()
            }
            withAnimation(SmoothSpring.standard) { showAttachMenu.toggle() }
        } label: {
            // Yazı kutusunun içinde: ayrı bir yuvarlak buton değil (kullanıcı isteği)
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(showAttachMenu ? Color.pufyPrimary : Color.primary)
                .rotationEffect(.degrees(showAttachMenu ? 45 : 0))
                .frame(width: 40, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PufyPressStyle())
        .accessibilityLabel(showAttachMenu ? String(localized: "Menüyü kapat") : String(localized: "Ekle"))
    }

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isSearchingWeb || viewModel.isReminderMode {
                HStack(spacing: 6) {
                    if viewModel.isSearchingWeb {
                        ModeChip(icon: "globe", title: String(localized: "Web'de Ara")) { viewModel.isSearchingWeb = false }
                    }
                    if viewModel.isReminderMode {
                        ModeChip(icon: "bell", title: String(localized: "Hatırlatıcı")) { viewModel.isReminderMode = false }
                    }
                }
                .padding(.leading, 10)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Eklenen görseller ve dosyalar yazı kutusunun içinde
            if !showAttachMenu && (!viewModel.selectedImages.isEmpty || !viewModel.selectedFiles.isEmpty || viewModel.isExtractingFiles) && dictation.phase == .idle {
                VStack(alignment: .leading, spacing: 6) {
                    if !viewModel.selectedImages.isEmpty {
                        selectedImagesStrip(size: 76)
                    }
                    if !viewModel.selectedFiles.isEmpty || viewModel.isExtractingFiles {
                        selectedFilesStrip
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if dictation.phase != .idle {
                DictationBar(dictation: dictation)
                    .transition(.opacity)
            } else {
            HStack(alignment: .bottom, spacing: 0) {
                plusButton
                    .padding(.leading, 4)
                TextField(placeholder, text: $viewModel.searchText, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.body)
                    .focused($composerFocused)
                    // iPad klavyesi: Enter gönderir, Shift+Enter yeni satır
                    .pufySubmitOnReturn(text: $viewModel.searchText) { send() }
                    .padding(.leading, 2)
                    .padding(.vertical, 12)
                    // ESKİ SORUN: sadece yazının olduğu ince şerit dokunulabiliyordu; kutunun boş
                    // kısımlarına basınca klavye açılmıyordu. Artık tüm alan dokunulabilir.
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .contentShape(Rectangle())
                    // simultaneous: imleç konumlandırma / metin seçme dokunuşlarını engellemesin
                    .simultaneousGesture(TapGesture().onEnded { composerFocused = true })

                sendButton
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            }
            .transition(.opacity)
            }
        }
        .frame(minHeight: 46)
        .pufyGlass(RoundedRectangle(cornerRadius: 23, style: .continuous))
        // "+" menüsü artık bu kutudan akarak çıkar (iOS 26 cam geçişi)
        .pufyGlassID("plus", in: glassNS)
    }

    /// Yazı kutusu boşken: mikrofon (ChatGPT gibi). Yazınca gönder okuna dönüşür.
    private var showsMic: Bool {
        !viewModel.isLoading && viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.selectedImages.isEmpty
    }

    private func startDictation() {
        composerFocused = false
        withAnimation(SmoothSpring.standard) { showAttachMenu = false }
        dictation.start { text in
            let current = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.searchText = current.isEmpty ? text : current + " " + text
            composerFocused = true
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if showsMic {
            Button(action: startDictation) {
                Image(systemName: "mic")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityLabel(String(localized: "Konuşarak yaz"))
        } else {
            arrowButton
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var arrowButton: some View {
        let loading = viewModel.isLoading
        return Button {
            if loading {
                PremiumHaptics.light()
                viewModel.cancelMessage()
            } else {
                send()
            }
        } label: {
            Image(systemName: loading ? "stop.fill" : "arrow.up")
                .font(.system(size: loading ? 13 : 16, weight: .bold))
                .foregroundStyle((canSend || loading) ? Color.pufyOnPrimary : Color.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill((canSend || loading) ? Color.pufyPrimary : Color.pufyDisabled))
                .pufySymbolReplace()
        }
        .buttonStyle(PremiumScaleButtonStyle())
        .disabled(!canSend && !loading)
        .animation(SmoothSpring.quick, value: loading)
        .animation(SmoothSpring.quick, value: canSend)
        .accessibilityLabel(loading ? String(localized: "Durdur") : String(localized: "Gönder"))
    }

    private func send() {
        guard GeminiService.shared.isConfigured else {
            NotificationCenter.default.post(name: NSNotification.Name("pufy_open_ai_connect"), object: nil)
            return
        }
        guard canSend else { return }
        PremiumHaptics.medium()
        viewModel.isVoiceInput = false
        withAnimation(SmoothSpring.standard) { showAttachMenu = false }
        trayData.removeAll()
        Task { await viewModel.sendMessage() }
    }

    // MARK: "+" Menüsü

    private var attachMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AttachTile(systemImage: "camera.fill", title: "Kamera") {
                        showCamera = true
                        withAnimation(SmoothSpring.standard) { showAttachMenu = false }
                    }

                    if photoManager.isAuthorized {
                        ForEach(photoManager.recentPhotos) { photo in
                            recentPhotoTile(photo)
                        }
                    } else {
                        AttachTile(systemImage: "photo.badge.plus", title: String(localized: "İzin ver")) {
                            photoManager.requestAuthorization()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
            }

            AttachMenuRow(icon: "photo.on.rectangle.angled", title: String(localized: "Fotoğraflar")) {
                showLibraryPicker = true
                withAnimation(SmoothSpring.standard) { showAttachMenu = false }
            }
            AttachMenuRow(icon: "doc", title: String(localized: "Dosya")) {
                withAnimation(SmoothSpring.standard) { showAttachMenu = false }
                showFilePicker = true
            }
            AttachMenuRow(
                icon: "globe",
                title: String(localized: "Web'de ara"),
                subtitle: DeepResearchManager.shared.isSearchAvailable ? String(localized: "Güncel bilgiyi internetten bulur") : String(localized: "Önce Ayarlar'dan SearXNG adresi gir"),
                isOn: viewModel.isSearchingWeb
            ) {
                viewModel.isSearchingWeb.toggle()
                if viewModel.isSearchingWeb { viewModel.isReminderMode = false }
                withAnimation(SmoothSpring.standard) { showAttachMenu = false }
                composerFocused = true
            }
            AttachMenuRow(icon: "bell", title: String(localized: "Hatırlatıcı kur"), subtitle: String(localized: "\"Yarın 9'da maçı hatırlat\" gibi"), isOn: viewModel.isReminderMode) {
                viewModel.isReminderMode.toggle()
                if viewModel.isReminderMode { viewModel.isSearchingWeb = false }
                withAnimation(SmoothSpring.standard) { showAttachMenu = false }
                composerFocused = true
            }
            AttachMenuRow(icon: "square.grid.2x2", title: String(localized: "Uygulamalar"), subtitle: String(localized: "Mini uygulamaların ve oyunların")) {
                withAnimation(SmoothSpring.standard) { showAttachMenu = false }
                onOpenApps()
            }
        }
        .padding(.bottom, 8)
    }

    private func recentPhotoTile(_ photo: RecentPhoto) -> some View {
        let selectedData = trayData[photo.id]
        let isSelected = selectedData.map { viewModel.selectedImages.contains($0) } ?? false

        return Button {
            PremiumHaptics.light()
            if isSelected, let data = selectedData {
                viewModel.selectedImages.removeAll { $0 == data }
                trayData[photo.id] = nil
            } else {
                loadingAssetID = photo.id
                photoManager.loadImageData(for: photo.id) { data in
                    loadingAssetID = nil
                    guard let data else { return }
                    trayData[photo.id] = data
                    if !viewModel.selectedImages.contains(data) { viewModel.selectedImages.append(data) }
                }
            }
        } label: {
            Image(uiImage: photo.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.pufyPrimary : .clear, lineWidth: 3)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.pufyOnPrimary, Color.pufyPrimary)
                            .padding(5)
                    }
                }
                .overlay {
                    if loadingAssetID == photo.id { ProgressView().tint(.white) }
                }
        }
        .buttonStyle(PremiumCardButtonStyle())
    }

    private func selectedImagesStrip(size: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, data in
                    if let thumb = ThumbnailCache.shared.image(for: data, key: "sel-\(data.count)-\(data.prefix(256).hashValue)", maxPixel: 260) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(SmoothSpring.quick) {
                                        if index < viewModel.selectedImages.count {
                                            let removed = viewModel.selectedImages.remove(at: index)
                                            trayData = trayData.filter { $0.value != removed }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(.black.opacity(0.55)))
                                }
                                .padding(4)
                                .accessibilityLabel(String(localized: "Görseli kaldır"))
                            }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var selectedFilesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.selectedFiles.enumerated()), id: \.element.id) { index, file in
                    fileChipView(file, canRemove: true) {
                        withAnimation(SmoothSpring.quick) {
                            viewModel.removeFile(at: index)
                        }
                    }
                }
                if viewModel.isExtractingFiles {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(localized: "Okunuyor…"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.pufyUserBubble, in: Capsule())
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func fileChipView(_ file: FileAttachment, canRemove: Bool, onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: fileIconName(for: file.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pufyPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .leading)

                Text(fileSubtext(for: file))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if canRemove {
                Button {
                    PremiumHaptics.light()
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .accessibilityLabel(String(localized: "Dosyayı kaldır"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.pufyUserBubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func fileIconName(for kind: String) -> String {
        switch kind {
        case "pdf": return "doc.richtext"
        case "docx": return "doc.text"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.plaintext"
        }
    }

    private func fileSubtext(for file: FileAttachment) -> String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
        if let pages = file.pageCount, pages > 0 {
            return "\(pages) sf · \(sizeStr)"
        }
        return sizeStr
    }

    private var supportedDocTypes: [UTType] {
        var types: [UTType] = [
            .pdf, .plainText, .commaSeparatedText, .json, .sourceCode, .html, .xml
        ]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let log = UTType(filenameExtension: "log") { types.append(log) }
        if let yaml = UTType(filenameExtension: "yaml") { types.append(yaml) }
        if let yml = UTType(filenameExtension: "yml") { types.append(yml) }
        return types
    }
}

private struct BottomMarkerKey: PreferenceKey {
    /// İşaretçi çizilmemişse (LazyVStack çok yukarıdayken onu bellekten atabilir) "çok uzakta" say.
    /// 0 olsaydı "en alttayız" sanılır, kullanıcı geçmişi okurken akış onu aşağı çekerdi.
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Composer Parçaları

private struct ModeChip: View {
    let icon: String
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Button {
            PremiumHaptics.light()
            withAnimation(SmoothSpring.quick) { onRemove() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.pufyOnSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.pufySoft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) modunu kapat")
    }
}

private struct AttachTile: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            PremiumHaptics.light()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.pufyPrimary)
            .frame(width: 76, height: 76)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.pufySoft))
        }
        .buttonStyle(PremiumCardButtonStyle())
    }
}

private struct AttachMenuRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            PremiumHaptics.light()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Color.pufyOnPrimary : Color.pufyPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isOn ? Color.pufyPrimary : Color.pufySoft))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.pufyPrimary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumCardButtonStyle())
    }
}

// MARK: - Mesaj Satırı

struct MessageRowView: View, Equatable {
    let message: Message
    var isLastResponse: Bool = false
    /// Bu mesaj şu an üretiliyor mu? (düşünüyor / akış sürüyor)
    var isGenerating: Bool = false
    var onImageTap: (UIImage) -> Void = { _ in }
    var onFileTap: (FileAttachment) -> Void = { _ in }
    var onRegenerate: () -> Void = {}
    @ObservedObject private var reportStore = AIReportStore.shared

    private var reportState: Int {
        let isRep = reportStore.isReported(messageID: message.id)
        let isRev = reportStore.isRevealed(messageID: message.id)
        return (isRep ? 1 : 0) + (isRev ? 2 : 0)
    }

    /// Kapanış (closure) alanları karşılaştırılamadığı için SwiftUI bu satırları her klavye
    /// vuruşunda yeniden çiziyordu. `.equatable()` ile sadece veri değişince çizilir.
    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.message == rhs.message
            && lhs.isLastResponse == rhs.isLastResponse
            && lhs.isGenerating == rhs.isGenerating
            && lhs.reportState == rhs.reportState
    }

    var body: some View {
        if message.role == .user {
            userRow
        } else {
            assistantRow
        }
    }

    // MARK: Kullanıcı

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let files = message.files, !files.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(files) { file in
                        Button {
                            PremiumHaptics.light()
                            onFileTap(file)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: fileIconName(for: file.kind))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.pufyPrimary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 160, alignment: .leading)

                                    Text(fileSubtext(for: file))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.pufyUserBubble, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dosya: \(file.name)")
                    }
                }
            }

            if !message.imageDatas.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(message.imageDatas.enumerated()), id: \.offset) { index, data in
                        if let thumb = ThumbnailCache.shared.image(for: data, key: "\(message.id)-\(index)") {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 230, maxHeight: 260, alignment: .trailing)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .onTapGesture {
                                    PremiumHaptics.light()
                                    onImageTap(UIImage(data: data) ?? thumb)
                                }
                                .accessibilityLabel(String(localized: "Gönderilen görsel"))
                        }
                    }
                }
            }

            if !message.content.isEmpty {
                SelectableText(text: AttributedString(message.content), hugs: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.pufyUserBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 44)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
    }

    private func fileIconName(for kind: String) -> String {
        switch kind {
        case "pdf": return "doc.richtext"
        case "docx": return "doc.text"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.plaintext"
        }
    }

    private func fileSubtext(for file: FileAttachment) -> String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
        if let pages = file.pageCount, pages > 0 {
            return "\(pages) sf · \(sizeStr)"
        }
        return sizeStr
    }

    // MARK: Asistan

    private static let tagRegexes: [NSRegularExpression] = [
        "!\\[[^\\]]*\\]\\([^)]*\\)",
        "\\[(?:THINK|SEARCH|REMINDER|DELETE_REMINDER|UPDATE_REMINDER|AI_TASK|TIMER|NEXT|SOURCES|IMAGES|DRAW|SLIDES|ACTIONS|UYGULAMA_YAP)\\s*:[^\\]]*(?:\\]|$)",
        // Not etiketinin içinde "- [ ] madde" köşeli parantezleri olur: "}]" ile biter, yarımsa sonuna kadar gizle
        "\\[(?:NOTE|DELETE_NOTE)\\s*:\\s*\\{[\\s\\S]*?\\}\\s*\\]",
        "\\[(?:NOTE|DELETE_NOTE)\\s*:[\\s\\S]*$",
        "\\[CHOICES[\\s\\S]*$",     // seçenek etiketi hep en sonda: oradan sonrasını gizle
        "(?i)\\[ARAY[UÜ]Z\\][\\s\\S]*?(?:\\[/ARAY[UÜ]Z\\]|$)", // Dinamik arayüz: kapanışa veya metin sonuna kadar gizle
        "(?i)\\[ARAY[UÜ]Z[\\s\\S]*$"
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Sohbetten mini uygulama oluşturma isteği
    private var appRequest: AppRequestData? {
        if let saved = message.appRequest { return saved }
        guard isGenerating, message.content.contains("[UYGULAMA_YAP") else { return nil }
        return JSONTag.decode("UYGULAMA_YAP", as: AppRequestData.self, from: message.content).value
    }

    /// Cevabın kartları: bitince mesajda kayıtlı; akış sırasında JSON'u tamamlanan kart hemen görünür
    private var widgets: [ChatWidget] {
        if let saved = message.widgets { return saved }
        guard isGenerating, message.content.contains("[WIDGET") else { return [] }
        return JSONTag.widgets(in: message.content).widgets
    }

    /// Akış sırasında JSON'u tamamlanan karşılaştırma kartı ve test hemen görünür; bitince mesajda kayıtlı
    private var compareCard: CompareData? {
        if let saved = message.compare { return saved }
        guard isGenerating, message.content.contains("[COMPARE") else { return nil }
        return JSONTag.decode("COMPARE", as: CompareData.self, from: message.content).value.flatMap { $0.isValid ? $0 : nil }
    }

    private var quizCard: QuizData? {
        if let saved = message.quiz { return saved }
        guard isGenerating, message.content.contains("[QUIZ") else { return nil }
        return JSONTag.decode("QUIZ", as: QuizData.self, from: message.content).value.flatMap { $0.isValid ? $0 : nil }
    }

    /// Eski bozuk kayıtlar (22 Ekim 2026 öncesi): açılış etiketi silinmiş, içerikte çıplak HTML + "[/ARAYUZ]" kalmış.
    /// Gösterirken aynı kurtarmayla HTML'i arayüz olarak ayır, metinde kod görünmesin.
    private var recoveredCanvas: (canvas: String?, text: String)? {
        guard !isGenerating, message.canvas == nil,
              message.content.range(of: "[/ARAY", options: .caseInsensitive) != nil else { return nil }
        return ChatViewModel.extractCanvas(from: message.content)
    }

    /// Görsel markdown'ı ve (akış sırasında yarım gelebilecek) araç etiketlerini gizler
    private var cleanContent: String {
        var source = recoveredCanvas?.text ?? message.content
        for name in ["WIDGET", "COMPARE", "QUIZ"] where source.contains("[\(name)") {
            source = JSONTag.extract(name, from: source).text
        }
        let mutable = NSMutableString(string: source)
        for regex in Self.tagRegexes {
            regex.replaceMatches(in: mutable, options: [], range: NSRange(location: 0, length: mutable.length), withTemplate: "")
        }
        return (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var imageURLs: [URL] {
        guard message.content.contains("![") else { return [] }
        let pattern = "!\\[[^\\]]*\\]\\(([^)]*)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = message.content as NSString
        return regex.matches(in: message.content, range: NSRange(location: 0, length: ns.length))
            .compactMap { URL(string: ns.substring(with: $0.range(at: 1))) }
            .map(GeminiService.resolveGeneratedImageURL)
    }

    /// Derin araştırmanın plan ve bulgu adımları (yoksa boş)
    private var researchLog: [String] {
        message.thinkingSteps.filter { $0.hasPrefix(DeepResearchManager.planPrefix) || $0.hasPrefix(DeepResearchManager.findingPrefix) }
    }

    private var statusText: String {
        message.thinkingSteps.last { !$0.hasPrefix(DeepResearchManager.planPrefix) && !$0.hasPrefix(DeepResearchManager.findingPrefix) } ?? String(localized: "Düşünüyor…")
    }

    private var assistantRow: some View {
        let isReported = reportStore.isReported(messageID: message.id)
        let isRevealed = reportStore.isRevealed(messageID: message.id)

        if isReported && !isRevealed {
            return AnyView(
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(AppLanguage.isEnglish ? "This response was reported and hidden." : "Bu cevap bildirildi ve gizlendi.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(AppLanguage.isEnglish ? "Show" : "Göster") {
                        withAnimation(SmoothSpring.standard) {
                            reportStore.toggleReveal(messageID: message.id)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        }

        let text = cleanContent
        let images = imageURLs
        let cards = widgets
        let compare = compareCard
        let quiz = quizCard
        let canvas = message.canvas ?? recoveredCanvas?.canvas
        let isGeneratingCanvas = isGenerating && canvas == nil && (message.content.range(of: "[ARAYUZ]", options: .caseInsensitive) != nil || message.content.range(of: "[ARAYÜZ]", options: .caseInsensitive) != nil)
        // Görsel üretiliyor: "yazıyor" göstergesi yerine desenli animasyon kartı
        let isDrawing = isGenerating && images.isEmpty && message.thinkingSteps.last == ResearchProgress.drawing.displayText
        let isThinking = isGenerating && text.isEmpty && images.isEmpty && cards.isEmpty && compare == nil && quiz == nil && canvas == nil && !isGeneratingCanvas && !isDrawing

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            if isReported && isRevealed {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(AppLanguage.isEnglish ? "Reported response" : "Bildirilen cevap")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(AppLanguage.isEnglish ? "Hide" : "Gizle") {
                        withAnimation(SmoothSpring.standard) {
                            reportStore.toggleReveal(messageID: message.id)
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            // Logo her cevapta tekrar etmez: düşünürken göstergenin içinde nefes alır,
            // cevap gelince sadece EN SON cevabın başında küçük ve sakin durur. Eski cevaplarda yok.
            if !isThinking && isLastResponse {
                HStack(spacing: 7) {
                    Image("chat_pp")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                    Text("Pufy")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }

            if isDrawing {
                ImageGeneratingCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            } else if isThinking {
                if researchLog.isEmpty {
                    ThinkingIndicator(status: statusText, reasoning: message.reasoning)
                        .transition(.opacity)
                } else {
                    // Derin araştırma: plan → bulgular → yazım aşama aşama görünür
                    ResearchLogView(steps: researchLog, status: statusText)
                        .transition(.opacity)
                }
            } else if let reasoning = message.reasoning, !reasoning.isEmpty {
                // Cevap gelmeye başladı/bitti: düşünce süreci katlanmış olarak durur
                ReasoningDisclosure(reasoning: reasoning)
            }
            if !isThinking && !researchLog.isEmpty {
                ResearchNotesDisclosure(steps: researchLog)
            }

            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                ChatWidgetCard(widget: card, messageID: message.id, index: index, isStatic: isGenerating)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if let compare {
                CompareCard(data: compare)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if let canvas {
                ChatCanvasCard(canvasHTML: canvas, messageID: message.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else if isGeneratingCanvas {
                ChatCanvasPlaceholderCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            ForEach(images, id: \.self) { url in
                GeneratedImageView(url: url, onTap: onImageTap)
            }


            if !text.isEmpty && !isDrawing {
                // Uzun bas → kelime seçimi (tüm mesajı kopyalamak için alttaki Kopyala düğmesi)
                MarkdownView(text: text)
                    .environment(\.pufyImageTap, onImageTap)
            }

            if let quiz {
                QuizCard(quiz: quiz, messageID: message.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if let deck = message.deck {
                SlideDeckCard(deck: deck, messageID: message.id, createdAt: message.timestamp)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if !isGenerating {
                if let sources = message.sources, !sources.isEmpty {
                    SourceChips(sources: sources)
                }
                badges
                if !text.isEmpty {
                    MessageActionBar(text: text, messageID: message.id,
                                     showRegenerate: isLastResponse, onRegenerate: onRegenerate)
                }
                // Eylem butonları sadece son cevapta (eski cevaplarda kalabalık etmesin)
                if isLastResponse, let actions = message.actions, !actions.isEmpty {
                    ActionChips(actions: actions)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let appReq = appRequest {
                    Button {
                        PremiumHaptics.medium()
                        TabManager.shared.openCreator(name: appReq.name, prompt: appReq.prompt)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.app")
                                .font(.system(size: 12, weight: .semibold))
                            Text(String(localized: "Uygulamayı oluştur"))
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(UIColor.secondarySystemBackground)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(PremiumScaleButtonStyle())
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(SmoothSpring.fade, value: isThinking)
        .animation(SmoothSpring.standard, value: isDrawing)
        .animation(SmoothSpring.standard, value: isLastResponse)
        )
    }

    @ViewBuilder
    private var badges: some View {
        let hasSearch = message.searchQuery != nil
        let reminder = message.reminderTitle
        if hasSearch || reminder != nil || message.noteTitle != nil {
            HStack(spacing: 6) {
                if hasSearch {
                    Badge(icon: "globe", text: String(localized: "Web'de arandı"), color: .pufyPrimary)
                }
                if let reminder {
                    Badge(icon: "bell.badge.fill", text: reminder, color: .pufyReminder)
                }
                if let note = message.noteTitle {
                    // Dokununca not sayfası açılır
                    Button {
                        PremiumHaptics.light()
                        if let id = message.noteID, NoteStore.shared.note(id) != nil { NoteStore.shared.presented = .init(id: id) }
                    } label: {
                        Badge(icon: "note.text", text: note, color: .pufyPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct Badge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
    }
}

/// Cevabın altındaki eylemler: kopyala, yeniden üret, paylaş, sesli oku, bildir (ChatGPT'deki gibi)
private struct MessageActionBar: View {
    let text: String
    let messageID: UUID
    let showRegenerate: Bool
    let onRegenerate: () -> Void
    @State private var copied = false
    @State private var showReport = false

    var body: some View {
        HStack(spacing: 2) {
            action(copied ? "checkmark" : "doc.on.doc", label: AppLanguage.isEnglish ? "Copy" : "Kopyala") {
                UIPasteboard.general.string = text
                withAnimation(SmoothSpring.quick) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(SmoothSpring.quick) { copied = false }
                }
            }
            if showRegenerate {
                action("arrow.clockwise", label: AppLanguage.isEnglish ? "Regenerate" : "Yeniden oluştur", perform: onRegenerate)
            }
            ShareLink(item: text) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AppLanguage.isEnglish ? "Share" : "Paylaş")
            SpeakButton(text: text, messageID: messageID)
            action("flag", label: AppLanguage.isEnglish ? "Report" : "Bildir") {
                showReport = true
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, -8)
        .sheet(isPresented: $showReport) {
            ReportSheet(
                messageID: messageID,
                messageText: text,
                modelName: GeminiService.shared.modelName,
                onDismiss: { showReport = false }
            )
        }
    }

    private func action(_ icon: String, label: String, perform: @escaping () -> Void) -> some View {
        Button {
            PremiumHaptics.light()
            perform()
        } label: {
            Image(systemName: icon)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
                .pufySymbolReplace()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Sesli okuma butonu — VoiceManager'ı yalnızca bu küçük görünüm izler
/// (eskiden HER mesaj satırı izliyordu; ses durumu değişince tüm sohbet yeniden çiziliyordu)
private struct SpeakButton: View {
    let text: String
    let messageID: UUID
    @ObservedObject private var voice = VoiceManager.shared

    var body: some View {
        let speaking = voice.speakingMessageID == messageID
        Button {
            PremiumHaptics.light()
            if speaking { voice.stopSpeaking() } else { voice.speak(text: text, messageID: messageID) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: speaking ? "stop.circle" : "speaker.wave.2")
                if speaking { SoundWaveView() }
            }
            .frame(minWidth: 34, minHeight: 30)
            .contentShape(Rectangle())
            .foregroundStyle(speaking ? Color.pufyPrimary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speaking ? String(localized: "Okumayı durdur") : String(localized: "Sesli oku"))
    }
}

/// Yapay zekanın ürettiği görsel (yerel dosya veya web adresi)
private struct GeneratedImageView: View {
    let url: URL
    let onTap: (UIImage) -> Void

    /// Yeni üretilen görsel bulanıktan netleşerek belirir (kartın yerini alırken); eski görseller hemen görünür
    @State private var revealed = false
    private static var shown: Set<URL> = []

    private var isFresh: Bool {
        guard url.isFileURL, !Self.shown.contains(url),
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return false }
        return date.timeIntervalSinceNow > -60
    }

    var body: some View {
        if url.isFileURL {
            if let image = UIImage(contentsOfFile: url.path) {
                let fresh = isFresh
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .blur(radius: fresh && !revealed ? 24 : 0)
                    .scaleEffect(fresh && !revealed ? 0.97 : 1)
                    .opacity(fresh && !revealed ? 0.4 : 1)
                    .onAppear {
                        guard fresh else { return }
                        withAnimation(.easeOut(duration: 1.1)) { revealed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Self.shown.insert(url) }
                    }
                    .onTapGesture { onTap(image) }
            } else {
                placeholder(text: String(localized: "Görsel artık cihazda bulunmuyor"))
            }
        } else {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else if phase.error != nil {
                    placeholder(text: String(localized: "Görsel yüklenemedi"))
                } else {
                    ProgressView()
                        .frame(width: 260, height: 200)
                        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private func placeholder(text: String) -> some View {
        Label(text, systemImage: "photo.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 260, height: 120)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Tam ekran görsel görüntüleyici (iki parmakla yakınlaştırma)
/// Tam ekran görsel (üretilen ya da gönderilen)
/// ESKİ: siyah zemin + görsel + kapat düğmesi. YENİ:
///  • iki parmakla / çift dokunarak yakınlaştırma, yakınken kaydırma
///  • aşağı çekerek kapatma (zemin solar, görsel küçülür)
///  • arkada görselin bulanık hali (renkli, canlı zemin)
///  • cam düğmeler: Kaydet (Fotoğraflar), Paylaş, Kopyala, "Bunu sor" (görseli yazı kutusuna ekler)
///  • tek dokunuş düğmeleri gizler/gösterir
private struct ImageViewer: View {
    let image: UIImage
    let onClose: () -> Void
    var onAsk: ((UIImage) -> Void)? = nil

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var chromeVisible = true
    @State private var toast: String?
    @State private var appeared = false
    @State private var backdrop: UIImage?

    private var isZoomed: Bool { scale * pinch > 1.01 }

    /// Zemin için renk yıkaması: görsel 48×48'e küçültülüp Core Image ile gerçek Gauss bulanıklığından geçirilir
    /// (şekil ve pikselleşme kalmaz, sadece yumuşak renk geçişi)
    private static func colorWash(of image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        guard let input = CIImage(image: small) else { return nil }
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 9).cropped(to: input.extent)
        guard let cg = CIContext(options: nil).createCGImage(blurred, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        let dismissProgress = isZoomed ? 0 : min(abs(drag.height) / 320, 1)

        ZStack {
            // Zemin: siyah + görselin bulanık hali. ESKİ HATA: bulanık görsel "ekranı doldur" ölçeğiyle
            // doğrudan yerleşime giriyordu → bütün görünümü büyütüyor, asıl görsel de ekranı kaplıyordu.
            // Şimdi zeminin içine çiziliyor ve kırpılıyor; yerleşimi etkilemiyor.
            Color.black
                .overlay {
                    // Görselin 12×12'lik hali büyütülüp bulanıklaştırılır: şekil kalmaz, sadece renk geçişi
                    if let backdrop {
                        Image(uiImage: backdrop)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .blur(radius: 40)
                            .opacity(0.4)
                    }
                }
                .clipped()
                .opacity(1 - dismissProgress * 0.85)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // Görsel kendi oranında, bir çerçevenin içinde (ekranı kaplamaz; küçük görseller büyütülmez)
            GeometryReader { geo in
                // Görselin kendi oranında, sığacağı TAM boyut (çerçeve ve köşeler görselin kendisine otursun)
                let fit = Self.fittedSize(image.size, in: CGSize(width: geo.size.width - 32, height: geo.size.height - 190))
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
                    .scaleEffect(scale * pinch * (1 - dismissProgress * 0.15))
                    .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                    .gesture(magnify.simultaneously(with: pan))
                    .onTapGesture(count: 2) {
                        PremiumHaptics.light()
                        withAnimation(SmoothSpring.standard) {
                            if isZoomed { scale = 1; offset = .zero } else { scale = 2.2 }
                        }
                    }
                    .onTapGesture {
                        withAnimation(SmoothSpring.quick) { chromeVisible.toggle() }
                    }
                    .scaleEffect(appeared ? 1 : 0.94)
                    .opacity(appeared ? 1 : 0)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            if chromeVisible && dismissProgress < 0.05 {
                VStack {
                    HStack {
                        GlassIconButton(systemImage: "xmark", size: 42, iconSize: 15, foreground: .white,
                                        accessibilityLabel: "Kapat", action: onClose)
                        Spacer()
                        Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .pufyGlass(Capsule())
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    Spacer()

                    actionBar
                        .padding(.bottom, 16)
                }
                .transition(.opacity)
            }

            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .pufyGlass(Capsule())
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!chromeVisible)
        .onAppear {
            backdrop = Self.colorWash(of: image)
            withAnimation(SmoothSpring.standard) { appeared = true }
        }
    }

    /// Oranı koruyarak sığdır; küçük görselleri büyütme
    static func fittedSize(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: Hareketler

    private var magnify: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                withAnimation(SmoothSpring.standard) {
                    scale = min(max(scale * value, 1), 5)
                    if scale <= 1.01 { scale = 1; offset = .zero }
                }
            }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                if isZoomed {
                    // Yakınken: görseli gezdir
                    withAnimation(SmoothSpring.quick) {
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
                } else {
                    let flick = value.predictedEndTranslation.height
                    if abs(value.translation.height) > 120 || abs(flick) > 420 {
                        PremiumHaptics.light()
                        onClose()
                    }
                }
            }
    }

    // MARK: Düğmeler

    private var actionBar: some View {
        HStack(spacing: 4) {
            actionButton(String(localized: "Kaydet"), "square.and.arrow.down") { save() }
            ShareLink(item: Image(uiImage: image), preview: SharePreview(String(localized: "Görsel"), image: Image(uiImage: image))) {
                actionLabel(String(localized: "Paylaş"), "square.and.arrow.up")
            }
            .buttonStyle(PufyPressStyle())
            actionButton(String(localized: "Kopyala"), "doc.on.doc") {
                UIPasteboard.general.image = image
                showToast(String(localized: "Kopyalandı"))
            }
            if let onAsk {
                actionButton(String(localized: "Sor"), "bubble.left.and.text.bubble.right") { onAsk(image) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .pufyGlass(Capsule())
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            PremiumHaptics.light()
            action()
        } label: {
            actionLabel(title, icon)
        }
        .buttonStyle(PufyPressStyle())
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(width: 64, height: 50)
        .contentShape(Rectangle())
    }

    private func save() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { showToast(String(localized: "Fotoğraflara erişim izni yok")) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    if success { PremiumHaptics.success() }
                    showToast(success ? String(localized: "Fotoğraflara kaydedildi") : String(localized: "Kaydedilemedi"))
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(SmoothSpring.standard) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(SmoothSpring.standard) { if toast == text { toast = nil } }
        }
    }
}

// MARK: - Düşünüyor Göstergesi
//
// Eskisi: soluk gri metin + zar zor görünen parıltı → "ekrana boş boş bakıyorum" hissi.
// Yenisi: nabız gibi atan nokta + belirgin parlayan durum yazısı; model düşüncesini
// gönderiyorsa (Gemini 3.x, DeepSeek…) son satırları canlı akar (ChatGPT/Gemini'deki gibi).

/// Derin araştırma sürerken: üstte nabız atan Pufy + durum, altında araştırılan konular ve gelen bulgular
private struct ResearchLogView: View {
    let steps: [String]
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SpinningPufyIconView().frame(width: 26, height: 26)
                ShimmerText(text: status, font: .subheadline.weight(.semibold))
                    .id(status)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(SmoothSpring.standard, value: status)
            ResearchStepList(steps: steps)
                .padding(.leading, 36)
        }
    }
}

/// Plan satırı ve "✓" bulguları
private struct ResearchStepList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                if step.hasPrefix(DeepResearchManager.planPrefix) {
                    Text(step)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.pufyPrimary)
                        Text(String(step.dropFirst(DeepResearchManager.findingPrefix.count)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(SmoothSpring.standard, value: steps.count)
    }
}

/// Cevap bittikten sonra araştırma adımları katlanmış durur
private struct ResearchNotesDisclosure: View {
    let steps: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                PremiumHaptics.light()
                withAnimation(SmoothSpring.standard) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(String(localized: "Araştırma notları"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if expanded {
                ResearchStepList(steps: steps)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 2) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ThinkingIndicator: View {
    let status: String
    let reasoning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SpinningPufyIconView()
                    .frame(width: 26, height: 26)
                ShimmerText(text: status, font: .subheadline.weight(.semibold))
                    .id(status)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(SmoothSpring.standard, value: status)

            if let reasoning, !reasoning.isEmpty {
                // Düşüncenin son birkaç satırı, üstü yumuşakça solarak
                Text(Self.tail(of: reasoning))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .frame(maxHeight: 74, alignment: .bottom)
                    .clipped()
                    .mask(
                        LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom)
                    )
                    .padding(.leading, 36)
                    .animation(.easeOut(duration: 0.2), value: reasoning.count)
            }
        }
    }

    /// Markdown yıldızlarını atıp son ~320 karakteri gösterir
    private static func tail(of text: String) -> String {
        let clean = text.replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > 320 ? "…" + String(clean.suffix(320)) : clean
    }
}

/// Cevaptan sonra: "Düşünce süreci" — dokununca açılır
private struct ReasoningDisclosure: View {
    let reasoning: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                PremiumHaptics.light()
                withAnimation(SmoothSpring.standard) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(String(localized: "Düşünce süreci"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(reasoning.replacingOccurrences(of: "**", with: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Üzerinden ışık geçen yazı: soluk taban + üstünde hareket eden parlak bant
struct ShimmerText: View {
    let text: String
    let font: Font
    @State private var phase: CGFloat = -0.6

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.tertiary)
            .overlay {
                GeometryReader { geo in
                    Text(text)
                        .font(font)
                        .foregroundStyle(.primary)
                        .mask(
                            LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: max(geo.size.width * 0.55, 40))
                                .offset(x: phase * geo.size.width)
                        )
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.1
                }
            }
    }
}

// MARK: - Sound Wave View (TimelineView tabanlı — performanslı)

struct SoundWaveView: View {
    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 12
    private let minHeight: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 5.0
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(Color.pufyPrimary)
                        .frame(width: barWidth, height: barHeight(for: i, phase: CGFloat(phase)))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func barHeight(for index: Int, phase: CGFloat) -> CGFloat {
        let normalized = (sin(phase + CGFloat(index) * 0.8) + 1) / 2
        return minHeight + normalized * (maxHeight - minHeight)
    }
}

// MARK: - Loading Pufy Icon (yumuşak nefes animasyonu)

struct SpinningPufyIconView: View {
    @State private var isPulsing = false

    var body: some View {
        Image("chat_pp")
            .resizable()
            .scaledToFit()
            .clipShape(Circle())
            .scaleEffect(isPulsing ? 1.08 : 0.92)
            .opacity(isPulsing ? 1.0 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - UIImagePickerController Wrapper (Ayarlar → profil fotoğrafı)

struct AppImagePicker: UIViewControllerRepresentable {
    var onImageSelected: (Data) -> Void
    @Environment(\.presentationMode) var presentationMode
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: AppImagePicker
        init(_ parent: AppImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = ImageUtils.preparedJPEG(from: image, maxDimension: 800) {
                parent.onImageSelected(data)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - PHPickerViewController Wrapper (Çoklu galeri seçimi)

struct MultiImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [Data]
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 10
        config.filter = .images
        config.selection = .ordered
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker
        init(_ parent: MultiImagePicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            guard !results.isEmpty else { return }

            // Sonuçlar paralel ve farklı thread'lerden gelir: kilit + sıra korumalı dizi
            // (eskiden ortak diziye kilitsiz ekleniyordu → nadiren çökme/kayıp görsel)
            var datas = [Data?](repeating: nil, count: results.count)
            let lock = NSLock()
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage,
                          let data = ImageUtils.preparedJPEG(from: image) else { return }
                    lock.lock()
                    datas[index] = data
                    lock.unlock()
                }
            }

            group.notify(queue: .main) {
                for data in datas.compactMap({ $0 }) where !self.parent.selectedImages.contains(data) {
                    self.parent.selectedImages.append(data)
                }
            }
        }
    }
}

// MARK: - Kullanıcının yukarı kaydırması (sürükleme hareketi eklemeden)

private struct UserScrollUpDetector: ViewModifier {
    let onScrollUp: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(UserScrollUp18(onScrollUp: onScrollUp))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct UserScrollUp18: ViewModifier {
    let onScrollUp: () -> Void
    @State private var interacting = false
    @State private var startOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase, context in
                interacting = phase == .interacting
                if interacting { startOffset = context.geometry.contentOffset.y }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, offset in
                // Parmak aşağı → içerik yukarı (eski mesajlara doğru)
                if interacting, startOffset - offset > 40 {
                    startOffset = offset
                    onScrollUp()
                }
            }
    }
}

// MARK: - Dosya Metin Önizleme Sayfası

struct FilePreviewSheet: View {
    let file: FileAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if file.truncated {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text(NSLocalizedString("Metin en fazla 60.000 karakter olacak şekilde sınırlandırıldı.", comment: ""))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                }

                ScrollView {
                    SelectableText(text: AttributedString(file.text), hugs: false)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
