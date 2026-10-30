package top.theez.carbide_shell

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Process
import android.os.StatFs
import android.provider.ContactsContract
import android.provider.Settings
import android.telephony.SmsManager

/**
 * 手机这一侧的几件事：设备信息、位置、联系人、短信、分享。
 *
 * 每个用到敏感权限的方法都先问一句有没有权限，没有就让 Dart 那边去要，
 * 不自己弹框，也不吞掉失败。
 */
object Device {
    /** Dart 用的代号 → 系统权限名。 */
    val PERMS: Map<String, String> = mapOf(
        "sms" to Manifest.permission.SEND_SMS,
        "location" to Manifest.permission.ACCESS_FINE_LOCATION,
        "contacts" to Manifest.permission.READ_CONTACTS,
    )

    fun has(context: Context, code: String): Boolean {
        // 这两项不是运行时权限，是系统设置里单独给的「访问权」。
        if (code == "notif") return notifAccess(context)
        if (code == "usage") return usageAccess(context)
        val perm = PERMS[code] ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return context.checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
    }

    /** 系统里那条「通知使用权」给没给。 */
    fun notifAccess(context: Context): Boolean {
        val flat = try {
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            )
        } catch (error: Throwable) {
            null
        } ?: return false
        val me = context.packageName
        return flat.split(':').any { it.startsWith("$me/") }
    }

    /** 系统里那条「使用情况访问」给没给。 */
    fun usageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        val mode = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName,
                )
            }
        } catch (error: Throwable) {
            return false
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** 应用名。查不到就把包名当名字。 */
    fun appLabel(context: Context, pkg: String): String {
        return try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (error: Throwable) {
            pkg
        }
    }

    /** 最近这些通知，新的在前。 */
    fun notifications(limit: Int, minutes: Int): List<Map<String, Any?>> {
        val span = minutes.coerceIn(1, 1440) * 60_000L
        val since = System.currentTimeMillis() - span
        // 通知栏上挂着的那些也要算进来，不然刚起来读就是空的。
        CarbideNotificationListener.instance?.harvest()
        return NotifLog.recent(limit.coerceIn(1, 100), since)
    }

    /** 每个应用最近用了多久，按分钟算，只留一分钟以上的前十几名。 */
    fun usage(context: Context, hours: Int): List<Map<String, Any?>> {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()
        val end = System.currentTimeMillis()
        val begin = end - hours.coerceIn(1, 72) * 3600_000L
        val stats = try {
            manager.queryAndAggregateUsageStats(begin, end)
        } catch (error: Throwable) {
            return emptyList()
        } ?: return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        for ((pkg, one) in stats) {
            val ms = one.totalTimeInForeground
            if (ms < 60_000L) continue
            out.add(
                mapOf(
                    "app" to appLabel(context, pkg),
                    "pkg" to pkg,
                    "minutes" to (ms / 60_000L).toInt(),
                    "last" to one.lastTimeUsed,
                ),
            )
        }
        out.sortByDescending { (it["minutes"] as? Int) ?: 0 }
        return if (out.size > 15) out.subList(0, 15) else out
    }

    /** 系统里给「通知使用权」的那一页。 */
    fun openNotifAccess(context: Context) {
        open(context, Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
    }

    /** 系统里给「使用情况访问」的那一页。 */
    fun openUsageAccess(context: Context) {
        open(context, Settings.ACTION_USAGE_ACCESS_SETTINGS)
    }

    private fun open(context: Context, action: String) {
        try {
            val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (error: Throwable) {
            appSettings(context)
        }
    }

    /** 现在这台机器的样子：机型、电量、网络、存储。不要权限。 */
    fun info(context: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["model"] = Build.MODEL ?: ""
        out["brand"] = Build.BRAND ?: ""
        out["sdk"] = Build.VERSION.SDK_INT
        out["abi"] = Build.SUPPORTED_ABIS.firstOrNull() ?: ""

        val battery = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        if (battery != null) {
            out["battery"] = battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            // isCharging 是 23 才有的，更老的系统就不写这一项。
            out["charging"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                battery.isCharging
            } else {
                false
            }
        }

        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val net = cm?.getNetworkCapabilities(cm.activeNetwork)
            out["network"] = when {
                net == null -> "offline"
                net.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                net.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                net.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                net.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "other"
            }
        } catch (error: Throwable) {
            out["network"] = ""
        }

        try {
            val stat = StatFs(Environment.getDataDirectory().path)
            out["freeMb"] = stat.availableBytes / (1024 * 1024)
            out["totalMb"] = stat.totalBytes / (1024 * 1024)
        } catch (error: Throwable) {
            // 量不出来就不写这两项
        }
        return out
    }

    /**
     * 手机此刻的状态信号：充电、电量、网络、亮屏、锁屏、耳机、铃音、勿扰、在放音乐。
     *
     * 拿不到的项就不写进表里，不编一个默认值。驾驶与运动状态系统不给第三方，也不写。
     */
    fun phoneState(context: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        try {
            val battery = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            if (battery != null) {
                out["battery"] = battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    out["charging"] = battery.isCharging
                }
            }
        } catch (error: Throwable) {
            // 读不到就不写
        }

        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
            if (pm != null) out["screenOn"] = pm.isInteractive
        } catch (error: Throwable) {
            // 同上
        }

        try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE)
                as? android.app.KeyguardManager
            if (km != null) out["locked"] = km.isKeyguardLocked
        } catch (error: Throwable) {
            // 同上
        }

        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val net = cm?.getNetworkCapabilities(cm.activeNetwork)
            out["network"] = when {
                net == null -> "offline"
                net.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                net.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                net.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                net.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "other"
            }
        } catch (error: Throwable) {
            out["network"] = ""
        }

        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            if (am != null) {
                out["ringer"] = when (am.ringerMode) {
                    android.media.AudioManager.RINGER_MODE_SILENT -> "silent"
                    android.media.AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                    else -> "normal"
                }
                out["music"] = am.isMusicActive
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    var headset = false
                    for (device in am.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)) {
                        when (device.type) {
                            android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
                            android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                            android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                            android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                            android.media.AudioDeviceInfo.TYPE_USB_HEADSET -> headset = true
                        }
                    }
                    out["headset"] = headset
                }
            }
        } catch (error: Throwable) {
            // 同上
        }

        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? android.app.NotificationManager
            if (nm != null && nm.isNotificationPolicyAccessGranted) {
                out["dnd"] = nm.currentInterruptionFilter !=
                    android.app.NotificationManager.INTERRUPTION_FILTER_ALL
            }
        } catch (error: Throwable) {
            // 没给「勿扰访问权」就不写这一项
        }
        return out
    }

    /** 最近一次定位。几个来源取最新的那一个，都没有就 null。 */
    fun location(context: Context): Map<String, Any?>? {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        var best: Location? = null
        for (name in manager.getProviders(true)) {
            val one = try {
                manager.getLastKnownLocation(name)
            } catch (error: SecurityException) {
                null
            } catch (error: Throwable) {
                null
            } ?: continue
            if (best == null || one.time > best.time) best = one
        }
        val fix = best ?: return null
        return mapOf(
            "lat" to fix.latitude,
            "lng" to fix.longitude,
            "accuracy" to fix.accuracy.toDouble(),
            "provider" to (fix.provider ?: ""),
            "at" to fix.time,
        )
    }

    /** 按名字找号码。名字空着就列最近的那些。 */
    fun contacts(context: Context, query: String, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val columns = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        val name = ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
        val key = query.trim()
        val selection = if (key.isEmpty()) null else "$name LIKE ?"
        val args = if (key.isEmpty()) null else arrayOf("%$key%")
        try {
            context.contentResolver.query(
                uri, columns, selection, args, "$name ASC",
            )?.use { cursor ->
                while (cursor.moveToNext() && out.size < limit) {
                    val who = cursor.getString(0) ?: ""
                    val phone = cursor.getString(1) ?: ""
                    if (phone.isEmpty()) continue
                    out.add(mapOf("name" to who, "phone" to phone))
                }
            }
        } catch (error: SecurityException) {
            throw IllegalStateException("没有读取联系人的权限")
        }
        return out
    }

    /** 发一条短信。太长就分条发。 */
    fun sendSms(context: Context, to: String, text: String) {
        @Suppress("DEPRECATION")
        val system: SmsManager? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
        val manager = system ?: throw IllegalStateException("这台机器发不了短信")
        val parts = manager.divideMessage(text)
        if (parts.size > 1) {
            manager.sendMultipartTextMessage(to, null, parts, null, null)
        } else {
            manager.sendTextMessage(to, null, text, null, null)
        }
    }

    /** 把一段话交给系统的分享面板。 */
    fun share(context: Context, text: String, subject: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain")
        send.putExtra(Intent.EXTRA_TEXT, text)
        if (subject.isNotEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, subject)
        val chooser = Intent.createChooser(send, subject.ifEmpty { "分享" })
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    }

    /** 这个应用在系统里的那一页。权限被拒过之后，只能去那里改。 */
    fun appSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
