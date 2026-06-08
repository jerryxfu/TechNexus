package net.jerryxf.technexus

import android.content.Context
import com.russhwolf.settings.Settings
import com.russhwolf.settings.SharedPreferencesSettings
import java.io.File

actual fun createSettings(): Settings {
    val sharedPreferences = AndroidBridge.context.getSharedPreferences("app_settings", Context.MODE_PRIVATE)
    return SharedPreferencesSettings(sharedPreferences)
}

actual fun saveInternal(name: String, data: String) = File(AndroidBridge.filesDir, name).writeText(data)

actual fun loadInternal(name: String): String? = try {
    File(AndroidBridge.filesDir, name).readText()
} catch (e: Exception) {
    e.printStackTrace()
    null
}

actual fun exists(name: String) = File(AndroidBridge.filesDir, name).exists()

actual fun delete(name: String) = File(AndroidBridge.filesDir, name).delete()
