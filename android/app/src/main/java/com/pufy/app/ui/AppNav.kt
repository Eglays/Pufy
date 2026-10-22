package com.pufy.app.ui

import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Ekranlar arası durum (iOS TabManager + ContentView durumları): hangi sekme açık (sohbet ya da mini uygulama),
 * uygulama değiştirici, ayarlar, açık not.
 */
object AppNav {
    /** null = sohbet; değilse açık mini uygulamanın kimliği */
    val activeAppID = MutableStateFlow<String?>(null)
    val switcherVisible = MutableStateFlow(false)
    /** Değiştirici kart görünümüyle mi açılsın (sıkıştırma hareketi) */
    var switcherOpensInCards = false
    val settingsVisible = MutableStateFlow(false)
    val sideMenuOpen = MutableStateFlow(false)
    val openNoteID = MutableStateFlow<String?>(null)
    val memoryBookVisible = MutableStateFlow(false)
    /** Uygulama oluşturucu: düzenlenen uygulama (null = yeni) + ilk istek */
    data class CreatorRequest(val appID: String?, val prompt: String? = null, val initialName: String? = null, val autoSend: Boolean = true)
    val creator = MutableStateFlow<CreatorRequest?>(null)

    fun openCreator(name: String? = null, prompt: String? = null) {
        creator.value = CreatorRequest(appID = null, prompt = prompt, initialName = name, autoSend = false)
    }
    val editingReminder = MutableStateFlow<com.pufy.app.data.Reminder?>(null)
    val onboarding = MutableStateFlow(!com.pufy.app.core.Settings.bool(com.pufy.app.core.Settings.ONBOARDING_DONE))
    val onboardingStep = MutableStateFlow(com.pufy.app.ui.onboarding.OnboardingStep.INTRO)

    fun openAIConnect() {
        onboardingStep.value = com.pufy.app.ui.onboarding.OnboardingStep.CONNECT_AI
        onboarding.value = true
    }

    fun showSwitcher(cards: Boolean = false) {
        if (switcherVisible.value) return
        switcherOpensInCards = cards
        switcherVisible.value = true
    }

    fun openChat() { activeAppID.value = null; switcherVisible.value = false }
    fun openApp(id: String) { activeAppID.value = id; switcherVisible.value = false; sideMenuOpen.value = false }
}
