import SwiftUI
import UIKit
import GameController

// MARK: - Pufy Renk Paleti
// Tek kaynak. 13 Ekim 2026: renkten bağımsız, sade siyah-beyaz (monokrom) tasarıma geçildi.
// Açık temada "ana renk" siyah, koyu temada beyaz. Ana rengin ÜSTÜNDEKİ ikon/yazı için
// `pufyOnPrimary` kullanılmalı (açıkta beyaz, koyuda siyah) — sabit `.white` koyu temada kaybolur.

extension Color {
    /// Ana vurgu — butonlar, seçili durumlar (açık: siyah, koyu: beyaz)
    static let pufyPrimary      = Color(light: 0x111111, dark: 0xF2F2F2)
    /// Ana rengin üstündeki ikon/yazı
    static let pufyOnPrimary    = Color(light: 0xFFFFFF, dark: 0x111111)
    /// En koyu ton
    static let pufyPrimaryDeep  = Color(light: 0x000000, dark: 0xFFFFFF)
    /// İkincil vurgu — nötr gri
    static let pufyIndigo       = Color(light: 0x48484A, dark: 0xC7C7CC)
    /// Çip / rozet / seçili satır zemini
    static let pufySoft         = Color(light: 0xF2F2F4, dark: 0x2A2A2C)
    /// Açık zemin üzerindeki metin/ikon
    static let pufyOnSoft       = Color(light: 0x1C1C1E, dark: 0xF2F2F7)
    /// Hatırlatıcı vurgusu (nötr)
    static let pufyReminder     = Color(light: 0x3A3A3C, dark: 0xD1D1D6)
    /// Kullanıcı mesaj balonu
    static let pufyUserBubble   = Color(light: 0xF2F2F4, dark: 0x2A2A2C)
    /// Gönder butonunun pasif hali
    static let pufyDisabled     = Color(light: 0xD8D8DC, dark: 0x3A3A3C)

    /// Karşılama yazısı (artık düz renk — eskiden mor gradyandı)
    static var pufyGradient: Color { .pufyPrimary }

    /// "#RRGGBB" → Color (geçersizse nil)
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(UIColor(hex: value))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue:  CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Liquid Glass Temelleri
// Kural (Apple HIG): Cam efekti SADECE içeriğin üzerinde yüzen kontrol katmanında
// kullanılır (üst bar, mesaj kutusu, yüzen butonlar). İçeriğin kendisi (mesajlar,
// kartlar, listeler) cam olmaz. Cam üstüne cam konmaz; yakın cam elemanlar
// GlassEffectContainer içinde gruplanır ki birbirine akabilsin (morph).

extension View {
    /// Liquid Glass (iOS 26+). Eski sürümlerde ince materyal + hafif kenar çizgisi.
    /// - interactive: dokununca cam büyür/parlar (butonlar için true)
    @ViewBuilder
    func pufyGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.85)) }
                    }
                }
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
    }

    /// Cam elemanlar arası morph geçişi için kimlik (iOS 26+; eskilerde etkisiz)
    @ViewBuilder
    func pufyGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// İki cam elemanı tek parça gibi birleştirir (ör. yan yana iki header butonu)
    @ViewBuilder
    func pufyGlassUnion<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectUnion(id: id, namespace: namespace)
        } else {
            self
        }
    }

    /// İçeriğin ÜZERİNDE yüzen bar (üst başlık / alt mesaj kutusu).
    /// iOS 26'da `safeAreaBar`: kaydırılan içerik camın altından geçer ve kenar efekti uygulanır.
    /// Eski sürümlerde `safeAreaInset` (aynı yerleşim, efekt yok).
    @ViewBuilder
    func pufyBar<Bar: View>(edge: VerticalEdge, @ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            self.safeAreaInset(edge: edge, spacing: 0, content: content)
        }
    }

    /// Sohbet listesi alta yapışık: ilk açılışta en altta başlar; klavye açılıp kapanınca ve
    /// içerik uzadıkça (kullanıcı alttaysa) alt kenar sabit kalır. iOS 18+ yerel davranış.
    @ViewBuilder
    func pufyChatScrollAnchor(followBottom: Bool) -> some View {
        if #available(iOS 18, *) {
            self
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(followBottom ? .bottom : nil, for: .sizeChanges)
        } else if #available(iOS 17, *) {
            self.defaultScrollAnchor(.bottom)
        } else {
            self
        }
    }

    /// Donanım klavyesinde (iPad) Enter → gönder, Shift+Enter → yeni satır.
    /// Ekran klavyesinde Return eskisi gibi yeni satır açar.
    /// İki katman: onKeyPress (iOS 17+) + çok satırlı TextField Return'ü kendisi işlerse diye metne eklenen
    /// satır sonunu yakalayan yedek (yalnızca donanım klavyesi bağlıyken ve Shift basılı değilken).
    func pufySubmitOnReturn(text: Binding<String>, _ action: @escaping () -> Void) -> some View {
        modifier(SubmitOnHardwareReturn(text: text, action: action))
    }

    /// iPad'de sayfalar (Kişisel Ağ, Ayarlar) küçük form kutusu yerine daha büyük "sayfa" boyutunda açılsın (iOS 18+)
    @ViewBuilder
    func pufyLargeSheet() -> some View {
        if #available(iOS 18, *) {
            self.presentationSizing(.page)
        } else {
            self
        }
    }

    /// SF Symbol değişimlerinde yumuşak geçiş (iOS 17+)
    @ViewBuilder
    func pufySymbolReplace() -> some View {
        if #available(iOS 17, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    /// iOS 26: kaydırılan içeriğin üst/alt barların altında yumuşakça kaybolması
    @ViewBuilder
    func pufySoftScrollEdges() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

/// Yakın cam elemanları gruplar: iOS 26'da birbirine akarak (morph) birleşirler.
struct PufyGlassContainer<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Buton Stilleri

/// Cam butonlar için basma stili. iOS 26'da interaktif cam zaten tepki verdiği için
/// ekstra ölçekleme yapılmaz (çift animasyon olmasın); eski sürümlerde hafif küçülür.
struct PufyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
                .contentShape(Rectangle())
        } else {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(SmoothSpring.quick, value: configuration.isPressed)
        }
    }
}

/// Yuvarlak cam ikon butonu (header, menü vb.)
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var tint: Color? = nil
    var foreground: Color = .primary
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            PremiumHaptics.light()
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .pufyGlass(Circle(), tint: tint, interactive: true)
        }
        .buttonStyle(PufyPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Shimmer (ChatGPT'deki "Düşünüyor…" parlaması)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    var active: Bool = true

    func body(content: Content) -> some View {
        if active {
            content
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color(UIColor.systemBackground).opacity(0.75), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

// MARK: - Donanım klavyesi: Enter ile gönder


private struct SubmitOnHardwareReturn: ViewModifier {
    @Binding var text: String
    let action: () -> Void
    @State private var previous = ""

    private var keyboardConnected: Bool { GCKeyboard.coalesced != nil }
    private var shiftDown: Bool {
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return false }
        return input.button(forKeyCode: .leftShift)?.isPressed == true || input.button(forKeyCode: .rightShift)?.isPressed == true
    }

    func body(content: Content) -> some View {
        content
            .modifier(KeyPressReturn(action: action))
            .onChange(of: text) { newValue in
                defer { previous = text }
                // Yedek: Return metne "\n" olarak eklendiyse geri al ve gönder
                guard keyboardConnected, !shiftDown, newValue.count == previous.count + 1, newValue.hasSuffix("\n") else { return }
                text = String(newValue.dropLast())
                action()
            }
    }
}

private struct KeyPressReturn: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
                action()
                return .handled
            }
        } else {
            content
        }
    }
}
