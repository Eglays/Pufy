import Foundation
import SwiftUI

// MARK: - AI Rapor Modeli
struct AIReport: Codable, Identifiable {
    let id: String
    let date: String
    let reason: String
    let description: String
    let messageText: String
    let modelName: String

    init(
        id: String = UUID().uuidString,
        date: String = ISO8601DateFormatter().string(from: Date()),
        reason: String,
        description: String,
        messageText: String,
        modelName: String
    ) {
        self.id = id
        self.date = date
        self.reason = reason
        self.description = description
        self.messageText = String(messageText.prefix(2000))
        self.modelName = modelName
    }
}

// MARK: - AI Rapor Deposu
final class AIReportStore: ObservableObject {
    static let shared = AIReportStore()

    @Published private(set) var reports: [AIReport] = []
    @Published var reportedMessageIDs: Set<UUID> = []
    @Published var revealedMessageIDs: Set<UUID> = []

    private let reportsKey = "ai_reports"
    private let reportedIDsKey = "ai_reported_message_ids"

    private init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: reportsKey),
           let list = try? JSONDecoder().decode([AIReport].self, from: data) {
            self.reports = list
        }
        if let strings = UserDefaults.standard.stringArray(forKey: reportedIDsKey) {
            self.reportedMessageIDs = Set(strings.compactMap { UUID(uuidString: $0) })
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: reportsKey)
        }
        let idStrings = reportedMessageIDs.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: reportedIDsKey)
    }

    func isReported(messageID: UUID) -> Bool {
        reportedMessageIDs.contains(messageID)
    }

    func isRevealed(messageID: UUID) -> Bool {
        revealedMessageIDs.contains(messageID)
    }

    func toggleReveal(messageID: UUID) {
        if revealedMessageIDs.contains(messageID) {
            revealedMessageIDs.remove(messageID)
        } else {
            revealedMessageIDs.insert(messageID)
        }
    }

    func submitReport(
        messageID: UUID,
        reason: String,
        description: String,
        messageText: String,
        modelName: String,
        completion: @escaping (AIReport) -> Void
    ) {
        let report = AIReport(
            reason: reason,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            messageText: messageText,
            modelName: modelName
        )
        reports.append(report)
        reportedMessageIDs.insert(messageID)
        revealedMessageIDs.remove(messageID)
        save()

        // REPORT_ENDPOINT doluysa POST at
        if let endpoint = LegalLinks.reportEndpoint, let url = URL(string: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(report)
            URLSession.shared.dataTask(with: request).resume()
        }

        completion(report)
    }

    func clearAll() {
        reports.removeAll()
        reportedMessageIDs.removeAll()
        revealedMessageIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: reportsKey)
        UserDefaults.standard.removeObject(forKey: reportedIDsKey)
    }
}

// MARK: - Bildir Formu (Sheet)
struct ReportSheet: View {
    let messageID: UUID
    let messageText: String
    let modelName: String
    let onDismiss: () -> Void

    @State private var selectedReasonIndex = 0
    @State private var description = ""
    @State private var submittedReport: AIReport? = nil

    private var reasons: [String] {
        if AppLanguage.isEnglish {
            return [
                "Offensive / hateful",
                "Sexual content",
                "Violent / dangerous",
                "False / misleading information",
                "Other"
            ]
        } else {
            return [
                "Saldırgan / nefret içeren",
                "Cinsel içerik",
                "Şiddet / tehlikeli",
                "Yanlış / yanıltıcı bilgi",
                "Diğer"
            ]
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let report = submittedReport {
                    successView(report)
                } else {
                    formView
                }
            }
            .navigationTitle(AppLanguage.isEnglish ? "Report Response" : "Cevabı Bildir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.isEnglish ? "Close" : "Kapat") {
                        onDismiss()
                    }
                }
            }
        }
    }

    private var formView: some View {
        Form {
            Section {
                ForEach(0..<reasons.count, id: \.self) { index in
                    HStack {
                        Text(reasons[index])
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedReasonIndex == index {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedReasonIndex = index
                    }
                }
            } header: {
                Text(AppLanguage.isEnglish ? "Reason for reporting" : "Bildirme sebebi")
            }

            Section {
                TextField(
                    AppLanguage.isEnglish ? "Additional details (optional)" : "Ek açıklama (isteğe bağlı)",
                    text: $description,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .onChange(of: description) { newValue in
                    if newValue.count > 500 {
                        description = String(newValue.prefix(500))
                    }
                }

                HStack {
                    Spacer()
                    Text("\(500 - description.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(AppLanguage.isEnglish ? "Explanation (max 500 characters)" : "Açıklama (en fazla 500 karakter)")
            }

            Section {
                Button {
                    let reason = reasons[selectedReasonIndex]
                    AIReportStore.shared.submitReport(
                        messageID: messageID,
                        reason: reason,
                        description: description,
                        messageText: messageText,
                        modelName: modelName
                    ) { report in
                        withAnimation {
                            self.submittedReport = report
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(AppLanguage.isEnglish ? "Submit Report" : "Bildirimi Gönder")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
    }

    private func successView(_ report: AIReport) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text(AppLanguage.isEnglish ? "Thank you, your report has been saved." : "Teşekkürler, bildirimin kaydedildi.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(AppLanguage.isEnglish ? "This response has been hidden in your chat." : "Bu cevap sohbetinde gizlendi.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 8)

            Button {
                openEmail(report)
            } label: {
                Label(
                    AppLanguage.isEnglish ? "Send via email as well" : "E-postayla da gönder",
                    systemImage: "envelope"
                )
                .font(.subheadline)
            }

            Spacer()

            Button(AppLanguage.isEnglish ? "Done" : "Tamam") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .padding()
    }

    private func openEmail(_ report: AIReport) {
        let subject = "[Pufy AI Report] \(report.reason) - \(report.id.prefix(8))"
        let body = """
        Report ID: \(report.id)
        Date: \(report.date)
        Reason: \(report.reason)
        Model: \(report.modelName)

        Description:
        \(report.description.isEmpty ? "(None)" : report.description)

        Response Text:
        \(report.messageText)
        """

        let urlString = "mailto:\(LegalLinks.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
