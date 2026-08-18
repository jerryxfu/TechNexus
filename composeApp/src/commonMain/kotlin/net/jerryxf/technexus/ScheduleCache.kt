package net.jerryxf.technexus

import kotlinx.serialization.Serializable
import net.jerryxf.technexus.shared.Event

/**
 * The last successfully fetched schedule, with the wall-clock time it arrived.
 *
 * [fetchedAtMs] is the *client's* fetch time, not [Event.dataAsOfTime]. The two
 * track each other while everything is healthy, but they answer different
 * questions, and the one the UI needs is "when did this phone last hear from the
 * server". That is the value that freezes and grows while you are stood in a
 * venue with no signal. `dataAsOfTime` would freeze too, but it would keep
 * claiming to be Nexus's opinion of freshness when really it is a fossil of one.
 */
@Serializable
data class CachedSchedule(
    val event: Event,
    val fetchedAtMs: Long
)

/**
 * Written to a file in Application Support rather than to [AppSettings].
 *
 * A real event runs to 140 matches (less), which is roughly 47 KB of JSON. That is
 * past the size where `NSUserDefaults` is the right home for a blob, and
 * [saveInternal] already writes to Application Support on both platforms.
 */
private const val CACHE_NAME = "last_schedule.json"

/**
 * Never throws. A cache write failing is not a reason for a refresh that
 * otherwise succeeded to look like a failure.
 */
fun saveCachedSchedule(event: Event, fetchedAtMs: Long) {
    try {
        save(CACHE_NAME, CachedSchedule(event, fetchedAtMs))
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

/**
 * Never throws. Returns null if there is nothing stored, or if what is stored
 * no longer decodes, which is what happens the first time the shape of [Event]
 * changes under a build that still has an old file on disk. Callers treat that
 * identically to "no cache", so a model change costs one cold start rather than a crash loop.
 *
 * The caller must check [CachedSchedule.event] against the currently selected
 * event before showing it. This function deliberately does not, because it has
 * no business reading settings.
 */
fun loadCachedSchedule(): CachedSchedule? =
    try {
        load<CachedSchedule>(CACHE_NAME)
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }

fun clearCachedSchedule() {
    try {
        delete(CACHE_NAME)
    } catch (e: Exception) {
        e.printStackTrace()
    }
}
