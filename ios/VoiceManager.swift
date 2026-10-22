import Foundation
import Speech
import AVFoundation
import SwiftUI

@MainActor
class VoiceManager: NSObject, ObservableObject {
    
    // MARK: - STT State
    @Published var isRecording: Bool = false
    @Published var transcribedText: String = ""
    @Published var micPermissionGranted: Bool = false
    @Published var speechPermissionGranted: Bool = false
    
    // MARK: - TTS State
    @Published var isSpeaking: Bool = false
    @Published var speakingMessageID: UUID? = nil
    
    // MARK: - Private STT
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    
    // MARK: - Private TTS
    private let synthesizer = AVSpeechSynthesizer()
    
    // MARK: - Singleton
    static let shared = VoiceManager()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        checkPermissions()
    }
    
    // MARK: - Permissions
    
    func checkPermissions() {
        // Mikrofon izni
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            micPermissionGranted = true
        default:
            micPermissionGranted = false
        }
        
        // Speech tanıma izni
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionGranted = true
        default:
            speechPermissionGranted = false
        }
    }
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                self?.speechPermissionGranted = authStatus == .authorized
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.micPermissionGranted = granted
                completion(granted)
            }
        }
    }
    
    // MARK: - STT: Recording
    
    func startRecording(onUpdate: @escaping (String) -> Void) {
        guard !isRecording else { return }
        
        // İzin yoksa iste
        guard micPermissionGranted && speechPermissionGranted else {
            requestPermissions { [weak self] granted in
                guard granted else { return }
                self?.startRecording(onUpdate: onUpdate)
            }
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }
        
        // Önceki task varsa iptal et
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Ses oturumunu ayarla
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                    onUpdate(text)
                }
            }
            
            if error != nil || (result?.isFinal == true) {
                Task { @MainActor in
                    self.stopRecordingEngine()
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            stopRecordingEngine()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        stopRecordingEngine()
    }
    
    private func stopRecordingEngine() {
        // 1. Recognition task'ı iptal et (Apple dikte servisi dahil)
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 2. Recognition request'i sonlandır
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // 3. Audio engine'i durdur ve tap'ı kaldır
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // 4. Audio session'ı tamamen kapat
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        
        isRecording = false
    }
    
    // MARK: - TTS: Speaking
    
    func speak(text: String, messageID: UUID) {
        // TTS aktifse durdur
        if isSpeaking {
            stopSpeaking()
            // Aynı mesajsa toggle gibi davran (dur)
            if speakingMessageID == messageID { return }
        }
        
        // Ses oturumunu ayarla
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
        
        // Markdown ve özel etiketleri temizle
        let cleanText = cleanForSpeech(text)
        guard !cleanText.isEmpty else { return }
        
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.52          // Doğal konuşma hızı
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.95
        utterance.postUtteranceDelay = 0.1
        
        speakingMessageID = messageID
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        speakingMessageID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - Helpers
    
    private func cleanForSpeech(_ text: String) -> String {
        var result = text
        // Özel etiketleri kaldır
        result = result.replacingOccurrences(of: "\\[THINK\\s*:[^\\]]*(?:\\]|$)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[SEARCH\\s*:[^\\]]*(?:\\]|$)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[REMINDER\\s*:[^\\]]*(?:\\]|$)", with: "", options: .regularExpression)
        // Markdown bold/italic
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        // Linkler
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        // # başlıklar
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        // Bullet'lar
        result = result.replacingOccurrences(of: "(?m)^[•\\*\\-]\\s+", with: "", options: .regularExpression)
        // Çift boşluklar
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            speakingMessageID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            speakingMessageID = nil
        }
    }
}
