package com.pufy.app

import android.app.Application
import com.pufy.app.ai.AiClient
import com.pufy.app.core.Settings
import com.pufy.app.data.AppFiles
import com.pufy.app.data.Stores
import com.pufy.app.data.ReminderStore
import com.pufy.app.ai.ChatEngine
import com.pufy.app.notify.Notifier
import com.pufy.app.sync.SyncService
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner

class PufyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        Settings.init(this)
        AppFiles.init(this)
        com.pufy.app.core.AIReportStore.init()
        com.tom_roush.pdfbox.android.PDFBoxResourceLoader.init(this)
        AiClient.init(this)
        Stores.load()
        Notifier.init(this)
        ReminderStore.cleanExpired()
        Notifier.rescheduleAll()
        SyncService.hookStores()
        SyncService.onTaskResult = { id, text -> ChatEngine.importTaskResult(id, text) }
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityResumed(a: android.app.Activity) { com.pufy.app.apps.AppTester.activity = java.lang.ref.WeakReference(a) }
            override fun onActivityPaused(a: android.app.Activity) { if (com.pufy.app.apps.AppTester.activity?.get() === a) com.pufy.app.apps.AppTester.activity = null }
            override fun onActivityCreated(a: android.app.Activity, b: android.os.Bundle?) {}
            override fun onActivityStarted(a: android.app.Activity) {}
            override fun onActivityStopped(a: android.app.Activity) {}
            override fun onActivitySaveInstanceState(a: android.app.Activity, b: android.os.Bundle) {}
            override fun onActivityDestroyed(a: android.app.Activity) {}
        })
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            // iOS ile aynı kural: açılınca / öne gelince çek, arka plana geçerken bekleyenleri gönder
            override fun onStart(owner: LifecycleOwner) { com.pufy.app.apps.Creator.foreground = true; SyncService.syncInBackground() }
            override fun onStop(owner: LifecycleOwner) { com.pufy.app.apps.Creator.foreground = false; SyncService.flushInBackground() }
        })
    }

    companion object {
        lateinit var instance: PufyApp
            private set
    }
}
