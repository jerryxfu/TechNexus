package net.jerryxf.technexus

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat


const val NOTIFICATION_CHANNEL_ID = "LiveActivity"
private val matchNotificationStyle = NotificationCompat.ProgressStyle()
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(20))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(3))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(10))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(25))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(25))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(25))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(25))
    .addProgressSegment(NotificationCompat.ProgressStyle.Segment(30))

@SuppressLint("StaticFieldLeak")
private var notification: NotificationCompat.Builder? = null

fun startMatchLiveActivity(title: String) {
    notification = NotificationCompat.Builder(AndroidBridge.context, NOTIFICATION_CHANNEL_ID)
        .setContentTitle(title)
        .setSmallIcon(AndroidBridge.appIcon)
        .setOngoing(true)
        .setShowWhen(false)
        .setStyle(matchNotificationStyle.setProgress(0))

    update()
}

fun setMatchActivityProgress(state: MatchState) {
    notification?.setStyle(matchNotificationStyle.setProgress((state.totalElapsed * 100) / MatchState.MATCH_DURATION))
    notification?.setShortCriticalText(state.timeString())
    update()
}

@SuppressLint("MissingPermission")
private fun update() = with(NotificationManagerCompat.from(AndroidBridge.context)) {
    if (ActivityCompat.checkSelfPermission(
            AndroidBridge.context,
            Manifest.permission.POST_NOTIFICATIONS
        ) != PackageManager.PERMISSION_GRANTED
    ) {
        ActivityCompat.requestPermissions(
            AndroidBridge.activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            0
        )
        return@with
    }
    notify(1, notification?.build() ?: return@with)
}
