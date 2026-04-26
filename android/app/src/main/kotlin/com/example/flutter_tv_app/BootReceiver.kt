package com.example.flutter_tv_app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Best-effort app launch when a TV finishes booting.
 *
 * Some Google TV/Android TV devices block background launches for regular apps.
 * This receiver first attempts direct launch, and if blocked, posts a visible
 * notification with an explicit content intent so the user can open quickly.
 */
class BootReceiver : android.content.BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        // Delay launch so the TV display/launcher is ready (some OEMs need this)
        val delayMs = 3000L
        Handler(Looper.getMainLooper()).postDelayed({
            launchAppOnBoot(context)
        }, delayMs)
    }

    private fun launchAppOnBoot(context: Context) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        } ?: return

        // Primary path for TVs that allow boot-time activity launches.
        try {
            context.startActivity(launchIntent)
            return
        } catch (_: Exception) {
            // Fall through and provide user-visible recovery.
        }

        postOpenAppNotification(context, launchIntent)
    }

    private fun postOpenAppNotification(context: Context, launchIntent: Intent) {
        val channelId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = CHANNEL_ID
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(
                android.app.NotificationChannel(
                    channelId,
                    "Boot launch",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
            channelId
        } else {
            ""
        }

        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            BOOT_REQUEST_CODE,
            launchIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(context.applicationInfo.loadLabel(context.packageManager).toString())
            .setContentText("Tap to open after startup")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        NotificationManagerCompat.from(context).notify(BOOT_NOTIFICATION_ID, builder.build())
    }

    companion object {
        private const val CHANNEL_ID = "boot_launch"
        private const val BOOT_REQUEST_CODE = 1001
        private const val BOOT_NOTIFICATION_ID = 1001
    }
}
