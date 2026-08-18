package net.jerryxf.technexus

import androidx.compose.ui.graphics.Color
import io.ktor.client.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.compression.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.serialization.kotlinx.json.*
import net.jerryxf.technexus.shared.jsonConfig
import kotlin.time.Duration.Companion.seconds

/**
 * The shared HTTP client.
 *
 * **No `HttpCache`, deliberately.** It used to be installed here and it froze the `Cache-Control`.
 * The server sent 15s, 300s, 3600s and *no header at all* all
 * arrived as `max-age=14400`, and `HttpCache` obeyed it faithfully. The 15s poll
 * loop kept running, the Live Activity kept logging an update every 15s, and the
 * response came out of an in-memory store for four hours without a single request
 * leaving the device. Schedule, Dynamic Island and Live Activity all froze
 * together because all three read the same `Event`.
 *
 * The zone setting is fixed, but the plugin does not come back:
 *
 * - Every endpoint here is either live (events, matches) or mutable (batteries).
 * - `/event/{key}` is cached 15s at the edge and the client polls every 15s.
 *
 * Edge caching via `s-maxage` from `Events.kt`.
 *
 * [HttpTimeout] is not optional. Without it the engine default applies,
 * which on Darwin is 60 seconds. One hung request on bad venue Wi-Fi stalls the
 * poll loop for a minute while every log line still looks healthy.
 */
val client = HttpClient {
    install(ContentNegotiation) {
        json(jsonConfig)
    }
    install(ContentEncoding) {
        deflate()
        gzip()
        identity()
        mode = ContentEncodingConfig.Mode.All
    }
    install(HttpTimeout) {
        requestTimeoutMillis = 10_000
        connectTimeoutMillis = 5_000
        socketTimeoutMillis = 10_000
    }
}

data class StatusConfig(val statusKey: String, val label: String, val color: Color)

val onField = StatusConfig("on field", "Done", Color.Gray)
val onDeck = StatusConfig("on deck", "On deck", Color.Blue)
val nowQueue = StatusConfig("now queuing", "Now queuing", Color.Yellow)
val queueSoon = StatusConfig("queuing soon", "Queuing soon", Color.Magenta)
val refreshInterval = 15.seconds
