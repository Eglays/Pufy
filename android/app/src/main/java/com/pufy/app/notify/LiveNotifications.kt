package com.pufy.app.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.pufy.app.MainActivity
import com.pufy.app.R
import java.util.concurrent.ConcurrentHashMap

/**
 * Android canlı bildirimler (iOS Live Activities karşılığı).
 * Zamanlayıcılar ve mini uygulamalar için durum çubuğunda ve kilit ekranında
 * süren (ongoing) bildirim gösterir. Geri sayım kronometresi veya ilerleme çubuğu barındırır.
 */
object LiveNotifications {
    const val CHANNEL_LIVE = "live"
    private lateinit var context: Context
    private val activeIds = ConcurrentHashMap.newKeySet<String>()

    fun init(ctx: Context) {
        context = ctx.applicationContext
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_LIVE,
            if (com.pufy.app.core.AppLocales.isEnglish()) "Live updates" else "Canlı güncellemeler",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = if (com.pufy.app.core.AppLocales.isEnglish()) "Timer and mini app live statuses" else "Zamanlayıcı ve mini uygulama canlı durumları"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    fun isActive(id: String): Boolean = activeIds.contains(id)

    fun start(
        id: String,
        title: String,
        subtitle: String? = null,
        endMillis: Long? = null,
        progress: Float? = null,
    ): Boolean {
        if (!::context.isInitialized || !Notifier.canNotify) return false

        val open = PendingIntent.getActivity(
            context,
            id.hashCode(),
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_LIVE)
            .setSmallIcon(R.drawable.splash_icon)
            .setContentTitle(Notifier.clean(title))
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        subtitle?.takeIf { it.isNotBlank() }?.let {
            builder.setContentText(Notifier.clean(it))
        }

        if (endMillis != null && endMillis > System.currentTimeMillis()) {
            builder.setUsesChronometer(true)
            builder.setChronometerCountDown(true)
            builder.setWhen(endMillis)
            builder.setShowWhen(true)
        }

        if (progress != null && progress in 0f..1f) {
            val pct = (progress * 100).toInt().coerceIn(0, 100)
            builder.setProgress(100, pct, false)
        }

        return try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), builder.build())
            activeIds.add(id)
            true
        } catch (e: Throwable) {
            false
        }
    }

    fun update(
        id: String,
        title: String? = null,
        subtitle: String? = null,
        endMillis: Long? = null,
        progress: Float? = null,
    ): Boolean {
        if (!::context.isInitialized || !Notifier.canNotify) return false
        val activeTitle = title ?: "Pufy"
        return start(id, activeTitle, subtitle, endMillis, progress)
    }

    fun end(id: String, finalStatus: String? = null) {
        if (!::context.isInitialized) return
        activeIds.remove(id)
        runCatching {
            NotificationManagerCompat.from(context).cancel(id.hashCode())
        }
    }

    fun endPrefix(prefix: String) {
        val targets = activeIds.filter { it.startsWith(prefix) }
        for (target in targets) {
            end(target)
        }
    }
}
