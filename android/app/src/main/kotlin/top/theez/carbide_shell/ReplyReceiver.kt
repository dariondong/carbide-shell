package top.theez.carbide_shell

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 通知上写完那句点「发送」，走到这里。
 *
 * 不去开应用：字直接递回还在跑的那段 Flutter，通知也重发一次把那格输入收回去，
 * 人留在原地。应用已经不在跑的时候，字先存着，下次打开应用再自动送出去。
 */
class ReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val text = ReplyBridge.textOf(intent)
        if (text.isEmpty()) return
        // 那条通知重发一次：输入框收回，回过的这句挂进历史。
        TaskService.replied(text)
        ReplyBridge.deliver(text)
    }
}
