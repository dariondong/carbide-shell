package top.theez.carbide_shell

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var askedNotifications = false

    /// 设置页问权限时先挂在这里，回调里再回话。
    private var pendingNotification: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 三条通知渠道建好，第一条通知就不会因为渠道不存在被系统静默丢掉。
        TaskService.ensureChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "begin" -> {
                        askNotifications()
                        TaskService.start(this, call.argument<String>("text").orEmpty())
                        result.success(null)
                    }

                    "update" -> {
                        TaskService.update(this, call.argument<String>("text").orEmpty())
                        result.success(null)
                    }

                    "end" -> {
                        TaskService.stop(this)
                        result.success(null)
                    }

                    "finish" -> {
                        TaskService.finish(this, call.argument<String>("text").orEmpty())
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
        }
    }

    private companion object {
        const val CHANNEL = "top.theez.carbide_shell/foreground"
        const val FILES = "top.theez.carbide_shell/files"
        const val REQ_NOTIFICATIONS = 0xCB02
    }
}
