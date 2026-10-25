package top.theez.carbide_shell

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/// 把一份字节写进系统的「下载」目录。
///
/// Android 10 起走 MediaStore，不需要任何存储权限；更早的系统只能写公共目录，
/// 那条路要 WRITE_EXTERNAL_STORAGE（清单里限到 28 及以下）。
object Downloads {
    /// 返回给人看的一句话：存到哪儿了。
    fun save(context: Context, name: String, bytes: ByteArray, mime: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("下载目录打不开")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("写不进去")
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "下载/$name"
        }
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) dir.mkdirs()
        val file = uniqueFile(dir, name)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    /// 同名的老文件不覆盖：后面挂一个 -2。
    private fun uniqueFile(dir: File, name: String): File {
        val first = File(dir, name)
        if (!first.exists()) return first
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val tail = if (dot > 0) name.substring(dot) else ""
        for (n in 2..99) {
            val next = File(dir, "$stem-$n$tail")
            if (!next.exists()) return next
        }
        return first
    }
}
