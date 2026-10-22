import SwiftUI

// MARK: - Görev Sohbeti ("uzay sohbeti")
//
// Kullanıcı isteği (13 Ekim 2026): zamanlanmış görevin sohbeti normal sohbet gibi olmasın.
//  • Yazma kutusu yok — burası soru sorulan yer değil.
//  • Üstte sabit görev balonu (ne istendiği, ne zaman / ne sıklıkla).
//  • Altta sonuçlar sırayla (tekrarlayan görevde her çalışmanın sonucu alt alta).
//  • Görev çalışırken belirgin bir "bakıyorum" animasyonu — eskiden boş ekran "bozuk" sanılıyordu.

struct TaskSessionView: View {
    @ObservedObject var viewModel: ChatViewModel
    let session: ChatSession
    var onImageTap: (UIImage) -> Void = { _ in }

    @ObservedObject private var runner = ScheduledTaskRunner.shared
    @ObservedObject private var reminders = ReminderManager.shared

    private let bottomID = "task_bottom"

    private var task: Reminder? { viewModel.task(forSession: session.id) }
    private var request: Message? { session.messages.first { $0.role == .user } }

    /// Eski sürümün görev akışı (sohbet içinde akış) bu sohbette sürüyor mu?
    private var streamingID: UUID? {
        viewModel.isLoading && viewModel.currentSessionID == session.id ? session.messages.last?.id : nil
    }

    private var results: [Message] {
        session.messages.filter { message in
            message.role == .model && (!message.content.isEmpty || message.id == streamingID)
        }
    }

    private var isRunning: Bool {
        if let task, runner.running.contains(task.id) { return true }
        if let streamingID, let last = session.messages.last, last.id == streamingID, last.content.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sabit görev balonu
            TaskHeaderCard(title: task?.title ?? session.title,
                           prompt: request?.content ?? "",
                           kind: kindLabel,
                           schedule: scheduleText,
                           isRepeating: task?.isRepeatingTask == true)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(results) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                ResultStamp(date: message.timestamp)
                                MessageRowView(message: message,
                                               isLastResponse: false,
                                               isGenerating: message.id == streamingID,
                                               onImageTap: onImageTap)
                                    .equatable()
                            }
                            .id(message.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        if isRunning {
                            TaskRunningView()
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        } else {
                            statusFooter
                        }

                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                    .animation(SmoothSpring.standard, value: results.count)
                    .animation(SmoothSpring.standard, value: isRunning)
                }
                .scrollDismissesKeyboard(.immediately)
                .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
                .onChange(of: results.count) { _ in
                    withAnimation(SmoothSpring.standard) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .onChange(of: isRunning) { _ in
                    withAnimation(SmoothSpring.standard) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Metinler

    private var kindLabel: String {
        guard let task else { return String(localized: "GÖREV") }
        return task.isRepeatingTask ? String(localized: "TEKRARLAYAN GÖREV") : String(localized: "ZAMANLANMIŞ GÖREV")
    }

    private var scheduleText: String {
        guard let task else { return "" }
        if let every = task.taskIntervalMinutes {
            let isEn = AppLanguage.isEnglish
            var text = isEn ? (every % 60 == 0 ? "Every \(every / 60) hours" : "Every \(every) min") : (every % 60 == 0 ? "Her \(every / 60) saatte" : "Her \(every) dk")
            if let until = task.taskUntil {
                text += isEn ? " · until \(Self.time.string(from: until))" : " · \(Self.time.string(from: until))'a kadar"
            }
            return text
        }
        let isEn = AppLanguage.isEnglish
        switch task.repeatType {
        case .none:    return Self.dayTime(task.date)
        case .daily:   return isEn ? "Daily at \(Self.time.string(from: task.date))" : "Her gün \(Self.time.string(from: task.date))"
        case .weekly:  return isEn ? "Weekly on \(Self.weekday.string(from: task.date)) at \(Self.time.string(from: task.date))" : "Her hafta \(Self.weekday.string(from: task.date)) \(Self.time.string(from: task.date))"
        case .monthly: return isEn ? "Monthly on day \(Calendar.current.component(.day, from: task.date))" : "Her ay \(Calendar.current.component(.day, from: task.date)). gün"
        case .yearly:  return isEn ? "Yearly on \(Self.dayTime(task.date))" : "Her yıl \(Self.dayTime(task.date))"
        }
    }

    // MARK: Alt durum

    @ViewBuilder
    private var statusFooter: some View {
        if let task {
            let next = runner.dueDate(for: task)
            VStack(spacing: 12) {
                if task.taskDone == true || !task.isActive {
                    Label(task.isActive ? String(localized: "Görev tamamlandı") : String(localized: "Görev durduruldu"),
                          systemImage: task.isActive ? "checkmark.circle.fill" : "stop.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if let next {
                    let isEn = AppLanguage.isEnglish
                    VStack(spacing: 3) {
                        Text(task.taskNextCheck != nil ? (isEn ? "No results yet · next check \(Self.time.string(from: next))" : "Henüz yok · sonraki kontrol \(Self.time.string(from: next))")
                                                      : (results.isEmpty ? (isEn ? "Runs \(Self.dayTime(next))" : "\(Self.dayTime(next)) çalışacak") : (isEn ? "Next: \(Self.time.string(from: next))" : "Sonraki: \(Self.time.string(from: next))")))
                            .font(.footnote.weight(.semibold))
                        if next > Date() {
                            Text(next, style: .relative)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        FooterButton(title: String(localized: "Şimdi bak"), systemImage: "bolt.fill", prominent: true) {
                            PremiumHaptics.medium()
                            viewModel.runTaskNow(reminderID: task.id)
                        }
                        if task.isRepeatingTask {
                            FooterButton(title: String(localized: "Durdur"), systemImage: "stop.fill", prominent: false) {
                                PremiumHaptics.light()
                                withAnimation(SmoothSpring.standard) { viewModel.stopTask(reminderID: task.id) }
                            }
                        }
                    }
                    if task.taskIntervalMinutes != nil {
                        Text(String(localized: "Uygulama açıkken tam zamanında çalışır; kapalıyken iOS geciktirebilir."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, results.isEmpty ? 24 : 4)
        }
    }

    // MARK: Biçimler

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "EEEE"
        return f
    }()

    static func dayTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let t = time.string(from: date)
        if calendar.isDateInToday(date) { return "\(String(localized: "Bugün")) \(t)" }
        if calendar.isDateInTomorrow(date) { return "\(String(localized: "Yarın")) \(t)" }
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Görev balonu

private struct TaskHeaderCard: View {
    let title: String
    let prompt: String
    let kind: String
    let schedule: String
    let isRepeating: Bool

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isRepeating ? "repeat" : "clock")
                    .font(.system(size: 11, weight: .bold))
                Text(kind)
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                Spacer(minLength: 8)
                if !schedule.isEmpty {
                    Text(schedule)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .lineLimit(2)

            if !prompt.isEmpty, prompt != title {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .onTapGesture { withAnimation(SmoothSpring.standard) { expanded.toggle() } }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.pufyUserBubble))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

/// Her sonucun üstünde: küçük logo + saat
private struct ResultStamp: View {
    let date: Date

    var body: some View {
        HStack(spacing: 7) {
            Image("chat_pp")
                .resizable()
                .scaledToFill()
                .frame(width: 18, height: 18)
                .clipShape(Circle())
            Text("Pufy · \(TaskSessionView.dayTime(date))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.pufyOnPrimary : .primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .pufyGlass(Capsule(), tint: prominent ? Color.pufyPrimary : nil, interactive: true)
        }
        .buttonStyle(PremiumScaleButtonStyle())
    }
}

// MARK: - Çalışıyor animasyonu

/// Logo etrafında yayılan dalgalar + yörüngede dönen nokta + değişen durum yazısı ve geçen süre
struct TaskRunningView: View {
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var phrases: [String] {
        [
            String(localized: "Görevi çalıştırıyorum…"),
            String(localized: "Web'de bakıyorum…"),
            String(localized: "Kaynakları karşılaştırıyorum…"),
            String(localized: "Sonucu yazıyorum…")
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            // İlk üç yazı ~4 sn'de bir değişir, sonra "Sonucu yazıyorum…"da kalır
            let phraseIndex = min(Int(t / 4), Self.phrases.count - 1)

            HStack(spacing: 16) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let p = CGFloat(((t / 2.4) + Double(i) / 3).truncatingRemainder(dividingBy: 1))
                        Circle()
                            .stroke(Color.primary.opacity(0.28 * (1 - p)), lineWidth: 1.2)
                            .frame(width: 36 + 44 * p, height: 36 + 44 * p)
                    }
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5, height: 5)
                        .offset(x: 27)
                        .rotationEffect(.radians(t * 2.4))
                    Image("chat_pp")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .scaleEffect(1 + 0.05 * sin(t * 3))
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    ShimmerText(text: Self.phrases[phraseIndex], font: .subheadline.weight(.semibold))
                        .id(phraseIndex)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    Text(Self.elapsed(t))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .animation(SmoothSpring.standard, value: phraseIndex)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Görev çalışıyor")
    }

    private static func elapsed(_ t: Double) -> String {
        let s = Int(t)
        return s < 60 ? (AppLanguage.isEnglish ? "\(s)s" : "\(s) sn") : String(format: "%d:%02d", s / 60, s % 60)
    }
}
