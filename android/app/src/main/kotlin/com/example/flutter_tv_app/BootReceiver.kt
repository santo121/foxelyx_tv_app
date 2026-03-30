package com.example.flutter_tv_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Starts MainActivity when the device (TV) finishes booting.
 * Uses full-screen intent on Android 10+ to comply with background activity restrictions.
 */
class BootReceiver : android.content.BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != "android.intent.action.QUICKBOOT_POWERON") return

        // Delay launch so the TV display/launcher is ready (some OEMs need this)
        val delayMs = 3000L
        Handler(Looper.getMainLooper()).postDelayed({
            launchAppOnBoot(context)
        }, delayMs)
    }

    private fun launchAppOnBoot(context: Context) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
            addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+: background activity start is restricted; use full-screen intent
            useFullScreenIntent(context, launchIntent)
        } else {
            context.startActivity(launchIntent)
        }
    }

    private fun useFullScreenIntent(context: Context, launchIntent: Intent) {
        val pendingIntent = PendingIntent.getActivity(
            context,
            BOOT_REQUEST_CODE,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App launch",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setShowBadge(false)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(context.applicationInfo.loadLabel(context.packageManager).toString())
            .setContentText("Opening…")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(BOOT_NOTIFICATION_ID, notification)
            pendingIntent.send()
        } catch (_: Exception) { }
        // Some TV OEMs allow direct start right after boot; try as fallback
        try {
            context.startActivity(launchIntent)
        } catch (_: Exception) { }
    }

    companion object {
        private const val CHANNEL_ID = "boot_launch"
        private const val BOOT_REQUEST_CODE = 1001
        private const val BOOT_NOTIFICATION_ID = 1001
    }
}
