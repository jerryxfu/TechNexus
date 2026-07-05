package net.jerryxf.technexus

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        AndroidBridge.setup(
            this,
            R.drawable.ic_launcher_foreground
        )

        setContent {
            App()
        }
    }

    override fun onDestroy() {
        net.jerryxf.technexus.onDestroy()
        super.onDestroy()
    }
}
