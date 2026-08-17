plugins {
    alias(libs.plugins.kotlinJvm)
    alias(libs.plugins.ktor)
    alias(libs.plugins.kotlinSerialization)
    application
}

kotlin { jvmToolchain(21) }

group = "net.jerryxf.technexus.server"
version = "1.0.0"

application {
    mainClass.set("net.jerryxf.technexus.server.ApplicationKt")

    val isDevelopment: Boolean = project.ext.has("development")
    applicationDefaultJvmArgs = listOf("-Dio.ktor.development=$isDevelopment")
}

dependencies {
    implementation(projects.shared)
    implementation(libs.logback)
    implementation(libs.exposed.core)
    implementation(libs.exposed.jdbc)
    implementation(libs.exposed.json)
    implementation(libs.exposed.datetime)
    implementation(libs.exposed.postgres)
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.cio)
    implementation(libs.ktor.server.contentNegotiation)
    implementation(libs.ktor.server.cors)
    implementation(libs.ktor.server.compression.core)
    implementation(libs.ktor.server.compression.zstd)
    implementation(libs.ktor.server.caching)
    implementation(libs.ktor.server.forwarded)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.cio)
    implementation(libs.ktor.client.contentNegotiation)
    implementation(libs.ktor.client.encoding)
    implementation(libs.ktor.serialization.json)
}
