package de.fcteugn.jugend

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = android.app.Application::class)
class LiveMatchPushTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager

    @Before
    fun prepare() {
        context = RuntimeEnvironment.getApplication()
        manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        context.getSharedPreferences("fc_teugn_live_event_alerts", Context.MODE_PRIVATE)
            .edit().clear().commit()
        manager.cancelAll()
    }

    private fun values(event: String = "goal-1", type: String = "HOME_GOAL") = mapOf(
        "liveMatch" to "true", "matchId" to "match-1", "entityId" to event,
        "entityType" to "LiveTickerEvent", "eventType" to type,
        "homeTeam" to "TSV Langquaid", "awayTeam" to "FC Teugn",
        "homeScore" to "1", "awayScore" to "0", "minute" to "12",
        "status" to "Live", "actionUrl" to "/matches/match-1?tab=live",
        "title" to "Player name must never appear", "body" to "Private player text",
    )

    private fun receive(values: Map<String, String>) {
        val intent = Intent("com.google.android.c2dm.intent.RECEIVE")
        values.forEach { (key, value) -> intent.putExtra(key, value) }
        LiveMatchPushReceiver().onReceive(context, intent)
    }

    @Test
    fun goalPushCreatesAudibleEventAlongsideSilentScore() {
        receive(values())
        val notifications = manager.activeNotifications
        assertEquals(2, notifications.size)
        val live = notifications.single { it.notification.channelId == "fc_teugn_live_match" }
        val alert = notifications.single { it.notification.channelId == "fc_teugn_live_events" }
        assertNull(manager.getNotificationChannel(live.notification.channelId).sound)
        val channel = manager.getNotificationChannel(alert.notification.channelId)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
        assertEquals(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), channel.sound)
        assertTrue(channel.shouldVibrate())
        assertEquals("Tor für TSV Langquaid · 1:0", alert.notification.extras.getString(Notification.EXTRA_TITLE))
        assertFalse(alert.notification.extras.toString().contains("Player name"))
        assertFalse(alert.notification.extras.toString().contains("Private player"))
        assertEquals(0, alert.notification.flags and Notification.FLAG_ONGOING_EVENT)
        val open = shadowOf(alert.notification.contentIntent).savedIntent
        assertEquals("/matches/match-1?tab=live", open.getStringExtra("fc_teugn_action_url"))
    }

    @Test
    fun eachNewEventAlertsButRetryAfterDismissalDoesNot() {
        assertTrue(LiveMatchEventNotification.show(context, values()))
        manager.cancelAll()
        assertFalse(LiveMatchEventNotification.show(context, values()))
        assertEquals(0, manager.activeNotifications.size)
        assertTrue(LiveMatchEventNotification.show(context, values("goal-2", "AWAY_GOAL")))
        assertTrue(LiveMatchEventNotification.show(context, values("end", "MATCH_END")))
        assertEquals(2, manager.activeNotifications.size)
        assertEquals(2, manager.activeNotifications.map { it.tag }.toSet().size)
    }

    @Test
    fun scoreRefreshDoesNotCreateOrReplaceEventAlert() {
        receive(values())
        val alert = manager.activeNotifications.single { it.tag != null }
        repeat(3) { LiveMatchNotification.update(context, values() + ("minute" to "13")) }
        assertEquals(2, manager.activeNotifications.size)
        assertEquals(alert.notification.`when`, manager.activeNotifications.single { it.tag != null }.notification.`when`)
    }

    @Test
    fun commentsAndUnrelatedMessagesDoNotAlert() {
        assertFalse(LiveMatchEventNotification.show(context, values(type = "COMMENT")))
        assertFalse(LiveMatchEventNotification.show(context, values() + ("entityType" to "Match")))
        assertFalse(LiveMatchEventNotification.show(context, values() - "entityId"))
        assertEquals(0, manager.activeNotifications.size)
    }

    @Test
    fun startAndEndHaveExplicitLabelsAndLegacyPushStillAlerts() {
        assertTrue(LiveMatchEventNotification.show(context, values("start", "MATCH_START")))
        assertTrue(LiveMatchEventNotification.show(context, values("end", "MATCH_END")))
        assertTrue(LiveMatchEventNotification.show(context, values("legacy") - "eventType"))
        val titles = manager.activeNotifications.map { it.notification.extras.getString(Notification.EXTRA_TITLE) }
        assertTrue(titles.containsAll(listOf("Anpfiff · 1:0", "Abpfiff · 1:0", "Liveticker · 1:0")))
    }

    @Test
    @Config(sdk = [33])
    fun notificationPermissionIsRespected() {
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        receive(values())
        assertEquals(0, manager.activeNotifications.size)
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        receive(values())
        assertEquals(2, manager.activeNotifications.size)
    }
}
