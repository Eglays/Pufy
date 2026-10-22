package com.pufy.app.ai

import com.pufy.app.core.extractJsonObject
import com.pufy.app.core.turkeyFormat
import com.pufy.app.core.arr
import com.pufy.app.core.bool
import com.pufy.app.core.str
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlin.coroutines.coroutineContext

/**
 * Cevap motoru — iOS DeepResearchManager.executeDeepResearch (Gemini yerleşik Google araması yolu):
 *  hakem → (zorunlu arama | serbest arama | aramasız + [ARA] ikinci şansı | kararsız: aramasız yazar + yapay zeka hakemi
 *  aynı anda) → derin soruda çok adımlı araştırma (plan → paralel arama + çapraz kontrol → zor işler modeli yazar)
 *  → [DRAW] varsa görsel üretimi.
 */
object ResearchEngine {
    enum class Mode { MUST_SEARCH, MAY_SEARCH, NO_SEARCH, DEVICE_ACTION;
        val usesSearch get() = this == MUST_SEARCH || this == MAY_SEARCH
        val directive get() = when (this) {
            MUST_SEARCH -> Prompts.MUST_SEARCH; MAY_SEARCH -> Prompts.MAY_SEARCH
            NO_SEARCH -> Prompts.NO_SEARCH; DEVICE_ACTION -> Prompts.DEVICE_ACTION
        }
    }

    const val DRAWING = "Görsel çiziliyor…"

    fun isEscalation(text: String) = text.trim().uppercase().startsWith(Prompts.ESCALATION.take(4))
    fun removingEscalation(text: String): String {
        if (!isEscalation(text)) return text
        val rest = text.trim()
        val close = rest.indexOf(']')
        return (if (close >= 0) rest.substring(close + 1) else rest).trim()
    }

    fun extractDraw(text: String): Pair<String, String>? {
        val m = Regex("""\[DRAW\s*:\s*([\s\S]+?)]""", RegexOption.IGNORE_CASE).find(text) ?: return null
        val prompt = m.groupValues[1].trim()
        if (prompt.length <= 3) return null
        return prompt to text.removeRange(m.range).trim()
    }

    class Callbacks(
        val progress: (String) -> Unit = {},
        val partial: ((text: String, reasoning: String) -> Unit)? = null,
        val sources: (List<Pair<String, String>>) -> Unit = {},
    )

    suspend fun execute(
        query: String,
        history: List<AiTurn>,
        images: List<ByteArray>,
        systemPrompt: String,
        forceSearch: Boolean,
        cb: Callbacks,
        forceDeep: Boolean = false,
        hasFiles: Boolean = false,
    ): String {
        val ai = AiClient
        var system = systemPrompt
        // Maç/skor sorularında o anki canlı skor verisi (sunucudaki flashscore özeti)
        if (!QueryRouter.skipsSearchNow(query)) LiveData.scores(query)?.let { system += "\n\n$it" }
        var weatherReady = false
        if (!QueryRouter.skipsSearchNow(query)) LiveData.weather(query, history)?.let { system += "\n\n$it"; weatherReady = true }

        val isDeviceAction = QueryRouter.skipsSearchNow(query) && !forceSearch
        val canDraw = ai.canGenerateImages
        val base = system + if (canDraw) Prompts.DRAW_RULES else ""

        // [DRAW] akışta görününce: "yazıyor" yerine görsel kartı
        var drawing = false
        val watchedPartial = cb.partial?.let { handler ->
            { text: String, reasoning: String ->
                if (canDraw && !drawing && text.contains("[DRAW")) {
                    drawing = true
                    cb.progress(if (com.pufy.app.core.AppLocales.isEnglish()) "Generating image…" else DRAWING)
                }
                handler(text, reasoning)
            }
        }
        val guardedProgress: (String) -> Unit = { if (!drawing) cb.progress(it) }

        cb.progress(if (com.pufy.app.core.AppLocales.isEnglish()) "Thinking…" else "Düşünüyor…")
        val lastUser = history.lastOrNull { it.role == "user" }?.text
        val lastAssistant = history.lastOrNull { it.role != "user" }
        val context = QueryRouter.Context(lastUser, lastAssistant?.text, lastAnswerWasSearched)
        val route = QueryRouter.quickRoute(query, images.isNotEmpty(), forceSearch, context, hasFiles = hasFiles).apply {
            if (isDeviceAction) { search = QueryRouter.Search.NO; reason = "zamanlanmış istek (arama görev vaktinde)"; if (thinking == "low") thinking = "minimal" }
            else if (weatherReady && !forceSearch && !deep && images.isEmpty() && QueryRouter.isOnlyWeather(query)) {
                search = QueryRouter.Search.NO; thinking = "minimal"; reason = "hava verisi hazır"
            }
        }
        if (forceDeep) {
            route.deep = true
            route.thinking = "high"
        }
        android.util.Log.d("Pufy", "Hakem: ${route.search} · düşünme ${route.thinking} · ${route.reason}")

        suspend fun write(mode: Mode, partial: ((String, String) -> Unit)?) = runWriter(
            notes = emptyList(), query = query, history = history, images = images,
            system = base + mode.directive, partial = partial, useSearch = mode.usesSearch && ai.canUseGoogleSearch,
            sources = cb.sources, thinking = route.thinking, progress = guardedProgress)

        var written: String = when {
            forceDeep -> {
                if (ai.canUseGoogleSearch) {
                    deepResearch(query, history, base, watchedPartial, cb.sources, guardedProgress)
                } else {
                    runWriter(
                        notes = emptyList(), query = query, history = history, images = images,
                        system = base + Prompts.NO_SEARCH, partial = watchedPartial, useSearch = false,
                        sources = cb.sources, thinking = "high", model = ai.deepModel, progress = guardedProgress
                    )
                }
            }
            route.search == QueryRouter.Search.YES && route.deep && ai.canUseGoogleSearch ->
                deepResearch(query, history, base, watchedPartial, cb.sources, guardedProgress)
            route.search == QueryRouter.Search.YES -> write(Mode.MUST_SEARCH, watchedPartial)
            route.search == QueryRouter.Search.OPTIONAL -> write(Mode.MAY_SEARCH, watchedPartial)
            route.search == QueryRouter.Search.NO && isDeviceAction -> write(Mode.DEVICE_ACTION, watchedPartial)
            else -> coroutineScope {
                // Aramasız yazar hemen başlar; ilk harfleri "[ARA]" olabilir diye ekrana verilmeden tutulur.
                // Kararsızsa hakem kararı gelene kadar da tutulur.
                val probe = EscalationProbe(gateOpen = route.search == QueryRouter.Search.NO)
                val fast = async {
                    runCatching {
                        write(Mode.NO_SEARCH, watchedPartial?.let { forward -> { t: String, r: String -> probe.receive(t, r, forward) } })
                    }
                }
                probe.onEscalate = { fast.cancel() }
                var needSearch = false
                if (route.search == QueryRouter.Search.UNKNOWN && ai.canUseGoogleSearch && QueryRouter.llmNeedsSearch(query, context)) {
                    needSearch = true
                    fast.cancel()
                }
                var fastText: String? = null
                if (!needSearch) {
                    watchedPartial?.let { probe.openGate(it) }
                    val result = runCatching { fast.await() }.getOrElse { Result.failure(it) }
                    val text = result.getOrNull()
                    when {
                        text != null && isEscalation(text) -> needSearch = true
                        text != null -> fastText = text
                        probe.escalated -> needSearch = true
                        else -> { coroutineContext.ensureActive(); throw result.exceptionOrNull() ?: IllegalStateException("Cevap alınamadı") }
                    }
                }
                fastText ?: write(Mode.MUST_SEARCH, watchedPartial)
            }
        }
        written = removingEscalation(written)

        if (!canDraw) return written
        val draw = extractDraw(written) ?: return written
        if (!drawing) { drawing = true; cb.progress(DRAWING) }
        return try {
            val image = ai.generateImage(draw.first, images)
            if (draw.second.isEmpty()) image else image + "\n\n" + draw.second
        } catch (e: CancellationException) { throw e } catch (e: Exception) {
            "Görseli şu an oluşturamadım: ${e.message}"
        }
    }

    /** Son cevap web aramasıyla mı yazıldı? (ChatEngine ayarlar) */
    var lastAnswerWasSearched = false

    private class EscalationProbe(var gateOpen: Boolean) {
        private var decided = false
        var escalated = false; private set
        private var pending: Pair<String, String>? = null
        var onEscalate: (() -> Unit)? = null

        @Synchronized fun receive(text: String, reasoning: String, forward: (String, String) -> Unit) {
            if (escalated) return
            if (!decided) {
                val head = text.trim().take(5).uppercase()
                if (head.startsWith(Prompts.ESCALATION.take(4))) { escalated = true; pending = null; onEscalate?.invoke(); return }
                if (head.length < 4 && Prompts.ESCALATION.startsWith(head)) {
                    if (gateOpen) forward("", reasoning) else pending = "" to reasoning
                    return
                }
                decided = true
            }
            if (gateOpen) forward(text, reasoning) else pending = text to reasoning
        }

        @Synchronized fun openGate(forward: (String, String) -> Unit) {
            gateOpen = true
            if (!escalated) pending?.let { forward(it.first, it.second) }
            pending = null
        }
    }

    // MARK: Derin araştırma (çok adımlı)

    private suspend fun deepResearch(query: String, history: List<AiTurn>, base: String, partial: ((String, String) -> Unit)?,
                                     sources: (List<Pair<String, String>>) -> Unit, progress: (String) -> Unit): String = coroutineScope {
        val ai = AiClient
        val now = turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy EEEE, HH:mm")
        val context = history.takeLast(4).joinToString("\n") { "${if (it.role == "user") "Kullanıcı" else "Pufy"}: ${it.text.take(400)}" }

        progress(if (com.pufy.app.core.AppLocales.isEnglish()) "Planning research…" else "Araştırma planlanıyor…")
        data class Sub(val q: String, val critical: Boolean)
        var subs = listOf(Sub(query, true))
        val planSystem = "Sen bir araştırma planlayıcısısın. Şu an $now (Türkiye saati). Kullanıcının son mesajını doğru ve eksiksiz cevaplamak\n" +
            "için web'de AYRI AYRI araştırılması gereken 2-4 alt soru çıkar (her biri tek başına anlaşılır, tarih/kişi/takım adı içeren\n" +
            "arama cümlesi). Kolay yanlış olabilecek bilgileri (skor, saat, tarih, fiyat, kadro, istatistik, kim/ne zaman) içeren alt\n" +
            "soruları \"critical\": true işaretle. SADECE JSON: {\"subqueries\":[{\"q\":\"…\",\"critical\":true}]}"
        runCatching {
            val raw = ai.generate((if (context.isEmpty()) "" else "Önceki konuşma:\n$context\n\n") + "Son mesaj: $query",
                system = planSystem, maxOutputTokens = 1500, responseMimeType = "application/json", timeoutSeconds = 20, thinking = "low")
            extractJsonObject(raw)?.arr("subqueries")?.mapNotNull { (it as? JsonObject)?.let { o -> Sub(o.str("q") ?: return@mapNotNull null, o.bool("critical") == true) } }
        }.getOrNull()?.takeIf { it.isNotEmpty() }?.let { subs = it.take(4) }

        val critical = subs.count { it.critical }
        val progressText = if (com.pufy.app.core.AppLocales.isEnglish()) {
            if (critical > 0) "Researching ${subs.size} topics concurrently, cross-checking $critical details…"
            else "Researching ${subs.size} topics concurrently…"
        } else {
            if (critical > 0) "${subs.size} konu aynı anda araştırılıyor, $critical bilgi çapraz kontrol ediliyor…"
            else "${subs.size} konu aynı anda araştırılıyor…"
        }
        progress(progressText)
        val researchSystem = "Sen bir araştırmacısın. Şu an $now (Türkiye saati). Verilen konuyu web'de ARA ve bulduklarını kısa notlar halinde yaz:\n" +
            "somut bilgiler (sayılar, tarihler, saatler, isimler), her birinin kaynağı (site adı) ve sayfanın tarihi. Saatleri Türkiye\n" +
            "saatine (TSİ) çevir. Eski sezon/yıl sayfalarını güncel sanma. Emin olmadığını ya da kaynakların çeliştiğini açıkça yaz.\n" +
            "Sohbet cümlesi kurma, sadece not."
        val jobs = subs.map { it.q to "Konu: ${it.q}" } + subs.filter { it.critical }.map {
            "Çapraz kontrol: ${it.q}" to "Bu bilgiyi FARKLI kaynaklardan bağımsız olarak doğrula (resmi site, canlı skor/fiyat siteleri, büyük haber ajansları): ${it.q}"
        }
        val notes = jobs.map { (label, prompt) ->
            async {
                runCatching { ai.generate(prompt, system = researchSystem, maxOutputTokens = 3000, timeoutSeconds = 90, useSearch = true, thinking = "low") }
                    .getOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.let { "### $label\n$it" }
            }
        }.awaitAll().filterNotNull()

        progress(if (notes.isEmpty()) "Yazıyor…" else "Bilgiler karşılaştırılıp yazılıyor…")
        val directive = "\n\n\nHAKEM KARARI — DERİN ARAŞTIRMA: Bu soru için birden çok bağımsız arama yapıldı; notlar aşağıda (ARAŞTIRMA SONUÇLARI).\n" +
            "Notları birleştir. Aynı bilgi için notlar ÇELİŞİYORSA daha güncel ve resmi kaynağı seç, önemliyse belirsizliği kısaca söyle.\n" +
            "Eksik kalan nokta varsa kendin Google'da ara. Saatleri TSİ ver. Kullandığın sitelerin alan adlarını sonda [SOURCES: …] ile yaz."
        runWriter(notes, query, history, emptyList(), base + directive, partial, useSearch = true, sources = sources,
            thinking = "high", model = ai.deepModel, progress = progress)
    }

    // MARK: Yazar

    private suspend fun runWriter(
        notes: List<String>, query: String, history: List<AiTurn>, images: List<ByteArray>, system: String,
        partial: ((String, String) -> Unit)?, useSearch: Boolean, sources: (List<Pair<String, String>>) -> Unit,
        thinking: String?, model: String? = null, progress: (String) -> Unit,
    ): String = coroutineScope {
        val ai = AiClient
        var finalSystem = system
        if (notes.isNotEmpty()) {
            finalSystem += "\n\n\nARAŞTIRMA SENTEZİ — Bugün: ${turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy EEEE HH:mm")}\n" +
                "- Aşağıdaki araştırma sonuçlarını sentezle; uydurma bilgi üretme.\n- Kesin olmayan bilgiyi kesinmiş gibi sunma, tarihleri belirt.\n" +
                "- Kaynakları doğal bir dille an (ör. \"ESPN'e göre…\"); çelişki varsa açıkla.\n- Yeterli veri yoksa: \"Bu konuda yeterli güncel bilgiye ulaşamadım.\" de.\n\n" +
                "[ARAŞTIRMA SONUÇLARI]\n" + notes.joinToString("\n\n---\n\n")
        }
        suspend fun once() = ai.generate(query, history, images, finalSystem, model = model, useSearch = useSearch, thinking = thinking)
        if (partial == null || !ai.streamingEnabled) return@coroutineScope once()

        // Model aramaya gidince birkaç saniye sessiz kalır: kullanıcı ne olduğunu görsün
        val hint: Job? = if (useSearch) launch { delay(4500); progress("Web'de araştırıyor…") } else null
        val full = StringBuilder()
        val reasoning = StringBuilder()
        val found = mutableListOf<Pair<String, String>>()
        var lastPush = 0L
        try {
            ai.stream(query, history, images, finalSystem, model = model, useSearch = useSearch, thinking = thinking).collect { chunk ->
                when (chunk) {
                    is StreamChunk.Text -> { full.append(chunk.text); hint?.cancel() }
                    is StreamChunk.Thought -> reasoning.append(chunk.text)
                    is StreamChunk.Sources -> chunk.sources.forEach { if (it !in found) found.add(it) }
                }
                val now = System.currentTimeMillis()
                if (now - lastPush > 40) { lastPush = now; partial(full.toString(), reasoning.toString()) }
            }
            partial(full.toString(), reasoning.toString())
            if (found.isNotEmpty()) sources(found)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            hint?.cancel()
            // Sunucu akışı desteklemiyorsa ve henüz hiçbir şey gelmediyse normal isteğe düş
            if (full.isNotEmpty()) throw e
            return@coroutineScope once()
        }
        hint?.cancel()
        if (full.isEmpty()) once() else full.toString()
    }
}
