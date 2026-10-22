package com.pufy.app

import androidx.compose.ui.test.junit4.createComposeRule
import com.github.takahirom.roborazzi.captureRoboImage
import com.pufy.app.ai.ChatEngine
import com.pufy.app.data.ChatSession
import com.pufy.app.data.ChatStore
import com.pufy.app.data.MemoryStore
import com.pufy.app.data.Message
import com.pufy.app.data.MiniApp
import com.pufy.app.data.MiniAppStore
import com.pufy.app.data.Note
import com.pufy.app.data.NoteStore
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import com.pufy.app.data.WebSource
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.RootScreen
import com.pufy.app.ui.theme.PufyTheme
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Google Play mağaza görselleri için ham ekranlar: build/store-shots/{tr,en} */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "tr-w400dp-h860dp-xxhdpi")
class StoreShotsTest {
    @get:Rule val rule = createComposeRule()

    @org.junit.Before fun reset() {
        AppNav.sideMenuOpen.value = false; AppNav.switcherVisible.value = false; AppNav.activeAppID.value = null
        AppNav.onboarding.value = false; AppNav.memoryBookVisible.value = false
    }

    private fun shot(lang: String, name: String, dark: Boolean = false, content: @androidx.compose.runtime.Composable () -> Unit) {
        rule.mainClock.autoAdvance = false
        rule.setContent { PufyTheme(dark = dark) { content() } }
        repeat(20) { rule.mainClock.advanceTimeBy(100) }
        rule.onNode(androidx.compose.ui.test.isRoot()).captureRoboImage("build/store-shots/$lang/$name.png")
    }

    // MARK: İçerik

    private fun research(en: Boolean): ChatSession {
        val q = if (en) "Plan a 2-day weekend in Lisbon for me" else "Bu hafta sonu Kapadokya'ya gidiyorum, 2 günlük plan yapar mısın?"
        val a = if (en) """
            Here's a relaxed 2-day plan that fits Lisbon's hills and best light:

            ## Day 1 — Old town
            - **Morning:** Tram 28 to Alfama, São Jorge Castle
            - **Sunset:** Miradouro da Senhora do Monte

            ## Day 2 — Belém
            - **Pastéis de Belém** right at opening
            - Jerónimos Monastery and the riverside walk

            | | Morning | Evening |
            |---|---|---|
            | Sat | Alfama | Bairro Alto |
            | Sun | Belém | LX Factory |

        """.trimIndent() else """
            Rahat bir tempoyla, ışığın en güzel olduğu saatlere göre bir plan:

            ## 1. Gün — Göreme
            - **Gün doğumu:** Balon turu ya da Aşıklar Tepesi
            - **Akşam:** Testi kebabı, Avanos

            ## 2. Gün — Vadiler
            - **Kızılçukur Vadisi** yürüyüşü (2 saat)
            - Uçhisar Kalesi'nde gün batımı

            | | Sabah | Akşam |
            |---|---|---|
            | Cmt | Balon | Avanos |
            | Paz | Vadi | Uçhisar |

        """.trimIndent()
        return ChatSession(title = if (en) "Lisbon weekend" else "Kapadokya planı", messages = listOf(
            Message(content = q, role = "user"),
            Message(content = a, role = "model",
                sources = if (en) listOf(WebSource("Visit Lisboa", "https://www.visitlisboa.com"), WebSource("Wikipedia", "https://en.wikipedia.org"))
                else listOf(WebSource("Kültür Portalı", "https://www.kulturportali.gov.tr"), WebSource("Vikipedi", "https://tr.wikipedia.org")),
                actions = if (en) listOf("Find hotels", "What to pack") else listOf("Otel öner", "Ne giysem?")),
        ))
    }

    private fun recipe(en: Boolean): ChatSession {
        val q = if (en) "I have chicken, rice and broccoli. What can I cook in 30 minutes?" else "Elimde tavuk, pirinç ve brokoli var. 30 dakikada ne pişiririm?"
        val a = if (en) """
            **Teriyaki chicken bowl** — ready in about 25 minutes.

            ## Ingredients
            - 2 chicken breasts, diced
            - 1 cup rice, 1 head of broccoli

            ## Steps
            1. Start the rice (15 min)
            2. Sear the chicken until golden
            3. Add the sauce and let it thicken

            | Per serving | |
            |---|---|
            | Calories | ~520 kcal |
            | Protein | 42 g |
        """.trimIndent() else """
            **Teriyaki soslu tavuk kasesi** — yaklaşık 25 dakikada hazır.

            ## Malzemeler
            - 2 tavuk göğsü, küp doğranmış
            - 1 su bardağı pirinç, 1 baş brokoli

            ## Yapılışı
            1. Pirinci ocağa koy (15 dk)
            2. Tavuğu kızarana kadar sotele
            3. Sosu ekle, koyulaşsın

            | Porsiyon başına | |
            |---|---|
            | Kalori | ~520 kcal |
            | Protein | 42 g |
        """.trimIndent()
        return ChatSession(title = if (en) "Quick dinner" else "Akşam yemeği", messages = listOf(
            Message(content = q, role = "user"),
            Message(content = a, role = "model", actions = if (en) listOf("Make it vegetarian", "Shopping list") else listOf("Vejetaryen yap", "Alışveriş listesi")),
        ))
    }

    private fun seedLibrary(en: Boolean) {
        ChatStore.upsert(ChatSession(title = if (en) "Lisbon weekend" else "Kapadokya planı", isPinned = true, messages = listOf(Message(content = "x", role = "user"))), notify = false)
        listOf(if (en) listOf("Quick dinner", "Birthday gift ideas", "Explain compound interest") else listOf("Akşam yemeği", "Doğum günü hediyesi", "Bileşik faiz nedir?"))
            .flatten().forEach { ChatStore.upsert(ChatSession(title = it, messages = listOf(Message(content = it, role = "user"))), notify = false) }
        NoteStore.upsert(Note(title = if (en) "Groceries" else "Alışveriş", content = if (en) "- [x] Milk\n- [ ] Eggs\n- [ ] Coffee" else "- [x] Süt\n- [ ] Yumurta\n- [ ] Kahve"), notify = false)
        NoteStore.upsert(Note(title = if (en) "Book list" else "Okunacaklar", content = if (en) "Project Hail Mary" else "Kürk Mantolu Madonna"), notify = false)
        ReminderStore.upsert(Reminder(title = if (en) "Call mom" else "Annemi ara", dateMillis = System.currentTimeMillis() + 3 * 3600_000L), notify = false)
        ReminderStore.upsert(Reminder(title = if (en) "Gym" else "Spor salonu", dateMillis = System.currentTimeMillis() + 26 * 3600_000L, repeat = "weekly"), notify = false)
    }

    private fun seedApps(en: Boolean) {
        listOf(
            Triple(if (en) "Water" else "Su Takibi", "drop", "#2F80ED"),
            Triple(if (en) "Calories" else "Kalori", "fork.knife", "#27AE60"),
            Triple("Pomodoro", "timer", "#EB5757"),
            Triple(if (en) "Expenses" else "Harcamalar", "creditcard", "#333333"),
            Triple(if (en) "Word Game" else "Kelime Oyunu", "puzzle", "#F2994A"),
            Triple(if (en) "Habits" else "Alışkanlıklar", "checklist", "#9B9B9B"),
            Triple(if (en) "Workout" else "Antrenman", "dumbbell", "#111111"),
        ).forEachIndexed { i, (name, icon, color) ->
            MiniAppStore.upsert(MiniApp.create(name, icon, name, "app$i", color, emptyList()), notify = false)
        }
    }

    private fun seedTask(en: Boolean): ChatSession {
        val prompt = if (en) "Tell me when Istanbul–Tokyo flights drop below $600" else "İstanbul–Tokyo uçuşu 15.000 TL'nin altına düşünce haber ver"
        val session = ChatSession(title = if (en) "Tokyo flight price" else "Tokyo uçuş fiyatı", isSpaceChat = true, messages = listOf(
            Message(content = prompt, role = "user"),
            Message(content = if (en) "Cheapest round trip right now is **$742**. I'll check again every 6 hours." else "Şu an en ucuz gidiş-dönüş **18.450 TL**. 6 saatte bir tekrar bakacağım.",
                role = "model", timestamp = com.pufy.app.core.nowSwift() - 2 * 86400),
            Message(content = if (en) """
                Price dropped!

                - **Round trip:** $579
                - **Dates:** 12–26 March
                - **Airline:** 1 stop, 14h 50m

                This is 22% below the average of the last 30 days.
            """.trimIndent() else """
                Fiyat düştü!

                - **Gidiş-dönüş:** 14.890 TL
                - **Tarih:** 12–26 Mart
                - **Uçuş:** 1 aktarmalı, 14 sa 50 dk

                Son 30 günün ortalamasından %22 daha ucuz.
            """.trimIndent(), role = "model"),
        ))
        ChatStore.upsert(session, notify = false)
        ReminderStore.upsert(Reminder(title = if (en) "Tokyo flight price" else "Tokyo uçuş fiyatı", dateMillis = System.currentTimeMillis() + 6 * 3600_000L,
            aiTaskPrompt = prompt, taskSessionID = session.id, taskIntervalMinutes = 360, isActive = true), notify = false)
        return session
    }

    private fun seedMemory(en: Boolean) {
        var n = 0
        fun m(cat: String, tr: String, enText: String, imp: Int, entity: String? = null, relTr: String? = null, relEn: String? = null) = MemoryStore.upsert(buildJsonObject {
            val text = if (en) enText else tr
            put("id", "m${n++}"); put("category", cat); put("text", text); put("detail", text); put("importance", imp)
            entity?.let { put("entity", it) }; (if (en) relEn else relTr)?.let { put("relation", it) }
        })
        m("identity", "Deniz", "Deniz", 5); m("identity", "28 yaşında", "28 years old", 4); m("identity", "İzmirli", "From Izmir", 3)
        m("people", "Elif", "Elif", 5, "Elif", "kız kardeşi", "sister"); m("people", "Mert", "Mert", 4, "Mert", "iş arkadaşı", "coworker")
        m("people", "Zeynep", "Zeynep", 3, "Zeynep", "en yakın arkadaşı", "best friend")
        m("work", "Ürün tasarımcısı", "Product designer", 5); m("work", "Uzaktan çalışıyor", "Works remotely", 3)
        m("interests", "Fotoğrafçılık", "Photography", 4); m("interests", "Kamp", "Camping", 3); m("interests", "Basketbol", "Basketball", 3)
        m("preferences", "Filtre kahve", "Filter coffee", 3); m("preferences", "Vejetaryen", "Vegetarian", 4)
        m("goals", "Japonya gezisi", "Trip to Japan", 5); m("goals", "Yarı maraton", "Half marathon", 4)
        m("places", "Kadıköy", "Lisbon", 3); m("health", "Polen alerjisi", "Pollen allergy", 4)
    }

    @Test fun trResearch() { research(false).also { ChatStore.upsert(it, notify = false); ChatEngine.open(it.id) }; shot("tr", "1-arastirma") { RootScreen() } }
    @Test fun trRecipeDark() { recipe(false).also { ChatStore.upsert(it, notify = false); ChatEngine.open(it.id) }; shot("tr", "2-tarif-gece", dark = true) { RootScreen() } }
    @Test fun trTask() { ChatEngine.open(seedTask(false).id); shot("tr", "3-gorev") { RootScreen() } }
    @Test fun trApps() { seedApps(false); AppNav.switcherOpensInCards = false; AppNav.switcherVisible.value = true; shot("tr", "4-uygulamalar") { RootScreen() } }
    @Test fun trMenu() { seedLibrary(false); AppNav.sideMenuOpen.value = true; shot("tr", "5-menu") { RootScreen() } }
    @Test @Config(qualifiers = "tr-w640dp-h1100dp-xxxhdpi") fun trMemory() { seedMemory(false); AppNav.memoryBookVisible.value = true; shot("tr", "6-kisisel-ag") { RootScreen() } }
    @Test fun trConnect() {
        AppNav.onboarding.value = true
        shot("tr", "7-yapay-zeka") { com.pufy.app.ui.onboarding.OnboardingScreen(needsSetup = true, initialStep = com.pufy.app.ui.onboarding.OnboardingStep.CONNECT_AI, onFinish = {}, onOpenSettings = {}) }
    }

    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi") fun enResearch() { research(true).also { ChatStore.upsert(it, notify = false); ChatEngine.open(it.id) }; shot("en", "1-arastirma") { RootScreen() } }
    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi") fun enRecipeDark() { recipe(true).also { ChatStore.upsert(it, notify = false); ChatEngine.open(it.id) }; shot("en", "2-tarif-gece", dark = true) { RootScreen() } }
    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi") fun enTask() { ChatEngine.open(seedTask(true).id); shot("en", "3-gorev") { RootScreen() } }
    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi") fun enApps() { seedApps(true); AppNav.switcherOpensInCards = false; AppNav.switcherVisible.value = true; shot("en", "4-uygulamalar") { RootScreen() } }
    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi") fun enMenu() { seedLibrary(true); AppNav.sideMenuOpen.value = true; shot("en", "5-menu") { RootScreen() } }
    @Test @Config(qualifiers = "en-w640dp-h1100dp-xxxhdpi") fun enMemory() { seedMemory(true); AppNav.memoryBookVisible.value = true; shot("en", "6-kisisel-ag") { RootScreen() } }
    @Test @Config(qualifiers = "en-w400dp-h860dp-xxhdpi") fun enConnect() {
        AppNav.onboarding.value = true
        shot("en", "7-yapay-zeka") { com.pufy.app.ui.onboarding.OnboardingScreen(needsSetup = true, initialStep = com.pufy.app.ui.onboarding.OnboardingStep.CONNECT_AI, onFinish = {}, onOpenSettings = {}) }
    }
}
