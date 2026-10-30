package top.theez.carbide_shell

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput as CompatRemoteInput

/**
 * 长任务期间的前台服务。
 *
 * 有这条通知在，切出去、锁屏也不会被系统当成后台进程掐掉，SSH 连接和模型的请求都能跑完。
 * 任务的进度由 Dart 那边每变一次就调一次 update，通知上那句「第几步」跟着走。
 * 跑完时如果人不在这个应用里，收掉常驻通知，另留一条「跑完了」，点一下回到对话。
 */
class TaskService : Service() {

    /** 跑任务的时候按住 CPU：锁屏之后也能把这一轮跑完，别让套接字在半路睡着。 */
    private var wake: android.os.PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty().ifBlank { DEFAULT_TEXT }
        // 样式和最近几句跟着 intent 进来，服务被重起一次也不会回到默认样子。
        intent?.getStringExtra(EXTRA_STYLE)?.takeIf { it.isNotEmpty() }?.let { style = it }
        intent?.getStringArrayListExtra(EXTRA_LINES)?.let { lines = it }
        if (!declare(text)) {
            // 系统不让起前台服务（缺权限、被后台限制）：这个任务照常在界面里跑，
            // 只是没有通知保护，别让服务挂在那儿。
            stopSelf()
            return START_NOT_STICKY
        }
        instance = this
        holdWake()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        releaseWake()
        super.onDestroy()
    }

    private fun holdWake() {
        try {
            if (wake == null) {
                val power = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                wake = power.newWakeLock(
                    android.os.PowerManager.PARTIAL_WAKE_LOCK,
                    "carbide:task"
                )
            }
            val lock = wake ?: return
            if (!lock.isHeld) lock.acquire(WAKE_LIMIT_MS)
        } catch (error: Throwable) {
            // 按不住就算了，通知还在，任务照跑。
        }
    }

    private fun releaseWake() {
        try {
            val lock = wake
            if (lock != null && lock.isHeld) lock.release()
        } catch (error: Throwable) {
            // ignore
        }
    }

    /** 把自己挂成前台；失败返回 false。 */
    private fun declare(text: String): Boolean {
        val note = ongoing(this, text)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, note)
            }
            true
        } catch (untyped: Throwable) {
            try {
                startForeground(NOTIFICATION_ID, note)
                true
            } catch (second: Throwable) {
                false
            }
        }
    }

    /** 只改那一行字。 */
    private fun relabel(text: String) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, ongoing(this, text))
        } catch (error: Throwable) {
            // 通知被拒（安卓 13 没给权限）也不该打断任务。
        }
    }

    companion object {
        const val EXTRA_TEXT = "text"
        const val EXTRA_STYLE = "style"
        const val EXTRA_LINES = "lines"

        /** 通知上那一格字，以及点了发出去之后走过来的那个 action。 */
        const val REPLY_KEY = "reply_text"
        const val ACTION_REPLY = "top.theez.carbide_shell.ACTION_REPLY"
        private const val REPLY_REQUEST = 0xCB04
        private const val CHANNEL_ID = "carbide_task"
        private const val DONE_CHANNEL_ID = "carbide_done"
        private const val NOTIFICATION_ID = 0xCB01
        private const val DONE_ID = 0xCB02
        private const val DEFAULT_TEXT = "正在执行"
        private const val ALERT_CHANNEL_ID = "carbide_alert"
        private const val ALERT_ID = 0xCB03
        private const val WAKE_LIMIT_MS = 30L * 60 * 1000

        /** 不带提升：普通常驻通知（也是判不出来时的退路）。 */
        private const val PROMO_PLAIN = -1

        /** 带 requestPromotedOngoing（安卓 16 QPR1 起才有）。 */
        private const val PROMO_REQUEST = 0

        /** 带彩色标记（安卓 16 首发版只认这一条）。 */
        private const val PROMO_COLORIZED = 1

        private const val PROMO_UNKNOWN = Int.MIN_VALUE

        /** 本机系统认哪种提升姿势，问过一次就记住。 */
        @Volatile
        private var promoCache: Int = PROMO_UNKNOWN

        /** 这一轮什么时候开始的，岛上的计时器从这儿走。 */
        @Volatile
        private var startedAt: Long = System.currentTimeMillis()

        /** 通知长什么样：一行、折开、一行一条、像聊天。 */
        const val STYLE_SIMPLE = "simple"
        const val STYLE_BIG = "big"
        const val STYLE_LIST = "list"
        const val STYLE_CHAT = "chat"

        /** 现在这条通知用的样式，跑完那条也跟着用。 */
        @Volatile
        private var style: String = STYLE_SIMPLE

        /** 最近说过的几句，大文本和会话样式拿它铺开。 */
        @Volatile
        private var lines: List<String> = emptyList()

        @Volatile
        private var instance: TaskService? = null

        /** 三条通知渠道建好。启动时调一次，第一条通知就不会因为渠道不存在被系统丢掉。 */
        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            ensureChannel(
                context, CHANNEL_ID,
                R.string.task_channel_name, R.string.task_channel_desc,
                NotificationManager.IMPORTANCE_LOW,
            )
            ensureChannel(
                context, DONE_CHANNEL_ID,
                R.string.task_done_channel_name, R.string.task_done_channel_desc,
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            ensureChannel(
                context, ALERT_CHANNEL_ID,
                R.string.alert_channel_name, R.string.alert_channel_desc,
                NotificationManager.IMPORTANCE_DEFAULT,
            )
        }

        /** 起服务（或更新已在跑的那条通知）。 */
        fun start(
            context: Context,
            text: String,
            style: String = STYLE_SIMPLE,
            lines: List<String> = emptyList(),
        ) {
            TaskService.style = style
            TaskService.lines = lines
            startedAt = System.currentTimeMillis()
            val intent = Intent(context, TaskService::class.java)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_STYLE, style)
                .putStringArrayListExtra(EXTRA_LINES, ArrayList(lines))
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Throwable) {
                // 安卓 12 起后台不许新起前台服务；这会儿任务可能已经在别的进程退出了。
                // 不抛给 Dart，界面照常跑完这一轮。
            }
        }

        /** 更新通知上那句进度。服务没起来就换成 start，起不来就算了。 */
        fun update(context: Context, text: String, lines: List<String> = emptyList()) {
            TaskService.lines = lines
            val live = instance
            if (live == null) {
                start(context, text, style, lines)
            } else {
                live.relabel(text)
            }
        }

        /** 现在能发通知吗：系统总开关和安卓 13 起那个权限。 */
        fun state(context: Context): Map<String, Any> {
            val allowed = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    val manager =
                        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.areNotificationsEnabled()
                } else {
                    true
                }
            } catch (error: Throwable) {
                true
            }
            val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            return mapOf(
                "allowed" to allowed,
                "granted" to granted,
                "sdk" to Build.VERSION.SDK_INT,
            )
        }

        /** 跑完了：收掉常驻通知，留一句结果，点一下回到对话。 */
        fun finish(
            context: Context,
            text: String,
            style: String = STYLE_SIMPLE,
            lines: List<String> = emptyList(),
        ) {
            TaskService.style = style
            TaskService.lines = lines
            stop(context)
            try {
                ensureChannel(
                    context, DONE_CHANNEL_ID,
                    R.string.task_done_channel_name, R.string.task_done_channel_desc,
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(DONE_ID, done(context, text))
            } catch (error: Throwable) {
                // 通知发不出去也就算了，任务本身已经跑完。
            }
        }

        /** 一条提示：不常驻，点一下回到应用。资源监听过线时用，不占常驻那条。 */
        /// [slot] 是要占的那一格：同一格后一条盖掉前一条，不同格并排留着。
        /// 0 留给资源监听过线那一条，其余从 1 起。
        fun alert(context: Context, title: String, text: String, slot: Int = 0) {
            try {
                ensureChannel(
                    context, ALERT_CHANNEL_ID,
                    R.string.alert_channel_name, R.string.alert_channel_desc,
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                val body = text.ifBlank { title }
                val note = Notification.Builder(context, ALERT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_carbide_stat)
                    .setContentTitle(title.ifBlank { context.getString(R.string.alert_title) })
                    .setContentText(body)
                    .setStyle(Notification.BigTextStyle().bigText(body))
                    .setAutoCancel(true)
                    .setContentIntent(tap(context))
                    .build()
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(ALERT_ID + slot.coerceIn(0, 63), note)
            } catch (error: Throwable) {
                // 通知发不出去也就算了，数据已经记下。
            }
        }

        fun stop(context: Context) {
            instance = null
            try {
                context.stopService(Intent(context, TaskService::class.java))
            } catch (error: Throwable) {
                // ignore
            }
            cancel(context, NOTIFICATION_ID)
        }

        private fun cancel(context: Context, id: Int) {
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.cancel(id)
            } catch (error: Throwable) {
                // ignore
            }
        }

        /** 点了通知回到那个对话。 */
        private fun tap(context: Context): PendingIntent {
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            return PendingIntent.getActivity(context, 0, open, flags)
        }

        /**
         * 跑任务的那条常驻通知。
         *
         * 用 androidx 的 NotificationCompat 而不是系统那个 Builder：安卓 16 的「实时更新」
         * 跟进的那两下（setRequestPromotedOngoing / setShortCriticalText）只有它才有，
         * 而 HyperOS 的岛画的正是被提升的那条通知。
         */
        private fun ongoing(context: Context, text: String): Notification {
            ensureChannel(
                context, CHANNEL_ID,
                R.string.task_channel_name, R.string.task_channel_desc,
                NotificationManager.IMPORTANCE_LOW,
            )
            val body = tails(text, lines)
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_carbide_stat)
                .setContentTitle(context.getString(R.string.task_notification_title))
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setContentIntent(tap(context))
            // 提升要求通知用可展开的样式之一：认不出来的就铺成大文本。
            builder.setStyle(
                compatStyle(context, body)
                    ?: NotificationCompat.BigTextStyle().bigText(body.joinToString("\n"))
            )
            tryAddReplyCompat(context, builder)
            promo(context, builder, shortOf(text))
            return builder.build()
        }

        /** 提示条上那几个字：说得出第几步就说步数，说不上就是「运行中」。 */
        private fun shortOf(text: String): String {
            val hit = Regex("第\\s*(\\d+)\\s*步").find(text)
            return if (hit != null) "${hit.groupValues[1]} 步" else "运行中"
        }

        /** 系统认不认提升：两种姿势各造一条真通知问它，认下就缓存。 */
        private fun promoMode(context: Context): Int {
            val cached = promoCache
            if (cached != PROMO_UNKNOWN) return cached
            var decided = PROMO_PLAIN
            for (mode in intArrayOf(PROMO_REQUEST, PROMO_COLORIZED)) {
                val probe = try {
                    NotificationCompat.Builder(context, CHANNEL_ID)
                        .setSmallIcon(R.drawable.ic_carbide_stat)
                        .setContentTitle("诊断")
                        .setContentText("诊断")
                        .setStyle(NotificationCompat.BigTextStyle().bigText("诊断"))
                        .setOngoing(true)
                        .also { hook(it, mode, "9s") }
                        .build()
                } catch (error: Throwable) {
                    null
                }
                if (probe != null && promotable(probe)) {
                    decided = mode
                    break
                }
            }
            promoCache = decided
            return decided
        }

        private fun promo(context: Context, builder: NotificationCompat.Builder, short: String) {
            val mode = promoMode(context)
            if (mode == PROMO_PLAIN) return
            try {
                hook(builder, mode, short)
            } catch (error: Throwable) {
                // 请系统考虑提升只是额外一句，挂不上也不能把通知弄丢。
            }
        }

        /** 两套门槛：安卓 16 QPR1 要请求标记且不能是彩色，首发版反过来只认彩色。 */
        private fun hook(builder: NotificationCompat.Builder, mode: Int, short: String) {
            when (mode) {
                PROMO_REQUEST -> {
                    builder.setRequestPromotedOngoing(true)
                    if (short.isNotEmpty()) builder.setShortCriticalText(short)
                }
                PROMO_COLORIZED -> {
                    builder.setColorized(true)
                    if (short.isNotEmpty()) builder.setShortCriticalText(short)
                }
                else -> return
            }
            // 岛上一秒一跳的那串数字交给系统自己走，不用为了它反复重发通知。
            builder.setWhen(startedAt)
                .setUsesChronometer(true)
                .setShowWhen(true)
        }

        private fun promotable(note: Notification): Boolean = try {
            Notification::class.java.getMethod("hasPromotableCharacteristics").invoke(note) == true
        } catch (error: Throwable) {
            false
        }

        /** 兼容版的样式：大文本 / 一行条 / 像聊天。 */
        private fun compatStyle(context: Context, body: List<String>): NotificationCompat.Style? {
            return try {
                when (style) {
                    STYLE_BIG -> NotificationCompat.BigTextStyle().bigText(body.joinToString("\n"))
                    STYLE_LIST -> {
                        val inbox = NotificationCompat.InboxStyle()
                        for (line in body) inbox.addLine(line)
                        inbox
                    }
                    STYLE_CHAT -> {
                        val me = Person.Builder()
                            .setName(context.getString(R.string.task_chat_me))
                            .build()
                        val sender = Person.Builder()
                            .setName(context.getString(R.string.task_chat_sender))
                            .build()
                        val chat = NotificationCompat.MessagingStyle(me)
                        val now = System.currentTimeMillis()
                        val ordered = body.reversed()
                        ordered.forEachIndexed { index, line ->
                            chat.addMessage(line, now - (ordered.size - index) * 1000L, sender)
                        }
                        chat
                    }
                    else -> null
                }
            } catch (error: Throwable) {
                null
            }
        }

        /** 通知上那颗「回复」，兼容版。加不上就只发通知，不影响任务。 */
        private fun tryAddReplyCompat(context: Context, builder: NotificationCompat.Builder) {
            try {
                val remote = CompatRemoteInput.Builder(REPLY_KEY)
                    .setLabel(context.getString(R.string.task_reply_hint))
                    .build()
                val action = NotificationCompat.Action.Builder(
                    R.drawable.ic_carbide_stat,
                    context.getString(R.string.task_reply_action),
                    replyIntent(context),
                ).addRemoteInput(remote).build()
                builder.addAction(action)
            } catch (error: Throwable) {
                // 系统太老或者厂商改过：这颗键就不出了。
            }
        }

        private fun done(context: Context, text: String): Notification {
            val body = text.ifBlank { context.getString(R.string.task_done_title) }
            val builder = Notification.Builder(context, DONE_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_carbide_stat)
                .setContentTitle(context.getString(R.string.task_done_title))
                .setContentText(body)
                .setAutoCancel(true)
                .setContentIntent(tap(context))
            val rich = styleOf(context, body)
                ?: Notification.BigTextStyle().bigText(tails(body, lines).joinToString("\n"))
            builder.setStyle(rich)
            tryAddReply(context, builder)
            return builder.build()
        }

        /** 最新一句在前，重复的不要，最多四行。 */
        private fun tails(text: String, more: List<String>): List<String> {
            val out = ArrayList<String>()
            if (text.isNotBlank()) out.add(text.trim())
            for (line in more) {
                val clean = line.trim()
                if (clean.isEmpty() || out.contains(clean)) continue
                out.add(clean)
                if (out.size >= 4) break
            }
            return out
        }

        /** 按设置里的样式铺开。认不出来就不加样式，回到一行。 */
        private fun styleOf(context: Context, text: String): Notification.Style? {
            val body = tails(text, lines)
            return try {
                when (style) {
                    STYLE_BIG -> Notification.BigTextStyle().bigText(body.joinToString("\n"))
                    STYLE_LIST -> {
                        val inbox = Notification.InboxStyle()
                        for (line in body) inbox.addLine(line)
                        inbox
                    }
                    STYLE_CHAT -> chat(context, body)
                    else -> null
                }
            } catch (error: Throwable) {
                null
            }
        }

        /** 会话样式：像一条一条聊过来的。系统太老就退回一行。 */
        private fun chat(context: Context, body: List<String>): Notification.Style? {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
            val sender = context.getString(R.string.task_chat_sender)
            @Suppress("DEPRECATION")
            val chatStyle = Notification.MessagingStyle(context.getString(R.string.task_chat_me))
            val now = System.currentTimeMillis()
            val ordered = body.reversed()
            ordered.forEachIndexed { index, line ->
                @Suppress("DEPRECATION")
                chatStyle.addMessage(line, now - (ordered.size - index) * 1000L, sender)
            }
            return chatStyle
        }

        /** 通知上那颗「回复」。加不上就只发通知，不影响任务。 */
        private fun tryAddReply(context: Context, builder: Notification.Builder) {
            try {
                builder.addAction(replyAction(context))
            } catch (error: Throwable) {
                // 系统太老或者厂商改过：这颗键就不出了。
            }
        }

        /** 写完点发送，字回到应用里当下一句。 */
        private fun replyAction(context: Context): Notification.Action {
            val remote = RemoteInput.Builder(REPLY_KEY)
                .setLabel(context.getString(R.string.task_reply_hint))
                .build()
            return Notification.Action.Builder(
                Icon.createWithResource(context, R.drawable.ic_carbide_stat),
                context.getString(R.string.task_reply_action),
                replyIntent(context),
            ).addRemoteInput(remote).build()
        }

        /**
         * 回复要一个可变（mutable）的 PendingIntent：那一格字是系统填进来的，
         * 写成不可变的在安卓 12 起会让回复直接丢掉。
         */
        private fun replyIntent(context: Context): PendingIntent {
            val open = Intent(context, MainActivity::class.java).apply {
                action = ACTION_REPLY
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            return PendingIntent.getActivity(context, REPLY_REQUEST, open, flags)
        }

        private fun ensureChannel(
            context: Context,
            id: String,
            nameRes: Int,
            descRes: Int,
            importance: Int,
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(id) != null) return
            val channel = NotificationChannel(id, context.getString(nameRes), importance)
            channel.description = context.getString(descRes)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
    }
}
