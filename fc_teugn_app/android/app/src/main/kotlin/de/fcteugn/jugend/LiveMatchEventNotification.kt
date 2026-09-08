package de.fcteugn.jugend

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

/** Audible events arrive only through FCM. Foreground score refreshes keep
 * updating the separate, silent LiveMatchNotification without making a sound. */
object LiveMatchEventNotification {
    private const val CHANNEL_ID = "fc_teugn_live_events"
    private const val HISTORY = "fc_teugn_live_event_alerts"
    private const val RECENT_EVENTS = "recent_events"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,
            "Liveticker-Ereignisse",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Anpfiff, Tore und Abpfiff mit Benachrichtigungston"
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build(),
            )
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        })
    }

    @Synchronized
    fun show(context: Context, values: Map<String, Any?>): Boolean {
        if (values["liveMatch"].toString() != "true" ||
            values["entityType"].toString() != "LiveTickerEvent") return false
        val matchId = values["matchId"]?.toString()?.trim().orEmpty()
        val eventId = values["entityId"]?.toString()?.trim().orEmpty()
        if (matchId.isBlank() || eventId.isBlank()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED) return false

        val eventType = values["eventType"]?.toString().orEmpty()
        if (eventType.isNotEmpty() && eventType !in setOf(
                "MATCH_START", "HOME_GOAL", "AWAY_GOAL", "MATCH_END",
            )) return false
        val eventKey = "$matchId:$eventId"
        val preferences = context.getSharedPreferences(HISTORY, Context.MODE_PRIVATE)
        val recent = preferences.getString(RECENT_EVENTS, "").orEmpty()
            .split('\n').filter { it.isNotEmpty() }
        if (eventKey in recent) return false

        createChannel(context)
        val home = values["homeTeam"]?.toString()?.trim().orEmpty().ifBlank { "Heim" }
        val away = values["awayTeam"]?.toString()?.trim().orEmpty().ifBlank { "Gast" }
        val score = "${values["homeScore"].asInt()}:${values["awayScore"].asInt()}"
        val minute = values["minute"].asInt().coerceAtLeast(1)
        // Build copy from team-only metadata. Never use a free-text scorer or
        // commentary field, including when a previous backend sends the push.
        val label = when (eventType) {
            "MATCH_START" -> "Anpfiff"
            "HOME_GOAL" -> "Tor für $home"
            "AWAY_GOAL" -> "Tor für $away"
            "MATCH_END" -> "Abpfiff"
            else -> "Liveticker"
        }
        val notificationId = 0x47000000 or (eventKey.hashCode() and 0x00ffffff)
        val action = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            // Each event opens its own match, even after another push arrives.
            putExtra("fc_teugn_action_url", "/matches/$matchId?tab=live")
            data = android.net.Uri.parse("fcteugn://live-event/${android.net.Uri.encode(eventKey)}")
        }
        val pendingIntent = PendingIntent.getActivity(context, notificationId, action,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
        }
        val body = "$home – $away · $minute. Minute"
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_fc_teugn)
            .setColor(0xffffe600.toInt())
            .setContentTitle("$label · $score")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setTimeoutAfter(60 * 60 * 1000L)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // A unique tag avoids even rare integer hash collisions between events.
        manager.notify(eventKey, notificationId, notification)
        preferences.edit().putString(RECENT_EVENTS,
            (recent + eventKey).takeLast(128).joinToString("\n")).apply()
        return true
    }

    private fun Any?.asInt(): Int = when (this) {
        is Number -> toInt()
        else -> toString().toIntOrNull() ?: 0
    }
}
