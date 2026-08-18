package net.jerryxf.technexus

import com.russhwolf.settings.Settings
import net.jerryxf.technexus.shared.jsonConfig

/**
 * Centralized app settings. Add new settings by following the pattern:
 *   1. Add KEY_ and DEFAULT_ constants
 *   2. Add get/set methods
 *   3. Remove the key in [AppSettings.resetToDefaults]
 *   4. Update UI in SettingsView.kt (Android) and SettingsView.swift (iOS)
 */
class AppSettings(private val _settings: () -> Settings) {
    private val settings = lazy { _settings() }
    fun getEventId(): String =
        settings.value.getStringOrNull(KEY_EVENT_ID) ?: DEFAULT_EVENT_ID

    fun setEventId(eventId: String) {
        settings.value.putString(KEY_EVENT_ID, eventId)
    }

    /** Empty is a valid value and means "no team" = highlighting is simply off. */
    fun getTeamNumber(): String =
        settings.value.getStringOrNull(KEY_TEAM_NUMBER) ?: DEFAULT_TEAM_NUMBER

    fun setTeamNumber(teamNumber: String) {
        settings.value.putString(KEY_TEAM_NUMBER, teamNumber)
    }

    /**
     * Removes the stored overrides rather than writing the defaults back, so the
     * getters fall through to DEFAULT_* on their own. One less place for a default
     * to be spelled out.
     *
     * Deliberately not [Settings.clear]. On iOS this instance is backed by
     * `NSUserDefaults.standardUserDefaults`, which is shared with SwiftUI's
     * `@AppStorage` and with keys Apple owns. Clearing it would reach well past
     * this app's settings. Named keys only.
     *
     * iOS-only preferences live in `@AppStorage` and are not reachable from here;
     * `SettingsView.swift` resets those alongside this call.
     */
    fun resetToDefaults() {
        settings.value.remove(KEY_EVENT_ID)
        settings.value.remove(KEY_TEAM_NUMBER)
    }

    companion object {
        private const val KEY_EVENT_ID = "event_id"

        // A demo event, not a real one: Nexus purges past seasons, so any real key
        // hardcoded here 404s the moment that event ends. Demo events persist.
        private const val DEFAULT_EVENT_ID = "demo1815"

        private const val KEY_TEAM_NUMBER = "team_number"

        private const val DEFAULT_TEAM_NUMBER = ""
    }
}

object SettingsManager {
    val settings = AppSettings { createSettings() }
}

expect fun createSettings(): Settings

expect fun saveInternal(name: String, data: String)

inline fun <reified T> save(name: String, data: T) = saveInternal(name, jsonConfig.encodeToString(data))

expect fun loadInternal(name: String): String?

inline fun <reified T> load(name: String) = loadInternal(name)?.let { jsonConfig.decodeFromString<T>(it) }

expect fun exists(name: String): Boolean

expect fun delete(name: String): Boolean
