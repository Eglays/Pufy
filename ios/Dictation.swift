import SwiftUI
import AVFoundation
import Speech

// MARK: - Yapay Zeka Destekli Dikte
//
// iPhone'un klavye diktesi Türkçe-İngilizce karışık konuşmada zayıf (kullanıcı geri bildirimi).
// SuperWhisper mantığı: önce sesi kaydet, bitince tamamını güçlü bir modelle tek seferde yazıya dök.
//  • Gemini formatı: ses doğrudan kullanıcının modeline gider (düşünme "low", ~2-3 sn)
//  • OpenAI uyumlu: /audio/transcriptions → whisper-large-v3-turbo ("Ultra v3 turbo")
//  • Sunucu sesi desteklemiyorsa: cihazdaki tanıma (son çare)

@MainActor
final class DictationManager: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, recording, transcribing }

    @Published private(set) var phase: Phase = .idle
    /// Son ~1,8 sn'nin ses seviyeleri (0…1) — dalga çizimi için
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 36)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    /// En uzun kayıt (sonra kendiliğinden durur ve yazıya döker)
    static let maxDuration: TimeInterval = 300

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startDate: Date?
    private var peakLevel: CGFloat = 0
    private var work: Task<Void, Never>?
    private var onText: ((String) -> Void)?

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pufy-dikte.m4a")
    }

    // MARK: Kayıt

    func start(onText: @escaping (String) -> Void) {
        guard phase == .idle else { return }
        errorMessage = nil
        self.onText = onText
        Task {
            guard await Self.requestMicPermission() else {
                errorMessage = String(localized: "Dikte için mikrofon izni gerekiyor. Ayarlar > Pufy'den açabilirsin.")
                return
            }
            beginRecording()
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
            try? FileManager.default.removeItem(at: fileURL)
            // Konuşma için küçük ama net: 16 kHz mono AAC (~4 KB/sn)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maxDuration + 1) else {
                throw NSError(domain: "Dictation", code: 1)
            }
            self.recorder = recorder
        } catch {
            errorMessage = String(localized: "Mikrofon başlatılamadı.")
            deactivateSession()
            return
        }

        levels = Array(repeating: 0, count: levels.count)
        peakLevel = 0
        elapsed = 0
        startDate = Date()
        PremiumHaptics.medium()
        withAnimation(SmoothSpring.standard) { phase = .recording }

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let recorder, phase == .recording else { return }
        recorder.updateMeters()
        // dB (-160…0) → 0…1; konuşma genelde -45…-10 dB arası
        let power = CGFloat(recorder.averagePower(forChannel: 0))
        let level = max(0, min(1, (power + 50) / 42))
        peakLevel = max(peakLevel, level)
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
        elapsed = Date().timeIntervalSince(startDate ?? Date())
        if elapsed >= Self.maxDuration { finish() }
    }

    /// Kaydı bitir ve yazıya dök
    func finish() {
        guard phase == .recording else { return }
        let duration = elapsed
        stopRecorder()
        PremiumHaptics.light()

        // Çok kısa ya da sessiz kayıt: sunucuya hiç gitme
        guard duration > 0.5, peakLevel > 0.18 else {
            withAnimation(SmoothSpring.standard) { phase = .idle }
            errorMessage = duration <= 0.5 ? nil : String(localized: "Ses algılanmadı.")
            return
        }
        guard let audio = try? Data(contentsOf: fileURL), !audio.isEmpty else {
            withAnimation(SmoothSpring.standard) { phase = .idle }
            errorMessage = String(localized: "Kayıt okunamadı.")
            return
        }

        withAnimation(SmoothSpring.standard) { phase = .transcribing }
        let url = fileURL
        work = Task {
            var text = ""
            do {
                text = try await GeminiService.shared.transcribe(audio: audio)
            } catch is CancellationError {
                return
            } catch {
                // Sunucu sesi desteklemiyor / ulaşılamıyor → cihazdaki tanıma
                text = (try? await Self.onDeviceTranscription(url: url)) ?? ""
                if text.isEmpty, !Task.isCancelled {
                    errorMessage = String(localized: "Ses yazıya dökülemedi. Bağlantını kontrol edip tekrar dene.")
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(SmoothSpring.standard) { phase = .idle }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                PremiumHaptics.success()
                onText?(cleaned)
            } else if errorMessage == nil {
                errorMessage = String(localized: "Ses algılanmadı.")
            }
        }
    }

    /// Kaydı ya da yazıya dökmeyi iptal et
    func cancel() {
        work?.cancel()
        work = nil
        if phase == .recording { stopRecorder() }
        try? FileManager.default.removeItem(at: fileURL)
        PremiumHaptics.light()
        withAnimation(SmoothSpring.standard) { phase = .idle }
    }

    private func stopRecorder() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Yardımcılar

    private static func requestMicPermission() async -> Bool {
        if #available(iOS 17, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    /// Son çare: cihazdaki konuşma tanıma (Türkçe)
    private static func onDeviceTranscription(url: URL) async throws -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")), recognizer.isAvailable else { return "" }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

// MARK: - Kayıt Çubuğu (yazı kutusunun yerine geçer)

struct DictationBar: View {
    @ObservedObject var dictation: DictationManager

    var body: some View {
        HStack(spacing: 10) {
            Button { dictation.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .accessibilityLabel("Vazgeç")

            ZStack {
                if dictation.phase == .transcribing {
                    ShimmerText(text: String(localized: "Yazıya dökülüyor…"), font: .subheadline.weight(.medium))
                        .transition(.opacity)
                } else {
                    LiveWaveform(levels: dictation.levels)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)

            if dictation.phase == .recording {
                Text(Self.format(dictation.elapsed))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button { dictation.finish() } label: {
                ZStack {
                    Circle().fill(Color.pufyPrimary)
                    if dictation.phase == .transcribing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.pufyOnPrimary)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.pufyOnPrimary)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .disabled(dictation.phase != .recording)
            .accessibilityLabel("Bitir ve yazıya dök")
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .animation(SmoothSpring.quick, value: dictation.phase)
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Canlı ses dalgası: ortadan simetrik, sade çubuklar (en yeni sağda)
struct LiveWaveform: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(0.35 + 0.65 * Double(levels[i])))
                        .frame(width: barWidth, height: max(3, levels[i] * geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.linear(duration: 0.05), value: levels)
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}
