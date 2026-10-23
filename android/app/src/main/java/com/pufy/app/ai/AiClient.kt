package com.pufy.app.ai

import android.content.Context
import android.util.Base64
import com.pufy.app.core.PufyJson
import com.pufy.app.core.Settings
import com.pufy.app.core.arr
import com.pufy.app.core.bool
import com.pufy.app.core.obj
import com.pufy.app.core.str
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Akışta gelen parça: cevabın kendisi, modelin düşünce süreci ya da arama kaynakları */
sealed interface StreamChunk {
    data class Text(val text: String) : StreamChunk
    data class Thought(val text: String) : StreamChunk
    data class Sources(val sources: List<Pair<String, String>>) : StreamChunk
}

/** Yapay zekaya giden tek bir tur (geçmiş) */
data class AiTurn(val role: String, val text: String, val images: List<ByteArray> = emptyList())

class AiException(val code: Int, message: String) : IOException(message)

enum class ApiFormat(val raw: String) { GEMINI("gemini"), OPENAI("openAI");
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: GEMINI }
}

/**
 * Yapay zeka istemcisi — iOS GeminiService'in birebir karşılığı. İki biçim konuşur:
 *  • Gemini REST (/v1beta/models/{model}:generateContent, akış: streamGenerateContent?alt=sse)
 *  • OpenAI uyumlu (/chat/completions)
 * Kendi yapay zeka sunucusu anahtarı "Authorization: Bearer" başlığında da gider (Google'ın kendi adresi hariç).
 */
object AiClient {
    private const val ENDPOINT = "gemini_endpoint"
    private const val MODEL = "gemini_model"
    private const val HEAVY = "pufy_heavy_model"
    private const val IMAGE = "pufy_image_model"
    private const val FORMAT = "pufy_api_format"
    private const val STREAMING = "pufy_streaming_enabled"
    private const val SEARCH = "pufy_google_search"
    private const val KEY = "ai_api_key"
    private const val PROVIDER = "pufy_ai_provider"
    private const val IMAGE_PROVIDER = "pufy_image_provider"
    private const val IMAGE_KEY = "ai_image_api_key"

    /** Ayar değişince ekranlar yenilensin diye (Compose sıradan özellikleri izlemez): bağlı mı + ana model */
    val configState = kotlinx.coroutines.flow.MutableStateFlow(false to "")
    fun refreshConfigState() { configState.value = isConfigured to modelName }

    var endpoint: String
        get() = Settings.string(ENDPOINT) ?: ""
        set(v) { Settings.setString(ENDPOINT, v.trim()); refreshConfigState() }
    var modelName: String
        get() = Settings.string(MODEL) ?: ""
        set(v) { Settings.setString(MODEL, v.trim()); refreshConfigState() }
    /** Zor işler (derin araştırma, uygulama yapımı) için ikinci model; boşsa ana model */
    var heavyModelName: String
        get() {
            val h = Settings.string(HEAVY)
            return if (!h.isNullOrEmpty()) h else modelName
        }
        set(v) = Settings.setString(HEAVY, v.trim())
    var imageModelName: String
        get() = Settings.string(IMAGE) ?: ""
        set(v) = Settings.setString(IMAGE, v.trim())
    var apiFormat: ApiFormat
        get() = ApiFormat.from(Settings.string(FORMAT))
        set(v) { Settings.setString(FORMAT, v.raw); refreshConfigState() }
    var streamingEnabled: Boolean
        get() = Settings.bool(STREAMING, true)
        set(v) = Settings.setBool(STREAMING, v)
    var googleSearchEnabled: Boolean
        get() = Settings.bool(SEARCH, true)
        set(v) = Settings.setBool(SEARCH, v)
    var apiKey: String
        get() = Settings.secret(KEY) ?: ""
        set(v) { Settings.setSecret(KEY, v.trim()); refreshConfigState() }

    var aiProvider: String
        get() {
            Settings.string(PROVIDER)?.let { return it }
            val ep = endpoint.lowercase()
            return when {
                ep.contains("generativelanguage.googleapis.com") -> "gemini"
                ep.contains("api.openai.com") -> "openai"
                ep.contains("api.anthropic.com") -> "anthropic"
                ep.contains("openrouter.ai") -> "openrouter"
                else -> "custom"
            }
        }
        set(v) { Settings.setString(PROVIDER, v); refreshConfigState() }

    var imageProvider: String
        get() = Settings.string(IMAGE_PROVIDER) ?: if (imageModelName.isNotBlank()) "same" else "off"
        set(v) = Settings.setString(IMAGE_PROVIDER, v)

    var imageApiKey: String
        get() = Settings.secret(IMAGE_KEY) ?: ""
        set(v) = Settings.setSecret(IMAGE_KEY, v.trim())

    val canUseGoogleSearch get() = apiFormat == ApiFormat.GEMINI && googleSearchEnabled
    /** Sağlayıcının kendi ses→metin servisi var mı (yoksa dikte cihazın konuşma tanımasıyla yapılır) */
    val supportsTranscription get() = apiFormat == ApiFormat.GEMINI ||
            endpoint.contains("api.openai.com") || endpoint.contains("api.groq.com")
    val canGenerateImages get() = imageProvider != "off" && imageModelName.isNotBlank()
    val deepModel get() = heavyModelName.trim().ifEmpty { modelName }
    val isConfigured get() = (aiProvider in listOf("ollama", "lmstudio") && endpoint.isNotBlank()) ||
            (apiKey.isNotBlank() && endpoint.isNotBlank()) ||
            (aiProvider == "custom" && endpoint.isNotBlank())

    lateinit var generatedImagesDir: File
        private set

    fun init(context: Context) {
        generatedImagesDir = File(context.filesDir, "GeneratedImages").apply { mkdirs() }
        refreshConfigState()
    }

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(150, TimeUnit.SECONDS)      // düşünen modeller uzun süre sessiz kalabiliyor
        .writeTimeout(60, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.MINUTES)
        .build()

    private val jsonType = "application/json".toMediaType()

    // MARK: Düşünme seviyesi (sadece Gemini 3 modellerinde var)

    fun supportsThinkingLevel(model: String) = model.lowercase().contains("gemini-3")

    fun thinkingLevel(level: String?, model: String): String? {
        if (level == null || !supportsThinkingLevel(model)) return null
        if (level == "minimal" && model.lowercase().contains("pro")) return "low"
        return level
    }

    // MARK: Tek seferlik cevap

    suspend fun generate(
        prompt: String,
        history: List<AiTurn> = emptyList(),
        images: List<ByteArray> = emptyList(),
        system: String? = null,
        maxOutputTokens: Int = 8192,
        model: String? = null,
        responseMimeType: String? = null,
        timeoutSeconds: Long? = null,
        useSearch: Boolean = false,
        thinking: String? = null,
    ): String = withContext(Dispatchers.IO) {
        val request = buildRequest(prompt, history, images, system, maxOutputTokens, model ?: modelName,
            responseMimeType, stream = false, useSearch = useSearch, thinking = thinking)
        val client = timeoutSeconds?.let { http.newBuilder().callTimeout(it, TimeUnit.SECONDS).readTimeout(it, TimeUnit.SECONDS).build() } ?: http
        val body = execute(client, request)
        when (apiFormat) {
            ApiFormat.GEMINI -> parseGemini(body)
            ApiFormat.OPENAI -> parseOpenAI(body)
        }
    }

    // MARK: Akış (Server-Sent Events)

    fun stream(
        prompt: String,
        history: List<AiTurn> = emptyList(),
        images: List<ByteArray> = emptyList(),
        system: String? = null,
        maxOutputTokens: Int = 8192,
        model: String? = null,
        useSearch: Boolean = false,
        thinking: String? = null,
    ): Flow<StreamChunk> = callbackFlow {
        val request = buildRequest(prompt, history, images, system, maxOutputTokens, model ?: modelName,
            null, stream = true, useSearch = useSearch, thinking = thinking)
        val call = http.newCall(request)
        val thread = Thread {
            try {
                call.execute().use { response ->
                    if (!response.isSuccessful) {
                        val raw = response.body.string().take(20_000)
                        close(httpError(response.code, raw))
                        return@use
                    }
                    val source = response.body.source()
                    while (!source.exhausted()) {
                        val line = source.readUtf8Line() ?: break
                        if (!line.startsWith("data:")) continue
                        val payload = line.removePrefix("data:").trim()
                        if (payload == "[DONE]") break
                        for (piece in parseDelta(payload)) trySend(piece)
                    }
                    close()
                }
            } catch (e: Exception) {
                close(if (call.isCanceled()) null else friendly(e))
            }
        }
        thread.start()
        awaitClose { call.cancel() }
    }.flowOn(Dispatchers.IO)

    // MARK: Dikte (ses → metin)

    const val DICTATION_PROMPT = "Sen bir dikte motorusun. Sesi kelimesi kelimesine yazıya dök. Türkçe ve İngilizce karışık olabilir; " +
        "her kelimeyi söylendiği dilde ve doğru yazımıyla yaz (meeting, deadline, feedback gibi). " +
        "Noktalama ve büyük harf kullan. \"ııı\", \"eee\" gibi dolgu seslerini ve tekrarları at. " +
        "Kişi cümlenin ortasında kendini düzeltirse (\"yarın, yok pazartesi\") son halini yaz. " +
        "Sadece metni yaz: açıklama, tırnak, başlık yok. Ses boşsa ya da konuşma yoksa hiçbir şey yazma."

    suspend fun transcribe(audio: ByteArray, mimeType: String = "audio/mp4"): String = withContext(Dispatchers.IO) {
        val base = normalizedBase()
        if (base.isEmpty()) throw AiException(400, "API adresi boş. Ayarlar'dan bir adres gir.")
        when (apiFormat) {
            ApiFormat.GEMINI -> {
                val url = "$base/v1beta/models/$modelName:generateContent".toHttpUrlOrNull()?.newBuilder()?.apply {
                    if (apiKey.isNotEmpty()) addQueryParameter("key", apiKey)
                }?.build() ?: throw AiException(400, "Geçersiz API adresi.")
                val body = buildJsonObject {
                    putJsonObject("systemInstruction") { putJsonArray("parts") { addJsonObject { put("text", DICTATION_PROMPT) } } }
                    putJsonArray("contents") {
                        addJsonObject {
                            put("role", "user")
                            putJsonArray("parts") {
                                addJsonObject { putJsonObject("inlineData") { put("mimeType", mimeType); put("data", Base64.encodeToString(audio, Base64.NO_WRAP)) } }
                                addJsonObject { put("text", "Bu sesi yazıya dök.") }
                            }
                        }
                    }
                    putJsonObject("generationConfig") {
                        put("temperature", 0); put("maxOutputTokens", 4096)
                        if (supportsThinkingLevel(modelName)) putJsonObject("thinkingConfig") { put("thinkingLevel", "low") }
                    }
                }
                val request = Request.Builder().url(url).post(body.toString().toRequestBody(jsonType)).apply { auth(this, base) }.build()
                clean(parseGemini(execute(http, request)))
            }
            ApiFormat.OPENAI -> {
                var root = base
                if (root.endsWith("/chat/completions")) root = root.removeSuffix("/chat/completions")
                val model = if (root.contains("api.openai.com")) "gpt-4o-mini-transcribe" else "whisper-large-v3-turbo"
                val multipart = okhttp3.MultipartBody.Builder().setType(okhttp3.MultipartBody.FORM)
                    .addFormDataPart("model", model)
                    .addFormDataPart("prompt", "Türkçe ve İngilizce karışık konuşma; noktalama kullan.")
                    .addFormDataPart("file", "dikte.m4a", audio.toRequestBody(mimeType.toMediaType()))
                    .build()
                val request = Request.Builder().url("$root/audio/transcriptions").post(multipart)
                    .apply { if (apiKey.isNotEmpty()) header("Authorization", "Bearer $apiKey") }.build()
                val json = PufyJson.parseToJsonElement(execute(http, request)) as? JsonObject
                clean(json?.str("text") ?: "")
            }
        }
    }

    private fun clean(text: String) = text.trim().trim('"', '“', '”').trim()

    // MARK: Görsel üretimi

    /** Görsel modeliyle üretir, kalıcı klasöre yazar; markdown döner ("![Görsel](file://…)") — iOS ile aynı biçim */
    suspend fun generateImage(prompt: String, images: List<ByteArray> = emptyList()): String = withContext(Dispatchers.IO) {
        val bytes = generateImageData(prompt, images)
        val file = File(generatedImagesDir, UUID.randomUUID().toString().uppercase() + ".jpg")
        file.writeBytes(bytes)
        "![Görsel](file://${file.absolutePath.replace(" ", "%20")})"
    }

    suspend fun generateImageData(prompt: String, images: List<ByteArray> = emptyList()): ByteArray = withContext(Dispatchers.IO) {
        val prov = imageProvider
        if (prov == "off") throw AiException(400, "Görsel oluşturma kapalı.")
        if (prov == "openai") {
            val key = imageApiKey.ifEmpty { apiKey }
            if (key.isBlank()) throw AiException(401, "OpenAI görsel API anahtarı boş.")
            val model = imageModelName.ifBlank { "dall-e-3" }
            val bodyObj = buildJsonObject {
                put("model", model)
                put("prompt", prompt)
                put("size", "1024x1024")
                put("response_format", "b64_json")
            }
            val request = Request.Builder()
                .url("https://api.openai.com/v1/images/generations")
                .header("Authorization", "Bearer $key")
                .post(bodyObj.toString().toRequestBody(jsonType))
                .build()
            val raw = PufyJson.parseToJsonElement(execute(http.newBuilder().readTimeout(180, TimeUnit.SECONDS).build(), request)) as? JsonObject
            val b64 = raw?.arr("data")?.firstOrNull()?.let { it as? JsonObject }?.str("b64_json")
                ?: throw AiException(500, "OpenAI görsel cevabı alınamadı.")
            return@withContext Base64.decode(b64, Base64.DEFAULT)
        } else {
            // Gemini (same ya da gemini)
            val geminiKey = if (prov == "gemini") imageApiKey.ifEmpty { apiKey } else apiKey
            val base = if (prov == "gemini") "https://generativelanguage.googleapis.com" else normalizedBase()
            val model = imageModelName
            val url = "$base/v1beta/models/$model:generateContent".toHttpUrlOrNull()?.newBuilder()?.apply {
                if (geminiKey.isNotEmpty()) addQueryParameter("key", geminiKey)
            }?.build() ?: throw AiException(400, "Geçersiz API adresi.")
            val body = buildJsonObject {
                putJsonArray("contents") {
                    addJsonObject {
                        put("role", "user")
                        putJsonArray("parts") {
                            addJsonObject { put("text", prompt) }
                            images.forEach { img ->
                                addJsonObject {
                                    putJsonObject("inlineData") {
                                        put("mimeType", "image/jpeg")
                                        put("data", Base64.encodeToString(img, Base64.NO_WRAP))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            val reqBuilder = Request.Builder().url(url).post(body.toString().toRequestBody(jsonType))
            if (geminiKey.isNotEmpty() && !base.contains("googleapis.com")) reqBuilder.header("Authorization", "Bearer $geminiKey")
            val raw = PufyJson.parseToJsonElement(execute(http.newBuilder().readTimeout(180, TimeUnit.SECONDS).build(), reqBuilder.build())) as? JsonObject
            val parts = raw?.arr("candidates")?.firstOrNull()?.let { it as? JsonObject }?.obj("content")?.arr("parts") ?: throw AiException(500, "Görsel modeli boş döndü.")
            for (p in parts) {
                val part = p as? JsonObject ?: continue
                part.obj("inlineData")?.str("data")?.let { return@withContext Base64.decode(it, Base64.DEFAULT) }
                part.str("thoughtSignature")?.let { sig -> runCatching { Base64.decode(sig, Base64.DEFAULT) }.getOrNull()?.takeIf { it.size > 1000 }?.let { return@withContext it } }
            }
            throw AiException(500, "Görsel modeli görsel üretmedi.")
        }
    }

    suspend fun fetchModels(endpoint: String, format: ApiFormat, apiKey: String): List<String> = withContext(Dispatchers.IO) {
        var base = endpoint.trim()
        if (base.isNotEmpty() && !base.contains("://")) base = "http://$base"
        while (base.endsWith("/")) base = base.dropLast(1)
        if (format == ApiFormat.GEMINI && base.endsWith("/v1beta")) base = base.removeSuffix("/v1beta")

        val request = if (format == ApiFormat.GEMINI) {
            val url = "$base/v1beta/models".toHttpUrlOrNull()?.newBuilder()?.apply {
                if (apiKey.isNotEmpty()) addQueryParameter("key", apiKey)
            }?.build() ?: throw AiException(400, "Geçersiz adres")
            Request.Builder().url(url).get().build()
        } else {
            val url = "$base/models".toHttpUrlOrNull() ?: throw AiException(400, "Geçersiz adres")
            val b = Request.Builder().url(url).get()
            val key = apiKey.trim().removePrefix("Bearer ").trim()
            if (base.contains("api.anthropic.com")) {
                // Anthropic'in model listesi Bearer değil kendi başlıklarını ister
                if (key.isNotEmpty()) b.header("x-api-key", key)
                b.header("anthropic-version", "2023-06-01")
            } else if (key.isNotEmpty()) b.header("Authorization", "Bearer $key")
            b.build()
        }

        val res = execute(http.newBuilder().callTimeout(15, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS).build(), request)
        val json = PufyJson.parseToJsonElement(res) as? JsonObject ?: throw AiException(500, "Sunucu cevabı okunamadı")

        val cleanKey = apiKey.trim().removePrefix("Bearer ").trim()
        if (format == ApiFormat.GEMINI) {
            json.arr("models")?.mapNotNull { item ->
                val obj = item as? JsonObject ?: return@mapNotNull null
                val methods = obj.arr("supportedGenerationMethods")?.mapNotNull { (it as? JsonPrimitive)?.content }
                if (methods != null && !methods.contains("generateContent")) return@mapNotNull null
                obj.str("name")?.removePrefix("models/")
            } ?: emptyList()
        } else {
            json.arr("data")?.mapNotNull { (it as? JsonObject)?.str("id") } ?: emptyList()
        }
    }

    /**
     * Sağlayıcının canlı model listesinden makul bir varsayılan seçer (hazır model adları zamanla eskiyor).
     * Önce önerilen ad, yoksa sağlayıcıya göre hızlı/ucuz ailenin en yeni sürümü, o da yoksa listenin ilki.
     */
    fun pickDefaultModel(providerId: String, models: List<String>, hint: String): String? {
        if (models.isEmpty()) return null
        if (hint.isNotEmpty() && models.contains(hint)) return hint
        val skip = listOf("embed", "tts", "audio", "image", "vision-preview", "live", "realtime", "transcribe", "whisper", "moderation", "guard", "search")
        val usable = models.filter { m -> skip.none { m.lowercase().contains(it) } }.ifEmpty { models }
        fun version(m: String) = Regex("""\d+(\.\d+)?""").findAll(m).map { it.value.toDoubleOrNull() ?: 0.0 }.firstOrNull() ?: 0.0
        fun newest(filter: (String) -> Boolean) = usable.filter(filter).maxByOrNull(::version)
        val lc = { m: String -> m.lowercase() }
        return when (providerId) {
            "gemini" -> newest { lc(it).contains("flash") && !lc(it).contains("lite") } ?: newest { lc(it).contains("gemini") }
            "openai" -> newest { lc(it).startsWith("gpt-") && lc(it).contains("mini") } ?: newest { lc(it).startsWith("gpt-") }
            "anthropic" -> newest { lc(it).contains("haiku") } ?: newest { lc(it).contains("sonnet") }
            "xai" -> newest { lc(it).contains("grok") && lc(it).contains("mini") } ?: newest { lc(it).contains("grok") }
            "mistral" -> usable.firstOrNull { lc(it).contains("small") && lc(it).contains("latest") } ?: newest { lc(it).contains("mistral") }
            else -> null
        } ?: usable.first()
    }

    /** İlk kurulum bağlantı denemesi: en fazla 20 token ile test isteği */
    suspend fun testConnectionDetailed(endpoint: String, format: ApiFormat, apiKey: String, model: String): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            var base = endpoint.trim()
            if (base.isNotEmpty() && !base.contains("://")) base = "http://$base"
            while (base.endsWith("/")) base = base.dropLast(1)
            if (format == ApiFormat.GEMINI && base.endsWith("/v1beta")) base = base.removeSuffix("/v1beta")

            val cleanKey = apiKey.trim().removePrefix("Bearer ").trim()
            if (base.isEmpty()) throw AiException(0, "İnternete ulaşılamadı")
            if (model.isEmpty()) throw AiException(404, "Model bulunamadı")

            val client = http.newBuilder().callTimeout(40, TimeUnit.SECONDS).readTimeout(40, TimeUnit.SECONDS).build()
            val request = if (format == ApiFormat.GEMINI) {
                val url = "$base/v1beta/models/$model:generateContent".toHttpUrlOrNull()?.newBuilder()?.apply {
                    if (cleanKey.isNotEmpty()) addQueryParameter("key", cleanKey)
                }?.build() ?: throw AiException(0, "İnternete ulaşılamadı")
                val b = Request.Builder().url(url)
                if (cleanKey.isNotEmpty() && !base.contains("googleapis.com")) b.header("Authorization", "Bearer $cleanKey")
                val jsonBody = """{"contents":[{"role":"user","parts":[{"text":"Merhaba"}]}],"generationConfig":{"maxOutputTokens":20}}"""
                b.post(jsonBody.toRequestBody("application/json".toMediaType())).build()
            } else {
                val path = if (base.endsWith("/chat/completions")) base else "$base/chat/completions"
                val url = path.toHttpUrlOrNull() ?: throw AiException(0, "İnternete ulaşılamadı")
                val b = Request.Builder().url(url)
                if (cleanKey.isNotEmpty()) b.header("Authorization", "Bearer $cleanKey")
                val limit = if (base.contains("api.openai.com")) "\"max_completion_tokens\":64" else "\"max_tokens\":20"
                val jsonBody = """{"model":"$model","messages":[{"role":"user","content":"Merhaba"}],$limit}"""
                b.post(jsonBody.toRequestBody("application/json".toMediaType())).build()
            }

            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        return@runCatching "Bağlandı"
                    }
                    when (response.code) {
                        401, 403 -> throw AiException(response.code, "Anahtar geçersiz")
                        404 -> throw AiException(response.code, "Model bulunamadı")
                        429 -> throw AiException(response.code, "Kota doldu ya da çok sık istek")
                        else -> {
                            val raw = response.body?.string().orEmpty()
                            val parsed = runCatching { PufyJson.parseToJsonElement(raw) as? JsonObject }.getOrNull()
                            val msg = parsed?.obj("error")?.str("message") ?: parsed?.str("message")
                            throw AiException(response.code, msg ?: "Hata: HTTP ${response.code}")
                        }
                    }
                }
            } catch (e: Exception) {
                if (e is AiException) throw e
                throw AiException(0, "İnternete ulaşılamadı")
            }
        }
    }

    /** Mesajdaki görsel adresi: başka cihazdan gelen tam yol yerine bu cihazdaki klasörde dosya adıyla bulunur */
    fun resolveGeneratedImage(url: String): File? {
        val name = url.substringAfterLast('/').substringBefore('?')
        if (name.isEmpty()) return null
        return File(generatedImagesDir, name).takeIf { it.exists() }
    }

    // MARK: İstek oluşturma

    fun normalizedBase(): String {
        var base = endpoint.trim()
        if (base.isNotEmpty() && !base.contains("://")) base = "http://$base"
        while (base.endsWith("/")) base = base.dropLast(1)
        if (apiFormat == ApiFormat.GEMINI && base.endsWith("/v1beta")) base = base.removeSuffix("/v1beta")
        return base
    }

    private fun auth(builder: Request.Builder, base: String) {
        if (apiKey.isNotEmpty() && !base.contains("googleapis.com")) builder.header("Authorization", "Bearer $apiKey")
    }

    private fun buildRequest(
        prompt: String, history: List<AiTurn>, images: List<ByteArray>, system: String?, maxOutputTokens: Int,
        model: String, responseMimeType: String?, stream: Boolean, useSearch: Boolean = false, thinking: String? = null,
    ): Request {
        val base = normalizedBase()
        if (base.isEmpty()) throw AiException(400, "API adresi boş. Ayarlar'dan bir adres gir.")
        if (model.isBlank()) throw AiException(400, "Model adı boş. Ayarlar'dan bir model adı gir.")
        return when (apiFormat) {
            ApiFormat.GEMINI -> {
                val method = if (stream) "streamGenerateContent" else "generateContent"
                val url = "$base/v1beta/models/$model:$method".toHttpUrlOrNull()?.newBuilder()?.apply {
                    if (apiKey.isNotEmpty()) addQueryParameter("key", apiKey)
                    if (stream) addQueryParameter("alt", "sse")
                }?.build() ?: throw AiException(400, "Geçersiz API adresi.")
                val body = geminiBody(prompt, history, images, system, maxOutputTokens, responseMimeType,
                    useSearch && googleSearchEnabled, thinkingLevel(thinking, model))
                Request.Builder().url(url).post(body.toString().toRequestBody(jsonType))
                    .apply { auth(this, base); if (stream) header("Accept", "text/event-stream") }.build()
            }
            ApiFormat.OPENAI -> {
                val path = if (base.endsWith("/chat/completions")) base else "$base/chat/completions"
                val body = openAIBody(prompt, history, images, system, model, stream)
                Request.Builder().url(path).post(body.toString().toRequestBody(jsonType))
                    .apply { if (apiKey.isNotEmpty()) header("Authorization", "Bearer $apiKey"); if (stream) header("Accept", "text/event-stream") }.build()
            }
        }
    }

    private fun geminiBody(
        prompt: String, history: List<AiTurn>, images: List<ByteArray>, system: String?, maxOutputTokens: Int,
        responseMimeType: String?, useSearch: Boolean, thinking: String?,
    ): JsonObject {
        // Gemini ardışık aynı rolü kabul etmez → birleştir; boş parça gönderilmez
        data class C(val role: String, val parts: MutableList<JsonObject>)
        val contents = mutableListOf<C>()
        fun append(role: String, parts: List<JsonObject>) {
            if (parts.isEmpty()) return
            val last = contents.lastOrNull()
            if (last != null && last.role == role) last.parts.addAll(parts) else contents.add(C(role, parts.toMutableList()))
        }
        fun imagePart(data: ByteArray) = buildJsonObject {
            putJsonObject("inlineData") { put("mimeType", "image/jpeg"); put("data", Base64.encodeToString(data, Base64.NO_WRAP)) }
        }
        for (turn in history) {
            val parts = turn.images.map(::imagePart).toMutableList()
            if (turn.text.isNotEmpty()) parts.add(buildJsonObject { put("text", turn.text) })
            append(if (turn.role == "user") "user" else "model", parts)
        }
        val current = images.map(::imagePart).toMutableList()
        if (prompt.isNotEmpty()) current.add(buildJsonObject { put("text", prompt) })
        append("user", current)

        return buildJsonObject {
            put("contents", buildJsonArray {
                for (c in contents) addJsonObject { put("role", c.role); put("parts", kotlinx.serialization.json.JsonArray(c.parts)) }
            })
            if (!system.isNullOrEmpty()) putJsonObject("systemInstruction") { putJsonArray("parts") { addJsonObject { put("text", system) } } }
            putJsonObject("generationConfig") {
                put("temperature", 0.7)
                put("maxOutputTokens", maxOutputTokens)
                if (responseMimeType != null) put("responseMimeType", responseMimeType)
                if (thinking != null) putJsonObject("thinkingConfig") { put("thinkingLevel", thinking) }
            }
            // JSON modu ile araç birlikte kullanılamıyor
            if (useSearch && responseMimeType == null) putJsonArray("tools") { addJsonObject { putJsonObject("google_search") {} } }
        }
    }

    private fun openAIBody(prompt: String, history: List<AiTurn>, images: List<ByteArray>, system: String?, model: String, stream: Boolean): JsonObject {
        fun content(text: String, imgs: List<ByteArray>) = if (imgs.isEmpty()) JsonPrimitive(text) else buildJsonArray {
            for (i in imgs) addJsonObject { put("type", "image_url"); putJsonObject("image_url") { put("url", "data:image/jpeg;base64," + Base64.encodeToString(i, Base64.NO_WRAP)) } }
            if (text.isNotEmpty()) addJsonObject { put("type", "text"); put("text", text) }
        }
        return buildJsonObject {
            put("model", model)
            put("stream", stream)
            putJsonArray("messages") {
                if (!system.isNullOrEmpty()) addJsonObject { put("role", "system"); put("content", system) }
                for (t in history) if (t.text.isNotEmpty() || t.images.isNotEmpty())
                    addJsonObject { put("role", if (t.role == "user") "user" else "assistant"); put("content", content(t.text, t.images)) }
                addJsonObject { put("role", "user"); put("content", content(prompt, images)) }
            }
        }
    }

    // MARK: Cevap okuma

    private fun parseGemini(body: String): String {
        val json = PufyJson.parseToJsonElement(body) as? JsonObject ?: throw AiException(500, "Sunucu cevabı okunamadı.")
        val parts = json.arr("candidates")?.firstOrNull()?.let { it as? JsonObject }?.obj("content")?.arr("parts")
            ?: throw AiException(500, "Modelden boş yanıt alındı.")
        val texts = mutableListOf<String>()
        for (p in parts) {
            val part = p as? JsonObject ?: continue
            if (part.bool("thought") == true) continue
            part.str("text")?.let { texts.add(it); continue }
            part.obj("inlineData")?.str("data")?.let { b64 ->
                val file = File(generatedImagesDir, UUID.randomUUID().toString().uppercase() + ".jpg")
                file.writeBytes(Base64.decode(b64, Base64.DEFAULT))
                texts.add("![Görsel](file://${file.absolutePath})")
            }
        }
        val text = texts.joinToString("\n")
        if (text.isEmpty()) throw AiException(500, "Modelden boş metin yanıtı alındı.")
        return text
    }

    private fun parseOpenAI(body: String): String {
        val json = PufyJson.parseToJsonElement(body) as? JsonObject ?: throw AiException(500, "Sunucu cevabı okunamadı.")
        val message = json.arr("choices")?.firstOrNull()?.let { it as? JsonObject }?.obj("message")
        message?.str("content")?.takeIf { it.isNotEmpty() }?.let { return it }
        message?.arr("content")?.mapNotNull { (it as? JsonObject)?.str("text") }?.joinToString("")?.takeIf { it.isNotEmpty() }?.let { return it }
        throw AiException(500, "Modelden boş yanıt alındı.")
    }

    private fun parseDelta(payload: String): List<StreamChunk> {
        val json = runCatching { PufyJson.parseToJsonElement(payload) as? JsonObject }.getOrNull() ?: return emptyList()
        return when (apiFormat) {
            ApiFormat.GEMINI -> {
                val candidate = json.arr("candidates")?.firstOrNull() as? JsonObject ?: return emptyList()
                val out = mutableListOf<StreamChunk>()
                candidate.obj("content")?.arr("parts")?.forEach { p ->
                    val part = p as? JsonObject ?: return@forEach
                    val text = part.str("text")
                    if (!text.isNullOrEmpty()) out.add(if (part.bool("thought") == true) StreamChunk.Thought(text) else StreamChunk.Text(text))
                }
                val sources = candidate.obj("groundingMetadata")?.arr("groundingChunks")?.mapNotNull { c ->
                    val web = (c as? JsonObject)?.obj("web") ?: return@mapNotNull null
                    val uri = web.str("uri") ?: return@mapNotNull null
                    (web.str("title") ?: uri) to uri
                }.orEmpty()
                if (sources.isNotEmpty()) out.add(StreamChunk.Sources(sources))
                out
            }
            ApiFormat.OPENAI -> {
                val delta = (json.arr("choices")?.firstOrNull() as? JsonObject)?.obj("delta") ?: return emptyList()
                buildList {
                    (delta.str("reasoning_content") ?: delta.str("reasoning"))?.takeIf { it.isNotEmpty() }?.let { add(StreamChunk.Thought(it)) }
                    delta.str("content")?.takeIf { it.isNotEmpty() }?.let { add(StreamChunk.Text(it)) }
                }
            }
        }
    }

    // MARK: Ağ ve hatalar

    private suspend fun execute(client: OkHttpClient, request: Request): String = suspendCancellableCoroutine { cont ->
        val call = client.newCall(request)
        cont.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (!cont.isActive) return
                cont.resumeWithException(friendly(e))
            }
            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val body = it.body.string()
                    if (!it.isSuccessful) cont.resumeWithException(httpError(it.code, body)) else cont.resume(body)
                }
            }
        })
    }

    fun friendly(e: Throwable): Throwable = when (e) {
        is AiException -> e
        is SocketTimeoutException -> AiException(-1001, "Yapay zeka sunucusu zamanında yanıt vermedi. Biraz sonra tekrar dene.")
        is UnknownHostException -> AiException(-1003, "Yapay zeka sunucusuna ulaşılamadı. İnternet bağlantını ve Ayarlar'daki adresi kontrol et.")
        is ConnectException -> AiException(-1004, "Yapay zeka sunucusuna bağlanılamadı. Sunucunun açık olduğundan emin ol.")
        is IOException -> if (e.message?.contains("Canceled", true) == true) e else AiException(-1005, "Bağlantı yarıda kesildi. Tekrar dene.")
        else -> e
    }

    private fun httpError(status: Int, raw: String): AiException {
        val json = runCatching { PufyJson.parseToJsonElement(raw) as? JsonObject }.getOrNull()
        json?.obj("error")?.str("message")?.let { return AiException(status, "API hatası ($status): $it") }
        json?.str("message")?.let { return AiException(status, "API hatası ($status): $it") }
        val message = when (status) {
            401, 403 -> "API anahtarı geçersiz veya yetki yok ($status)."
            404 -> "Adres ya da model bulunamadı (404). Ayarlar'ı kontrol et."
            429 -> "Yapay zeka kotası doldu, biraz bekleyip tekrar dene (429)."
            502, 503, 530 -> "Yapay zeka sunucusuna ulaşılamıyor ($status)."
            else -> if (raw.isBlank() || raw.contains("<html", true)) "Sunucu hatası: HTTP $status" else raw.take(200)
        }
        return AiException(status, message)
    }

    suspend fun testConnection(): Result<String> = runCatching {
        generate("Sadece 'Tamam' yaz.", maxOutputTokens = 64, timeoutSeconds = 15).trim()
    }

    @Suppress("unused")
    private suspend fun isActive() = currentCoroutineContext().isActive
}
