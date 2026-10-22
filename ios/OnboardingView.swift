import SwiftUI

// MARK: - Sağ Kenardan Çekme (Uygulamalar)
//
// İki parmakla kıstırma gizli bir hareketti; uygulamayı ilk kez açan biri bilemezdi.
// Artık ekranın sağ kenarından ortaya doğru çekince de Uygulamalar açılır. Çekerken parmağı
// takip eden bir cam tutamaç görünür. İlk birkaç açılışta kenarda ince bir ipucu çizgisi durur.

struct EdgeSwipeToApps: View {
    let isEnabled: Bool
    let onOpen: () -> Void

    @AppStorage("pufy_edge_hint_count") private var hintCount = 0
    @State private var drag: CGFloat = 0
    @State private var showHint = false
    @State private var hintPulse = false

    private let threshold: CGFloat = 90

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                // Parmağı takip eden tutamaç
                if drag > 4 {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                        if drag > 50 { Text("Uygulamalar").font(.subheadline.weight(.semibold)) }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .pufyGlass(Capsule())
                    .scaleEffect(min(1, 0.6 + drag / threshold * 0.4))
                    .offset(x: max(-drag * 0.7, -140) + 60)
                    .opacity(min(1, drag / 40))
                    .transition(.opacity)
                }

                // İlk açılışlardaki ipucu çizgisi (dokununca da açılır)
                if showHint && drag == 0 {
                    Capsule()
                        .fill(Color.primary.opacity(hintPulse ? 0.35 : 0.15))
                        .frame(width: 4, height: 54)
                        .padding(.trailing, 3)
                        .offset(x: hintPulse ? -3 : 0)
                        .onTapGesture(perform: onOpen)
                        .transition(.opacity)
                        .accessibilityLabel("Uygulamalar")
                        .accessibilityAddTraits(.isButton)
                }

                // Görünmez dokunma şeridi (kenarın orta kısmı — üst bar ve mesaj kutusuyla çakışmaz)
                Color.clear
                    .frame(width: 16, height: max(geo.size.height - 300, 100))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .global)
                            .onChanged { value in
                                guard isEnabled else { return }
                                drag = max(0, -value.translation.width)
                            }
                            .onEnded { value in
                                let predicted = -value.predictedEndTranslation.width
                                if isEnabled && (drag > threshold || predicted > threshold * 2) {
                                    PremiumHaptics.medium()
                                    onOpen()
                                    hintCount += 10   // hareket öğrenildi: ipucu bir daha gösterilmez
                                    showHint = false
                                }
                                withAnimation(SmoothSpring.standard) { drag = 0 }
                            }
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
        }
        .allowsHitTesting(isEnabled)
        .onAppear {
            guard hintCount < 5 else { return }
            hintCount += 1
            withAnimation(.easeOut(duration: 0.4).delay(2)) { showHint = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(2)) { hintPulse = true }
            // 10 sn sonra kendiliğinden kaybolur
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                withAnimation(.easeOut(duration: 0.5)) { showHint = false }
            }
        }
    }
}

// MARK: - İlk Açılış Rehberi

struct OnboardingView: View {
    let needsSetup: Bool
    var initialStep: Step = .intro(0)
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    @State private var step: Step = .intro(0)

    // Yapay zeka kurulum state'i
    @State private var selectedPresetId: String = "gemini"
    @State private var customEndpoint: String = ""
    @State private var customFormat: APIFormat = .openAI
    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var model: String = ""
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var showModelPicker: Bool = false
    @State private var modelSearchQuery: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var isTesting: Bool = false
    @State private var presentedURL: IdentifiableURL? = nil

    enum Step: Equatable {
        case intro(Int)
        case privacy
        case connectAI
    }

    enum TestStatus: Equatable {
        case idle
        case success
        case failure(String)
    }

    private struct IntroPage {
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let introPages: [IntroPage] = [
        IntroPage(icon: "bubble.left.and.text.bubble.right",
                  title: "Pufy'ye hoş geldin",
                  text: "Sorularını cevaplayan, web'de araştıran, hatırlatıcı kuran kişisel yapay zeka asistanın. İstediğin yapay zeka modelini bağlayabilirsin."),
        IntroPage(icon: "point.3.connected.trianglepath.dotted",
                  title: "Seni tanır",
                  text: "Konuştukça seninle ilgili önemli şeyleri öğrenir ve kişisel ağında saklar. Gerektiğinde hatırlar, istemediğini silersin."),
        IntroPage(icon: "square.grid.2x2",
                  title: "Uygulamalar",
                  text: "Ekranın sağ kenarından ortaya doğru çek ya da iki parmakla kıstır. Ne istediğini anlat, Pufy senin için bir uygulama ya da oyun yazsın."),
        IntroPage(icon: "mic",
                  title: "Konuşarak yaz",
                  text: "Mesaj kutusundaki mikrofona dokun, Türkçe ya da İngilizce karışık konuş; Pufy sesini yazıya döker.")
    ]

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            switch step {
            case .intro(let index):
                introView(currentIndex: index)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            case .privacy:
                privacyView
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .connectAI:
                connectAIView
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .animation(SmoothSpring.standard, value: step)
        .onAppear {
            if initialStep != .intro(0) {
                step = initialStep
            }
        }
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
        }
        .sheet(item: $presentedURL) { item in
            SafariView(url: item.url)
        }
        .environment(\.openURL, OpenURLAction { url in
            presentedURL = IdentifiableURL(url: url)
            return .handled
        })
    }

    // MARK: - 1. Tanıtım Sayfaları

    private func introView(currentIndex: Int) -> some View {
        VStack(spacing: 0) {
            TabView(selection: Binding(
                get: { currentIndex },
                set: { step = .intro($0) }
            )) {
                ForEach(Array(introPages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 22) {
                        Spacer()
                        ZStack {
                            Circle().fill(Color.pufySoft).frame(width: 128, height: 128)
                            Image(systemName: item.icon)
                                .font(.system(size: 50, weight: .regular))
                                .foregroundStyle(Color.pufyPrimary)
                            if index == 2 { SwipeHandDemo() }
                        }
                        Text(item.title)
                            .font(.system(.title, design: .rounded).weight(.bold))
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(0..<introPages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: i == currentIndex ? 18 : 6, height: 6)
                }
            }
            .animation(SmoothSpring.quick, value: currentIndex)
            .padding(.bottom, 24)

            Button {
                PremiumHaptics.medium()
                if currentIndex < introPages.count - 1 {
                    withAnimation(SmoothSpring.standard) { step = .intro(currentIndex + 1) }
                } else {
                    withAnimation(SmoothSpring.standard) { step = .privacy }
                }
            } label: {
                Text("Devam")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.pufyOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.pufyPrimary))
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .padding(.horizontal, 24)

            Button("Geç") { onFinish() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

            let legalText: LocalizedStringKey = AppLanguage.isEnglish
                ? "By continuing, you agree to the [Terms of Service](\(LegalLinks.termsURLString)) and [Privacy Policy](\(LegalLinks.privacyURLString))."
                : "Devam ederek [Kullanım koşulları](\(LegalLinks.termsURLString)) ve [Gizlilik politikası](\(LegalLinks.privacyURLString))'nı kabul etmiş olursun."

            Text(legalText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
    }

    // MARK: - 2. "Verilerin sende" Ekranı

    private var privacyView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.pufySoft)
                        .frame(width: 88, height: 88)
                    Image(systemName: "lock.shield")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(Color.pufyPrimary)
                }

                Text(AppLanguage.isEnglish ? "Your data stays with you" : "Verilerin sende")
                    .font(.system(.title2, design: .rounded).weight(.bold))
            }

            Spacer().frame(height: 28)

            ScrollView {
                VStack(spacing: 18) {
                    privacyItem(
                        icon: "iphone",
                        title: AppLanguage.isEnglish ? "Stored on your device" : "Cihazında saklanır",
                        desc: AppLanguage.isEnglish
                            ? "Chats, notes, reminders, and Personal Network stay only on this phone, protected by device encryption."
                            : "Sohbetlerin, notların, hatırlatıcıların ve Kişisel Ağ'ın yalnızca bu telefonda durur, telefonunun şifrelemesiyle korunur."
                    )
                    privacyItem(
                        icon: "person.slash",
                        title: AppLanguage.isEnglish ? "No account, no tracking" : "Hesap yok, takip yok",
                        desc: AppLanguage.isEnglish
                            ? "No sign-up. No ads, analytics, or tracking."
                            : "Kayıt olmazsın. Reklam, analitik ya da izleme yok."
                    )
                    privacyItem(
                        icon: "key",
                        title: AppLanguage.isEnglish ? "Your key is encrypted" : "Anahtarın şifreli",
                        desc: AppLanguage.isEnglish
                            ? "Your API key is stored securely on your device, never shared."
                            : "API anahtarın cihazında şifreli tutulur, kimseyle paylaşılmaz."
                    )
                    privacyItem(
                        icon: "paperplane",
                        title: AppLanguage.isEnglish ? "Only goes to the AI you choose" : "Sadece seçtiğin yapay zekaya gider",
                        desc: AppLanguage.isEnglish
                            ? "Your messages are sent only to the provider you connect (or the model on your computer). Never to us."
                            : "Mesajların yalnızca bağladığın sağlayıcıya (ya da kendi bilgisayarındaki modele) gönderilir. Bize hiç gelmez."
                    )
                }
                .padding(.horizontal, 24)
            }

            Spacer().frame(height: 16)

            VStack(spacing: 12) {
                Button {
                    PremiumHaptics.medium()
                    withAnimation(SmoothSpring.standard) { step = .connectAI }
                } label: {
                    Text("Devam")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.pufyPrimary))
                }
                .buttonStyle(PremiumScaleButtonStyle())

                if let privacyURL = URL(string: LegalLinks.privacyURLString) {
                    Link(destination: privacyURL) {
                        Text(AppLanguage.isEnglish ? "Privacy Policy" : "Gizlilik politikası")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func privacyItem(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color.pufySoft).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.pufyPrimary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(desc)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - 3. Yapay Zekanı Bağla Ekranı

    private var currentPreset: ProviderPreset? {
        ProviderPreset.all.first { $0.id == selectedPresetId }
    }

    private var isCurrentLocal: Bool {
        currentPreset?.isLocal == true
    }

    private var requiresKey: Bool {
        currentPreset?.requiresKey ?? true
    }

    private var effectiveEndpoint: String {
        if isCurrentLocal || selectedPresetId == "custom" {
            let trimmed = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return currentPreset?.baseURL ?? ""
        }
        return currentPreset?.baseURL ?? ""
    }

    private var effectiveFormat: APIFormat {
        if selectedPresetId == "custom" { return customFormat }
        return currentPreset?.format ?? .openAI
    }

    private var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return currentPreset?.modelHint ?? "gemini-2.5-flash"
    }

    private var isNonLocalInsecureHttp: Bool {
        let ep = effectiveEndpoint.lowercased()
        guard ep.hasPrefix("http://"), let host = URL(string: ep)?.host?.lowercased() else { return false }
        let parts = host.split(separator: ".")
        let is172Private = parts.count > 1 && parts[0] == "172" && (16...31).contains(Int(parts[1]) ?? 0)
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") ||
            host.hasPrefix("192.168.") || host.hasPrefix("10.") || is172Private
        return !isLocal
    }

    private var connectAIView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Yapay zekanı bağla")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Kendi yapay zekanı ya da bilgisayarındaki modeli bağlayabilirsin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                // Sağlayıcı Listesi (2 sütunlu ızgara: 12 seçenek rahat sığar)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sağlayıcı seç")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(ProviderPreset.all) { preset in
                            providerButton(preset: preset)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Yerel sağlayıcılar veya Özel sunucu adres alanı
                if isCurrentLocal || selectedPresetId == "custom" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sunucu adresi")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(currentPreset?.baseURL.isEmpty == false ? currentPreset!.baseURL : "http://192.168.1.10:11434/v1", text: $customEndpoint)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .pufyGlass(RoundedRectangle(cornerRadius: 14))

                        if isNonLocalInsecureHttp {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Güvenli olmayan bağlantı, https kullan")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        if let help = currentPreset?.helpText {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(help)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.pufySoft))
                        }

                        if selectedPresetId == "custom" {
                            Picker("Format", selection: $customFormat) {
                                Text("Gemini").tag(APIFormat.gemini)
                                Text("OpenAI uyumlu").tag(APIFormat.openAI)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // API Anahtarı (Yalnızca anahtar gerektiren sağlayıcılar)
                if currentPreset?.isLocal != true {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API anahtarı")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let keyUrl = currentPreset?.keyURL, let url = URL(string: keyUrl) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Text("Anahtar al")
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .font(.caption.weight(.medium))
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Group {
                                if showKey {
                                    TextField("API anahtarını yapıştır", text: $apiKey)
                                } else {
                                    SecureField("API anahtarını yapıştır", text: $apiKey)
                                }
                            }
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                if let clip = UIPasteboard.general.string {
                                    apiKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                    testStatus = .idle
                                }
                            } label: {
                                Text("Yapıştır")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.pufyPrimary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .pufyGlass(RoundedRectangle(cornerRadius: 14))
                    }
                }

                // Model Alanı
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField(currentPreset?.modelHint.isEmpty == false ? currentPreset!.modelHint : "model adı", text: $model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: model) { _ in testStatus = .idle }

                        let canFetch = !requiresKey || !apiKey.isEmpty
                        Button {
                            fetchModelsAction()
                        } label: {
                            HStack(spacing: 4) {
                                if isFetchingModels {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Modelleri getir")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(canFetch ? Color.pufyPrimary : Color.secondary)
                        }
                        .disabled(!canFetch || isFetchingModels)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .pufyGlass(RoundedRectangle(cornerRadius: 14))
                }

                // Bağlantıyı Dene Butonu ve Durum
                let canTest = !requiresKey || !apiKey.isEmpty
                VStack(spacing: 10) {
                    Button(action: runConnectionTest) {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTesting ? "Test ediliyor..." : "Bağlantıyı dene")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.pufySoft))
                        .foregroundStyle(Color.primary)
                    }
                    .disabled(isTesting || !canTest)
                    .opacity(canTest ? 1 : 0.6)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .success:
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Bağlandı")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 4)
                        .transition(.scale.combined(with: .opacity))
                    case .failure(let reason):
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                            Button("Yine de devam et") {
                                saveAndContinue()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 4)

                Spacer(minLength: 24)

                // Devam & Sonra Yaparım
                VStack(spacing: 12) {
                    let canProceed = testStatus == .success || apiKey.isEmpty || isCurrentLocal
                    Button(action: saveAndContinue) {
                        Text("Devam")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.pufyOnPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.pufyPrimary))
                    }
                    .buttonStyle(PremiumScaleButtonStyle())
                    .disabled(!canProceed)
                    .opacity(canProceed ? 1.0 : 0.6)

                    Button("Sonra yaparım") {
                        onFinish()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func providerButton(preset: ProviderPreset) -> some View {
        let isSelected = selectedPresetId == preset.id
        return Button {
            PremiumHaptics.light()
            selectedPresetId = preset.id
            testStatus = .idle
            model = preset.modelHint
            if preset.isLocal {
                customEndpoint = preset.baseURL
                apiKey = ""
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    if preset.id == "gemini" {
                        Text("Ücretsiz")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                }
                Text(preset.isLocal ? "Yerel model" : preset.format.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .pufyGlass(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func fetchModelsAction() {
        isFetchingModels = true
        Task {
            do {
                let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Bearer ", with: "")
                let list = try await GeminiService.shared.fetchModels(
                    endpoint: effectiveEndpoint,
                    format: effectiveFormat,
                    apiKey: cleanKey
                )
                await MainActor.run {
                    isFetchingModels = false
                    availableModels = list
                    showModelPicker = true
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                    testStatus = .failure(isCurrentLocal ? "Bilgisayara ulaşılamadı. Aynı Wi-Fi'de misiniz?" : "Modeller alınamadı: \(error.localizedDescription)")
                }
            }
        }
    }

    private func runConnectionTest() {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Bearer ", with: "")
        isTesting = true
        testStatus = .idle

        Task {
            let res = await GeminiService.shared.testConnectionDetailed(
                endpoint: effectiveEndpoint,
                format: effectiveFormat,
                apiKey: cleanKey,
                model: effectiveModel
            )
            await MainActor.run {
                isTesting = false
                switch res {
                case .success:
                    testStatus = .success
                    PremiumHaptics.success()
                case .failure(let error):
                    let msg = isCurrentLocal ? "Bilgisayara ulaşılamadı. Aynı Wi-Fi'de misiniz?" : error.localizedDescription
                    testStatus = .failure(msg)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func saveAndContinue() {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Bearer ", with: "")
        let endpointToSave = effectiveEndpoint
        let modelToSave = effectiveModel
        let formatToSave = effectiveFormat
        let isGemini = formatToSave == .gemini
        let imageModelToSave = isGemini ? "gemini-3.1-flash-image" : ""

        if !cleanKey.isEmpty || isCurrentLocal {
            AIConfig.save(
                apiKey: cleanKey,
                endpoint: endpointToSave,
                model: modelToSave,
                format: formatToSave,
                imageModel: imageModelToSave,
                streaming: true,
                searxngURL: "",
                jinaKey: "",
                googleSearch: isGemini,
                heavyModel: modelToSave
            )
        }
        onFinish()
    }

    // Model Seçim Sheet
    private var modelPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(filteredModels, id: \.self) { item in
                    Button {
                        model = item
                        showModelPicker = false
                        testStatus = .idle
                    } label: {
                        HStack {
                            Text(item)
                                .font(.body)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if model == item {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.pufyPrimary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $modelSearchQuery, prompt: "Model ara")
            .navigationTitle("Modeller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { showModelPicker = false }
                }
            }
        }
    }

    private var filteredModels: [String] {
        if modelSearchQuery.isEmpty { return availableModels }
        return availableModels.filter { $0.localizedCaseInsensitiveContains(modelSearchQuery) }
    }
}

/// Rehberde sağdan sola çekme hareketini gösteren el animasyonu
private struct SwipeHandDemo: View {
    @State private var move = false

    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 30))
            .foregroundStyle(.secondary)
            .offset(x: move ? -10 : 60, y: 52)
            .opacity(move ? 0 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { move = true }
            }
    }
}
