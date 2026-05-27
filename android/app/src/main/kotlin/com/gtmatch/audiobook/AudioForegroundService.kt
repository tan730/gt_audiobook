package com.gtmatch.audiobook

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class AudioForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(intent?.getStringExtra("title") ?: "正在播放")
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GT听书",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("GT听书")
            .setContentText(title)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setChannelId(CHANNEL_ID)
        }

        return builder.build()
    }

    companion object {
        const val CHANNEL_ID = "gt_audiobook_foreground"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.gtmatch.audiobook.START"
        const val ACTION_STOP = "com.gtmatch.audiobook.STOP"
        const val EXTRA_TITLE = "title"
    }
}
