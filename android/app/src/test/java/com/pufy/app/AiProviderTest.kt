package com.pufy.app

import com.pufy.app.ai.AiClient
import com.pufy.app.ai.AiException
import com.pufy.app.ai.ApiFormat
import com.pufy.app.ai.StreamChunk
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

/**
 * Sağlayıcı biçimlerinin uçtan uca kontrolü: yerel sahte sunucu, Gemini ve OpenAI uyumlu API'lerin
 * gerçek istek/cevap biçimini taklit eder. Gerçek anahtar kullanılmaz.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AiProviderTest {
    data class Seen(val method: String, val path: String, val query: String?, val headers: Map<String, String>, val body: String)

    private lateinit var server: ServerSocket
    private val seen = java.util.Collections.synchronizedList(mutableListOf<Seen>())
    private var reply: (Seen) -> Triple<Int, String, String> = { Triple(200, "application/json", "{}") }
    private val base get() = "http://127.0.0.1:${server.localPort}"

    /** Minimal HTTP/1.1 sunucusu (her bağlantıda tek istek, sonra kapatır) */
    @Before fun start() {
        server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        thread(isDaemon = true) {
            while (!server.isClosed) {
                val sock = runCatching { server.accept() }.getOrNull() ?: break
                thread(isDaemon = true) {
                    sock.use { c ->
                        val input = c.getInputStream().buffered()
                        fun line(): String {
                            val sb = StringBuilder()
                            while (true) { val ch = input.read(); if (ch == -1 || ch == '\n'.code) break; if (ch != '\r'.code) sb.append(ch.toChar()) }
                            return sb.toString()
                        }
                        val (method, target) = line().split(" ").let { it[0] to it[1] }
                        val headers = mutableMapOf<String, String>()
                        while (true) { val h = line(); if (h.isEmpty()) break; val i = h.indexOf(':'); headers[h.substring(0, i).trim().lowercase()] = h.substring(i + 1).trim() }
                        val len = headers["content-length"]?.toInt() ?: 0
                        val body = ByteArray(len).also { var r = 0; while (r < len) { val n = input.read(it, r, len - r); if (n < 0) break; r += n } }
                        val s = Seen(method, target.substringBefore('?'), target.substringAfter('?', "").ifEmpty { null }, headers, body.decodeToString())
                        seen.add(s)
                        val (code, type, text) = reply(s)
                        val bytes = text.toByteArray()
                        val out = c.getOutputStream()
                        out.write("HTTP/1.1 $code X\r\nContent-Type: $type\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
                        out.write(bytes); out.flush()
                    }
                }
            }
        }
        AiClient.apiKey = ""
        AiClient.modelName = ""
    }

    @After fun stop() = server.close()

    private fun configure(endpoint: String, format: ApiFormat, key: String, model: String) {
        AiClient.endpoint = endpoint; AiClient.apiFormat = format; AiClient.apiKey = key; AiClient.modelName = model
    }

    // MARK: Gemini

    @Test fun geminiGenerate() = runBlocking {
        configure(base, ApiFormat.GEMINI, "KEY123", "gemini-test")
        reply = { Triple(200, "application/json", """{"candidates":[{"content":{"parts":[{"text":"Merhaba!"}]}}]}""") }
        val text = AiClient.generate("selam", system = "Sen Pufy'sin")
        assertEquals("Merhaba!", text)
        val r = seen.single()
        assertEquals("/v1beta/models/gemini-test:generateContent", r.path)
        assertTrue(r.query!!.contains("key=KEY123"))
        assertTrue(r.body.contains("\"systemInstruction\""))
        assertTrue(r.body.contains("\"role\":\"user\""))
    }

    @Test fun geminiStreamSkipsThoughtsAndReadsSources() = runBlocking {
        configure(base, ApiFormat.GEMINI, "K", "gemini-test")
        reply = {
            Triple(200, "text/event-stream", listOf(
                """{"candidates":[{"content":{"parts":[{"text":"düşünüyorum","thought":true}]}}]}""",
                """{"candidates":[{"content":{"parts":[{"text":"Mer"}]}}]}""",
                """{"candidates":[{"content":{"parts":[{"text":"haba"}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://a.com","title":"A"}}]}}]}""",
            ).joinToString("") { "data: $it\r\n\r\n" })
        }
        val chunks = AiClient.stream("selam").toList()
        assertEquals("Merhaba", chunks.filterIsInstance<StreamChunk.Text>().joinToString("") { it.text })
        assertEquals(1, chunks.filterIsInstance<StreamChunk.Thought>().size)
        assertEquals("https://a.com", chunks.filterIsInstance<StreamChunk.Sources>().single().sources.single().second)
        val r = seen.single()
        assertEquals("/v1beta/models/gemini-test:streamGenerateContent", r.path)
        assertTrue(r.query!!.contains("alt=sse"))
    }

    // MARK: OpenAI uyumlu (OpenAI, Claude, OpenRouter, Groq, DeepSeek, Mistral, xAI, NVIDIA, Ollama, LM Studio)

    @Test fun openAIGenerateSendsBearerAndMessages() = runBlocking {
        configure("$base/v1", ApiFormat.OPENAI, "sk-test", "gpt-test")
        reply = { Triple(200, "application/json", """{"choices":[{"message":{"role":"assistant","content":"Selam!"}}]}""") }
        val text = AiClient.generate("merhaba", system = "Sistem")
        assertEquals("Selam!", text)
        val r = seen.single()
        assertEquals("/v1/chat/completions", r.path)
        assertEquals("Bearer sk-test", r.headers["authorization"])
        assertTrue(r.body.contains("\"model\":\"gpt-test\""))
        assertTrue(r.body.contains("\"role\":\"system\""))
        assertTrue("max_tokens sohbet isteğinde olmamalı (yeni OpenAI modelleri reddediyor)", !r.body.contains("max_tokens"))
    }

    @Test fun openAIStreamReadsReasoningAndContent() = runBlocking {
        configure("$base/v1", ApiFormat.OPENAI, "k", "deepseek-reasoner")
        reply = {
            Triple(200, "text/event-stream", listOf(
                """{"choices":[{"delta":{"reasoning_content":"önce düşüneyim"}}]}""",
                """{"choices":[{"delta":{"content":"Cev"}}]}""",
                """{"choices":[{"delta":{"content":"ap"}}]}""",
            ).joinToString("") { "data: $it\n\n" } + "data: [DONE]\n\n")
        }
        val chunks = AiClient.stream("soru").toList()
        assertEquals("Cevap", chunks.filterIsInstance<StreamChunk.Text>().joinToString("") { it.text })
        assertEquals("önce düşüneyim", chunks.filterIsInstance<StreamChunk.Thought>().single().text)
    }

    @Test fun localServerWithoutKeySendsNoAuthorization() = runBlocking {
        configure("$base/v1", ApiFormat.OPENAI, "", "llama3")
        reply = { Triple(200, "application/json", """{"choices":[{"message":{"content":"ok"}}]}""") }
        assertEquals("ok", AiClient.generate("x"))
        assertNull(seen.single().headers["authorization"])
    }

    @Test fun endpointWithoutSchemeAndTrailingSlashIsNormalized() = runBlocking {
        configure("127.0.0.1:${server.localPort}/v1/", ApiFormat.OPENAI, "", "llama3")
        reply = { Triple(200, "application/json", """{"choices":[{"message":{"content":"ok"}}]}""") }
        assertEquals("ok", AiClient.generate("x"))
        assertEquals("/v1/chat/completions", seen.single().path)
    }

    // MARK: Hatalar

    @Test fun invalidKeyBecomesReadable401() = runBlocking {
        configure("$base/v1", ApiFormat.OPENAI, "bad", "gpt-test")
        reply = { Triple(401, "application/json", """{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}""") }
        val e = runCatching { AiClient.generate("x") }.exceptionOrNull() as AiException
        assertEquals(401, e.code)
        assertTrue(e.message!!.contains("Incorrect API key"))
    }

    @Test fun anthropicStyleErrorIsRead() = runBlocking {
        configure("$base/v1", ApiFormat.OPENAI, "k", "claude-x")
        reply = { Triple(404, "application/json", """{"type":"error","error":{"type":"not_found_error","message":"model: claude-x"}}""") }
        val e = runCatching { AiClient.generate("x") }.exceptionOrNull() as AiException
        assertEquals(404, e.code)
        assertTrue(e.message!!.contains("claude-x"))
    }

    // MARK: Model listesi ve bağlantı testi

    @Test fun fetchModelsBothFormats() = runBlocking {
        reply = { s ->
            if (s.path.startsWith("/v1beta")) Triple(200, "application/json",
                """{"models":[{"name":"models/gemini-a","supportedGenerationMethods":["generateContent"]},{"name":"models/embed-x","supportedGenerationMethods":["embedContent"]}]}""")
            else Triple(200, "application/json", """{"data":[{"id":"m1"},{"id":"m2"}]}""")
        }
        assertEquals(listOf("gemini-a"), AiClient.fetchModels(base, ApiFormat.GEMINI, "k"))
        assertEquals(listOf("m1", "m2"), AiClient.fetchModels("$base/v1", ApiFormat.OPENAI, "k"))
    }

    @Test fun connectionTestSucceeds() = runBlocking {
        reply = { Triple(200, "application/json", """{"choices":[{"message":{"content":"Merhaba"}}]}""") }
        assertTrue(AiClient.testConnectionDetailed("$base/v1", ApiFormat.OPENAI, "k", "m1").isSuccess)
        reply = { Triple(404, "application/json", """{"error":{"message":"not found"}}""") }
        val e = AiClient.testConnectionDetailed("$base/v1", ApiFormat.OPENAI, "k", "eski-model").exceptionOrNull() as AiException
        assertEquals(404, e.code)
    }

    // MARK: Varsayılan model seçimi

    @Test fun pickDefaultModelPrefersFastCurrentFamily() {
        assertEquals("gemini-3.5-flash", AiClient.pickDefaultModel("gemini",
            listOf("gemini-2.5-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.5-pro", "gemini-3.5-flash-image"), "gemini-9-flash"))
        assertEquals("gpt-5-mini", AiClient.pickDefaultModel("openai", listOf("gpt-4o-mini", "gpt-5-mini", "gpt-5", "whisper-1", "gpt-5-mini-tts"), "gpt-1"))
        assertEquals("claude-haiku-5-5", AiClient.pickDefaultModel("anthropic", listOf("claude-sonnet-5-5", "claude-haiku-5-5", "claude-haiku-4-5"), "claude-3-5-haiku"))
        assertEquals("llama-3.3-70b-versatile", AiClient.pickDefaultModel("groq", listOf("whisper-large-v3", "llama-3.3-70b-versatile"), "llama-3.3-70b-versatile"))
        assertEquals("qwen3", AiClient.pickDefaultModel("ollama", listOf("qwen3", "llama3"), ""))
        assertNull(AiClient.pickDefaultModel("openai", emptyList(), "x"))
    }
}
