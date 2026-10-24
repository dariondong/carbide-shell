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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

                    "battery" -> {
                        openBatterySettings()
                        result.success(null)
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
     * 安卓 13 起没有通知权限时，前台服务照样跑，但那条通知看不见。
     * 只在第一次跑任务时问一次，拒了就不再烦人。
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
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0xCB02)
    }

    private companion object {
        const val CHANNEL = "top.theez.carbide_shell/foreground"
    }
}
