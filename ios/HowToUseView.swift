//
//  HowToUseView.swift
//  Pufy Agent
//
//  PROMPT-8 Adım 4: Ayarlar -> Yardım -> Nasıl kullanılır ekranı
//

import SwiftUI

struct HowToUseView: View {
    var body: some View {
        List {
            // MARK: - Sohbet
            section(
                title: AppLanguage.isEnglish ? "Chat" : "Sohbet",
                icon: "bubble.left.and.bubble.right",
                items: [
                    (icon: "mic", text: AppLanguage.isEnglish ? "Type your prompt or tap the microphone to speak." : "Yaz ya da mikrofona basarak konuşabilirsin."),
                    (icon: "hand.tap", text: AppLanguage.isEnglish ? "Long-press any message to copy or report an inappropriate response." : "Mesaja basılı tutarak kopyalayabilir ya da uygunsuz bir cevabı bildirebilirsin."),
                    (icon: "sparkles", text: AppLanguage.isEnglish ? "Ask for slide decks, quizzes, comparison cards, or tables directly in chat." : "Sohbet içinde sunum, test, karşılaştırma kartı ya da tablolar isteyebilirsin.")
                ]
            )

            // MARK: - Menü
            section(
                title: AppLanguage.isEnglish ? "Menu" : "Menü",
                icon: "sidebar.left",
                items: [
                    (icon: "hand.draw", text: AppLanguage.isEnglish ? "Tap the ≡ button at top-left or swipe from left to right." : "Sol üstteki ≡ butonundan ya da soldan sağa kaydırarak açabilirsin."),
                    (icon: "clock", text: AppLanguage.isEnglish ? "Access your past chats, notes, and reminders here." : "Geçmiş sohbetlerine, notlarına ve hatırlatıcılarına buradan ulaşırsın.")
                ]
            )

            // MARK: - Uygulamalar
            section(
                title: AppLanguage.isEnglish ? "Apps" : "Uygulamalar",
                icon: "square.grid.2x2",
                items: [
                    (icon: pinchIcon, text: pinchText),
                    (icon: "plus.circle", text: AppLanguage.isEnglish ? "Tap '+ New', describe what you want, and Pufy will write the mini app for you." : "'+ Yeni' kartıyla ne istediğini yaz, Pufy senin için mini uygulama kodlasın."),
                    (icon: "slider.horizontal.3", text: AppLanguage.isEnglish ? "Mini apps work offline too; edit them anytime via bottom bar." : "Mini uygulamalar internetsiz de çalışır; alttaki Düzenle butonuyla güncelleyebilirsin.")
                ]
            )

            // MARK: - Hatırlatıcı ve Görevler
            section(
                title: AppLanguage.isEnglish ? "Reminders & Tasks" : "Hatırlatıcı ve Görevler",
                icon: "bell",
                items: [
                    (icon: "alarm", text: AppLanguage.isEnglish ? "Just say 'remind me tomorrow at 9' or '15 min timer'." : "'Yarın 9'da hatırlat' ya da '15 dk sayaç' demen yeterli."),
                    (icon: "calendar.badge.clock", text: AppLanguage.isEnglish ? "Recurring and scheduled tasks appear in the menu's task list." : "Tekrarlayan ve zamanlanmış görevler menüdeki görev sohbetlerinde listelenir."),
                    (icon: "play.circle", text: AppLanguage.isEnglish ? "Manage tasks using 'Run now', 'Stop', or 'Delete'." : "Görevleri 'Şimdi bak', 'Durdur' veya 'Sil' ile yönetebilirsin.")
                ]
            )

            // MARK: - Kişisel Ağ
            section(
                title: AppLanguage.isEnglish ? "Personal Network" : "Kişisel Ağ",
                icon: "point.3.connected.trianglepath.dotted",
                items: [
                    (icon: "brain", text: AppLanguage.isEnglish ? "Pufy learns important details about you organically as you chat." : "Pufy sohbet ettikçe seni tanır, önemli bilgileri kendiliğinden öğrenir."),
                    (icon: "circle.grid.cross", text: AppLanguage.isEnglish ? "Explore your profile in Network or List view from the menu." : "Menüden Kişisel Ağ'ı açarak Ağ veya Liste görünümünde inceleyebilirsin."),
                    (icon: "trash", text: AppLanguage.isEnglish ? "Tap any information item to edit or forget it." : "Bir bilgiye dokunarak düzenleyebilir ya da silebilirsin.")
                ]
            )

            // MARK: - Dosya ve Dikte
            section(
                title: AppLanguage.isEnglish ? "Files & Dictation" : "Dosya ve Dikte",
                icon: "paperclip",
                items: [
                    (icon: "photo.on.rectangle", text: AppLanguage.isEnglish ? "Attach photos and documents (PDF, TXT, DOCX, code) via the '+' button." : "Giriş alanındaki '+' butonundan fotoğraf ve dosya (PDF, TXT, DOCX, kod) ekleyebilirsin."),
                    (icon: "doc.on.doc", text: AppLanguage.isEnglish ? "Up to 3 files (~60k characters total) supported per message." : "En fazla 3 dosya (toplam ~60 bin karakter) eklenebilir."),
                    (icon: "waveform", text: AppLanguage.isEnglish ? "Dictate naturally using the microphone button." : "Mikrofon butonuyla sesini doğrudan metne dönüştürebilirsin.")
                ]
            )

            // MARK: - Gizlilik
            section(
                title: AppLanguage.isEnglish ? "Privacy" : "Gizlilik",
                icon: "lock.shield",
                items: [
                    (icon: "person.crop.circle.badge.xmark", text: AppLanguage.isEnglish ? "No account required; your chats, notes, and network remain on device." : "Hesap açma zorunluluğu yoktur; sohbetler ve veriler sadece cihazında saklanır."),
                    (icon: "key", text: AppLanguage.isEnglish ? "Your API key is stored securely on device; messages go solely to your selected provider." : "API anahtarın cihazda güvenle saklanır; mesajlar sadece seçtiğin yapay zeka sağlayıcısına iletilir."),
                    (icon: "hand.raised", text: AppLanguage.isEnglish ? "Zero ads, zero trackers, zero server uploads." : "Reklam veya gizli takip kodu içermez.")
                ]
            )
        }
        .navigationTitle(AppLanguage.isEnglish ? "How to Use" : "Nasıl Kullanılır")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(title: String, icon: String, items: [(icon: String, text: String)]) -> some View {
        Section {
            ForEach(0..<items.count, id: \.self) { idx in
                let item = items[idx]
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.pufyPrimary)
                        .frame(width: 20, alignment: .center)
                        .padding(.top, 2)

                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary)
        }
    }

    private var pinchIcon: String {
        #if targetEnvironment(macCatalyst)
        return "hand.point.up.left.and.hand.point.up.right"
        #else
        return "arrow.down.right.and.arrow.up.left"
        #endif
    }

    private var pinchText: String {
        #if targetEnvironment(macCatalyst)
        return AppLanguage.isEnglish ? "Pinch on trackpad to access Apps switcher." : "Trackpad üzerinde iki parmakla kıstırarak Uygulamalar'a geçebilirsin."
        #else
        return AppLanguage.isEnglish ? "Pinch with two fingers on screen to open Apps switcher." : "Ekranda iki parmakla kıstırarak Uygulamalar'a geçebilirsin."
        #endif
    }
}
