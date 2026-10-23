package com.pufy.app.ui.chat

import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.pufy.app.ai.AiClient
import com.pufy.app.core.AppLocales
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * iOS DictationManager: kaydeder, yapay zekaya yazıya döktürür (Pufy Dikte ile aynı istem).
 * Sağlayıcının ses servisi yoksa (Claude, DeepSeek, Ollama…) Android'in kendi konuşma tanıması kullanılır.
 */
class Dictation(private val context: Context) {
    enum class Phase { IDLE, RECORDING, TRANSCRIBING }

    val phase = MutableStateFlow(Phase.IDLE)
    /** 0…1 ses seviyesi (dalga çizimi için) */
    val level = MutableStateFlow(0f)
    val error = MutableStateFlow<String?>(null)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + com.pufy.app.core.SafeErrors)
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var meter: Job? = null

    private var recognizer: SpeechRecognizer? = null
    private var pendingText: ((String) -> Unit)? = null
    private var listenIntent: Intent? = null
    private val heard = StringBuilder()

    fun start() {
        if (phase.value != Phase.IDLE) return
        if (AiClient.supportsTranscription) startRecording() else startRecognizer()
    }

    fun cancel() {
        pendingText = null
        stopRecorder()
        recognizer?.let { runCatching { it.cancel() }; it.destroy() }
        recognizer = null
        phase.value = Phase.IDLE
    }

    fun finish(onText: (String) -> Unit) {
        if (phase.value != Phase.RECORDING) return
        recognizer?.let {
            // Cihaz tanıması: durdurunca son sonuç onResults ile gelir
            pendingText = onText
            phase.value = Phase.TRANSCRIBING
            it.stopListening()
            return
        }
        stopRecorder()
        val audio = file?.takeIf { it.exists() && it.length() > 2_000 }?.readBytes()
        if (audio == null) { phase.value = Phase.IDLE; return }
        phase.value = Phase.TRANSCRIBING
        scope.launch {
            val text = runCatching { withContext(Dispatchers.IO) { AiClient.transcribe(audio, "audio/mp4") } }
            phase.value = Phase.IDLE
            text.onSuccess { t -> t.trim().takeIf { it.isNotEmpty() }?.let(onText) }
                .onFailure { error.value = AiClient.friendly(it).message ?: context.getString(com.pufy.app.R.string.dictation_transcribe_failed) }
        }
    }

    // MARK: Yapay zekayla yazıya dökme (kayıt)

    private fun startRecording() {
        val out = File(context.cacheDir, "dikte.m4a").apply { delete() }
        val r = (if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder())
        runCatching {
            r.setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioSamplingRate(16_000)
            r.setAudioEncodingBitRate(48_000)
            r.setOutputFile(out.absolutePath)
            r.prepare()
            r.start()
        }.onFailure { r.release(); error.value = context.getString(com.pufy.app.R.string.dictation_mic_failed); return }
        recorder = r; file = out
        phase.value = Phase.RECORDING
        meter = scope.launch {
            while (isActive) {
                level.value = ((recorder?.maxAmplitude ?: 0) / 12_000f).coerceIn(0.05f, 1f)
                delay(80)
            }
        }
    }

    private fun stopRecorder() {
        meter?.cancel(); meter = null
        recorder?.let { runCatching { it.stop() }; it.release() }
        recorder = null
    }

    // MARK: Cihazın konuşma tanıması

    private fun startRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            error.value = context.getString(com.pufy.app.R.string.dictation_unavailable)
            return
        }
        heard.clear()
        val sr = SpeechRecognizer.createSpeechRecognizer(context)
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) { level.value = ((rmsdB + 2f) / 12f).coerceIn(0.05f, 1f) }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onResults(results: Bundle?) {
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }?.let {
                    if (heard.isNotEmpty()) heard.append(' ')
                    heard.append(it)
                }
                // Kullanıcı henüz durdurmadıysa (tanıma sessizlikte kendi bitti) dinlemeye devam et
                if (pendingText == null && phase.value == Phase.RECORDING) restart() else deliver()
            }
            override fun onError(code: Int) {
                // Sessizlikte zaman aşımı hata sayılmaz
                val silent = code == SpeechRecognizer.ERROR_NO_MATCH || code == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                if (silent && pendingText == null && phase.value == Phase.RECORDING) { restart(); return }
                if (!silent && heard.isEmpty()) error.value = context.getString(com.pufy.app.R.string.dictation_transcribe_failed)
                deliver()
            }
        })
        val tag = if (AppLocales.isEnglish()) "en-US" else "tr-TR"
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, tag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            // Kullanıcı durdurana kadar dinle: uzun sessizlikte kendiliğinden kesilmesin
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 4000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 4000L)
        }
        recognizer = sr
        listenIntent = intent
        phase.value = Phase.RECORDING
        runCatching { sr.startListening(intent) }.onFailure {
            sr.destroy(); recognizer = null; phase.value = Phase.IDLE
            error.value = context.getString(com.pufy.app.R.string.dictation_mic_failed)
        }
    }

    private fun restart() {
        val sr = recognizer ?: return
        val intent = listenIntent ?: return
        runCatching { sr.startListening(intent) }.onFailure { deliver() }
    }

    private fun deliver() {
        val text = heard.toString().trim()
        val callback = pendingText
        pendingText = null
        recognizer?.destroy(); recognizer = null
        phase.value = Phase.IDLE
        if (text.isNotEmpty()) callback?.invoke(text)
    }
}
