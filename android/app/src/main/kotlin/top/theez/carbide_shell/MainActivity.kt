package top.theez.carbide_shell

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
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

                    else -> result.notImplemented()
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
