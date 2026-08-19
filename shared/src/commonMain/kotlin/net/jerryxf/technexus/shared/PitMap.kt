package net.jerryxf.technexus.shared

import kotlinx.serialization.Serializable

/**
 * Pit map geometry, from `GET /event/{key}/map`.
 *
 * ## Coordinate system
 *
 * Nexus documents only that **10 units is approximately 1 foot**. It does not
 * document the axis directions, so they were verified against the rendered
 * reference map Nexus publishes alongside the API examples:
 *
 * - Origin is **top-left**, **y increases downward**. Pit `A1` sits at
 *   `y = 1020` in a map `1300` tall and renders at the *bottom* of Nexus's own
 *   image; `A9` at `y = 220` renders at the top.
 * - `angle` is in **degrees, clockwise**. An arrow at `-90` renders pointing
 *   left, one at `90` points right.
 *
 * Both match screen conventions exactly, so a `Canvas` needs no axis flip and
 * no angle negation. That is convenient but not guaranteed by contract — if a
 * future map ever renders mirrored, this is the assumption to re-check first.
 *
 * ## Wire shape
 *
 * Nexus returns every collection as an **object keyed by id** — pits by pit
 * address, everything else by an opaque `a0` / `l1` / `r2` handle. Kotlin maps
 * bridge awkwardly to Swift dictionaries, so the wire types below are parsed
 * and then flattened into lists with the key folded in, the same way
 * [NexusEvent] is flattened into [EventSummary].
 *
 * Consumers should use [PitMap] and never touch the `*Wire` types.
 */
@Serializable
data class MapPoint(
    val x: Double = 0.0,
    val y: Double = 0.0
)

/**
 * Position, extent and rotation, shared by every element on the map.
 *
 * [position] is the **centre** of the element, not its origin. A renderer that
 * treats it as a top-left corner draws everything offset by half its own size,
 * which looks plausible on a grid of equally sized pits and wrong everywhere
 * else.
 */
data class MapGeometry(
    val position: MapPoint,
    val size: MapPoint,
    /** Clockwise degrees about [position]. Zero when Nexus omits it. */
    val angle: Double
)

/**
 * One pit.
 *
 * [team] is null for a pit that exists on the floor but has nobody assigned to
 * it. Nexus's own renderer draws those hatched with the address showing, which
 * is worth copying: an empty pit is a landmark when you're counting down a row.
 */
data class PitBox(
    /** Pit address, e.g. `A1`, `C12`. The wire key. */
    val address: String,
    val team: String?,
    val geometry: MapGeometry
)

/** A named region — `Pit admin`, `Inspection`, `EMT`, `Machine shop`. */
data class MapArea(
    val id: String,
    val label: String,
    val geometry: MapGeometry
)

/** Free text placed on the map — `Field`, `Practice field`, `Main gym`. */
data class MapLabel(
    val id: String,
    val text: String,
    val geometry: MapGeometry
)

/**
 * Nexus constrains arrow colour to four values. Modelled as an enum rather than
 * a string so the renderer can't be handed something it has no colour for.
 * Blue is the documented default when the field is absent.
 */
enum class ArrowColor { RED, BLUE, PURPLE, GRAY }

/**
 * An arrow indicating an entrance, exit or path.
 *
 * At `angle = 0` a single arrow points up and a double arrow points up *and*
 * down, per the Nexus schema.
 */
data class MapArrow(
    val id: String,
    val isDoubleEnded: Boolean,
    val color: ArrowColor,
    val geometry: MapGeometry
)

/** A wall, divider, or region teams can't walk through. */
data class MapWall(
    val id: String,
    val geometry: MapGeometry
)

/**
 * A parsed pit map, ready to render.
 *
 * [size] is the full extent of the map in the same units as every element.
 * Everything except [pits] can legitimately be empty — the schema marks
 * `areas`, `labels`, `arrows` and `walls` as nullable, and the simplest real
 * maps are a grid of pits and nothing else.
 */
data class PitMap(
    val size: MapPoint,
    val pits: List<PitBox>,
    val areas: List<MapArea>,
    val labels: List<MapLabel>,
    val arrows: List<MapArrow>,
    val walls: List<MapWall>
) {
    /**
     * Team number to pit address, derived from [pits].
     *
     * When a map exists it is strictly better than `GET /event/{key}/pits`:
     * same information, already fetched, and guaranteed consistent with what's
     * drawn on screen. The separate endpoint is only needed when there is no
     * map at all.
     */
    fun addressFor(team: String): String? =
        pits.firstOrNull { it.team == team }?.address

    fun pitFor(team: String): PitBox? =
        pits.firstOrNull { it.team == team }
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

/**
 * Geometry as it arrives. Every field carries a default: the Nexus schema does
 * not mark `position` or `size` as required, and a missing one should degrade
 * to a zero-sized element at the origin rather than failing the whole parse and
 * taking the map down with it.
 */
@Serializable
data class MapElementWire(
    val position: MapPoint = MapPoint(),
    val size: MapPoint = MapPoint(),
    val angle: Double? = null
) {
    val geometry: MapGeometry get() = MapGeometry(position, size, angle ?: 0.0)
}

@Serializable
data class PitWire(
    val position: MapPoint = MapPoint(),
    val size: MapPoint = MapPoint(),
    val angle: Double? = null,
    val team: String? = null
)

@Serializable
data class LabelledWire(
    val position: MapPoint = MapPoint(),
    val size: MapPoint = MapPoint(),
    val angle: Double? = null,
    val label: String = ""
)

@Serializable
data class ArrowWire(
    val position: MapPoint = MapPoint(),
    val size: MapPoint = MapPoint(),
    val angle: Double? = null,
    val type: String? = null,
    val color: String? = null
)

@Serializable
data class PitMapWire(
    val size: MapPoint = MapPoint(),
    val pits: Map<String, PitWire> = emptyMap(),
    val areas: Map<String, LabelledWire>? = null,
    val labels: Map<String, LabelledWire>? = null,
    val arrows: Map<String, ArrowWire>? = null,
    val walls: Map<String, MapElementWire>? = null
) {
    fun toPitMap(): PitMap = PitMap(
        size = size,
        // Sorted by address so the list has a stable order for the fallback
        // views. Draw order doesn't matter for pits — they don't overlap.
        pits = pits.map { (address, p) ->
            PitBox(address, p.team, MapGeometry(p.position, p.size, p.angle ?: 0.0))
        }.sortedBy { it.address },
        areas = areas.orEmpty().map { (id, a) ->
            MapArea(id, a.label, MapGeometry(a.position, a.size, a.angle ?: 0.0))
        },
        labels = labels.orEmpty().map { (id, l) ->
            MapLabel(id, l.label, MapGeometry(l.position, l.size, l.angle ?: 0.0))
        },
        arrows = arrows.orEmpty().map { (id, r) ->
            MapArrow(
                id = id,
                isDoubleEnded = r.type == "double",
                color = when (r.color) {
                    "red" -> ArrowColor.RED
                    "purple" -> ArrowColor.PURPLE
                    "gray" -> ArrowColor.GRAY
                    // Blue is the documented default, and is also where an
                    // unrecognised value lands. A new colour Nexus adds later
                    // should draw as an arrow, not vanish.
                    else -> ArrowColor.BLUE
                },
                geometry = MapGeometry(r.position, r.size, r.angle ?: 0.0)
            )
        },
        walls = walls.orEmpty().map { (id, w) -> MapWall(id, w.geometry) }
    )
}

/**
 * One row of `GET /event/{key}/pits`, which Nexus returns as team number to
 * address. Flattened for the same reason [EventSummary] is.
 */
data class PitAddress(
    val team: String,
    val address: String
)
