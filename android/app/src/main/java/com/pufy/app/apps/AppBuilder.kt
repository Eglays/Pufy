package com.pufy.app.apps

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import com.pufy.app.ai.AiClient
import com.pufy.app.ai.AiTurn
import com.pufy.app.ai.Prompts
import com.pufy.app.ai.StreamChunk
import com.pufy.app.core.PufyJson
import com.pufy.app.data.Message
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.coroutines.coroutineContext
import kotlin.math.exp

// iOS AppBuilder + AppAgent karşılığı: plan → görseller → kod (FILE / PATCH / DELETE blokları) → uygula → dene → incele → düzelt

data class AgentStep(val id: String, val title: String, val state: State = State.PENDING, val detail: String? = null) {
    enum class State { PENDING, RUNNING, DONE, FAILED }
}

data class FileProgress(val path: String, val state: State, val added: Int, val removed: Int) {
    enum class State { WRITING, WRITTEN, PATCHED, DELETED, FAILED }
}

data class BuildMeta(val name: String?, val icon: String?, val color: String?, val tagline: String?)

data class BuildResult(val reply: String, val meta: BuildMeta?, val changedFiles: List<String>, val failedPatches: List<String>, val qualityNote: String? = null) {
    val didChangeFiles get() = changedFiles.isNotEmpty()
}

class AppBuilder {
    val isBuilding = MutableStateFlow(false)
    val status = MutableStateFlow("")
    val steps = MutableStateFlow<List<AgentStep>>(emptyList())
    val files = MutableStateFlow<List<FileProgress>>(emptyList())
    val liveReply = MutableStateFlow("")
    val reasoning = MutableStateFlow("")
    val progress = MutableStateFlow(0.0)

    private var originals: Map<String, List<String>> = emptyMap()
    private var phase = 0.05 to 0.95
    private var partialOutput = ""

    private fun setStep(id: String, title: String, state: AgentStep.State, detail: String? = null) {
        steps.value = steps.value.let { list ->
            if (list.any { it.id == id }) list.map { if (it.id == id) it.copy(title = title, state = state, detail = detail ?: it.detail) else it }
            else list + AgentStep(id, title, state, detail)
        }
    }

    suspend fun build(request: String, history: List<Message>, folder: String): BuildResult {
        isBuilding.value = true
        try {
            progress.value = 0.02; files.value = emptyList(); steps.value = emptyList(); reasoning.value = ""; liveReply.value = ""
            originals = MiniAppFiles.textFiles(folder).associate { it.first to it.second.split("\n") }
            status.value = "Plan çıkarılıyor…"
            val hasApp = MiniAppFiles.hasFiles(folder)

            setStep("plan", "Plan çıkarılıyor", AgentStep.State.RUNNING)
            val plan = AppAgent.plan(request, history, folder, hasApp)
            coroutineContext.ensureActive()
            if (plan?.chat == true) {
                steps.value = emptyList(); status.value = "Düşünüyor…"; phase = 0.05 to 0.95
                val raw = stream(baseMessage(request, folder, hasApp), history)
                status.value = ""
                return apply(raw, folder, null)
            }
            setStep("plan", plan?.summary?.let { "Plan: $it" } ?: "Plan hazır", AgentStep.State.DONE)
            plan?.todo?.take(7)?.forEachIndexed { i, item -> steps.value = steps.value + AgentStep("todo$i", item) }
            progress.value = 0.08

            // Görseller (en fazla 8, üçerli gruplar hâlinde aynı anda)
            val made = mutableListOf<Triple<String, Pair<Int, Int>, String>>()
            val wanted = plan?.assets.orEmpty().take(8)
            if (wanted.isNotEmpty() && AiClient.canGenerateImages) {
                status.value = "Görseller çiziliyor…"
                setStep("assets", "Görseller çiziliyor (0/${wanted.size})", AgentStep.State.RUNNING)
                var done = 0
                for (batch in wanted.chunked(3)) {
                    coroutineContext.ensureActive()
                    val results = coroutineScope { batch.map { a -> async { AppAgent.makeAsset(a, plan?.style, folder)?.let { Triple(it.first, it.second, a.note ?: a.prompt) } } }.awaitAll() }
                    made += results.filterNotNull()
                    done += batch.size
                    setStep("assets", "Görseller çiziliyor ($done/${wanted.size})", AgentStep.State.RUNNING)
                    progress.value = 0.08 + 0.22 * done / wanted.size
                }
                setStep("assets", if (made.isEmpty()) "Görseller çizilemedi" else "${made.size} görsel hazır", if (made.isEmpty()) AgentStep.State.FAILED else AgentStep.State.DONE)
            }
            val assetsText = assetsText(folder, made)

            MiniAppFiles.ensureKit(folder)
            setStep("code", "Kod yazılıyor", AgentStep.State.RUNNING)
            phase = maxOf(progress.value, 0.1) to 0.7
            var message = baseMessage(request, folder, hasApp)
            if (plan != null) message += "\n\n[PLAN]\nÖzet: ${plan.summary ?: ""}\nStil: ${plan.style ?: "-"}\nYapılacaklar:\n" + plan.todo.orEmpty().joinToString("\n") { "- $it" }
            if (assetsText.isNotEmpty()) message += "\n\n$assetsText"
            val raw = stream(message, history)
            coroutineContext.ensureActive()
            var result = apply(raw, folder, request)
            MiniAppFiles.ensureKit(folder)
            if (result.failedPatches.isNotEmpty()) {
                val retry = retryFailedPatches(result.failedPatches, request, folder)
                result = result.copy(changedFiles = result.changedFiles + retry.changedFiles, failedPatches = retry.failedPatches)
            }
            setStep("code", if (result.didChangeFiles) "Kod yazıldı · ${result.changedFiles.toSet().size} dosya" else "Kod değişmedi",
                if (result.didChangeFiles) AgentStep.State.DONE else AgentStep.State.FAILED)
            steps.value = steps.value.map { if (it.id.startsWith("todo")) it.copy(state = AgentStep.State.DONE) else it }

            // Dene → incele → gerekirse düzelt (en fazla 3 tur)
            if (result.didChangeFiles && MiniAppFiles.hasFiles(folder)) {
                var lastScore: Double? = null
                var fixes = 0
                for (round in 1..3) {
                    coroutineContext.ensureActive()
                    val testID = "test$round"
                    setStep(testID, if (round == 1) "Deneniyor" else "Yeniden deneniyor", AgentStep.State.RUNNING)
                    status.value = "Uygulama deneniyor…"
                    progress.value = 0.72 + 0.09 * (round - 1)
                    val run = AppTester.run(folder)
                    if (run == null) { setStep(testID, "Görsel deneme atlandı (Pufy arka plandaydı)", AgentStep.State.DONE); break }
                    status.value = "Ekran görüntüsüne bakılıyor…"
                    val review = AppAgent.review(request, plan, run, round)
                    if (review == null) { setStep(testID, if (run.errors.isEmpty()) "Denendi" else "Denendi · ${run.errors.size} hata", AgentStep.State.DONE); break }
                    val score = review.score ?: 0.0
                    lastScore = score
                    val issues = review.issues
                    setStep(testID, "Deneme $round: ${fmt(score)}/10" + if (issues.isEmpty() && run.errors.isEmpty()) "" else " · ${issues.size + run.errors.size} sorun",
                        AgentStep.State.DONE, (run.errors.take(2) + issues.take(3)).joinToString("\n"))
                    val needsFix = (score < 8.5 || run.errors.isNotEmpty()) && (issues.isNotEmpty() || run.errors.isNotEmpty())
                    if (!needsFix || round >= 3) break

                    val fixID = "fix$round"
                    setStep(fixID, "Düzeltiliyor", AgentStep.State.RUNNING)
                    status.value = "Sorunlar düzeltiliyor…"
                    phase = progress.value to progress.value + 0.08
                    files.value = emptyList()
                    val fixPrompt = """
                        |[MEVCUT DOSYALAR]
                        |${MiniAppFiles.promptText(folder)}
                        |
                        |${assetsText(folder, emptyList())}
                        |
                        |[DENEME SONUCU — tur $round] Puan: ${fmt(score)}/10
                        |Konsol hataları:
                        |${if (run.errors.isEmpty()) "yok" else run.errors.joinToString("\n") { "- $it" }}
                        |Sorunlar:
                        |${issues.joinToString("\n") { "- $it" }}
                        |Talimat: ${review.fix ?: "Sorunları gider."}
                        |
                        |Bu sorunları KÖKÜNDEN düzelt (asıl istek: $request). Sadece gerekeni PATCH ile değiştir; dosyanın yarısından
                        |fazlası değişecekse FILE ile tamamını yaz. Hazır görselleri kullanmaya devam et. En sonda tek cümleyle ne düzelttiğini yaz.
                    """.trimMargin()
                    var fixed = apply(stream(fixPrompt, emptyList()), folder, null)
                    MiniAppFiles.ensureKit(folder)
                    if (fixed.failedPatches.isNotEmpty()) {
                        val retry = retryFailedPatches(fixed.failedPatches, review.fix ?: request, folder)
                        fixed = fixed.copy(changedFiles = fixed.changedFiles + retry.changedFiles)
                    }
                    setStep(fixID, if (fixed.didChangeFiles) "Düzeltildi" else "Düzeltilemedi", if (fixed.didChangeFiles) AgentStep.State.DONE else AgentStep.State.FAILED)
                    if (!fixed.didChangeFiles) break
                    fixes++
                    result = result.copy(changedFiles = result.changedFiles + fixed.changedFiles.filter { it !in result.changedFiles })
                }
                if (lastScore != null) result = result.copy(qualityNote = "Kalite kontrolü: ${fmt(lastScore)}/10" +
                    (if (fixes > 0) " · $fixes tur düzeltildi" else "") + (if (made.isEmpty()) "" else " · ${made.size} görsel çizildi"))
            }
            progress.value = 0.98
            status.value = ""
            return result
        } finally {
            isBuilding.value = false
        }
    }

    private fun fmt(score: Double) = if (score % 1.0 == 0.0) score.toInt().toString() else "%.1f".format(score)

    private fun baseMessage(request: String, folder: String, hasApp: Boolean): String {
        if (!hasApp) return "[CİHAZ] ${deviceDescription()}\n\n$request"
        return "[MEVCUT DOSYALAR]\n${MiniAppFiles.promptText(folder)}\n\n[CİHAZ]\n${deviceDescription()}\n\n[İSTEK]\n$request"
    }

    private suspend fun retryFailedPatches(failed: List<String>, request: String, folder: String): BuildResult {
        status.value = "Bazı değişiklikler eşleşmedi, dosyalar yeniden yazılıyor…"
        val prompt = "[MEVCUT DOSYALAR]\n${MiniAppFiles.promptText(folder)}\n\nÖnceki yamaların şu dosyalarda SEARCH kısmı eşleşmedi: ${failed.joinToString(", ")}.\n" +
            "Bu dosyaların istenen değişikliği içeren TAM halini <<<FILE>>> bloğuyla ver. Açıklama yazma.\nİstenen değişiklik: $request"
        return apply(stream(prompt, emptyList()), folder, null)
    }

    // MARK: Akış (bağlantı koparsa kaldığı yerden sürer)

    private suspend fun stream(prompt: String, history: List<Message>): String {
        var attempt = 0
        var done = ""
        while (true) {
            partialOutput = ""
            val current = if (done.isEmpty()) prompt else continuationPrompt(prompt, done)
            try {
                val text = streamOnce(current, history, done)
                return if (done.isEmpty()) text else done + "\n" + text
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!isTransient(e)) throw e
                val kept = closedPrefix(partialOutput)
                if (kept.isNotEmpty()) done = if (done.isEmpty()) kept else "$done\n$kept"
                attempt++
                if (attempt > 5) throw e
                status.value = if (done.isEmpty()) "Bağlantı koptu, yeniden deneniyor…" else "Bağlantı koptu, kaldığı yerden devam ediliyor…"
                delay(listOf(2L, 4, 8, 15, 30)[attempt - 1] * 1000)
            }
        }
    }

    private suspend fun streamOnce(prompt: String, history: List<Message>, prefix: String): String {
        val turns = history.filter { it.content.isNotEmpty() }.map { AiTurn(if (it.isUser) "user" else "model", it.content) }
        var full = ""
        var thought = ""
        var last = 0L
        if (AiClient.streamingEnabled) {
            try {
                AiClient.stream(prompt, turns, system = Prompts.APP_BUILDER, maxOutputTokens = 32000, model = AiClient.deepModel, thinking = "high").collect { chunk ->
                    when (chunk) {
                        is StreamChunk.Text -> { full += chunk.text; partialOutput = full }
                        is StreamChunk.Thought -> thought += chunk.text
                        else -> Unit
                    }
                    val now = System.currentTimeMillis()
                    if (now - last > 80) { last = now; reasoning.value = thought; updateProgress(if (prefix.isEmpty()) full else "$prefix\n$full") }
                }
                reasoning.value = thought
                updateProgress(if (prefix.isEmpty()) full else "$prefix\n$full")
                if (full.isNotEmpty()) return full
            } catch (e: CancellationException) { throw e } catch (e: Exception) { if (full.isNotEmpty()) throw e }
        }
        status.value = "Kod yazılıyor…"
        full = AiClient.generate(prompt, turns, system = Prompts.APP_BUILDER, maxOutputTokens = 32000, model = AiClient.deepModel, thinking = "high")
        updateProgress(full)
        return full
    }

    private fun updateProgress(text: String) {
        val list = mutableListOf<FileProgress>()
        var openPath: String? = null
        for (b in scanBlocks(text)) {
            val state = if (b.closed) (if (b.kind == Kind.PATCH) FileProgress.State.PATCHED else FileProgress.State.WRITTEN) else FileProgress.State.WRITING
            if (b.kind == Kind.DELETE) {
                list.removeAll { it.path == b.path }
                list.add(FileProgress(b.path, FileProgress.State.DELETED, 0, originals[b.path]?.size ?: 0)); continue
            }
            val (added, removed) = when (b.kind) {
                Kind.FILE -> if (b.closed) lineDiff(originals[b.path] ?: emptyList(), trimBlockBody(b.body).split("\n")) else (b.body.count { it == '\n' } to 0)
                else -> parsePatch(b.body).fold(0 to 0) { acc, (s, r) -> val d = lineDiff(s.split("\n"), r.split("\n")); (acc.first + d.first) to (acc.second + d.second) }
            }
            val i = list.indexOfFirst { it.path == b.path }
            if (i >= 0) list[i] = list[i].copy(state = state, added = list[i].added + added, removed = list[i].removed + removed)
            else list.add(FileProgress(b.path, state, added, removed))
            if (!b.closed) openPath = b.path
        }
        files.value = list
        liveReply.value = stripBlocks(text)
        val fraction = 1 - exp(-text.length / 15_000.0)
        progress.value = minOf(0.97, phase.first + (phase.second - phase.first) * fraction)
        status.value = when {
            openPath != null -> "$openPath yazılıyor…"
            list.isNotEmpty() -> "Tamamlanıyor…"
            liveReply.value.isNotEmpty() -> "Yazıyor…"
            else -> status.value
        }
    }

    // MARK: Uygula

    private fun apply(raw: String, folder: String, snapshotLabel: String?): BuildResult {
        val blocks = scanBlocks(raw).filter { it.closed || it.kind == Kind.DELETE }
        val meta = parseMeta(raw)
        val secrets = parseSecrets(raw)
        if (!secrets.isNullOrEmpty()) {
            MiniAppSecrets.merge(secrets, folder)
        }
        val changed = mutableListOf<String>()
        val failed = mutableListOf<String>()
        if (blocks.isEmpty()) {
            fencedHTML(raw)?.takeIf { !MiniAppFiles.hasFiles(folder) }?.let { html ->
                MiniAppFiles.write("index.html", html, folder)
                return BuildResult(cleanReply(raw), meta, listOf("index.html"), emptyList())
            }
        } else if (snapshotLabel != null) MiniAppFiles.snapshot(folder, snapshotLabel)

        for (b in blocks) when (b.kind) {
            Kind.FILE -> if (MiniAppFiles.write(b.path, trimBlockBody(b.body), folder)) changed.add(b.path)
            Kind.DELETE -> { MiniAppFiles.delete(b.path, folder); changed.add(b.path) }
            Kind.PATCH -> {
                var content = MiniAppFiles.read(b.path, folder) ?: run { failed.add(b.path); null } ?: continue
                var all = true
                for ((search, replacement) in parsePatch(b.body)) {
                    val updated = replace(search, replacement, content)
                    if (updated != null) content = updated else all = false
                }
                if (all && MiniAppFiles.write(b.path, content, folder)) changed.add(b.path) else failed.add(b.path)
            }
        }
        return BuildResult(cleanReply(raw), meta, changed, failed)
    }

    companion object {
        enum class Kind { FILE, PATCH, DELETE }
        data class Block(val kind: Kind, val path: String, val body: String, val closed: Boolean)

        private val header = Regex("<<<[ \\t]*(FILE|PATCH|DELETE)[ \\t:]+([^\\n>]+?)[ \\t]*(?:>>>|(?=\\n))", RegexOption.IGNORE_CASE)
        private val end = Regex("<<<[ \\t]*END[ \\t]*(?:>>>)?", RegexOption.IGNORE_CASE)

        fun scanBlocks(text: String): List<Block> {
            val blocks = mutableListOf<Block>()
            var location = 0
            while (location < text.length) {
                val h = header.find(text, location) ?: break
                val keyword = h.groupValues[1].uppercase()
                val bodyStart = h.range.last + 1
                val path = MiniAppFiles.sanitized(h.groupValues[2]) ?: run { location = bodyStart; null } ?: continue
                if (keyword == "DELETE") { blocks.add(Block(Kind.DELETE, path, "", true)); location = bodyStart; continue }
                val kind = if (keyword == "FILE") Kind.FILE else Kind.PATCH
                val e = end.find(text, bodyStart)
                if (e != null) { blocks.add(Block(kind, path, text.substring(bodyStart, e.range.first), true)); location = e.range.last + 1 }
                else { blocks.add(Block(kind, path, text.substring(bodyStart), false)); break }
            }
            return blocks
        }

        fun closedPrefix(text: String): String = end.findAll(text).lastOrNull()?.let { text.substring(0, it.range.last + 1) } ?: ""

        fun continuationPrompt(prompt: String, written: String) = "$prompt\n\n[YARIM KALAN CEVABIN — bağlantı koptu]\n" +
            "Bu isteğe verdiğin cevabın aşağıdaki kısmı yazıldı ve UYGULANDI:\n$written\n\n" +
            "Şimdi KALDIĞIN YERDEN DEVAM ET: yukarıdaki dosya ve yamaları TEKRAR YAZMA; kalan dosyaları/yamaları aynı biçimde " +
            "(<<<FILE …>>> / <<<PATCH …>>> … <<<END>>>) yaz, en sonda tek cümlelik özetini ekle. META'yı tekrar yazma."

        fun isTransient(e: Throwable): Boolean {
            if (e is java.io.IOException && e !is com.pufy.app.ai.AiException) return true
            if (e is com.pufy.app.ai.AiException && e.code in setOf(429, 500, 502, 503, 504, 529)) return true
            val t = (e.message ?: "").lowercase()
            return listOf("connection", "bağlantı", "timed out", "zaman aşımı", "network", "socket", "overloaded", "quota", "unavailable", "yoğun", "abort").any { t.contains(it) }
        }

        fun parseMeta(text: String): BuildMeta? = metaJson(text)?.let { j ->
            fun s(k: String) = (j[k] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() }
            BuildMeta(s("name"), s("icon"), s("color"), s("tagline"))
        }

        fun parseSecrets(text: String): Map<String, String>? = metaJson(text)?.let { j ->
            val sec = j["secrets"] as? JsonObject ?: return null
            sec.entries.mapNotNull { (k, v) ->
                val s = (v as? JsonPrimitive)?.content?.trim()
                if (!s.isNullOrEmpty()) k to s else null
            }.toMap().takeIf { it.isNotEmpty() }
        }

        private fun metaJson(text: String): JsonObject? {
            val open = text.indexOf("<<<META", ignoreCase = true).takeIf { it >= 0 } ?: return null
            var line = text.substring(open + 7).substringBefore("\n").trim().removePrefix(":")
            line = line.substringBefore(">>>")
            val s = line.indexOf('{'); val e = line.lastIndexOf('}')
            if (s < 0 || e <= s) return null
            return runCatching { PufyJson.parseToJsonElement(line.substring(s, e + 1)).jsonObject }.getOrNull()
        }

        fun parsePatch(body: String): List<Pair<String, String>> {
            val pairs = mutableListOf<Pair<String, String>>()
            var cursor = 0
            while (true) {
                val s = body.indexOf("<<<<<<< SEARCH", cursor).takeIf { it >= 0 } ?: break
                val mid = body.indexOf("=======", s + 14).takeIf { it >= 0 } ?: break
                val e = body.indexOf(">>>>>>> REPLACE", mid + 7).takeIf { it >= 0 } ?: break
                pairs.add(trimOneNewline(body.substring(s + 14, mid)) to trimOneNewline(body.substring(mid + 7, e)))
                cursor = e + 15
            }
            return pairs
        }

        fun replace(search: String, replacement: String, content: String): String? {
            if (search.isEmpty()) return null
            val i = content.indexOf(search)
            if (i >= 0) return content.substring(0, i) + replacement + content.substring(i + search.length)
            val lines = content.split("\n")
            val want = search.split("\n").map { it.trim() }
            if (want.isEmpty() || want.size > lines.size) return null
            for (start in 0..(lines.size - want.size)) {
                if ((0 until want.size).all { lines[start + it].trim() == want[it] }) {
                    return (lines.subList(0, start) + replacement.split("\n") + lines.subList(start + want.size, lines.size)).joinToString("\n")
                }
            }
            return null
        }

        private fun trimOneNewline(s: String) = s.removePrefix("\n").removeSuffix("\n")

        fun trimBlockBody(body: String): String {
            var t = body.trimStart('\n')
            if (t.startsWith("```") && t.contains("\n")) {
                t = t.substringAfter("\n")
                val fence = t.lastIndexOf("```"); if (fence >= 0) t = t.substring(0, fence)
            }
            return t.trim() + "\n"
        }

        private val blockStrip = Regex("<<<[ \\t]*(FILE|PATCH)[^\\n]*[\\s\\S]*?(<<<[ \\t]*END[ \\t]*(>>>)?|$)", RegexOption.IGNORE_CASE)
        private val metaStrip = Regex("<<<[ \\t]*(META|DELETE)[^\\n]*", RegexOption.IGNORE_CASE)
        fun stripBlocks(text: String) = metaStrip.replace(blockStrip.replace(text, ""), "").trim()
        fun cleanReply(raw: String) = stripBlocks(raw).replace(Regex("```[\\s\\S]*?```"), "").replace(Regex("\\n{3,}"), "\n\n").trim()

        private fun fencedHTML(text: String): String? {
            val start = text.indexOf("```html", ignoreCase = true).takeIf { it >= 0 } ?: return null
            val rest = text.substring(start + 7)
            val html = rest.substringBefore("```").trim()
            return html.takeIf { it.contains("<") }
        }

        /** Satır farkı (eklenen, silinen) — en uzun ortak alt dizi ile */
        fun lineDiff(old: List<String>, new: List<String>): Pair<Int, Int> {
            if (old.size * new.size > 4_000_000) return new.size to old.size
            val dp = Array(old.size + 1) { IntArray(new.size + 1) }
            for (i in old.indices.reversed()) for (j in new.indices.reversed())
                dp[i][j] = if (old[i] == new[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
            val common = dp[0][0]
            return (new.size - common) to (old.size - common)
        }

        fun deviceDescription(): String {
            val m = com.pufy.app.PufyApp.instance.resources.displayMetrics
            val w = (m.widthPixels / m.density).toInt(); val h = (m.heightPixels / m.density).toInt()
            val tablet = minOf(w, h) >= 600
            return "Android ${if (tablet) "tablet" else "telefon"} (Chrome WebView), ekran ${w}×$h dp, ${if (w > h) "yatay" else "dikey"}. " +
                "Uygulama iPhone, iPad ve Android'in her yönünde düzgün çalışmalı."
        }

        fun assetsText(folder: String, fresh: List<Triple<String, Pair<Int, Int>, String>>): String {
            val all = MiniAppFiles.existingAssets(folder)
            if (all.isEmpty()) return ""
            val notes = fresh.associateBy { it.first }
            val lines = all.map { path ->
                notes[path]?.let { f -> "- $path (${f.second.first}×${f.second.second}, ${if (path.endsWith(".png")) "şeffaf PNG" else "JPEG"}): ${f.third}" } ?: "- $path"
            }
            return "[HAZIR GÖRSELLER — MUTLAKA KULLAN]\n${lines.joinToString("\n")}\n" +
                "Bu dosyalar uygulama klasöründe. <img src=\"assets/…\"> ya da canvas'ta new Image() + drawImage ile kullan (yüklenmesini bekle,\n" +
                "oranını koru). Bu nesneleri CSS daireleri, emoji ya da düz şekillerle ÇİZME; görselin yerine geçecek kod yazma."
        }
    }
}

// MARK: Ajan: plan, görsel, inceleme

data class AppPlan(val chat: Boolean?, val summary: String?, val style: String?, val todo: List<String>?, val assets: List<Asset>?) {
    data class Asset(val file: String, val prompt: String, val kind: String?, val note: String?)
}

data class AppReview(val score: Double?, val issues: List<String>, val fix: String?)

object AppAgent {
    private fun jsonIn(raw: String): JsonObject? {
        val s = raw.indexOf('{'); val e = raw.lastIndexOf('}')
        if (s < 0 || e <= s) return null
        return runCatching { PufyJson.parseToJsonElement(raw.substring(s, e + 1)).jsonObject }.getOrNull()
    }
    private fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" }
    private fun JsonObject.strs(k: String) = (this[k] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content } ?: emptyList()

    suspend fun plan(request: String, history: List<Message>, folder: String, hasApp: Boolean): AppPlan? = runCatching {
        val existing = if (hasApp) MiniAppFiles.textFiles(folder).joinToString(", ") { "${it.first} (${it.second.length} karakter)" } else "yok (yeni uygulama)"
        val assets = MiniAppFiles.existingAssets(folder).joinToString(", ")
        val context = history.takeLast(4).joinToString("\n") { "${if (it.isUser) "Kullanıcı" else "Pufy"}: ${it.content.take(500)}" }
        val raw = AiClient.generate((if (context.isEmpty()) "" else "Önceki konuşma:\n$context\n\n") + "İstek: $request",
            system = Prompts.appPlanner(existing, assets), maxOutputTokens = 4000, model = AiClient.deepModel,
            responseMimeType = "application/json", timeoutSeconds = 60, thinking = "high")
        val j = jsonIn(raw) ?: return null
        AppPlan((j["chat"] as? JsonPrimitive)?.content?.toBooleanStrictOrNull(), j.str("summary"), j.str("style"), j.strs("todo"),
            (j["assets"] as? JsonArray)?.mapNotNull { a -> (a as? JsonObject)?.let { o ->
                AppPlan.Asset(o.str("file") ?: return@let null, o.str("prompt") ?: return@let null, o.str("kind"), o.str("note")) } })
    }.getOrNull()

    /** Görsel üretir; nesnelerin beyaz zeminini temizler (iOS Vision ile yapıyor; burada kenardan taşma doldurma) */
    suspend fun makeAsset(asset: AppPlan.Asset, style: String?, folder: String): Pair<String, Pair<Int, Int>>? = runCatching {
        val safe = MiniAppFiles.sanitized(asset.file) ?: return null
        val kind = asset.kind ?: "sprite"
        val styleText = style?.let { " Overall art direction: $it." } ?: ""
        val prompt = when (kind) {
            "background" -> "${asset.prompt}.$styleText Full-bleed background image for a mobile app/game screen, portrait orientation, no text, no UI, no characters in the foreground, clean composition with calm areas for UI."
            "illustration" -> "${asset.prompt}.$styleText Single centered illustration, plain pure white background, no text, no border."
            else -> "${asset.prompt}.$styleText Single object only, centered, fully visible with margin around it, isolated on a plain pure white background, no shadow on the ground, no text, no border, crisp edges, high detail game asset."
        }
        val data = AiClient.generateImageData(prompt)
        withContext(Dispatchers.Default) {
            var bmp = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return@withContext null
            if (kind != "background") bmp = removeWhiteBackground(bmp)
            val maxSide = if (kind == "background") 1280 else 512
            val scale = minOf(1f, maxSide.toFloat() / maxOf(bmp.width, bmp.height))
            if (scale < 1f) bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
            val jpeg = kind == "background"
            val path = safe.substringBeforeLast('.') + if (jpeg) ".jpg" else ".png"
            val out = ByteArrayOutputStream().also { bmp.compress(if (jpeg) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG, 85, it) }.toByteArray()
            File(MiniAppFiles.folder(folder), path).apply { parentFile?.mkdirs() }.writeBytes(out)
            path to (bmp.width to bmp.height)
        }
    }.getOrNull()

    /** Kenarlardan başlayarak beyaza yakın zemini şeffaf yapar, sonra nesneye kırpar */
    private fun removeWhiteBackground(src: Bitmap): Bitmap {
        val w = src.width; val h = src.height
        val px = IntArray(w * h); src.getPixels(px, 0, w, 0, 0, w, h)
        fun whiteish(c: Int) = Color.red(c) > 232 && Color.green(c) > 232 && Color.blue(c) > 232
        val seen = BooleanArray(w * h)
        val stack = ArrayDeque<Int>()
        for (x in 0 until w) { stack.add(x); stack.add((h - 1) * w + x) }
        for (y in 0 until h) { stack.add(y * w); stack.add(y * w + w - 1) }
        while (stack.isNotEmpty()) {
            val i = stack.removeLast()
            if (i < 0 || i >= px.size || seen[i] || !whiteish(px[i])) continue
            seen[i] = true; px[i] = 0
            val x = i % w
            if (x > 0) stack.add(i - 1); if (x < w - 1) stack.add(i + 1); stack.add(i - w); stack.add(i + w)
        }
        // nesneye kırp
        var minX = w; var minY = h; var maxX = -1; var maxY = -1
        for (y in 0 until h) for (x in 0 until w) if (Color.alpha(px[y * w + x]) > 0) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y }
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply { setPixels(px, 0, w, 0, 0, w, h) }
        if (maxX < 0) return src
        val pad = 4
        val l = maxOf(0, minX - pad); val t = maxOf(0, minY - pad)
        return Bitmap.createBitmap(out, l, t, minOf(w, maxX + pad + 1) - l, minOf(h, maxY + pad + 1) - t)
    }

    suspend fun review(request: String, plan: AppPlan?, run: AppTester.Run, round: Int): AppReview? = runCatching {
        var text = "[KULLANICI İSTEĞİ]\n$request\n"
        if (plan != null) text += "\n[PLAN]\n${plan.summary ?: ""}\nStil: ${plan.style ?: "-"}\nYapılacaklar: ${plan.todo.orEmpty().joinToString("; ")}\n"
        text += "\n[KONSOL HATALARI]\n" + (if (run.errors.isEmpty()) "yok" else run.errors.take(8).joinToString("\n"))
        text += "\n\n[EKRANLAR] 1: açılış" + (if (run.shots.size > 1) (if (run.interacted) ", 2: ana düğmeye basıldıktan sonra" else ", 2: birkaç saniye sonra") else "") +
            (if (run.darkShot) ", SON: aynı ekran telefon GECE MODUNDAYKEN" else "")
        text += "\nDeneme turu: $round"
        val raw = AiClient.generate(text, images = run.shots, system = Prompts.APP_REVIEWER, maxOutputTokens = 3000, model = AiClient.deepModel,
            responseMimeType = "application/json", timeoutSeconds = 120, thinking = "high")
        val j = jsonIn(raw) ?: return null
        AppReview((j["score"] as? JsonPrimitive)?.content?.toDoubleOrNull(), j.strs("issues"), j.str("fix"))
    }.getOrNull()
}
