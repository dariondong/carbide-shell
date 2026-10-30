package top.theez.carbide_shell

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * 长按输入框说话：用系统自带的语音识别把话认成字，一句句送回界面。
 *
 * 自己起一个 [SpeechRecognizer]，不弹系统那个识别界面：认出来的半成品跟着话筒往输入框里长，
 * 松手时收尾。识别服务是系统或输入法带的那一个，机器上没有就如实回一句「没有」。
 */
object SpeechHelper {
    private val ui = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null
    private var recognizer: SpeechRecognizer? = null
    private var listening = false

    fun attach(channel: MethodChannel?) {
        this.channel = channel
    }

    /** 这台机器有没有能用的识别服务。 */
    fun available(context: Context): Boolean = try {
        SpeechRecognizer.isRecognitionAvailable(context)
    } catch (error: Throwable) {
        false
    }

    /** 开始听。结果走 [emit]，一条一条回给界面。 */
    fun start(context: Context) {
        if (!available(context)) {
            emit("error", code = "no-service")
            return
        }
        ui.post {
            try {
                release()
                val engine = SpeechRecognizer.createSpeechRecognizer(context.applicationContext)
                engine.setRecognitionListener(Listener())
                recognizer = engine
                listening = true
                engine.startListening(intent(context))
                emit("state", on = true)
            } catch (error: Throwable) {
                release()
                emit("error", code = "start-failed")
            }
        }
    }

    /** 说完了（松手）：让识别服务把最后一句定下来。 */
    fun stop() {
        ui.post {
            if (!listening) return@post
            try {
                recognizer?.stopListening()
            } catch (error: Throwable) {
                // 已经停了就算了，下面照常收尾。
            }
        }
    }

    /** 不要了：直接取消，不发结果。 */
    fun cancel() {
        ui.post {
            try {
                recognizer?.cancel()
            } catch (error: Throwable) {
                // ignore
            }
            release()
            emit("state", on = false)
        }
    }

    fun release() {
        listening = false
        try {
            recognizer?.destroy()
        } catch (error: Throwable) {
            // ignore
        }
        recognizer = null
    }

    private fun intent(context: Context): Intent {
        val lang = try {
            Locale.getDefault().toLanguageTag()
        } catch (error: Throwable) {
            "zh-CN"
        }
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // 说完之后多久算说完：短一点，松手到出字不用干等。
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 700L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
        }
    }

    fun firstOf(bundle: Bundle?): String {
        val list = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        return list?.firstOrNull()?.trim().orEmpty()
    }

    fun emit(method: String, text: String = "", done: Boolean = false, on: Boolean = false, code: String = "") {
        val link = channel ?: return
        ui.post {
            try {
                link.invokeMethod(
                    method,
                    mapOf("text" to text, "done" to done, "on" to on, "code" to code),
                )
            } catch (error: Throwable) {
                // 界面那边没接上就当没听见，不影响这次识别。
            }
        }
    }

    /** 系统回调都在主线程上，照原样往下递。 */
    private class Listener : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}

        override fun onBeginningOfSpeech() {}

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {}

        override fun onPartialResults(partialResults: Bundle?) {
            val text = firstOf(partialResults)
            if (text.isNotEmpty()) SpeechHelper.emit("text", text = text)
        }

        override fun onResults(results: Bundle?) {
            val text = firstOf(results)
            SpeechHelper.emit("text", text = text, done = true)
            SpeechHelper.release()
            SpeechHelper.emit("state", on = false)
        }

        override fun onError(error: Int) {
            SpeechHelper.emit("error", code = reasonOf(error))
            SpeechHelper.release()
            SpeechHelper.emit("state", on = false)
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}

        /** 系统那几个错误号翻成人话：没听到话不算错，别弹提示。 */
        private fun reasonOf(error: Int): String = when (error) {
            SpeechRecognizer.ERROR_NO_MATCH -> "no-match"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no-speech"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
            SpeechRecognizer.ERROR_AUDIO -> "audio"
            else -> "error"
        }
    }
}
