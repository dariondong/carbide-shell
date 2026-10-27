package top.theez.carbide_shell

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

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
        private const val CHANNEL_ID = "carbide_task"
        private const val DONE_CHANNEL_ID = "carbide_done"
        private const val NOTIFICATION_ID = 0xCB01
        private const val DONE_ID = 0xCB02
        private const val DEFAULT_TEXT = "正在执行"
        private const val ALERT_CHANNEL_ID = "carbide_alert"
        private const val ALERT_ID = 0xCB03
        private const val WAKE_LIMIT_MS = 30L * 60 * 1000

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
        fun start(context: Context, text: String) {
            val intent = Intent(context, TaskService::class.java).putExtra(EXTRA_TEXT, text)
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
        fun update(context: Context, text: String) {
            val live = instance
            if (live == null) {
                start(context, text)
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
        fun finish(context: Context, text: String) {
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

        private fun ongoing(context: Context, text: String): Notification {
            ensureChannel(
                context, CHANNEL_ID,
                R.string.task_channel_name, R.string.task_channel_desc,
                NotificationManager.IMPORTANCE_LOW,
            )
            return Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_carbide_stat)
                .setContentTitle(context.getString(R.string.task_notification_title))
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setContentIntent(tap(context))
                .build()
        }

        private fun done(context: Context, text: String): Notification {
            val body = text.ifBlank { context.getString(R.string.task_done_title) }
            return Notification.Builder(context, DONE_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_carbide_stat)
                .setContentTitle(context.getString(R.string.task_done_title))
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(tap(context))
                .build()
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
