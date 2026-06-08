package net.jerryxf.technexus

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        AndroidBridge.setup(
            this,
            R.drawable.ic_launcher_foreground
        )

        val requestPermissionLauncher = registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { isGranted ->
            if (!isGranted)
                println("no notifs for you")
        }

        requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)

        (applicationContext.getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Live activities",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )

        setContent {
            App()
        }
    }

    override fun onDestroy() {
        dispose()
        super.onDestroy()
    }
}
