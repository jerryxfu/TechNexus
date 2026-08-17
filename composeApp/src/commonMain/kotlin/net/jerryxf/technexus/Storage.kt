package net.jerryxf.technexus

import com.russhwolf.settings.Settings
import net.jerryxf.technexus.shared.jsonConfig

/**
 * Centralized app settings. Add new settings by following the pattern:
 *   1. Add KEY_ and DEFAULT_ constants
 *   2. Add get/set methods
 *   3. Update UI in SettingsView.kt (Android) and SettingsView.swift (iOS)
 */
class AppSettings(private val _settings: () -> Settings) {
    private val settings = lazy { _settings() }
    fun getEventId(): String =
        settings.value.getStringOrNull(KEY_EVENT_ID) ?: DEFAULT_EVENT_ID

    fun setEventId(eventId: String) {
        settings.value.putString(KEY_EVENT_ID, eventId)
    }

    fun getTeamNumber(): String =
        settings.value.getStringOrNull(KEY_TEAM_NUMBER) ?: DEFAULT_TEAM_NUMBER

    fun setTeamNumber(teamNumber: String) {
        settings.value.putString(KEY_TEAM_NUMBER, teamNumber)
    }

    companion object {
        private const val KEY_EVENT_ID = "event_id"
        // A demo event, not a real one: Nexus purges past seasons, so any real key
        // hardcoded here 404s the moment that event ends. Demo events persist.
        private const val DEFAULT_EVENT_ID = "demo1815"

        private const val KEY_TEAM_NUMBER = "team_number"
        private const val DEFAULT_TEAM_NUMBER = "3990"
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
