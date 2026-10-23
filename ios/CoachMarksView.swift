import SwiftUI

// MARK: - İlk Açılış İpuçları (Coach Marks)
//
// Kullanıcı kurulumu tamamlayıp ilk kez sohbet ekranına geldiğinde 3 adımlı rehber gösterilir.
// 1. İki parmakla kıstırma (uygulamalara geçiş) + kodla çizilen kıstırma animasyonu
// 2. Yan menü (≡ butonu spotlight)
// 3. Giriş alanı (composer spotlight)

struct CoachMarksView: View {
    @Binding var isPresented: Bool
    var onPinchSuccess: (() -> Void)? = nil

    @State private var currentStep = 0
    @State private var pinchAnimationPhase: CGFloat = 0
    @State private var pulseAnimation = false
    @State private var didCompletePinch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let totalSteps = 3

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Karartma katmanı (Spotlight maskesi ile)
                spotlightOverlay(in: geo)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        advanceStep()
                    }

                // Adım içeriği
                VStack {
                    if currentStep == 0 {
                        stepPinchContent(in: geo)
                    } else if currentStep == 1 {
                        stepMenuContent(in: geo)
                    } else {
                        stepComposerContent(in: geo)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .simultaneousGesture(
            currentStep == 0 ?
                MagnificationGesture()
                    .onChanged { scale in
                        if scale < 0.88 && !didCompletePinch {
                            didCompletePinch = true
                            PremiumHaptics.success()
                            onPinchSuccess?()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                withAnimation(SmoothSpring.standard) {
                                    currentStep = 1
                                }
                            }
                        }
                    }
                : nil
        )
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Spotlight Maskeli Karartma

    @ViewBuilder
    private func spotlightOverlay(in geo: GeometryProxy) -> some View {
        let size = geo.size
        let safeTop = geo.safeAreaInsets.top
        let safeBottom = geo.safeAreaInsets.bottom

        Canvas { context, canvasSize in
            // Tam ekran karartma (%55 siyah)
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(Color.black.opacity(0.55)))

            // Spotlight oyması
            context.blendMode = .clear

            if currentStep == 1 {
                // ≡ Menü düğmesi (sol üst, yaklaşık x: 38, y: safeTop + 24)
                let menuRect = CGRect(x: 16, y: safeTop + 6, width: 44, height: 44)
                context.fill(Path(ellipseIn: menuRect), with: .color(.black))
            } else if currentStep == 2 {
                // Alttaki composer (yaklaşık y: size.height - safeBottom - 60)
                let composerRect = CGRect(
                    x: 16,
                    y: size.height - safeBottom - 68,
                    width: size.width - 32,
                    height: 56
                )
                context.fill(Path(roundedRect: composerRect, cornerRadius: 28), with: .color(.black))
            }
        }
        .overlay {
            // Spotlight nabız atan monokrom çerçeveler
            if currentStep == 1 {
                Circle()
                    .stroke(Color.white.opacity(pulseAnimation ? 0.7 : 0.2), lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .position(x: 38, y: safeTop + 28)
                    .allowsHitTesting(false)
            } else if currentStep == 2 {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.white.opacity(pulseAnimation ? 0.7 : 0.2), lineWidth: 2)
                    .frame(width: size.width - 28, height: 60)
                    .scaleEffect(pulseAnimation ? 1.02 : 1.0)
                    .position(x: size.width / 2, y: size.height - safeBottom - 40)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Adım 1: Kıstırma Animasyonu ve Kartı

    @ViewBuilder
    private func stepPinchContent(in geo: GeometryProxy) -> some View {
        VStack(spacing: 32) {
            Spacer()

            // İki parmak kıstırma animasyonu (kodla çizim, ~44pt daireler, 1.6s periyot)
            ZStack {
                if didCompletePinch {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(Color.pufyPrimary)
                        Text("Harika!")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if reduceMotion {
                    // Hareketi azalt: sabit çizim
                    HStack(spacing: 60) {
                        fingerCircle
                        fingerCircle
                    }
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    // Dinamik iki parmak ucu dairesi
                    let spread: CGFloat = 60 * (1.0 - pinchAnimationPhase)
                    HStack(spacing: max(16, spread * 2)) {
                        fingerCircle
                        fingerCircle
                    }
                }
            }
            .frame(height: 120)

            // Cam kart
            cardView(
                title: didCompletePinch ? "Harika!" : "Uygulamalarına ulaş",
                subtitle: didCompletePinch ? "Şimdi diğer özelliklere göz atalım." : "İki parmakla kıstır. Uygulamalarına buradan geçersin. Üstteki ızgara düğmesi de aynı işi yapar.",
                step: 1
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var fingerCircle: some View {
        Circle()
            .fill(Color.white.opacity(0.85))
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 4))
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }

    // MARK: - Adım 2: Menü

    @ViewBuilder
    private func stepMenuContent(in geo: GeometryProxy) -> some View {
        VStack {
            Spacer().frame(height: geo.safeAreaInsets.top + 60)

            cardView(
                title: "Menü",
                subtitle: "Sohbetlerin, notların, hatırlatıcıların ve Kişisel Ağ burada. Soldan sağa kaydırarak da açabilirsin.",
                step: 2
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Adım 3: Giriş Alanı

    @ViewBuilder
    private func stepComposerContent(in geo: GeometryProxy) -> some View {
        VStack {
            Spacer()

            cardView(
                title: "Her şeyi sor",
                subtitle: "Yaz ya da mikrofona bas. Hatırlatıcı kur, araştırma yaptır, 'yarın 9'da hatırlat' de.",
                step: 3
            )
            .padding(.horizontal, 24)

            Spacer().frame(height: geo.safeAreaInsets.bottom + 84)
        }
    }

    // MARK: - Cam Yüzeyli Kart

    private func cardView(title: String, subtitle: String, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            HStack {
                // Adım noktaları
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { idx in
                        Circle()
                            .fill(idx == (step - 1) ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                Button {
                    PremiumHaptics.light()
                    dismissPermanently()
                } label: {
                    Text("Atla")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }

                Button {
                    PremiumHaptics.light()
                    advanceStep()
                } label: {
                    Text(step == totalSteps ? "Başla" : "Sonraki")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.pufyPrimary))
                }
                .buttonStyle(PremiumScaleButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(20)
        .pufyGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
    }

    // MARK: - Yardımcılar

    private func advanceStep() {
        if currentStep < totalSteps - 1 {
            withAnimation(SmoothSpring.standard) {
                currentStep += 1
            }
        } else {
            dismissPermanently()
        }
    }

    private func dismissPermanently() {
        UserDefaults.standard.set(true, forKey: "coach_marks_completed")
        withAnimation(SmoothSpring.standard) {
            isPresented = false
        }
    }

    private func startAnimations() {
        guard !reduceMotion else { return }

        // Parmak kıstırma döngüsü ~1.6 saniye
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pinchAnimationPhase = 0.85
        }

        // Spotlight nabız döngüsü
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }
}

// MARK: - Bağlamsal Tek Seferlik İpucu Balonu

struct HintBubbleView: View {
    let text: LocalizedStringKey
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pufyPrimary)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                PremiumHaptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 340)
        .pufyGlass(Capsule(), interactive: true)
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
        .onTapGesture {
            PremiumHaptics.light()
            onDismiss()
        }
    }
}
