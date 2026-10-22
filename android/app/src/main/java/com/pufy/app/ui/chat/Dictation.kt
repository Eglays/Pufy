package com.pufy.app.ui.chat

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import com.pufy.app.ai.AiClient
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

/** iOS DictationManager: kaydeder, yapay zekaya yazıya döktürür (Pufy Dikte ile aynı istem) */
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

    fun start() {
        if (phase.value != Phase.IDLE) return
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

    fun cancel() { stopRecorder(); phase.value = Phase.IDLE }

    fun finish(onText: (String) -> Unit) {
        if (phase.value != Phase.RECORDING) return
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

    private fun stopRecorder() {
        meter?.cancel(); meter = null
        recorder?.let { runCatching { it.stop() }; it.release() }
        recorder = null
    }
}
