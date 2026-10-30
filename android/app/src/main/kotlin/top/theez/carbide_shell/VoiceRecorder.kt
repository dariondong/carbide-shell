package top.theez.carbide_shell

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * 在线识别录的那一段：16k 单声道 16 位，按一下录、松手收成 wav。
 *
 * 系统识别引擎拉不起来时走这一条：自己录，录完交给网上的识别服务认字。
 * 采样率与声道是各家识别接口最认的那一档，前端不再重采样。
 */
object VoiceRecorder {
    private const val RATE = 16000

    private var record: AudioRecord? = null
    private var thread: Thread? = null
    private var buffer: ByteArrayOutputStream? = null

    @Volatile
    private var running = false

    /** 现在是不是在录。 */
    val active: Boolean get() = running

    fun start(context: Context): Boolean {
        if (running) stopRecording()
        val least = AudioRecord.getMinBufferSize(
            RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val chunk = if (least > 0) maxOf(least, 4096) else 4096
        val fresh = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                chunk * 2,
            )
        } catch (error: Throwable) {
            return false
        }
        if (fresh.state != AudioRecord.STATE_INITIALIZED) {
            try {
                fresh.release()
            } catch (error: Throwable) {
                // ignore
            }
            return false
        }
        val sink = ByteArrayOutputStream()
        buffer = sink
        record = fresh
        try {
            fresh.startRecording()
        } catch (error: Throwable) {
            release()
            return false
        }
        running = true
        thread = Thread {
            val page = ByteArray(chunk)
            while (running) {
                val read = try {
                    fresh.read(page, 0, page.size)
                } catch (error: Throwable) {
                    -1
                }
                if (read > 0) {
                    synchronized(sink) { sink.write(page, 0, read) }
                } else if (read < 0) {
                    break
                }
            }
        }.also { it.start() }
        return true
    }

    /** 收起来，写成 wav 放缓存目录。没录到东西就回空串。 */
    fun stop(context: Context): String {
        stopRecording()
        val sink = buffer ?: return ""
        val pcm = synchronized(sink) { sink.toByteArray() }
        buffer = null
        if (pcm.isEmpty()) return ""
        val dir = File(context.cacheDir, "voice")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, "v" + System.currentTimeMillis() + ".wav")
        return try {
            file.writeBytes(wav(pcm))
            file.absolutePath
        } catch (error: Throwable) {
            ""
        }
    }

    /** 不要了：这一段丢掉。 */
    fun cancel() {
        stopRecording()
        buffer = null
    }

    private fun stopRecording() {
        running = false
        val worker = thread
        thread = null
        try {
            record?.stop()
        } catch (error: Throwable) {
            // 已经停了就算了
        }
        try {
            worker?.join(1500)
        } catch (error: Throwable) {
            // ignore
        }
        release()
    }

    private fun release() {
        try {
            record?.release()
        } catch (error: Throwable) {
            // ignore
        }
        record = null
    }

    /** 44 字节的头，后面照抄录到的 PCM。 */
    private fun wav(pcm: ByteArray): ByteArray {
        val head = ByteArray(44)
        val total = pcm.size + 36
        put(head, 0, "RIFF")
        int32(head, 4, total)
        put(head, 8, "WAVE")
        put(head, 12, "fmt ")
        int32(head, 16, 16)
        short16(head, 20, 1)
        short16(head, 22, 1)
        int32(head, 24, RATE)
        int32(head, 28, RATE * 2)
        short16(head, 32, 2)
        short16(head, 34, 16)
        put(head, 36, "data")
        int32(head, 40, pcm.size)
        return head + pcm
    }

    private fun put(target: ByteArray, at: Int, text: String) {
        for (i in text.indices) target[at + i] = text[i].code.toByte()
    }

    private fun int32(target: ByteArray, at: Int, value: Int) {
        target[at] = (value and 0xff).toByte()
        target[at + 1] = ((value shr 8) and 0xff).toByte()
        target[at + 2] = ((value shr 16) and 0xff).toByte()
        target[at + 3] = ((value shr 24) and 0xff).toByte()
    }

    private fun short16(target: ByteArray, at: Int, value: Int) {
        target[at] = (value and 0xff).toByte()
        target[at + 1] = ((value shr 8) and 0xff).toByte()
    }
}
