import SwiftUI
import UIKit

// MARK: - Premium Haptic Manager (Singleton Generators — avoid re-creation overhead)
struct PremiumHaptics {
    // Singleton generator'lar — her çağrıda yeniden oluşturmak yerine
    // tek nesne üzerinden prepare() + impactOccurred() çağrılır
    private static let lightGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()
    
    private static let mediumGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()
    
    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        return g
    }()
    
    static func light() {
        lightGenerator.impactOccurred(intensity: 0.5)
        lightGenerator.prepare() // Sonraki kullanım için hazırla
    }
    
    static func medium() {
        mediumGenerator.impactOccurred(intensity: 0.7)
        mediumGenerator.prepare()
    }
    
    private static let softGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        return g
    }()

    /// Cevap yazılırken çok hafif tık hissi
    static func typingTick() {
        softGenerator.impactOccurred(intensity: 0.55)
        softGenerator.prepare()
    }
    
    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
}

// MARK: - Smooth Spring Presets (120Hz ProMotion optimize — tüm uygulamada tutarlı)
enum SmoothSpring {
    /// Buton basışları, küçük UI — hızlı, 120Hz'de tereyağı gibi
    static let quick       = Animation.spring(response: 0.26, dampingFraction: 0.78, blendDuration: 0)
    /// Menü, sayfa geçişleri — dengeli
    static let standard    = Animation.spring(response: 0.36, dampingFraction: 0.84, blendDuration: 0)
    /// Tam ekran overlay'ler — zarif
    static let gentle      = Animation.spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0)
    /// Kart bırakma — yaylı ama anlık
    static let snappy      = Animation.spring(response: 0.26, dampingFraction: 0.74, blendDuration: 0)
    /// Fade geçişler
    static let fade        = Animation.easeInOut(duration: 0.20)
    /// Sürükleme sırasında — interaktif, 120Hz'de ekstra akıcı
    static let interactive = Animation.interactiveSpring(response: 0.20, dampingFraction: 0.80, blendDuration: 0)
}

// MARK: - Premium Scale Button Style (Yumuşatılmış — dokunma yorgunluğu yok)
struct PremiumScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0), value: configuration.isPressed)
    }
}

// MARK: - Premium Card Button Style (Daha ince — kartlar/listeler için)
struct PremiumCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.78, blendDuration: 0), value: configuration.isPressed)
    }
}

// MARK: - View Extension for Quick Premium Button Application
extension View {
    func premiumButtonStyle() -> some View {
        self.buttonStyle(PremiumScaleButtonStyle())
    }
    
    func premiumCardStyle() -> some View {
        self.buttonStyle(PremiumCardButtonStyle())
    }
}

// MARK: - Liquid Glass Kısayolları
// Asıl uygulama PufyTheme.swift içindeki `pufyGlass` modifier'ında.
// Eski çağrılar bozulmasın diye isimler korundu; artık iOS 26'da interaktif cam da destekleniyor.

extension View {
    /// Yuvarlak cam efekti (ikon butonları)
    func liquidGlassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        pufyGlass(Circle(), tint: tint, interactive: interactive)
    }

    /// Kapsül cam efekti (uzun butonlar, metin kutuları)
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        pufyGlass(Capsule(), tint: tint, interactive: interactive)
    }

    /// Yuvarlatılmış dikdörtgen cam efekti (paneller)
    func liquidGlassRoundedRect(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        pufyGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive)
    }
}
