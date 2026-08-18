package net.jerryxf.technexus.shared

class MatchId {
    private constructor(type: MatchType, number: UShort) {
        this.type = type
        this.number = number
    }

    val type: MatchType
    val number: UShort

    val isPlayoff: Boolean
        get() = type == MatchType.PLAYOFF || type == MatchType.FINAL

    /**
     * The Blue Alliance match key, or null when we can't build a correct one.
     *
     * **Playoffs return null on purpose.** TBA keys elimination matches by
     * bracket position — `2024casf_sf7m1`, `2024casf_f1m2` — while Nexus numbers
     * them sequentially as `Playoff 7`, `Final 1`. There is no arithmetic that
     * turns one into the other without modelling the double-elimination bracket,
     * and the bracket changed shape in 2023 and will change again.
     *
     * Returning null is the honest answer. The previous version built
     * `<event>_em7`, which is not a key TBA has ever used, so the request 404'd
     * and the failure looked like a missing match rather than a malformed
     * request.
     *
     * Alliance numbers, which is what playoff matches were wanted for, now come
     * from Nexus directly — see `Alliances.kt` on the server.
     */
    fun getTBAKey(event: String): String? {
        val short = type.tbaShort ?: return null
        return event + "_" + short + number
    }

    /**
     * [tbaShort] is null where TBA has no equivalent: it doesn't publish
     * practice matches at all, and elimination keys can't be derived (above).
     */
    enum class MatchType(val short: String, val tbaShort: String?) {
        PRACTICE("p", null),
        QUALIFICATION("q", "qm"),
        PLAYOFF("sf", null),
        FINAL("f", null)
    }

    companion object {
        /**
         * Parses a Nexus label. The documented set is `Practice N`,
         * `Qualification N`, `Qualification N Replay`, `Playoff N` and
         * `Final N`.
         *
         * `Playoff` and `Final` used to be missing — the enum had an
         * `ELIMINATION` case with a `// TODO : check` beside it, and Nexus never
         * emits that word — so every playoff and final label parsed to null.
         */
        fun fromLabel(label: String): MatchId? {
            val lbl = label.lowercase()

            val type = when {
                lbl.startsWith("practice") -> MatchType.PRACTICE
                lbl.startsWith("qualification") -> MatchType.QUALIFICATION
                lbl.startsWith("playoff") -> MatchType.PLAYOFF
                lbl.startsWith("final") -> MatchType.FINAL
                else -> return null
            }

            // Second token, so "Qualification 24 Replay" parses as 24 like its
            // original rather than failing on the trailing word.
            val number = label.split(" ").getOrNull(1)?.toUShortOrNull() ?: return null

            return MatchId(type, number)
        }

        /**
         * Parses a short form such as `q24`.
         *
         * The number used to be read with `subSequence(1, length - 1)`, which
         * drops the *last* character as well as the first: `q10` parsed as
         * qualification **1**, `q24` as 2. Single-digit matches were correct,
         * which is why it survived. It is `substring(1)` — everything after the
         * type letter.
         */
        fun fromShort(short: String): MatchId? {
            val lbl = short.lowercase()
            if (lbl.isEmpty()) return null

            val type = when (lbl[0]) {
                'p' -> MatchType.PRACTICE
                'q' -> MatchType.QUALIFICATION
                'e' -> MatchType.PLAYOFF // legacy spelling, kept so old links resolve
                else -> return null
            }

            val number = lbl.substring(1).toUShortOrNull() ?: return null

            return MatchId(type, number)
        }
    }
}
