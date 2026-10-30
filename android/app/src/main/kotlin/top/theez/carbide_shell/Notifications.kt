package top.theez.carbide_shell

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * 最近收到的通知，只在内存里留一份。
 *
 * 监听服务被系统拉起后一直在收，但应用不往磁盘写这些内容：读一次就是读一次，
 * 关掉应用就没了。最多留 400 条，够回答「刚才谁发了什么」。
 */
object NotifLog {
    data class Item(
        val pkg: String,
        val app: String,
        val title: String,
        val text: String,
        val at: Long,
    )

    private const val CAP = 400

    private val ring = ArrayDeque<Item>()

    @Synchronized
    fun add(item: Item) {
        // 通知栏上挂着的那些会被反复收一遍，同一条只留一份。
        for (old in ring) {
            if (old.pkg == item.pkg && old.at == item.at && old.title == item.title &&
                old.text == item.text
            ) {
                return
            }
        }
        ring.addLast(item)
        while (ring.size > CAP) ring.removeFirst()
    }

    /** 新的在前。 */
    @Synchronized
    fun recent(limit: Int, sinceMs: Long): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        for (item in ring) {
            if (item.at < sinceMs) continue
            out.add(
                mapOf(
                    "pkg" to item.pkg,
                    "app" to item.app,
                    "title" to item.title,
                    "text" to item.text,
                    "at" to item.at,
                ),
            )
        }
        out.reverse()
        return if (out.size > limit) out.subList(0, limit) else out
    }

    @Synchronized
    fun clear() {
        ring.clear()
    }
}

/**
 * 系统的通知监听服务。用户必须在设置里手动给「通知使用权」，应用不能自己打开。
 *
 * 只看标题和正文，不碰通知自带的按钮和回复框；自己发的那几条也不收。
 */
class CarbideNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        instance = this
        harvest()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    /**
     * 通知栏上现在挂着的那些。
     *
     * 应用刚起来、或者刚拿到通知使用权时，上面那条 ring 还是空的，读出来就是「没有通知」。
     * 所以每次读之前先问一遍系统，把已经在的都收进来。
     */
    fun harvest() {
        val live = try {
            activeNotifications ?: return
        } catch (error: Throwable) {
            return
        }
        for (sbn in live) collect(sbn)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        collect(sbn)
    }

    private fun collect(sbn: StatusBarNotification?) {
        val posted = sbn ?: return
        val context = applicationContext ?: return
        if (posted.packageName == context.packageName) return
        val notification: Notification = posted.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val one = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val summary = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString().orEmpty()
        val body = if (big.isNotBlank()) big else if (one.isNotBlank()) one else summary
        if (title.isBlank() && body.isBlank()) return

        NotifLog.add(
            NotifLog.Item(
                pkg = posted.packageName,
                app = Device.appLabel(context, posted.packageName),
                title = title.take(200),
                text = body.take(600),
                at = posted.postTime,
            ),
        )
    }

    companion object {
        /** 系统绑上来的那一个。读通知之前靠它去问系统现在挂着哪些。 */
        @Volatile
        var instance: CarbideNotificationListener? = null
    }
}
