package de.fcteugn.jugend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveMatchPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        if (!extras.getString("liveMatch").equals("true", ignoreCase = true)) return
        val values = extras.keySet().associateWith { key -> extras.get(key) }
        LiveMatchNotification.update(context.applicationContext, values)
    }
}
