package de.fcteugn.jugend

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "de.fcteugn.jugend/notifications"
        private const val UPDATE_CHANNEL = "de.fcteugn.jugend/app_update"
        private const val NOTIFICATION_CHANNEL_ID = "fc_teugn_important"
        private const val ACTION_URL_EXTRA = "fc_teugn_action_url"
    }

    private var notificationMethodChannel: MethodChannel? = null
    private var updateMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        createNotificationChannel()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> {
                        val title = call.argument<String>("title") ?: "FC Teugn Talents"
                        val body = call.argument<String>("body") ?: ""
                        val actionUrl = call.argument<String>("actionUrl")
                        result.success(showNotification(title, body, actionUrl))
                    }
                    "getInitialPushAction" -> {
                        result.success(consumePushAction(intent))
                    }
                    else -> result.notImplemented()
                }
            }
        }
        updateMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "APK-Pfad fehlt.", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumePushAction(intent)?.let { actionUrl ->
            notificationMethodChannel?.invokeMethod("notificationOpened", actionUrl)
        }
    }

    private fun consumePushAction(sourceIntent: Intent?): String? {
        val actionUrl = sourceIntent?.getStringExtra(ACTION_URL_EXTRA)
        sourceIntent?.removeExtra(ACTION_URL_EXTRA)
        return actionUrl
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Wichtige Vereinsnachrichten",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Termine, Nominierungen, Spieländerungen und wichtige Hinweise"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            val allowedDirectory = File(cacheDir, "app_updates").canonicalFile
            val apk = File(path).canonicalFile
            val insideUpdateDirectory = apk.path.startsWith(
                allowedDirectory.path + File.separator,
            )
            if (!insideUpdateDirectory || !apk.isFile) {
                result.error("invalid_apk", "Die APK-Datei ist ungültig.", null)
                return
            }

            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
                startActivity(settingsIntent)
                result.success("permissionRequired")
                return
            }

            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk,
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("FC Teugn Talents Update", apkUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (installIntent.resolveActivity(packageManager) == null) {
                result.success("unsupported")
                return
            }
            startActivity(installIntent)
            result.success("launched")
        } catch (error: Exception) {
            result.error("install_failed", error.message, null)
        }
    }

    private fun showNotification(title: String, body: String, actionUrl: String?): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val notificationId = (System.currentTimeMillis() and 0x7fffffff).toInt()
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            actionUrl?.takeIf { it.isNotBlank() }?.let {
                putExtra(ACTION_URL_EXTRA, it)
            }
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_fc_teugn)
            .setColor(0xffffe600.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setPriority(Notification.PRIORITY_HIGH)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, builder.build())
        return true
    }
}
