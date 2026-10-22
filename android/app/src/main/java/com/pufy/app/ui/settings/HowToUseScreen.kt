package com.pufy.app.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Chat
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material.icons.outlined.ViewCarousel
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType

@Composable
fun HowToUseScreen(onClose: () -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    val isEn = com.pufy.app.core.AppLocales.isEnglish()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(c.background)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        // Üst başlık çubuğu
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Outlined.ArrowBack,
                contentDescription = stringResource(R.string.close),
                tint = c.text,
                modifier = Modifier
                    .size(24.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .pressable { Haptics.light(view); onClose() }
            )
            Spacer(Modifier.width(16.dp))
            Text(
                stringResource(R.string.how_to_use),
                style = PufyType.title.copy(fontWeight = FontWeight.Bold),
                color = c.text
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            // MARK: Sohbet
            HelpCard(
                title = if (isEn) "Chat" else "Sohbet",
                icon = Icons.Outlined.Chat,
                items = listOf(
                    Icons.Outlined.Mic to if (isEn) "Type your prompt or tap the microphone to speak." else "Yaz ya da mikrofona basarak konuşabilirsin.",
                    Icons.Outlined.TouchApp to if (isEn) "Long-press any message to copy or report an inappropriate response." else "Mesaja basılı tutarak kopyalayabilir ya da uygunsuz bir cevabı bildirebilirsin.",
                    Icons.Outlined.AutoAwesome to if (isEn) "Ask for slide decks, quizzes, comparison cards, or tables directly in chat." else "Sohbet içinde sunum, test, karşılaştırma kartı ya da tablolar isteyebilirsin."
                )
            )

            // MARK: Menü
            HelpCard(
                title = if (isEn) "Menu" else "Menü",
                icon = Icons.Outlined.Menu,
                items = listOf(
                    Icons.Outlined.Menu to if (isEn) "Tap the ≡ button at top-left to open the menu." else "Sol üstteki ≡ butonundan menüyü açabilirsin.",
                    Icons.Outlined.Description to if (isEn) "Access your past chats, notes, and reminders here." else "Geçmiş sohbetlerine, notlarına ve hatırlatıcılarına buradan ulaşırsın."
                )
            )

            // MARK: Uygulamalar
            HelpCard(
                title = if (isEn) "Apps" else "Uygulamalar",
                icon = Icons.Outlined.ViewCarousel,
                items = listOf(
                    Icons.Outlined.ViewCarousel to if (isEn) "Pinch with two fingers on the main screen to open Apps switcher." else "Ana ekranda iki parmakla kıstırarak Uygulamalar ekranına geçebilirsin.",
                    Icons.Rounded.Add to if (isEn) "Tap '+ New', describe what you want, and Pufy will write the mini app for you." else "'+ Yeni' kartıyla ne istediğini yaz, Pufy senin için mini uygulama kodlasın.",
                    Icons.Outlined.PlayCircle to if (isEn) "Mini apps work offline too; edit them anytime via bottom bar." else "Mini uygulamalar internetsiz de çalışır; alttaki Düzenle butonuyla güncelleyebilirsin."
                )
            )

            // MARK: Hatırlatıcı ve Görevler
            HelpCard(
                title = if (isEn) "Reminders & Tasks" else "Hatırlatıcı ve Görevler",
                icon = Icons.Outlined.Alarm,
                items = listOf(
                    Icons.Outlined.Alarm to if (isEn) "Just say 'remind me tomorrow at 9' or '15 min timer'." else "'Yarın 9'da hatırlat' ya da '15 dk sayaç' demen yeterli.",
                    Icons.Outlined.Description to if (isEn) "Recurring and scheduled tasks appear in the menu's task list." else "Tekrarlayan ve zamanlanmış görevler menüdeki görev sohbetlerinde listelenir.",
                    Icons.Outlined.PlayCircle to if (isEn) "Manage tasks using 'Run now', 'Stop', or 'Delete'." else "Görevleri 'Şimdi bak', 'Durdur' veya 'Sil' ile yönetebilirsin."
                )
            )

            // MARK: Kişisel Ağ
            HelpCard(
                title = if (isEn) "Personal Network" else "Kişisel Ağ",
                icon = Icons.Outlined.Hub,
                items = listOf(
                    Icons.Outlined.Psychology to if (isEn) "Pufy learns important details about you organically as you chat." else "Pufy sohbet ettikçe seni tanır, önemli bilgileri kendiliğinden öğrenir.",
                    Icons.Outlined.Hub to if (isEn) "Explore your profile in Network or List view from the menu." else "Menüden Kişisel Ağ'ı açarak Ağ veya Liste görünümünde inceleyebilirsin.",
                    Icons.Outlined.TouchApp to if (isEn) "Tap any information item to edit or forget it." else "Bir bilgiye dokunarak düzenleyebilir ya da silebilirsin."
                )
            )

            // MARK: Dosya ve Dikte
            HelpCard(
                title = if (isEn) "Files & Dictation" else "Dosya ve Dikte",
                icon = Icons.Outlined.AttachFile,
                items = listOf(
                    Icons.Outlined.AttachFile to if (isEn) "Attach photos and documents (PDF, TXT, DOCX, code) via the '+' button." else "Giriş alanındaki '+' butonundan fotoğraf ve dosya (PDF, TXT, DOCX, kod) ekleyebilirsin.",
                    Icons.Outlined.Description to if (isEn) "Up to 3 files (~60k characters total) supported per message." else "En fazla 3 dosya (toplam ~60 bin karakter) eklenebilir.",
                    Icons.Outlined.Mic to if (isEn) "Dictate naturally using the microphone button." else "Mikrofon butonuyla sesini doğrudan metne dönüştürebilirsin."
                )
            )

            // MARK: Gizlilik
            HelpCard(
                title = if (isEn) "Privacy" else "Gizlilik",
                icon = Icons.Outlined.Shield,
                items = listOf(
                    Icons.Outlined.Lock to if (isEn) "No account required; your chats, notes, and network remain on device." else "Hesap açma zorunluluğu yoktur; sohbetler ve veriler sadece cihazında saklanır.",
                    Icons.Outlined.Shield to if (isEn) "Your API key is stored securely on device; messages go solely to your selected provider." else "API anahtarın cihazda güvenle saklanır; mesajlar sadece seçtiğin yapay zeka sağlayıcısına iletilir.",
                    Icons.Outlined.TouchApp to if (isEn) "Zero ads, zero trackers, zero server uploads." else "Reklam veya gizli takip kodu içermez."
                )
            )

            Spacer(Modifier.size(24.dp))
        }
    }
}

@Composable
private fun HelpCard(
    title: String,
    icon: ImageVector,
    items: List<Pair<ImageVector, String>>
) {
    val c = Pufy.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(c.secondaryBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(icon, null, modifier = Modifier.size(18.dp), tint = c.primary)
            Text(title, style = PufyType.headline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items.forEach { (itemIcon, text) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        itemIcon,
                        null,
                        modifier = Modifier
                            .padding(top = 2.dp)
                            .size(15.dp),
                        tint = c.secondaryText
                    )
                    Text(
                        text,
                        style = PufyType.subheadline,
                        color = c.text,
                        lineHeight = 20.sp,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}
