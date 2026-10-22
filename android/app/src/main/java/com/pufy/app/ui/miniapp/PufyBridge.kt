package com.pufy.app.ui.miniapp

import android.content.Context
import android.content.Intent
import android.view.HapticFeedbackConstants
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.pufy.app.ai.AiClient
import com.pufy.app.core.PufyJson
import com.pufy.app.core.newID
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.AppFiles
import com.pufy.app.data.MiniApp
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import com.pufy.app.notify.Notifier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.time.Instant

/**
 * window.pufy köprüsü — iOS PufyBridge ile aynı API (aynı uygulama iki cihazda da çalışsın):
 * storage, haptic, notify/notifyDaily/cancelNotification, remind, ai, fetch, secret, pickPhoto/takePhoto, share, work, live.
 * Yapay zeka anahtarı sayfaya hiç gitmez; istekler Pufy üzerinden yapılır.
 */
class PufyBridge(
    private val context: Context,
    private val app: MiniApp,
    private val folder: String,
    private val onError: (String) -> Unit,
    private val onLayout: (Int) -> Unit,
    private val onPickPhoto: (camera: Boolean, reply: (String?) -> Unit) -> Unit,
) {
    var webView: WebView? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + com.pufy.app.core.SafeErrors)
    private val storageFile get() = File(AppFiles.miniAppData, "$folder.json")

    fun dispose() = scope.cancel()

    @JavascriptInterface fun post(raw: String) {
        val msg = runCatching { PufyJson.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return
        val id = msg.s("__id")
        scope.launch {
            val result = runCatching { handle(msg.s("action"), msg) }
            reply(id, result.getOrNull(), result.exceptionOrNull()?.let { AiClient.friendly(it).message ?: "Hata" })
        }
    }

    @JavascriptInterface fun log(kind: String, message: String) { if (kind == "error" || kind == "console") scope.launch { onError(message.take(400)) } }
    @JavascriptInterface fun layout(spot: Int) { if (spot in 0..5) scope.launch { onLayout(spot) } }

    private fun reply(id: String, value: JsonElement?, error: String?) {
        val js = "window.__pufyReply(${JsonPrimitive(id)}, ${value ?: JsonNull}, ${error?.let { JsonPrimitive(it) } ?: JsonNull})"
        webView?.evaluateJavascript(js, null)
    }

    private fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content ?: ""
    private fun JsonObject.d(k: String) = (this[k] as? JsonPrimitive)?.doubleOrNull
    private fun JsonObject.b(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull ?: false

    private fun storage(): MutableMap<String, String> = runCatching {
        PufyJson.parseToJsonElement(storageFile.readText()).jsonObject.mapValues { it.value.jsonPrimitive.content }.toMutableMap()
    }.getOrDefault(mutableMapOf())

    private fun saveStorage(map: Map<String, String>) {
        storageFile.parentFile?.mkdirs()
        storageFile.writeText(JsonObject(map.mapValues { JsonPrimitive(it.value) }).toString())
        com.pufy.app.data.MiniAppStore.dataChanged(folder)
    }

    private suspend fun handle(action: String, body: JsonObject): JsonElement = when (action) {
        "storage.get" -> storage()[body.s("key")]?.let(::JsonPrimitive) ?: JsonNull
        "storage.set" -> { val s = storage(); s[body.s("key")] = body.s("value").ifEmpty { "null" }; saveStorage(s); JsonPrimitive(true) }
        "storage.remove" -> { val s = storage(); s.remove(body.s("key")); saveStorage(s); JsonPrimitive(true) }
        "storage.keys" -> JsonArray(storage().keys.map(::JsonPrimitive))
        "haptic" -> {
            webView?.performHapticFeedback(when (body.s("style")) {
                "success" -> if (android.os.Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK
                "error", "warning" -> if (android.os.Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
                "heavy", "medium" -> HapticFeedbackConstants.CONTEXT_CLICK
                else -> HapticFeedbackConstants.CLOCK_TICK
            })
            JsonPrimitive(true)
        }
        "notify", "notifyDaily" -> {
            val key = "pufyapp.$folder.${newID()}"
            val title = body.s("title").ifEmpty { app.name }
            if (action == "notifyDaily") {
                val hour = body.d("hour")?.toInt() ?: 9; val minute = body.d("minute")?.toInt() ?: 0
                Notifier.scheduleApp(key, Notifier.nextDaily(hour, minute), title, body.s("body"), hour, minute)
            } else {
                val seconds = body.d("seconds") ?: 0.0
                if (seconds <= 0) Notifier.show(key, title, body.s("body"), app = true)
                else Notifier.scheduleApp(key, System.currentTimeMillis() + (seconds * 1000).toLong(), title, body.s("body"))
            }
            JsonPrimitive(key)
        }
        "cancelNotification" -> JsonPrimitive(Notifier.cancelApp("pufyapp.$folder.", body.s("id")))
        "remind" -> {
            val date = runCatching { Instant.parse(body.s("date")).toEpochMilli() }.getOrNull()
            require(date != null && date > System.currentTimeMillis()) { "Geçersiz veya geçmiş tarih" }
            val note = Notifier.clean(body.s("note"))
            ReminderStore.upsert(Reminder(title = Notifier.clean(body.s("title").ifEmpty { "Hatırlatıcı" }),
                note = if (note.isEmpty()) "${app.name} uygulamasından" else "$note · ${app.name}", dateMillis = date))
            JsonPrimitive(true)
        }
        "ai" -> {
            val json = body.b("json")
            val search = body.b("search") && AiClient.canUseGoogleSearch
            var system = body.s("system")
            if (search) system += "\nŞu an: ${turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy EEEE HH:mm")} (Türkiye). Web'de ara; sadece gerçek, doğrulanmış bilgi ver, uydurma." +
                if (json) " SADECE istenen JSON'u yaz; açıklama ya da kod bloğu yazma." else ""
            val text = AiClient.generate(body.s("prompt"), system = system.ifEmpty { null },
                responseMimeType = if (json && !search) "application/json" else null, timeoutSeconds = if (search) 120 else null, useSearch = search)
            if (json) {
                val s = listOf(text.indexOf('{'), text.indexOf('[')).filter { it >= 0 }.minOrNull()
                val e = maxOf(text.lastIndexOf('}'), text.lastIndexOf(']'))
                JsonPrimitive(if (s != null && e > s) text.substring(s, e + 1) else text)
            } else JsonPrimitive(text)
        }
        "fetch" -> withContext(Dispatchers.IO) {
            val url = body.s("url")
            require(url.startsWith("https://") || url.startsWith("http://")) { "Geçersiz adres" }
            val method = body.s("method").uppercase().ifEmpty { "GET" }
            val payload = body.s("body").takeIf { body["body"] !is JsonNull && it.isNotEmpty() }
            val request = Request.Builder().url(url).apply {
                (body["headers"] as? JsonObject)?.forEach { (k, v) -> header(k, (v as? JsonPrimitive)?.content ?: v.toString()) }
                method(method, if (method == "GET" || method == "HEAD") null else (payload ?: "").toRequestBody())
            }.build()
            AiClient.http.newCall(request).execute().use { r ->
                JsonPrimitive(buildJsonObject {
                    put("ok", r.isSuccessful); put("status", r.code)
                    put("headers", JsonObject(r.headers.toMultimap().mapValues { JsonPrimitive(it.value.joinToString(", ")) }))
                    put("text", r.body.string().take(3_000_000))
                }.toString())
            }
        }
        "secret" -> {
            val name = body.s("name")
            val value = if (name != null) com.pufy.app.apps.MiniAppSecrets.get(name, folder) else null
            if (value != null) JsonPrimitive(value) else JsonNull
        }
        "photo" -> kotlinx.coroutines.suspendCancellableCoroutine { cont ->
            onPickPhoto(body.s("source") == "camera") { data -> cont.resumeWith(Result.success(data?.let(::JsonPrimitive) ?: JsonNull)) }
        }
        "share" -> {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, body.s("text")), null)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            JsonPrimitive(true)
        }
        "work.start", "work.update", "work.end" -> JsonPrimitive(true)
        "live.start" -> {
            val params = parseLiveParams(body.s("template"), app.name)
            val endMillis = params.seconds?.let { System.currentTimeMillis() + it * 1000L }
            val liveId = "pufyapp.$folder.${com.pufy.app.core.newID().take(8)}"
            val ok = com.pufy.app.notify.LiveNotifications.start(
                id = liveId,
                title = params.title,
                subtitle = params.subtitle,
                endMillis = endMillis,
                progress = params.progress
            )
            if (ok) JsonPrimitive(liveId) else JsonNull
        }
        "live.update" -> {
            val id = body.s("id") ?: ""
            if (id.startsWith("pufyapp.$folder.")) {
                val params = parseLiveParams(body.s("template"), app.name)
                val endMillis = params.seconds?.let { System.currentTimeMillis() + it * 1000L }
                val ok = com.pufy.app.notify.LiveNotifications.update(
                    id = id,
                    title = params.title,
                    subtitle = params.subtitle,
                    endMillis = endMillis,
                    progress = params.progress
                )
                JsonPrimitive(ok)
            } else {
                JsonPrimitive(false)
            }
        }
        "live.end" -> {
            val id = body.s("id")
            val status = body.s("status")
            if (!id.isNullOrEmpty() && id.startsWith("pufyapp.$folder.")) {
                com.pufy.app.notify.LiveNotifications.end(id, status)
            } else {
                com.pufy.app.notify.LiveNotifications.endPrefix("pufyapp.$folder.")
            }
            JsonPrimitive(true)
        }
        else -> error("Bilinmeyen işlem: $action")
    }

    private data class LiveParams(val title: String, val subtitle: String, val seconds: Long?, val progress: Float?)

    private fun parseLiveParams(templateStr: String?, defaultTitle: String): LiveParams {
        var title = defaultTitle
        var subtitle = ""
        var seconds: Long? = null
        var progress: Float? = null

        if (!templateStr.isNullOrBlank()) {
            runCatching {
                val json = com.pufy.app.core.PufyJson.parseToJsonElement(templateStr).jsonObject
                val style = (json["style"] as? JsonPrimitive)?.content
                val t = (json["title"] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() }
                if (t != null) title = t
                val sub = (json["subtitle"] as? JsonPrimitive)?.content
                val st = (json["status"] as? JsonPrimitive)?.content
                val sec = (json["seconds"] as? JsonPrimitive)?.doubleOrNull?.toLong()
                if (sec != null && sec > 0) seconds = sec
                val prog = (json["progress"] as? JsonPrimitive)?.doubleOrNull?.toFloat()
                if (prog != null && prog >= 0) progress = prog.coerceIn(0f, 1f)

                if (style == "score") {
                    val home = (json["home"] as? JsonObject)?.let {
                        (it["short"] as? JsonPrimitive)?.content ?: (it["name"] as? JsonPrimitive)?.content
                    } ?: "Ev"
                    val away = (json["away"] as? JsonObject)?.let {
                        (it["short"] as? JsonPrimitive)?.content ?: (it["name"] as? JsonPrimitive)?.content
                    } ?: "Dep"
                    val homeScore = (json["homeScore"] as? JsonPrimitive)?.content ?: "0"
                    val awayScore = (json["awayScore"] as? JsonPrimitive)?.content ?: "0"
                    val minute = (json["minute"] as? JsonPrimitive)?.content
                    title = "$home $homeScore - $awayScore $away"
                    subtitle = listOfNotNull(minute, st ?: sub).filter { it.isNotBlank() }.joinToString(" · ")
                } else if (style == "metric") {
                    val value = (json["value"] as? JsonPrimitive)?.content ?: ""
                    val unit = (json["unit"] as? JsonPrimitive)?.content ?: ""
                    val change = (json["change"] as? JsonPrimitive)?.content
                    val changeText = if (!change.isNullOrBlank()) " ($change)" else ""
                    subtitle = "$unit$value$changeText".trim()
                } else {
                    subtitle = listOfNotNull(sub, st).filter { it.isNotBlank() }.joinToString(" · ")
                }
            }
        }
        return LiveParams(title, subtitle, seconds, progress)
    }

    companion object {
        /** iOS PufyBridgeScript ile aynı API; iletişim PufyNative arayüzü + söz (promise) cevapları */
        fun script(userName: String): String {
            val name = JsonPrimitive(userName).toString()
            return """
(function(){
  if (window.pufy) return;
  var seq = 0, waiting = {};
  window.__pufyReply = function(id, value, error) {
    var w = waiting[id]; if (!w) return; delete waiting[id];
    if (error != null) w.reject(new Error(error)); else w.resolve(value);
  };
  var send = function(action, payload) {
    return new Promise(function(resolve, reject) {
      var id = 'm' + (++seq); waiting[id] = {resolve: resolve, reject: reject};
      PufyNative.post(JSON.stringify(Object.assign({action: action, __id: id}, payload || {})));
    });
  };
  var report = function(kind, message) { try { PufyNative.log(kind, String(message)); } catch (e) {} };
  window.addEventListener('error', function(e) { report('error', e.message + (e.filename ? ' (' + e.filename.split('/').pop() + ':' + e.lineno + ')' : '')); });
  window.addEventListener('unhandledrejection', function(e) { var r = e.reason; report('error', 'Promise: ' + ((r && (r.stack || r.message)) || r)); });
  var origError = console.error;
  console.error = function() {
    var args = Array.prototype.slice.call(arguments);
    report('console', args.map(function(x){ return (x && x.stack) || (typeof x === 'object' ? JSON.stringify(x) : String(x)); }).join(' '));
    origError.apply(console, args);
  };
  window.pufy = {
    version: 1,
    platform: 'android',
    user: { name: $name },
    storage: {
      get: function(key) { return send('storage.get', {key: key}).then(function(v){ return v == null ? null : JSON.parse(v); }); },
      set: function(key, value) { return send('storage.set', {key: key, value: JSON.stringify(value === undefined ? null : value)}); },
      remove: function(key) { return send('storage.remove', {key: key}); },
      keys: function() { return send('storage.keys'); }
    },
    haptic: function(style) { send('haptic', {style: style || 'light'}); },
    notify: function(title, body, seconds, opts) { opts = opts || {}; return send('notify', {title: String(title), body: String(body || ''), seconds: Number(seconds || 0), repeat: !!opts.repeat}); },
    notifyDaily: function(title, body, hour, minute) { return send('notifyDaily', {title: String(title), body: String(body || ''), hour: Number(hour), minute: Number(minute || 0)}); },
    cancelNotification: function(id) { return send('cancelNotification', {id: String(id)}); },
    cancelAllNotifications: function() { return send('cancelNotification', {id: ''}); },
    remind: function(title, date, note) { return send('remind', {title: String(title), date: (date instanceof Date ? date.toISOString() : String(date)), note: String(note || '')}); },
    ai: function(prompt, opts) { opts = opts || {}; return send('ai', {prompt: String(prompt), system: String(opts.system || ''), json: !!opts.json, search: !!opts.search}).then(function(t){ return opts.json ? JSON.parse(t) : t; }); },
    fetch: function(url, opts) { opts = opts || {}; return send('fetch', {url: String(url), method: String(opts.method || 'GET'), headers: opts.headers || {}, body: (opts.body == null ? null : (typeof opts.body === 'string' ? opts.body : JSON.stringify(opts.body)))}).then(function(r){ r = JSON.parse(r); try { r.json = JSON.parse(r.text); } catch (e) { r.json = null; } return r; }); },
    secret: function(name) { return send('secret', {name: String(name)}); },
    pickPhoto: function() { return send('photo', {source: 'library'}); },
    takePhoto: function() { return send('photo', {source: 'camera'}); },
    share: function(text) { return send('share', {text: String(text)}); },
    work: {
      start: function(title) { return send('work.start', {title: String(title || '')}); },
      update: function(o) { o = o || {}; return send('work.update', {progress: (o.progress == null ? -1 : Number(o.progress)), status: String(o.status || '')}); },
      end: function() { return send('work.end'); }
    },
    live: {
      start: function(o) { return send('live.start', {template: JSON.stringify(o || {})}); },
      update: function(id, o) { return send('live.update', {id: String(id), template: JSON.stringify(o || {})}); },
      end: function(id, o) { return send('live.end', {id: String(id || '')}); }
    }
  };
  document.dispatchEvent(new Event('pufyready'));
})();
"""
        }

        const val VIEWPORT = "(function(){var c='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';" +
            "var m=document.querySelector('meta[name=viewport]');if(m){m.setAttribute('content',c);}else{m=document.createElement('meta');m.name='viewport';m.content=c;(document.head||document.documentElement).appendChild(m);}})();"
    }
}
