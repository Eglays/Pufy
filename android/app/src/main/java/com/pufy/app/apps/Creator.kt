package com.pufy.app.apps

import com.pufy.app.core.SafeErrors
import com.pufy.app.core.newID
import com.pufy.app.core.nowSwift
import com.pufy.app.data.Message
import com.pufy.app.data.MiniApp
import com.pufy.app.data.MiniAppStore
import com.pufy.app.notify.Notifier
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/**
 * Uygulama oluşturma oturumu (iOS AppCreatorView'un durumu). Ekrandan bağımsız yaşar:
 * ekran kapansa ya da Pufy arka plana geçse de yapım sürer, bitince uygulama kaydedilir ve bildirim gelir.
 */
class CreatorSession(editing: MiniApp?) {
    var appID: String? = editing?.id
    val folder: String = editing?.folderName ?: newID()
    val name = MutableStateFlow(editing?.name ?: "")
    val icon = MutableStateFlow(editing?.icon ?: "app.dashed")
    val colorHex = MutableStateFlow(editing?.colorHex)
    var tagline = editing?.description ?: ""
    val messages = MutableStateFlow(editing?.messages ?: emptyList())
    val versions = MutableStateFlow(MiniAppFiles.versions(folder))
    val builder = AppBuilder()
    private var job: Job? = null

    val isBuilding get() = builder.isBuilding.value

    fun send(text: String) {
        val request = text.trim()
        if (request.isEmpty() || job?.isActive == true) return
        val history = messages.value.filter { it.content.isNotEmpty() }.takeLast(8)
        messages.value = messages.value + Message(content = request, role = "user")
        builder.isBuilding.value = true
        job = Creator.scope.launch {
            val display = name.value.ifEmpty { "Uygulaman" }
            try {
                val result = builder.build(request, history, folder)
                var reply = result.reply.ifEmpty { if (result.didChangeFiles) "Hazır! Açıp deneyebilirsin." else "Anladım." }
                if (result.failedPatches.isNotEmpty()) reply += "\n\nŞu dosyalarda değişiklik uygulanamadı: ${result.failedPatches.joinToString(", ")}. Tekrar dener misin?"
                result.qualityNote?.let { reply += "\n\n$it" }
                result.meta?.let { m ->
                    if ((name.value.isEmpty() || appID == null) && !m.name.isNullOrBlank()) name.value = m.name
                    m.icon?.let { icon.value = it }
                    m.color?.takeIf { com.pufy.app.ui.components.colorFromHex(it) != null }?.let { colorHex.value = it }
                    m.tagline?.let { tagline = it }
                }
                messages.value = messages.value + Message(content = reply, role = "model", thinkingSteps = result.changedFiles.distinct().map { "✓ $it" })
                if (result.didChangeFiles) { persist(); versions.value = MiniAppFiles.versions(folder) } else persistIfNeeded()
                if (!Creator.foreground) Notifier.show("creator.$folder", if (result.didChangeFiles) "${name.value.ifEmpty { display }} hazır" else "Pufy cevap verdi",
                    if (result.didChangeFiles) "Açmak için dokun." else reply.take(120), app = true)
            } catch (e: CancellationException) {
                messages.value = messages.value + Message(content = "Durduruldu.", role = "model")
                persistIfNeeded()
            } catch (e: Throwable) {
                val msg = com.pufy.app.ai.AiClient.friendly(e).message ?: "Bilinmeyen hata"
                messages.value = messages.value + Message(content = "Bir sorun oluştu: $msg", role = "model")
                if (!Creator.foreground) Notifier.show("creator.$folder", "$display oluşturulamadı", msg, app = true)
                persistIfNeeded()
            }
        }
    }

    fun cancel() { job?.cancel() }

    fun restore(v: MiniAppFiles.Version) {
        MiniAppFiles.restore(v, folder)
        versions.value = MiniAppFiles.versions(folder)
        messages.value = messages.value + Message(content = "${com.pufy.app.core.turkeyFormat(v.dateMillis, "d MMM HH:mm")} sürümüne dönüldü.", role = "model")
        persist()
    }

    fun persist() {
        if (!MiniAppFiles.hasFiles(folder)) return
        val finalName = name.value.trim().ifEmpty { "Yeni Uygulama" }
        val existing = appID?.let { MiniAppStore.app(it) }
        if (existing != null) {
            MiniAppStore.upsert(existing.with {
                put("name", JsonPrimitive(finalName)); put("icon", JsonPrimitive(icon.value))
                colorHex.value?.let { put("colorHex", JsonPrimitive(it)) }
                if (tagline.isNotEmpty()) put("description", JsonPrimitive(tagline))
                put("messages", JsonArray(messages.value.map { it.toJson() })); put("folderName", JsonPrimitive(folder))
                remove("appSpecJson"); put("updatedAt", JsonPrimitive(nowSwift()))
            })
        } else {
            val app = MiniApp.create(finalName, icon.value, tagline, folder, colorHex.value, messages.value)
            appID = app.id
            MiniAppStore.upsert(app)
        }
    }

    fun persistIfNeeded() { if (appID != null) persist() }
}

object Creator {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + SafeErrors)
    @Volatile var foreground = true
    private val sessions = HashMap<String, CreatorSession>()

    /** Düzenlenen uygulamanın açık oturumu (yoksa yeni) */
    fun session(app: MiniApp?): CreatorSession {
        val key = app?.id ?: "new"
        sessions[key]?.let { s -> if (app != null || s.appID == null || s.isBuilding) return s }
        return CreatorSession(app).also { s -> sessions[key] = s }
    }

    /** Yeni uygulama ekranı kapanırken: yapım bitmişse bir sonraki "yeni" boş başlasın */
    fun release(session: CreatorSession) {
        if (session.isBuilding) return
        session.persistIfNeeded()
        sessions.entries.removeAll { it.value === session && it.key == "new" }
        session.appID?.let { sessions[it] = session }
    }
}
