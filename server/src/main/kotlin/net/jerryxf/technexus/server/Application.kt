package net.jerryxf.technexus.server

import io.ktor.client.*
import io.ktor.client.plugins.cache.*
import io.ktor.client.plugins.cache.storage.*
import io.ktor.client.plugins.compression.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.cio.*
import io.ktor.server.engine.*
import io.ktor.server.plugins.cachingheaders.*
import io.ktor.server.plugins.compression.*
import io.ktor.server.plugins.compression.zstd.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.plugins.forwardedheaders.*
import kotlinx.coroutines.runBlocking
import net.jerryxf.technexus.shared.jsonConfig
import org.jetbrains.exposed.v1.jdbc.Database
import java.nio.file.Files
import java.nio.file.Paths
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation as ClientContentNegotiation
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation as ServerContentNegotiation

val server = embeddedServer(CIO, 6867, "0.0.0.0", module = Application::module)

fun main() {
    server.start(true)
}

fun Application.module() {
    // First, so a missing environment variable or an unreachable database stops the server here rather than surfacing as a 500 during a match.
    connectDatabase()

    install(CORS) {
        anyHost()
        maxAgeInSeconds = 3600
    }
    install(ServerContentNegotiation) {
        json(jsonConfig)
    }
    install(Compression) {
        gzip()
        deflate()
        identity()
        zstd()
    }
    install(CachingHeaders)
    install(XForwardedHeaders)

    server.monitor.subscribe(ApplicationStopped) { client.close() }

    batteries()
    events()
    matches()
}

/**
 * Connects Postgres and creates any missing tables.
 *
 * [Database.connect] only opens a connection, it never creates schema, which is
 * why `/batteries` returned `relation "batteries" does not exist` against a
 * database that had never been set up by hand. [createSchema] closes that gap.
 *
 * Failures propagate. A server that starts without its database only moves the
 * error to a request handler, where it reads as a bug in the app.
 */
private fun Application.connectDatabase() {
    Database.connect(
        "jdbc:postgresql://${Config.dbUrl}",
        "org.postgresql.Driver",
        Config.dbUser,
        Config.dbPassword
    )
    runBlocking { createSchema() }
    log.info("Database connected, schema verified")
}

val client = HttpClient {
    install(ClientContentNegotiation) {
        json(jsonConfig)
    }
    install(ContentEncoding) {
        deflate()
        gzip()
        identity()
    }
    install(HttpCache) {
        // Honours frc.nexus and TBA cache headers, so repeat requests inside a
        // window never leave the box. TECHNEXUS_CACHE_DIR exists because a
        // container's working directory is frequently read-only.
        publicStorage(
            FileStorage(
                Files.createDirectories(
                    Paths.get(System.getenv("TECHNEXUS_CACHE_DIR") ?: "ktorCache")
                ).toFile()
            )
        )
    }
}
