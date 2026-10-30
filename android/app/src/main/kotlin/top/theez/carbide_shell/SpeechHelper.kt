package top.theez.carbide_shell

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
 *
 * 两处跟得比较细的地方：
 * - 没说话时引擎会自己收尾并报「没认出来」。手指还按着就当这一句没听清，重开一段接着听，
 *   免得刚按下去还没来得及开口就结束了。
 * - 说完一句（还没松手）也重开一段，那段字已经交给界面了，接着说的接在后面。
 */
object SpeechHelper {
    private val ui = Handler(Looper.getMainLooper())

    /// 一句都没听出来时最多重开几段，别无限重试。
    private const val MAX_RETRY = 3

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var recognizer: SpeechRecognizer? = null

    /// 手指还按着（这一轮还没松手）。
    private var holding = false

    /// 松手了，等引擎把最后一句吐出来。
    private var closing = false

    private var retries = 0

    /** 真开口说话了：这一段就是有效的，重试次数归零。 */
    fun beganSpeech() {
        retries = 0
    }

    /// 最近一次出错的原因，诊断那一页拿它说话。
    var lastError = ""

    /** 最近一次认出来的字，诊断时看一眼有没有真收到东西。 */
    var lastText = ""

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
        appContext = context.applicationContext
        if (!available(context)) {
            emit("error", code = "no-service")
            return
        }
        ui.post {
            holding = true
            closing = false
            retries = 0
            open()
        }
    }

    /** 说完了（松手）：让识别服务把最后一句定下来。 */
    fun stop() {
        ui.post {
            if (!holding) return@post
            holding = false
            closing = true
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
            holding = false
            closing = false
            close()
            emit("state", on = false)
        }
    }

    /** 这台机器这一套走到哪一步：一行一条。 */
    fun diag(context: Context): List<String> {
        val out = ArrayList<String>()
        out.add("系统：Android ${android.os.Build.VERSION.SDK_INT}")
        out.add("机型：${android.os.Build.MANUFACTURER} ${android.os.Build.BRAND} ${android.os.Build.MODEL}")
        out.add("语音识别可用：" + if (available(context)) "是" else "否")
        out.add("识别服务：" + services(context))
        out.add("麦克风权限：" + if (Device.has(context, "mic")) "给了" else "没有")
        out.add("语言：" + language())
        out.add("最近一次出错：" + lastError.ifEmpty { "还没试过" })
        out.add("最近认出的字：" + lastText.ifEmpty { "还没有" })
        return out
    }

    /** 装在这台机器上、能接识别请求的服务。一个都没有就是真的没法用。 */
    private fun services(context: Context): String = try {
        val found = context.packageManager.queryIntentServices(
            Intent(android.speech.RecognitionService.SERVICE_INTERFACE),
            PackageManager.GET_SERVICES,
        )
        if (found.isEmpty()) {
            "一个都没有"
        } else {
            found.joinToString(" / ") { it.serviceInfo.packageName }
        }
    } catch (error: Throwable) {
        "读不到"
    }

    private fun language(): String = try {
        Locale.getDefault().toLanguageTag()
    } catch (error: Throwable) {
        "zh-CN"
    }

    /** 起一段新的识别。手指按着就一直有这一段。 */
    private fun open() {
        val ctx = appContext ?: return
        try {
            release()
            val engine = SpeechRecognizer.createSpeechRecognizer(ctx)
            engine.setRecognitionListener(Listener())
            recognizer = engine
            engine.startListening(intent())
            emit("state", on = true)
        } catch (error: Throwable) {
            close()
            emit("error", code = "start-failed")
        }
    }

    /** 手指还按着、但这一句结束了：换一段接着听。 */
    fun reopen(): Boolean {
        if (!holding || closing) return false
        if (retries >= MAX_RETRY) return false
        retries += 1
        open()
        return true
    }

    /** 收掉这一段识别器（不动「按着」这个状态）。 */
    private fun release() {
        try {
            recognizer?.destroy()
        } catch (error: Throwable) {
            // ignore
        }
        recognizer = null
    }

    /** 这一轮彻底结束。 */
    fun close() {
        holding = false
        closing = false
        release()
    }

    private fun intent(): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
    }

    fun firstOf(bundle: Bundle?): String {
        val list = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        return list?.firstOrNull()?.trim().orEmpty()
    }

    fun emit(
        method: String,
        text: String = "",
        done: Boolean = false,
        on: Boolean = false,
        code: String = "",
    ) {
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

        override fun onBeginningOfSpeech() {
            SpeechHelper.beganSpeech()
        }

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {}

        override fun onPartialResults(partialResults: Bundle?) {
            val text = SpeechHelper.firstOf(partialResults)
            if (text.isEmpty()) return
            SpeechHelper.lastText = text
            SpeechHelper.emit("text", text = text)
        }

        override fun onResults(results: Bundle?) {
            val text = SpeechHelper.firstOf(results)
            if (text.isNotEmpty()) SpeechHelper.lastText = text
            SpeechHelper.emit("text", text = text, done = true)
            // 手指还按着：这一段算说完，重开一段，接着说的接在后面。
            if (SpeechHelper.reopen()) return
            SpeechHelper.close()
            SpeechHelper.emit("state", on = false)
        }

        override fun onError(error: Int) {
            val code = reasonOf(error)
            SpeechHelper.lastError = "$code（$error）"
            // 还没开口就没认出来、手指也还按着：重开一段，别一下子就结束。
            if (code == "no-match" || code == "no-speech") {
                if (SpeechHelper.reopen()) return
            }
            SpeechHelper.emit("error", code = code)
            SpeechHelper.close()
            SpeechHelper.emit("state", on = false)
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}

        /** 系统那几个错误号翻成人话：没听到话不算大错，界面上不弹提示。 */
        private fun reasonOf(error: Int): String = when (error) {
            SpeechRecognizer.ERROR_NO_MATCH -> "no-match"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no-speech"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
            SpeechRecognizer.ERROR_AUDIO -> "audio"
            SpeechRecognizer.ERROR_CLIENT -> "client"
            SpeechRecognizer.ERROR_SERVER -> "server"
            else -> "error"
        }
    }
}
