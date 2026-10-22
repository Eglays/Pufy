package com.pufy.app.ai

import com.pufy.app.core.TR
import com.pufy.app.core.turkeyFormat
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.selects.select

// Hakem (iOS QueryRouter.swift'in birebir karşılığı; ipucu listeleri Cues'ta, iOS'tan üretilir):
//  1) Anında karar: ZORUNLU ARA / SERBEST (görsel) / ARAMA YOK / KARARSIZ
//  2) Kararsızda aramasız cevap hemen başlar; aynı anda yapay zekaya "arama gerekir mi?" sorulur
//  3) Aramasız yazar güncel bilgi gerektiğini fark ederse "[ARA]" ile yükseltir
//  4) Düşünme: basit aramasız işler "minimal", aramalı/kararsız "low", kod/analiz/itiraz "high"

object QueryRouter {
    enum class Search { YES, OPTIONAL, NO, UNKNOWN }

    data class Route(var search: Search, var thinking: String, var reason: String, var deep: Boolean = false)

    data class Context(val lastUser: String?, val lastAssistant: String?, val lastAnswerWasSearched: Boolean) {
        companion object { val EMPTY = Context(null, null, false) }
    }

    private fun lower(q: String) = q.lowercase(TR) + " "

    /** İpucu kelimenin BAŞINDA mı? ("maç" ✓ "amaç" ✗, "dün " ✓ "dünya" ✗) */
    fun has(q: String, cues: List<String>): Boolean = cues.any { cue ->
        var from = 0
        while (true) {
            val i = q.indexOf(cue, from)
            if (i < 0) return@any false
            if (i == 0 || !q[i - 1].isLetter()) return@any true
            from = i + 1
        }
        @Suppress("UNREACHABLE_CODE") false
    }

    fun quickRoute(query: String, hasImages: Boolean, forceSearch: Boolean, context: Context = Context.EMPTY, hasFiles: Boolean = false): Route {
        val q = lower(query)
        val (search, reason) = if (forceSearch) {
            Search.YES to "kullanıcı web araması modunu açtı"
        } else if (hasFiles) {
            Search.NO to "dosyalı mesaj (arama kapalı)"
        } else {
            quickSearch(q, hasImages, context)
        }
        val deep = needsDeepThinking(q) || has(q, Cues.challengeCues)
        val thinking = if (deep) "high" else if (search == Search.NO) "minimal" else "low"
        return Route(search, thinking, reason, deep = search == Search.YES && !hasImages && !hasFiles && needsDeepResearch(q, context))
    }

    private fun quickSearch(q: String, hasImages: Boolean, context: Context): Pair<Search, String> {
        if (!hasImages && Regex("""^[\d\s.,+\-*/x×÷()^%=?]+$""").matches(q.trim())) return Search.NO to "matematik"
        if (has(q, Cues.explicitSearchCues)) return Search.YES to "açık arama isteği"
        val mathWords = listOf("kere", "çarpı", "artı", "eksi", "bölü", "karekök", "kaç eder", "kaç yapar", "yüzde kaç", "toplamı")
        if (!hasImages && has(q, mathWords) && !has(q, Cues.freshCues)) return Search.NO to "matematik"
        if (has(q, Cues.noteCues) && !has(q, Cues.topicFreshCues)) return Search.NO to "not işlemi"
        if (has(q, Cues.personalCues) && !has(q, Cues.topicFreshCues)) return Search.NO to "kişisel sohbet"
        if (has(q, Cues.freshCues)) return Search.YES to "güncel bilgi ipucu"
        if (has(q, Cues.challengeCues)) return if (context.lastAnswerWasSearched) Search.YES to "güncel cevaba itiraz" else Search.UNKNOWN to "itiraz (bağlama bakılacak)"
        if (hasImages) return if (has(q, Cues.imageStaticCues)) Search.NO to "görsel + statik istek" else Search.OPTIONAL to "görsel (içerik güncel olabilir)"
        if (has(q, Cues.staticCues)) return Search.NO to "statik konu"
        if (q.trim().split(" ").size <= 3 && !q.contains("?")) {
            return if (context.lastAnswerWasSearched) Search.UNKNOWN to "güncel konunun kısa devamı" else Search.NO to "kısa sohbet"
        }
        return Search.UNKNOWN to "belirsiz"
    }

    private fun needsDeepThinking(q: String) = q.length > 400 || q.contains("```") || has(q, Cues.deepCues)

    fun needsDeepResearch(q: String, context: Context): Boolean {
        if (has(q, Cues.deepResearchCues)) return true
        if (q.length > 160) return true
        if (q.count { it == '?' } >= 2) return true
        if (context.lastAnswerWasSearched && has(q, Cues.challengeCues)) return true
        return false
    }

    private val noteDetailCues = Cues.noteCues + listOf("not ", "notu", "notlar", "notum", "liste", "aldım", "işaretle", "çıkar", "ekle", "sil")
    fun isNoteRequest(query: String) = has(lower(query), noteDetailCues)
    fun mentionsScheduling(query: String) = has(lower(query), Cues.schedulingCues)

    fun isOnlyWeather(query: String): Boolean {
        val q = lower(query)
        val weatherWords = setOf("hava durumu", "hava nasıl", "yağmur")
        return !has(q, Cues.topicFreshCues.filter { it !in weatherWords }) && !has(q, Cues.explicitSearchCues) && !has(q, Cues.challengeCues)
    }

    // MARK: İleri zamanlı istekler (iOS DeepResearchManager)
    private fun matches(list: List<Regex>, query: String): Boolean { val t = query.lowercase(TR); return list.any { it.containsMatchIn(t) } }
    fun isEventRequest(query: String) = matches(Cues.eventPatterns, query)
    fun isSchedulingRequest(query: String) = matches(Cues.timedPatterns, query) || isEventRequest(query)
    fun skipsSearchNow(query: String) = matches(Cues.timedPatterns, query) && !isEventRequest(query)

    /** Kararsız sorular için yapay zeka hakemi (~1,5 sn; 4 sn'yi aşarsa "arama yok") */
    suspend fun llmNeedsSearch(query: String, context: Context = Context.EMPTY): Boolean = coroutineScope {
        val today = turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy EEEE")
        var prompt = ""
        context.lastUser?.takeIf { it.isNotEmpty() }?.let { prompt += "Önceki kullanıcı mesajı: \"${it.take(300)}\"\n" }
        context.lastAssistant?.takeIf { it.isNotEmpty() }?.let {
            prompt += "Asistanın önceki cevabı${if (context.lastAnswerWasSearched) " (web aramasıyla yazılmıştı)" else ""}: \"${it.take(400)}\"\n"
        }
        prompt += "SON MESAJ: \"${query.take(1000)}\""
        val ask = async {
            runCatching {
                AiClient.generate(prompt, system = Prompts.searchJudge(today), maxOutputTokens = 300,
                    responseMimeType = "application/json", timeoutSeconds = 6, thinking = "minimal")
            }.getOrNull()?.replace(" ", "")?.contains("\"search\":true") ?: false
        }
        val timeout = async { delay(4000); false }
        val result = select { ask.onAwait { it }; timeout.onAwait { it } }
        ask.cancel(); timeout.cancel()
        result
    }
}
