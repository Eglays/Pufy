package com.pufy.app

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.github.takahirom.roborazzi.captureRoboImage
import com.pufy.app.ai.ChatEngine
import com.pufy.app.data.ChatSession
import com.pufy.app.data.ChatStore
import com.pufy.app.data.Message
import com.pufy.app.data.MiniApp
import com.pufy.app.data.MiniAppStore
import com.pufy.app.data.Note
import com.pufy.app.data.NoteStore
import com.pufy.app.data.WebSource
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.RootScreen
import com.pufy.app.ui.settings.SettingsScreen
import com.pufy.app.ui.theme.PufyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Arayüzün ekran görüntüleri (emülatörsüz): build/screens klasörü */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "tr-w400dp-h860dp-xxhdpi")
class ScreensTest {
    @get:Rule val rule = createComposeRule()

    @org.junit.Before fun reset() {
        AppNav.sideMenuOpen.value = false; AppNav.switcherVisible.value = false; AppNav.activeAppID.value = null; AppNav.onboarding.value = false
    }

    private fun seed() {
        val answer = """
            İki telefonun öne çıkan farkları:

            ## Kamera
            - **48 MP** ana kamera, daha geniş sensör
            - Gece çekiminde belirgin iyileşme
            - 5x optik yakınlaştırma

            | Özellik | iPhone 17 Pro Max | iPhone 18 Pro Max |
            |---|---|---|
            | İşlemci | A19 Pro | A20 Pro |
            | Pil | 4.685 mAh | ~5.000 mAh |

            > İpucu: Fotoğraf çok çekiyorsan beklemek mantıklı.
        """.trimIndent()
        val session = ChatSession(title = "iPhone karşılaştırma", messages = listOf(
            Message(content = "iPhone 17 Pro Max mı 18 Pro Max mı?", role = "user"),
            Message(content = answer, role = "model", sources = listOf(WebSource("Apple", "https://www.apple.com"), WebSource("The Verge", "https://www.theverge.com")),
                actions = listOf("Fiyatları karşılaştır", "Kamera örnekleri")),
        ))
        ChatStore.upsert(session, notify = false)
        ChatStore.upsert(ChatSession(title = "Japonya rotası", messages = listOf(Message(content = "Japonya", role = "user"))), notify = false)
        ChatStore.upsert(ChatSession(title = "Fenerbahçe maçı", isPinned = true, messages = listOf(Message(content = "maç", role = "user"))), notify = false)
        NoteStore.upsert(Note(title = "Alışveriş", content = "- [ ] Süt\n- [x] Ekmek"), notify = false)
        MiniAppStore.upsert(MiniApp.create("Su Takibi", "drop.fill", "Günlük su", "su", "#2F80ED", emptyList()), notify = false)
        MiniAppStore.upsert(MiniApp.create("Kalori", "fork.knife", "Kalori sayacı", "kalori", "#27AE60", emptyList()), notify = false)
        ChatEngine.open(session.id)
    }

    private fun shot(name: String, dark: Boolean = false, content: @androidx.compose.runtime.Composable () -> Unit) {
        rule.setContent { PufyTheme(dark = dark) { content() } }
        rule.mainClock.advanceTimeBy(1500)
        rule.onRoot().captureRoboImage("build/screens/$name.png")
    }

    private fun androidx.compose.ui.test.junit4.ComposeContentTestRule.onRoot() = onNode(androidx.compose.ui.test.isRoot())

    @Test fun welcome() { ChatEngine.newSession(); shot("01-karsilama") { RootScreen() } }
    @Test fun chat() { seed(); shot("02-sohbet") { RootScreen() } }
    @Test fun chatDark() { seed(); shot("03-sohbet-gece", dark = true) { RootScreen() } }
    @Test fun menu() { seed(); AppNav.sideMenuOpen.value = true; shot("04-menu") { RootScreen() } }
    @Test fun switcherGrid() { seed(); AppNav.switcherOpensInCards = false; AppNav.switcherVisible.value = true; shot("05-uygulamalar") { RootScreen() } }
    @Test fun settings() { shot("06-ayarlar") { SettingsScreen {} } }

    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi")
    fun enChat() { seed(); shot("09-en-sohbet") { RootScreen() } }

    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi")
    fun enSettings() { shot("10-en-ayarlar") { SettingsScreen {} } }

    @Test fun taskSession() {
        val taskSession = ChatSession(
            title = "Fenerbahçe ilk 11",
            messages = listOf(
                Message(content = "Fenerbahçe ilk 11'i açıklanınca yaz", role = "user"),
                Message(
                    content = "İlk 11 henüz açıklanmadı. TFF ve kulüp kanallarını 15 dakikada bir kontrol ediyorum.",
                    role = "model",
                    timestamp = com.pufy.app.core.nowSwift() - 15 * 60
                ),
                Message(
                    content = """
                        Fenerbahçe ilk 11 açıklandı:

                        - **Kaleci:** Livakovic
                        - **Defans:** Osayi, Becao, Djiku, Ferdi
                        - **Orta Saha:** İsmail, Fred, Szymanski
                        - **Hücum:** İrfan Can, Dzeko, Tadic
                    """.trimIndent(),
                    role = "model",
                    timestamp = com.pufy.app.core.nowSwift()
                )
            ),
            isSpaceChat = true
        )
        ChatStore.upsert(taskSession, notify = false)
        val task = com.pufy.app.data.Reminder(
            title = "Fenerbahçe ilk 11",
            dateMillis = System.currentTimeMillis() + 30 * 60_000L,
            aiTaskPrompt = "Fenerbahçe ilk 11'i açıklanınca yaz",
            taskSessionID = taskSession.id,
            taskIntervalMinutes = 15,
            repeat = "none",
            isActive = true
        )
        com.pufy.app.data.ReminderStore.upsert(task, notify = false)
        ChatEngine.open(taskSession.id)
        shot("08-gorev") { RootScreen() }
    }

    @Test fun switcherChatCardClickReturnsToChat() {
        seed()
        AppNav.activeAppID.value = "su"
        AppNav.switcherOpensInCards = true
        AppNav.switcherVisible.value = true
        rule.setContent { PufyTheme { RootScreen() } }
        rule.mainClock.advanceTimeBy(500)
        rule.onNodeWithTag("switcher-card-chat").performClick()
        rule.mainClock.advanceTimeBy(500)
        assertNull(AppNav.activeAppID.value)
        assertFalse(AppNav.switcherVisible.value)
    }

    @Test fun onboardingConnectAI() {
        AppNav.onboarding.value = true
        shot("11-kurulum-yapay-zeka") {
            com.pufy.app.ui.onboarding.OnboardingScreen(
                needsSetup = true,
                initialStep = com.pufy.app.ui.onboarding.OnboardingStep.CONNECT_AI,
                onFinish = {},
                onOpenSettings = {}
            )
        }
    }

    @Test fun onboardingPrivacy() {
        AppNav.onboarding.value = true
        shot("12-kurulum-gizlilik") {
            com.pufy.app.ui.onboarding.OnboardingScreen(
                needsSetup = false,
                initialStep = com.pufy.app.ui.onboarding.OnboardingStep.PRIVACY,
                onFinish = {},
                onOpenSettings = {}
            )
        }
    }

    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi")
    fun enOnboardingConnectAI() {
        AppNav.onboarding.value = true
        shot("13-en-kurulum-yapay-zeka") {
            com.pufy.app.ui.onboarding.OnboardingScreen(
                needsSetup = true,
                initialStep = com.pufy.app.ui.onboarding.OnboardingStep.CONNECT_AI,
                onFinish = {},
                onOpenSettings = {}
            )
        }
    }
}
