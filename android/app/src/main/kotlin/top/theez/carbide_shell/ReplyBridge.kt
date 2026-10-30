package top.theez.carbide_shell

import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * 通知里回的那一句往 Flutter 递。
 *
 * 通知上那颗「回复」现在发的是一个广播，不再把应用拉到眼前：广播收下字以后直接丢给
 * 还在跑的那段 Flutter（任务在跑，进程和引擎都在），通知照旧挂着，人留在原地。
 *
 * 引擎已经收了（应用没在跑）时，字先存到盘上，下次打开应用再递过去：不丢，也不跳。
 */
object ReplyBridge {
    private const val PREFS = "carbide_reply"
    private const val KEY_HELD = "pending_reply"

    private val ui = Handler(Looper.getMainLooper())

    /// 往 Dart 送消息的那个道，建好之后才能把通知里的回复递过去。
    @Volatile
    private var channel: MethodChannel? = null

    /// 存盘要用到的应用上下文。
    @Volatile
    private var app: Context? = null

    /// 还没递出去的那句。
    @Volatile
    private var held: String? = null

    /// 引擎建好之后接上。攒着的字当场递出去。
    fun attach(context: Context?, channel: MethodChannel?) {
        this.app = context?.applicationContext
        this.channel = channel
        flush()
    }

    /** 从 intent 里取出通知上写的那句。没有就返回空串。 */
    fun textOf(intent: Intent?): String {
        if (intent == null) return ""
        return try {
            val results = RemoteInput.getResultsFromIntent(intent) ?: return ""
            results.getCharSequence(TaskService.REPLY_KEY)?.toString()?.trim().orEmpty()
        } catch (error: Throwable) {
            ""
        }
    }

    /// 递一句给 Dart。那边还没接上就先存着，下次打开应用再递。
    fun deliver(text: String) {
        val body = text.trim()
        if (body.isEmpty()) return
        held = body
        if (channel == null) {
            save(body)
            return
        }
        flush()
    }

    /// 取走攒着的那句（内存里没有就看盘）。Dart 启动时问一次。
    fun take(context: Context?): String? {
        val memory = held
        held = null
        if (memory != null) return memory
        val ctx = context?.applicationContext ?: app ?: return null
        return try {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val saved = prefs.getString(KEY_HELD, null)
            if (saved != null) prefs.edit().remove(KEY_HELD).apply()
            saved
        } catch (error: Throwable) {
            null
        }
    }

    private fun flush() {
        val link = channel ?: return
        val text = held ?: return
        held = null
        ui.post {
            try {
                link.invokeMethod("reply", text, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        // 已经到 Dart 手上了。
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        keep(text)
                    }

                    override fun notImplemented() {
                        keep(text)
                    }
                })
            } catch (error: Throwable) {
                keep(text)
            }
        }
    }

    /// 没递到就存起来，下次打开应用再说，别让人白写一句。
    private fun keep(text: String) {
        if (held == null) held = text
        save(text)
    }

    private fun save(text: String) {
        val ctx = app ?: return
        try {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_HELD, text)
                .apply()
        } catch (error: Throwable) {
            // 存不下也没关系，下一次打开应用时再说。
        }
    }
}
