package top.theez.carbide_shell

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.speech.RecognizerIntent
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

    /** 送去系统设置页的那几项：人回来之后再回话，那时才知道给没给。 */
    private val accessWaits = HashMap<Int, MethodChannel.Result>()

    /** 往 Dart 送消息用的那个道，建好之后才能把通知里的回复递过去。 */
    private var replyChannel: MethodChannel? = null

    /// 等系统认字界面回来的那一次请求。
    private var systemInput: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        rebindNotifListener()
        readReply(intent)
    }

    /**
     * 升级之后、或者系统把监听服务丢掉以后，那一头可能迟迟不重新绑上。
     * 有「通知使用权」就请求系统重绑一次；没有就什么都不做。
     */
    private fun rebindNotifListener() {
        if (!Device.notifAccess(this)) return
        try {
            NotificationListenerService.requestRebind(
                ComponentName(this, CarbideNotificationListener::class.java),
            )
        } catch (error: Throwable) {
            // 系统不给就算了，下一次进来再试。
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readReply(intent)
    }

    /** 通知上写的那句就在 intent 里，取出来交给 Dart。 */
    private fun readReply(intent: Intent?) {
        val text = ReplyBridge.textOf(intent)
        if (text.isEmpty()) return
        ReplyBridge.deliver(text)
    }

    /** 递一句给 Dart。那边还没接好就留着等它来取。 */
    private fun flushReply() {
        ReplyBridge.attach(this, replyChannel)
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
                            call.argument<String>("state").orEmpty().ifBlank { TaskService.STATE_RUN },
                        )
                        result.success(null)
                    }

                    "update" -> {
                        TaskService.update(
                            this,
                            call.argument<String>("text").orEmpty(),
                            call.argument<List<String>>("lines") ?: emptyList(),
                            call.argument<String>("state").orEmpty().ifBlank { TaskService.STATE_RUN },
                        )
                        result.success(null)
                    }

                    "end" -> {
                        TaskService.stop(this)
                        result.success(null)
                    }

                    "complete", "finish" -> {
                        TaskService.complete(
                            this,
                            call.argument<String>("text").orEmpty(),
                            call.argument<String>("style").orEmpty().ifBlank { "simple" },
                            call.argument<List<String>>("lines") ?: emptyList(),
                            call.argument<Boolean>("residual") ?: true,
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

                    "diag" -> result.success(TaskService.diag(this))

                    "request" -> requestNotifications(result)

                    "notifSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }

                    "takePendingReply" -> result.success(ReplyBridge.take(this))

                    else -> result.notImplemented()
                }
            }
        // 通知里的回复可能比 Dart 那边接上得早，这时才把道接上。
        flushReply()
        // 长按输入框说话：系统自带的语音识别，认出来的字一条条回给界面。
        val speech = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPEECH)
        SpeechHelper.attach(speech)
        speech.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(SpeechHelper.available(this))

                "start" -> {
                    if (!Device.has(this, "mic") &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                    ) {
                        // 没给麦克风权限：先回一句，界面去要，要到了再叫一次 start。
                        result.success(mapOf("ok" to false, "need" to "mic"))
                    } else {
                        SpeechHelper.start(this)
                        result.success(mapOf("ok" to true))
                    }
                }

                "grant" -> requestDevice("mic", result)

                // 在线识别：自己录音，录完交给网上的服务认字。
                "recordStart" -> {
                    if (!Device.has(this, "mic") &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                    ) {
                        result.success(mapOf("ok" to false, "need" to "mic"))
                    } else {
                        result.success(mapOf("ok" to VoiceRecorder.start(this)))
                    }
                }

                "recordStop" -> result.success(VoiceRecorder.stop(this))

                "recordCancel" -> {
                    VoiceRecorder.cancel()
                    result.success(null)
                }

                // 系统那个认字界面：只认一次，认完把字回回去。
                "systemInput" -> openSystemInput(result)

                "diag" -> result.success(SpeechHelper.diag(this))

                "stop" -> {
                    SpeechHelper.stop()
                    result.success(null)
                }

                "cancel" -> {
                    SpeechHelper.cancel()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
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

                    "phoneState" -> result.success(Device.phoneState(this))

                    "has" -> result.success(
                        if (call.argument<String>("perm").orEmpty() == "notif") {
                            Device.canReadNotifs(this)
                        } else {
                            Device.has(this, call.argument<String>("perm").orEmpty())
                        },
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

                    "notifs" -> {
                        if (!Device.canReadNotifs(this)) {
                            result.error("no-permission", "没有通知读取权限", null)
                            return@setMethodCallHandler
                        }
                        result.success(
                            Device.notifications(
                                call.argument<Int>("limit") ?: 40,
                                call.argument<Int>("minutes") ?: 720,
                            ),
                        )
                    }

                    "usage" -> {
                        if (!Device.has(this, "usage")) {
                            result.error("no-permission", "没有使用情况访问权限", null)
                            return@setMethodCallHandler
                        }
                        result.success(Device.usage(this, call.argument<Int>("hours") ?: 24))
                    }

                    "openApp" -> result.success(
                        Device.openApp(this, call.argument<String>("query").orEmpty()),
                    )

                    "setAlarm" -> result.success(
                        Device.setAlarm(
                            this,
                            call.argument<Int>("hour") ?: 7,
                            call.argument<Int>("minute") ?: 0,
                            call.argument<String>("label").orEmpty(),
                            call.argument<Boolean>("skipUi") ?: true,
                        ),
                    )

                    "setTimer" -> result.success(
                        Device.setTimer(
                            this,
                            call.argument<Int>("seconds") ?: 300,
                            call.argument<String>("label").orEmpty(),
                            call.argument<Boolean>("skipUi") ?: true,
                        ),
                    )

                    "volume" -> result.success(Device.volume(this))

                    "setVolume" -> result.success(
                        Device.setVolume(
                            this,
                            call.argument<String>("stream").orEmpty(),
                            call.argument<Int>("percent") ?: -1,
                            call.argument<String>("mode").orEmpty(),
                        ),
                    )

                    "notifAccess" -> result.success(Device.notifAccess(this))

                    "usageAccess" -> result.success(Device.usageAccess(this))

                    "openNotifAccess" -> {
                        Device.openNotifAccess(this)
                        result.success(true)
                    }

                    "openUsageAccess" -> {
                        Device.openUsageAccess(this)
                        result.success(true)
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

    /** 从系统那两页回来：这一项现在到底给没给。 */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SYSTEM_INPUT) {
            val waiting = systemInput?.also { systemInput = null } ?: return
            val text = if (resultCode == RESULT_OK) {
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
                    .orEmpty()
            } else {
                ""
            }
            waiting.success(text)
            return
        }
        val waiting = accessWaits.remove(requestCode) ?: return
        val code = if (requestCode == REQ_NOTIF_ACCESS) "notif" else "usage"
        waiting.success(accessGiven(code))
    }

    /** 叫起系统自带的认字界面，认完从 onActivityResult 回去。 */
    private fun openSystemInput(result: MethodChannel.Result) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE,
                java.util.Locale.getDefault().toLanguageTag(),
            )
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "说一句，认完自动回来")
        }
        systemInput?.success("")
        systemInput = result
        try {
            startActivityForResult(intent, REQ_SYSTEM_INPUT)
        } catch (error: Throwable) {
            if (systemInput === result) systemInput = null
            result.error("no-activity", "这台机器上没有认字界面", null)
        }
    }

    /** 通知读取得听监听服务那一头的，其余照常问权限。 */
    private fun accessGiven(code: String): Boolean =
        if (code == "notif") Device.canReadNotifs(this) else Device.has(this, code)

    /** 设置里打开一项扩展时问一次权限，结果照实回话。 */
    private fun requestDevice(code: String, result: MethodChannel.Result) {
        // 通知读取和使用情况不是弹框能给的，只能把人送到系统那一页；
        // 回来之后才问得到答案，所以先挂在这里，人回来再回话。
        if (code == "notif" || code == "usage") {
            if (accessGiven(code)) {
                result.success(true)
                return
            }
            val requestCode = if (code == "notif") REQ_NOTIF_ACCESS else REQ_USAGE_ACCESS
            val action = if (code == "notif") {
                Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS
            } else {
                Settings.ACTION_USAGE_ACCESS_SETTINGS
            }
            accessWaits[requestCode] = result
            try {
                startActivityForResult(Intent(action), requestCode)
            } catch (error: Throwable) {
                accessWaits.remove(requestCode)
                if (code == "notif") Device.openNotifAccess(this) else Device.openUsageAccess(this)
                result.success(false)
            }
            return
        }
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
        const val SPEECH = "top.theez.carbide_shell/speech"
        const val REQ_NOTIFICATIONS = 0xCB02

        /** 送去系统设置页要权限的两个号。 */
        const val REQ_NOTIF_ACCESS = 0xCB31
        const val REQ_USAGE_ACCESS = 0xCB32

        /** 叫系统认字界面回来用的号。 */
        const val REQ_SYSTEM_INPUT = 0xCB41

        /** 每一项扩展权限问一次用的号。 */
        val DEVICE_REQ: Map<String, Int> = mapOf(
            "sms" to 0xCB21,
            "location" to 0xCB22,
            "contacts" to 0xCB23,
            "mic" to 0xCB24,
        )
    }
}
