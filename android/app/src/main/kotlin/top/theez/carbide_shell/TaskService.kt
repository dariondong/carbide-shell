package top.theez.carbide_shell

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 长任务期间的前台服务。
 *
 * 有这条通知在，切出去、锁屏也不会被系统当成后台进程掐掉，SSH 连接和模型的请求都能跑完。
 * 任务的进度由 Dart 那边每变一次就调一次 update，通知上那句「第几步」跟着走。
 */
class TaskService : Service() {

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
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** 把自己挂成前台；失败返回 false。 */
    private fun declare(text: String): Boolean {
        val note = build(text)
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

    private fun build(text: String): Notification {
        ensureChannel(this)
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val tap = PendingIntent.getActivity(this, 0, open, flags)
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_carbide_stat)
            .setContentTitle(getString(R.string.task_notification_title))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(tap)
            .build()
    }

    /** 只改那一行字。服务没在跑就什么都不做，任务本身不受影响。 */
    private fun relabel(text: String) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, build(text))
        } catch (error: Throwable) {
            // 通知被拒（安卓 13 没给权限）也不该打断任务。
        }
    }

    companion object {
        const val EXTRA_TEXT = "text"
        private const val CHANNEL_ID = "carbide_task"
        private const val NOTIFICATION_ID = 0xCB01
        private const val DEFAULT_TEXT = "正在执行"

        @Volatile
        private var instance: TaskService? = null

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

        fun stop(context: Context) {
            instance = null
            try {
                context.stopService(Intent(context, TaskService::class.java))
            } catch (error: Throwable) {
                // ignore
            }
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.cancel(NOTIFICATION_ID)
            } catch (error: Throwable) {
                // ignore
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(CHANNEL_ID, context.getString(R.string.task_channel_name), NotificationManager.IMPORTANCE_LOW)
            channel.description = context.getString(R.string.task_channel_desc)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
    }
}
