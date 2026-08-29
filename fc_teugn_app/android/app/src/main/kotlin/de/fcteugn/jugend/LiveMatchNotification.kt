package de.fcteugn.jugend

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle

object LiveMatchNotification {
    private const val CHANNEL_ID = "fc_teugn_live_match"
    private const val ACTION_URL_EXTRA = "fc_teugn_action_url"
    private const val PROMOTED_ONGOING_EXTRA = "android.requestPromotedOngoing"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Live-Spielstand",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Spielstand und Spielminute während eines laufenden Spiels"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    fun update(context: Context, values: Map<String, Any?>): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val matchId = values["matchId"]?.toString()?.trim().orEmpty()
        if (matchId.isBlank()) return false
        createChannel(context)

        val homeTeam = values["homeTeam"]?.toString()?.trim().orEmpty().ifBlank { "Heim" }
        val awayTeam = values["awayTeam"]?.toString()?.trim().orEmpty().ifBlank { "Gast" }
        val homeScore = values["homeScore"].asInt()
        val awayScore = values["awayScore"].asInt()
        val minute = values["minute"].asInt().coerceAtLeast(1)
        val status = values["status"]?.toString()?.trim().orEmpty().ifBlank { "Live" }
        val finished = values["finished"].asBoolean()
        val actionUrl = values["actionUrl"]?.toString()?.trim().orEmpty()
        val notificationId = notificationId(matchId)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (actionUrl.isNotBlank()) putExtra(ACTION_URL_EXTRA, actionUrl)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val score = "$homeScore : $awayScore"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val extras = Bundle().apply {
            // Android 16+ can promote eligible ongoing notifications to the
            // lock screen and status chip. Older systems ignore this extra.
            putBoolean(PROMOTED_ONGOING_EXTRA, !finished)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_fc_teugn)
            .setColor(0xffffe600.toInt())
            .setContentTitle("$homeTeam  $score  $awayTeam")
            .setContentText(if (finished) "Abpfiff · Endstand" else "$status · $minute. Minute")
            .setSubText("FC Teugn Talents · Matchday Space")
            .setStyle(
                Notification.BigTextStyle().bigText(
                    if (finished) {
                        "$homeTeam $score $awayTeam · Abpfiff"
                    } else {
                        "$homeTeam $score $awayTeam · $status · $minute. Minute"
                    },
                ),
            )
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(!finished)
            .setAutoCancel(finished)
            .setOnlyAlertOnce(true)
            .setWhen(System.currentTimeMillis() - ((minute - 1) * 60_000L))
            .setShowWhen(!finished)
            .setUsesChronometer(!finished && status.equals("Live", ignoreCase = true))
            .setExtras(extras)
            .setTimeoutAfter(if (finished) 60 * 60 * 1000L else 8 * 60 * 60 * 1000L)
            .setPriority(Notification.PRIORITY_HIGH)

        // Auf neuen Android-Versionen wird der kurze Spielstand im Statuschip
        // verwendet. Reflection hält den Build kompatibel mit älteren SDKs.
        if (!finished) {
            runCatching {
                builder.javaClass
                    .getMethod("setShortCriticalText", String::class.java)
                    .invoke(builder, score)
            }
        }
        val notification = builder.build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
        return true
    }

    fun cancel(context: Context, matchId: String) {
        if (matchId.isBlank()) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId(matchId))
    }

    private fun notificationId(matchId: String): Int =
        0x46000000 or (matchId.hashCode() and 0x00ffffff)

    private fun Any?.asInt(): Int = when (this) {
        is Number -> toInt()
        else -> toString().toIntOrNull() ?: 0
    }

    private fun Any?.asBoolean(): Boolean = when (this) {
        is Boolean -> this
        else -> toString().equals("true", ignoreCase = true)
    }
}
