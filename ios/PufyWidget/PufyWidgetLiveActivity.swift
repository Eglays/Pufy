import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Pufy Canlı Etkinlik (Kilit Ekranı + Dinamik Ada)
//
// ESKİ SORUNLAR:
//  • Logo yerine "P" harfi vardı: widget'taki görsel 2048 px / 3,4 MB'tı, canlı etkinliklerin görsel
//    sınırını aştığı için yüklenmiyordu → 40/80/120 px sürümler eklendi.
//  • Geri sayım `Date.now...bitiş` aralığıyla çiziliyordu: süre dolduktan sonra yeniden çizilince
//    aralık ters dönüp eklenti çökebiliyordu.
//  • Sadece metin vardı; ilerleme yoktu.
//  • Logo görseli widget paketine hiç girmiyordu (project.yml'de geçersiz "resources:" anahtarı).
//  • Zemin rengi verilmezse iOS 17+ sistem camı yerine DÜZ SİYAH çiziyor (bilinen davranış) → her modda siyahtı.
//    Artık zemin moda göre yarı saydam: altta kilit ekranı bulanıklaşır, üstte hafif cam parlaması (opak cam görünümü).
// YENİ: gerçek logo, açık/koyu moda uyan kilit ekranı, canlı geri sayım + dolan çubuk, Dinamik Ada'da halka.

private extension Color {
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

private extension PufyLiveActivityAttributes {
    /// Mini uygulamanın kimlik rengi; Pufy'nin kendi etkinliklerinde nil (ön plan rengi kullanılır)
    var accentColor: Color? { Color(hexString: colorHex) }

    /// Mini uygulama etkinliği → o uygulamayı açar (kimlik: pufyapp.<klasör>.<no>)
    var deepLink: URL? {
        let parts = reminderID.split(separator: ".")
        if kind == .app, parts.count >= 3, parts[0] == "pufyapp" {
            return URL(string: "pufy://app/\(parts[1])")
        }
        return URL(string: "pufy://home")
    }

    var caption: String {
        if let appName { return appName.uppercased(with: Locale(identifier: "tr_TR")) }
        switch kind {
        case .reminder: return "PUFY · HATIRLATICI"
        case .timer:    return "PUFY · ZAMANLAYICI"
        case .task:     return "PUFY"
        case .app:      return "PUFY"
        }
    }
}

private extension PufyLiveActivityAttributes.ContentState {
    /// Geri sayım aralığı — her zaman geçerli (başlangıç ≤ bitiş)
    var countdownRange: ClosedRange<Date>? {
        guard let endDate else { return nil }
        return min(startDate, endDate)...endDate
    }
}

/// Uygulama logosu (Pufy) ya da mini uygulamanın renkli ikon kutusu
private struct ActivityIcon: View {
    let attributes: PufyLiveActivityAttributes
    let size: CGFloat

    var body: some View {
        if attributes.appName != nil {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill((attributes.accentColor ?? .gray).gradient)
                .overlay(
                    Image(systemName: attributes.symbol)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .frame(width: size, height: size)
        } else {
            Image("chat_pp")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

/// Sağdaki büyük değer: geri sayım, yüzde ya da tamamlandı işareti
private struct TrailingValue: View {
    let state: PufyLiveActivityAttributes.ContentState
    let isStale: Bool
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        if state.isFinished || isStale {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: fontSize * 0.9, weight: .semibold))
                .foregroundStyle(color)
        } else if let range = state.countdownRange {
            Text(timerInterval: range, countsDown: true)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText(countsDown: true))
        } else if let progress = state.progress {
            Text("%\(Int(progress * 100))")
                .font(.system(size: fontSize * 0.8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

/// Alttaki ilerleme çubuğu: geri sayımda zamanla kendiliğinden dolar
private struct ActivityProgressBar: View {
    let state: PufyLiveActivityAttributes.ContentState
    let accent: Color
    let isStale: Bool

    var body: some View {
        if state.isFinished || isStale {
            ProgressView(value: 1).tint(accent)
        } else if let range = state.countdownRange {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent)
        } else if let progress = state.progress {
            ProgressView(value: min(max(progress, 0), 1)).tint(accent)
        }
    }
}

/// Dinamik Ada'daki küçük halka
private struct RingProgress: View {
    let state: PufyLiveActivityAttributes.ContentState
    let accent: Color
    let isStale: Bool

    var body: some View {
        if state.isFinished || isStale {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
        } else if let range = state.countdownRange {
            ProgressView(timerInterval: range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(accent)
        } else if let progress = state.progress {
            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.circular)
                .tint(accent)
        } else {
            ProgressView().progressViewStyle(.circular).tint(accent)
        }
    }
}

// MARK: - Widget

struct PufyWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PufyLiveActivityAttributes.self) { context in
            // Kilit ekranı: moda uyan opak cam (zemin LockScreenLiveActivityView içinde, renk şemasını orada okur)
            LockScreenLiveActivityView(context: context)
                .widgetURL(context.attributes.deepLink)

        } dynamicIsland: { context in
            // Dinamik Ada her zaman siyah → içerik beyaz
            let attributes = context.attributes
            let state = context.state
            let accent = attributes.accentColor ?? .white
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if state.resolvedStyle == "score", let home = state.home {
                        SideBadge(side: home, size: 44).padding(.leading, 6)
                    } else {
                    HStack(spacing: 8) {
                        ActivityIcon(attributes: attributes, size: 30)
                        Text(attributes.appName ?? "Pufy")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.resolvedStyle == "score", let away = state.away {
                        SideBadge(side: away, size: 44).padding(.trailing, 6)
                    } else if state.resolvedStyle != "metric" {
                        TrailingValue(state: state, isStale: context.isStale, fontSize: 24, color: .white)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if state.resolvedStyle == "score" {
                        VStack(spacing: 0) {
                            Text("\(state.homeScore ?? 0) - \(state.awayScore ?? 0)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(state.minute ?? state.status ?? "")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else if state.resolvedStyle == "metric", let value = state.value {
                        Text(value + (state.unit.map { " " + $0 } ?? ""))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.resolvedStyle == "score" {
                        HStack {
                            Text(state.home?.name ?? "").lineLimit(1)
                            Spacer()
                            Text(state.away?.name ?? "").lineLimit(1)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                    } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(state.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let status = state.status ?? (context.isStale ? "Süre doldu" : nil) {
                                Text(status)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        ActivityProgressBar(state: state, accent: accent, isStale: context.isStale)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                if state.resolvedStyle == "score", let home = state.home {
                    HStack(spacing: 4) {
                        SideBadge(side: home, size: 20)
                        Text("\(state.homeScore ?? 0)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                } else {
                    ActivityIcon(attributes: attributes, size: 22)
                }
            } compactTrailing: {
                if state.resolvedStyle == "score", let away = state.away {
                    HStack(spacing: 4) {
                        Text("\(state.awayScore ?? 0)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                        SideBadge(side: away, size: 20)
                    }
                } else if state.resolvedStyle == "metric", let value = state.value {
                    Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 64)
                } else {
                if state.countdownRange != nil, !state.isFinished, !context.isStale {
                    TrailingValue(state: state, isStale: context.isStale, fontSize: 14, color: .white)
                        .frame(maxWidth: 52)
                } else {
                    RingProgress(state: state, accent: accent, isStale: context.isStale)
                        .frame(width: 20, height: 20)
                }
                }
            } minimal: {
                RingProgress(state: state, accent: accent, isStale: context.isStale)
                    .frame(width: 20, height: 20)
            }
            .widgetURL(attributes.deepLink)
            .keylineTint(accent)
        }
    }
}

// MARK: - Kilit Ekranı

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<PufyLiveActivityAttributes>
    @Environment(\.colorScheme) private var scheme

    /// Opak cam: açık modda süt beyazı, koyu modda füme — kilit ekranı arkadan bulanık görünür
    private var glassTint: Color {
        scheme == .dark ? Color(white: 0.08).opacity(0.55) : Color.white.opacity(0.68)
    }

    var body: some View {
        Group {
            switch context.state.resolvedStyle {
            case "score":  ScoreLockScreen(context: context)
            case "metric": MetricLockScreen(context: context)
            default:       standardLayout
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        // Camın üst kenarından süzülen hafif ışık (Liquid Glass parlaması)
        .background(
            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.35), .clear],
                           startPoint: .top, endPoint: .center)
        )
        .activityBackgroundTint(glassTint)
        .activitySystemActionForegroundColor(scheme == .dark ? .white : .black)
    }

    /// Geri sayım / ilerleme şablonu
    private var standardLayout: some View {
        let attributes = context.attributes
        let state = context.state
        // Açık/koyu moda uyan ön plan; mini uygulamalarda çubuk kendi renginde
        let accent = attributes.accentColor ?? .primary

        return VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ActivityIcon(attributes: attributes, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(attributes.caption)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(state.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let line = context.isStale ? "Süre doldu" : (state.status ?? (state.subtitle.isEmpty ? nil : state.subtitle)) {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                TrailingValue(state: state, isStale: context.isStale, fontSize: 30, color: .primary)
            }

            ActivityProgressBar(state: state, accent: accent, isStale: context.isStale)
        }
    }
}

// MARK: - Şablon: Skor (maç, oyun, yarış)

/// Takım rozeti: renkli daire + kısa ad (canlı etkinlik ağdan görsel indiremez; logolar yerine renk + kısaltma)
private struct SideBadge: View {
    let side: PufyLiveActivityAttributes.ContentState.Side
    let size: CGFloat

    private var label: String {
        if let short = side.short, !short.isEmpty { return String(short.prefix(4)).uppercased() }
        let words = side.name.split(separator: " ")
        if words.count >= 2 { return words.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased() }
        return String(side.name.prefix(3)).uppercased()
    }

    var body: some View {
        Circle()
            .fill((Color(hexString: side.color) ?? .gray).gradient)
            .overlay(
                Text(label)
                    .font(.system(size: size * (label.count > 3 ? 0.26 : 0.32), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .padding(4)
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .frame(width: size, height: size)
    }
}

private struct ScoreLockScreen: View {
    let context: ActivityViewContext<PufyLiveActivityAttributes>

    var body: some View {
        let state = context.state
        let home = state.home ?? .init(name: "Ev")
        let away = state.away ?? .init(name: "Deplasman")
        let finished = state.isFinished || context.isStale

        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ActivityIcon(attributes: context.attributes, size: 16)
                Text(state.title.isEmpty ? context.attributes.caption : state.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !finished {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("CANLI")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.secondary)
                } else {
                    Text("MAÇ SONU")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                team(home)
                VStack(spacing: 2) {
                    Text("\(state.homeScore ?? 0) - \(state.awayScore ?? 0)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(finished ? "Bitti" : (state.minute ?? state.status ?? ""))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 96)
                team(away)
            }
        }
    }

    private func team(_ side: PufyLiveActivityAttributes.ContentState.Side) -> some View {
        VStack(spacing: 5) {
            SideBadge(side: side, size: 40)
            Text(side.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Şablon: Değer (fiyat, kur, sayaç…)

private struct MetricLockScreen: View {
    let context: ActivityViewContext<PufyLiveActivityAttributes>

    var body: some View {
        let state = context.state
        HStack(alignment: .center, spacing: 14) {
            ActivityIcon(attributes: context.attributes, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.caption)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if let line = state.status ?? (state.subtitle.isEmpty ? nil : state.subtitle) {
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(state.value ?? "—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    if let unit = state.unit {
                        Text(unit)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let change = state.change {
                    Label(change, systemImage: state.trend == "down" ? "arrow.down.right" : (state.trend == "up" ? "arrow.up.right" : "minus"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(state.trend == "down" ? Color.red : (state.trend == "up" ? Color.green : Color.secondary))
                }
            }
        }
    }
}

