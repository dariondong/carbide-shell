package top.theez.carbide_shell

import android.Manifest
import android.app.RemoteInput
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var askedNotifications = false

    /**
     * 设置页问权限时先挂在这里，回调里再回话。
     */
    private var pendingNotification: MethodChannel.Result? = null

    /** 正在等系统回话的扩展权限请求，按请求号存着。 */
    private val deviceWaits = HashMap<Int, MethodChannel.Result>()

    /// 往 Dart 送消息用的那个道，建好之后才能把通知里的回复递过去。
    private var replyChannel: MethodChannel? = null

    /// 人在通知里写的那句。Dart 那边还没接上就先挂在这里。
    private var pendingReply: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readReply(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readReply(intent)
    }

    /** 通知上写的那句就在 intent 里，取出来交给 Dart。 */
    private fun readReply(intent: Intent?) {
        val text = try {
            val results = RemoteInput.getResultsFromIntent(intent) ?: return
            results.getCharSequence(TaskService.REPLY_KEY)?.toString()?.trim().orEmpty()
        } catch (error: Throwable) {
            ""
        }
        if (text.isEmpty()) return
        pendingReply = text
        flushReply()
    }

    /** 递一句给 Dart。那边还没接好就留着等它来取。 */
    private fun flushReply() {
        val channel = replyChannel ?: return
        val text = pendingReply ?: return
        pendingReply = null
        channel.invokeMethod("reply", text, object : MethodChannel.Result {
            override fun success(result: Any?) {
                // 已经到 Dart 手上了。
            }

            override fun error(code: String, message: String?, details: Any?) {
                if (pendingReply == null) pendingReply = text
            }

            override fun notImplemented() {
                if (pendingReply == null) pendingReply = text
            }
        })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 三条通知渠道建好，第一条通知就不会因为渠道不存在被系统静默丢掉。
        TaskService.ensureChannels(this)
        val foreground = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        replyChannel = foreground
        foreground.setMethodCallHandler { call, result ->
                when (call.method) {
                    "begin" -> {
                        askNotifications()
                        TaskService.start(
                            this,
                            call.argument<String>("text").orEmpty(),
                            call.argument<String>("style").orEmpty().ifBlank { "simple" },
                            call.argument<List<String>>("lines") ?: emptyList(),
                        )
                        result.success(null)
                    }

                    "update" -> {
                        TaskService.update(
                            this,
                            call.argument<String>("text").orEmpty(),
                            call.argument<List<String>>("lines") ?: emptyList(),
                        )
                        result.success(null)
                    }

                    "end" -> {
                        TaskService.stop(this)
                        result.success(null)
                    }

                    "finish" -> {
                        TaskService.finish(
                            this,
                            call.argument<String>("text").orEmpty(),
                            call.argument<String>("style").orEmpty().ifBlank { "simple" },
                            call.argument<List<String>>("lines") ?: emptyList(),
                        )
                        result.success(null)
                    }

                    "alert" -> {
                        askNotifications()
                        TaskService.alert(
                            this,
                            call.argument<String>("title").orEmpty(),
                            call.argument<String>("text").orEmpty(),
                            call.argument<Int>("slot") ?: 0,
                        )
                        result.success(null)
                    }

                    "battery" -> {
                        openBatterySettings()
                        result.success(null)
                    }

                    "prepare" -> {
                        TaskService.ensureChannels(this)
                        result.success(TaskService.state(this))
                    }

                    "notifyState" -> result.success(TaskService.state(this))

                    "request" -> requestNotifications(result)

                    "notifSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }

                    "takePendingReply" -> {
                        val text = pendingReply
                        pendingReply = null
                        result.success(text)
                    }

                    else -> result.notImplemented()
                }
            }
        // 通知里的回复可能比 Dart 那边接上得早，再接一次。
        flushReply()
        // 临时文件下载到「下载」目录。Android 10 起走 MediaStore，不要权限。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> {
                        val name = call.argument<String>("name").orEmpty()
                        val bytes = call.argument<ByteArray>("bytes")
                        val mime = call.argument<String>("mime")
                            ?: "application/octet-stream"
                        if (name.isEmpty() || bytes == null) {
                            result.error("bad-args", "缺少文件名或者内容", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(Downloads.save(this, name, bytes, mime))
                        } catch (error: Throwable) {
                            result.error("save-failed", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        // 手机这一侧：设备信息、位置、联系人、短信、分享。用之前先看权限。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(Device.info(this))

                    "has" -> result.success(
                        Device.has(this, call.argument<String>("perm").orEmpty()),
                    )

                    "request" -> requestDevice(
                        call.argument<String>("perm").orEmpty(),
                        result,
                    )

                    "location" -> {
                        if (!Device.has(this, "location")) {
                            result.error("no-permission", "没有位置的权限", null)
                            return@setMethodCallHandler
                        }
                        result.success(Device.location(this))
                    }

                    "contacts" -> {
                        if (!Device.has(this, "contacts")) {
                            result.error("no-permission", "没有读取联系人的权限", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(
                                Device.contacts(
                                    this,
                                    call.argument<String>("query").orEmpty(),
                                    (call.argument<Int>("limit") ?: 20).coerceIn(1, 50),
                                ),
                            )
                        } catch (error: Throwable) {
                            result.error("contacts-failed", error.message, null)
                        }
                    }

                    "sms" -> {
                        if (!Device.has(this, "sms")) {
                            result.error("no-permission", "没有发短信的权限", null)
                            return@setMethodCallHandler
                        }
                        val to = call.argument<String>("to").orEmpty().trim()
                        val text = call.argument<String>("text").orEmpty()
                        if (to.isEmpty() || text.isEmpty()) {
                            result.error("bad-args", "号码和内容都得写", null)
                            return@setMethodCallHandler
                        }
                        try {
                            Device.sendSms(this, to, text)
                            result.success(true)
                        } catch (error: Throwable) {
                            result.error("sms-failed", error.message, null)
                        }
                    }

                    "share" -> {
                        try {
                            Device.share(
                                this,
                                call.argument<String>("text").orEmpty(),
                                call.argument<String>("subject").orEmpty(),
                            )
                            result.success(true)
                        } catch (error: Throwable) {
                            result.error("share-failed", error.message, null)
                        }
                    }

                    "appSettings" -> {
                        try {
                            Device.appSettings(this)
                            result.success(true)
                        } catch (error: Throwable) {
                            result.error("settings-failed", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 系统的省电与后台限制那一页。有的系统会把跑着的服务一起清掉，
     * 这一项由用户自己放开，应用不偷偷改系统设置。
     */
    private fun openBatterySettings() {
        val tries = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in tries) {
            try {
                startActivity(intent)
                return
            } catch (error: Throwable) {
                // 这一层没有就试下一层
            }
        }
    }

    /**
     * 系统的通知设置页：权限拒了之后不再弹框，得由用户自己去打开。
     */
    private fun openNotificationSettings() {
        val tries = listOf(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in tries) {
            try {
                startActivity(intent)
                return
            } catch (error: Throwable) {
                // 这一层没有就试下一层
            }
        }
    }

    /**
     * 安卓 13 起没有通知权限时，前台服务照样跑，但那条通知看不见。
     * 第一次跑任务时问一次，设置里也能主动再问。
     */
    private fun askNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (askedNotifications) return
        askedNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    /** 设置页点的那一下：把结果回给 Dart，界面照着刷新。 */
    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(TaskService.state(this))
            return
        }
        pendingNotification = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATIONS) {
            pendingNotification?.success(TaskService.state(this))
            pendingNotification = null
            return
        }
        val waiting = deviceWaits.remove(requestCode) ?: return
        val code = DEVICE_REQ.entries.firstOrNull { it.value == requestCode }?.key
        waiting.success(code != null && Device.has(this, code))
    }

    /** 设置里打开一项扩展时问一次权限，结果照实回话。 */
    private fun requestDevice(code: String, result: MethodChannel.Result) {
        val perm = Device.PERMS[code]
        val requestCode = DEVICE_REQ[code]
        if (perm == null || requestCode == null) {
            result.error("bad-args", "没有这一项权限", null)
            return
        }
        if (Device.has(this, code) || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        deviceWaits[requestCode] = result
        requestPermissions(arrayOf(perm), requestCode)
    }

    private companion object {
        const val CHANNEL = "top.theez.carbide_shell/foreground"
        const val FILES = "top.theez.carbide_shell/files"
        const val DEVICE = "top.theez.carbide_shell/device"
        const val REQ_NOTIFICATIONS = 0xCB02

        /** 每一项扩展权限问一次用的号。 */
        val DEVICE_REQ: Map<String, Int> = mapOf(
            "sms" to 0xCB21,
            "location" to 0xCB22,
            "contacts" to 0xCB23,
        )
    }
}
