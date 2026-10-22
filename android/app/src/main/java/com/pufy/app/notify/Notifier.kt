package com.pufy.app.notify

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.pufy.app.MainActivity
import com.pufy.app.R
import com.pufy.app.core.AppLocales
import com.pufy.app.core.Settings
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import java.util.Calendar

/**
 * Bildirimler: hatırlatıcılar, zamanlayıcılar ve mini uygulama bildirimleri (iOS UNUserNotificationCenter karşılığı).
 * Emojisiz, sade metin (iOS kuralıyla aynı). Zamanlananlar AlarmManager ile; telefon yeniden açılınca tekrar kurulur.
 */
object Notifier {
    private const val CHANNEL_REMINDERS = "reminders"
    private const val CHANNEL_APPS = "apps"
    private const val APP_ALARMS = "pufy_app_alarms"
    private lateinit var context: Context

    fun init(ctx: Context) {
        context = ctx.applicationContext
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_REMINDERS, if (AppLocales.isEnglish()) "Reminders" else "Hatırlatıcılar", NotificationManager.IMPORTANCE_HIGH))
        nm.createNotificationChannel(NotificationChannel(CHANNEL_APPS, if (AppLocales.isEnglish()) "App notifications" else "Uygulama bildirimleri", NotificationManager.IMPORTANCE_DEFAULT))
        LiveNotifications.init(context)
        ReminderStore.scheduler = { reminder, id -> if (reminder == null) cancel("r.$id") else scheduleReminder(reminder) }
    }

    val canNotify get() = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun clean(text: String) = text.replace(Regex("[\\p{So}\\p{Cn}\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{FE0F}]"), "").replace(Regex("\\s{2,}"), " ").trim()

    fun show(key: String, title: String, body: String, app: Boolean = false) {
        if (!canNotify) return
        val open = PendingIntent.getActivity(context, key.hashCode(), Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(context, if (app) CHANNEL_APPS else CHANNEL_REMINDERS)
            .setSmallIcon(R.drawable.splash_icon)
            .setContentTitle(clean(title))
            .setContentText(clean(body).ifEmpty { null })
            .setStyle(NotificationCompat.BigTextStyle().bigText(clean(body)))
            .setAutoCancel(true)
            .setContentIntent(open)
            .setPriority(if (app) NotificationCompat.PRIORITY_DEFAULT else NotificationCompat.PRIORITY_HIGH)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(key.hashCode(), n) }
    }

    // MARK: Zamanlama

    private fun pending(key: String, title: String, body: String, app: Boolean, flags: Int = PendingIntent.FLAG_UPDATE_CURRENT): PendingIntent? =
        PendingIntent.getBroadcast(context, key.hashCode(), Intent(context, AlarmReceiver::class.java)
            .putExtra("key", key).putExtra("title", title).putExtra("body", body).putExtra("app", app),
            PendingIntent.FLAG_IMMUTABLE or flags)

    private fun scheduleAt(key: String, at: Long, title: String, body: String, app: Boolean) {
        val am = context.getSystemService(AlarmManager::class.java)
        val pi = pending(key, title, body, app) ?: return
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
    }

    fun cancel(key: String) {
        if (key.startsWith("r.")) {
            LiveNotifications.end("timer." + key.removePrefix("r."))
        }
        val pi = PendingIntent.getBroadcast(context, key.hashCode(), Intent(context, AlarmReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pi)
        pi.cancel()
    }

    fun scheduleReminder(r: Reminder) {
        cancel("r.${r.id}")
        if (!r.isActive || r.isAITask) return     // yapay zeka görevleri sunucuda çalışır
        val at = nextOccurrence(r) ?: return
        val title = if (r.isTimer) (if (AppLocales.isEnglish()) "Timer completed" else "Süre doldu") else r.title
        val body = if (r.isTimer) r.title else r.note
        scheduleAt("r.${r.id}", at, title, body, app = false)
        if (r.isTimer) {
            LiveNotifications.start("timer.${r.id}", title = r.title, subtitle = (if (AppLocales.isEnglish()) "Countdown" else "Geri sayım"), endMillis = at)
        }
    }

    fun rescheduleAll() {
        ReminderStore.reminders.value.forEach { scheduleReminder(it) }
        appAlarms().forEach { o ->
            val at = o["at"]?.jsonPrimitive?.long ?: return@forEach
            if (at > System.currentTimeMillis()) scheduleAt(o.s("key"), at, o.s("title"), o.s("body"), app = true)
        }
    }

    /** Tekrarlı hatırlatıcının bir sonraki zamanı (iOS Reminder.nextOccurrence) */
    fun nextOccurrence(r: Reminder, now: Long = System.currentTimeMillis()): Long? {
        if (r.repeat == "none") return r.dateMillis.takeIf { it > now }
        val cal = Calendar.getInstance().apply { timeInMillis = r.dateMillis }
        var guard = 0
        while (cal.timeInMillis <= now && guard++ < 4000) {
            when (r.repeat) {
                "daily" -> cal.add(Calendar.DAY_OF_YEAR, 1)
                "weekly" -> cal.add(Calendar.WEEK_OF_YEAR, 1)
                "monthly" -> cal.add(Calendar.MONTH, 1)
                "yearly" -> cal.add(Calendar.YEAR, 1)
                "weekdays" -> { do cal.add(Calendar.DAY_OF_YEAR, 1) while (cal.get(Calendar.DAY_OF_WEEK) in setOf(Calendar.SATURDAY, Calendar.SUNDAY)) }
                else -> return null
            }
        }
        return cal.timeInMillis
    }

    // MARK: Mini uygulama bildirimleri (pufy.notify)

    private fun JsonObject.s(k: String) = this[k]?.jsonPrimitive?.content ?: ""
    private fun appAlarms(): List<JsonObject> = runCatching {
        com.pufy.app.core.PufyJson.parseToJsonElement(Settings.string(APP_ALARMS) ?: "[]").jsonArray.map { it.jsonObject }
    }.getOrDefault(emptyList())
    private fun saveAppAlarms(list: List<JsonObject>) = Settings.setString(APP_ALARMS, JsonArray(list).toString())

    fun scheduleApp(key: String, at: Long, title: String, body: String, dailyHour: Int? = null, dailyMinute: Int = 0) {
        scheduleAt(key, at, title, body, app = true)
        saveAppAlarms(appAlarms().filter { it.s("key") != key && (it["at"]?.jsonPrimitive?.long ?: 0) > System.currentTimeMillis() } + buildJsonObject {
            put("key", key); put("at", at); put("title", title); put("body", body)
            dailyHour?.let { put("hour", it); put("minute", dailyMinute) }
        })
    }

    fun cancelApp(prefix: String, exact: String?): Int {
        val list = appAlarms()
        val hit = list.filter { if (exact.isNullOrEmpty()) it.s("key").startsWith(prefix) else it.s("key") == exact }
        hit.forEach { cancel(it.s("key")) }
        saveAppAlarms(list - hit.toSet())
        return hit.size
    }

    internal fun fired(key: String, title: String, body: String, app: Boolean) {
        if (key.startsWith("r.")) {
            LiveNotifications.end("timer." + key.removePrefix("r."))
        }
        show(key, title, body, app)
        if (key.startsWith("r.")) {
            val r = ReminderStore.reminder(key.removePrefix("r.")) ?: return
            if (r.repeat != "none") scheduleReminder(r)
        } else {
            val entry = appAlarms().firstOrNull { it.s("key") == key }
            val hour = entry?.get("hour")?.jsonPrimitive?.content?.toIntOrNull()
            if (hour != null) {
                val minute = entry["minute"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
                scheduleApp(key, nextDaily(hour, minute), title, body, hour, minute)
            }
        }
    }

    fun nextDaily(hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        if (cal.timeInMillis <= System.currentTimeMillis()) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Notifier.fired(intent.getStringExtra("key") ?: return, intent.getStringExtra("title") ?: "Pufy",
            intent.getStringExtra("body") ?: "", intent.getBooleanExtra("app", false))
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) Notifier.rescheduleAll()
    }
}
