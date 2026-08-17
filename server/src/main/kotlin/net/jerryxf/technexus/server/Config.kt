package net.jerryxf.technexus.server

/**
 * Server configuration, read from the environment.
 *
 * Every value is required and there is no fallback file. A missing variable
 * fails at startup naming all of them at once, rather than throwing an
 * `IndexOutOfBoundsException` from line four of a text file or surfacing on the
 * first request that happens to need it.
 *
 * Reading from the environment is what makes a container deploy possible without
 * baking secrets into an image, and it means rotating a key is a redeploy rather
 * than an SSH session.
 */
object Config {

    /** frc.nexus API key, from https://frc.nexus/api */
    val nexusApiKey: String

    /** The Blue Alliance key, used for match scores. */
    val tbaApiKey: String

    /** Postgres host and database, e.g. `localhost:5432/technexus`. */
    val dbUrl: String
    val dbUser: String
    val dbPassword: String

    init {
        val missing = mutableListOf<String>()

        fun read(name: String): String {
            val value = System.getenv(name)?.takeIf(String::isNotBlank)
            if (value == null) missing += name
            return value.orEmpty()
        }

        nexusApiKey = read("NEXUS_API_KEY")
        tbaApiKey = read("TBA_API_KEY")
        dbUrl = read("DB_URL")
        dbUser = read("DB_USER")
        dbPassword = read("DB_PASSWORD")

        if (missing.isNotEmpty()) {
            error("Missing required environment variables: ${missing.joinToString(", ")}")
        }
    }
}
