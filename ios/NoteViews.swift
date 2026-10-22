import SwiftUI

// MARK: - Not sayfası (menüdeki nota ya da sohbetteki "Not güncellendi" rozetine dokununca)

struct NoteDetailView: View {
    let noteID: UUID
    var startEditing = false
    @ObservedObject private var store = NoteStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field { case title, content }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "d MMMM, HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let note = store.note(noteID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if editing { editor } else { reader(note) }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    ContentUnavailableNote()
                }
            }
            .background(Color(UIColor.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { saveIfEditing(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Kapat")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let note = store.note(noteID), !editing {
                        Menu {
                            ShareLink(item: "\(note.title)\n\n\(note.content)") { Label("Paylaş", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Notu sil", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                        }
                    }
                    Button(editing ? "Bitti" : "Düzenle") {
                        if editing { saveIfEditing() } else { beginEditing() }
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(String(localized: "Not silinsin mi?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(String(localized: "Sil"), role: .destructive) { store.delete(noteID); dismiss() }
            } message: {
                Text(String(localized: "Tüm cihazlarından kalkar."))
            }
        }
        .onAppear { if startEditing { beginEditing() } }
    }

    // MARK: Okuma

    @ViewBuilder
    private func reader(_ note: Note) -> some View {
        Text(note.title)
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.4)
            .padding(.bottom, 4)
        Text((AppLanguage.isEnglish ? "Updated: " : "Güncellendi: ") + Self.dateFormatter.string(from: note.updatedAt))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)

        if let p = note.checklistProgress {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.pufySoft)
                        Capsule().fill(Color.pufyPrimary)
                            .frame(width: geo.size.width * CGFloat(p.done) / CGFloat(max(p.total, 1)))
                    }
                }
                .frame(height: 6)
                Text("\(p.done)/\(p.total)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 18)
            .animation(SmoothSpring.standard, value: p.done)
        }

        if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button { beginEditing() } label: {
                Text(String(localized: "Boş not. Yazmak için dokun ya da sohbette Pufy'ye \"buna şunu ekle\" de."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }

        let lines = note.content.components(separatedBy: "\n")
        ForEach(Array(lines.enumerated()), id: \.offset) { index, raw in
            lineView(NoteLine(raw), index: index)
        }
    }

    @ViewBuilder
    private func lineView(_ line: NoteLine, index: Int) -> some View {
        switch line {
        case .check(let done, let text):
            Button {
                PremiumHaptics.light()
                withAnimation(SmoothSpring.quick) { store.toggle(noteID, line: index) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(done ? Color.pufyPrimary : Color.secondary.opacity(0.6))
                        .pufySymbolReplace()
                    Text(text)
                        .font(.body)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Color.secondary).frame(width: 5, height: 5).offset(y: -3)
                Text(LocalizedStringKey(text)).font(.body)
            }
            .padding(.vertical, 4)
        case .heading(let text):
            Text(text)
                .font(.title3.weight(.bold))
                .padding(.top, 16)
                .padding(.bottom, 4)
        case .text(let text):
            Text(LocalizedStringKey(text))
                .font(.body)
                .padding(.vertical, 3)
        case .blank:
            Color.clear.frame(height: 8)
        }
    }

    // MARK: Düzenleme

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(String(localized: "Başlık"), text: $draftTitle)
                .font(.system(size: 30, weight: .bold))
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .content }
            Text(String(localized: "Liste maddesi için satıra \"- [ ] \" ile başla."))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $draftContent)
                .font(.body)
                .frame(minHeight: 360)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.pufySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($focus, equals: .content)
        }
    }

    private func beginEditing() {
        guard let note = store.note(noteID) else { return }
        draftTitle = note.title
        draftContent = note.content
        withAnimation(SmoothSpring.standard) { editing = true }
        focus = note.content.isEmpty ? (note.title == "Yeni Not" ? .title : .content) : nil
    }

    private func saveIfEditing() {
        guard editing else { return }
        store.update(noteID, title: draftTitle, content: draftContent)
        withAnimation(SmoothSpring.standard) { editing = false }
        focus = nil
    }
}

private struct ContentUnavailableNote: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(String(localized: "Bu not silinmiş.")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Menüdeki satır

struct NoteRow: View {
    let note: Note
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(note.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let p = note.checklistProgress, p.total > 0 {
                    ZStack {
                        Circle().stroke(Color.pufySoft, lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(p.done) / CGFloat(p.total))
                            .stroke(Color.pufyPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .pufyGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
