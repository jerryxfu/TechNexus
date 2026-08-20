import ComposeApp
import SwiftUI

/// Draws a Nexus pit map.
///
/// Pure rendering. `zoom` and `pan` are inputs so the caller decides whether
/// the map is a static preview or something you can move around.
///
/// Zoom is a parameter and not `.scaleEffect` because scaling the rendered view magnifies text as pixels.
/// Feeding the zoom back into the transform makes `Canvas` re-resolve every label at its new size,
/// so a team number is as crisp at 4x as at 1x. It costs a redraw per gesture frame,
/// which for a few hundred rectangles is not close to a problem.
struct PitMapCanvas: View {
    let map: PitMap

    /// Team number to colour, from `HighlightedTeamsStore`. Drawn as the pit's **fill**, because it answers "which one is mine".
    var highlights: [String: Color] = [:]

    /// Team number to live match status, from `PitStatusHighlights`.
    /// Drawn as the pit's **outline** plus a second line of text, because it answers "what's happening".
    ///
    /// Kept on a separate channel from `highlights` rather than merged into one dictionary so a pit can carry both at once:
    /// your team, on field, reads as your colour ringed in green instead of forcing a choice between them.
    var statuses: [String: TeamStatus] = [:]

    /// Whether the view constrains itself to the map's own aspect ratio.
    ///
    /// True for the inline preview, which sits in a `ScrollView` and has to declare a height.
    /// **False full screen**, where the canvas should take the whole page and do its own fit internally.
    /// Leaving it on there fits the map twice, once into the aspect box and again inside `draw`,
    /// and the screen's pan clamping then computes against a size the canvas never actually had.
    var fitsAspectRatio: Bool = true

    /// Margin the map is fitted inside, in points, at `zoom == 1`.
    ///
    /// Zero for the inline preview, which already has real padding around it.
    /// Non-zero full screen, where without it the map sits flush against both
    /// bezels on its limiting axis while floating in letterbox on the other.
    var fitInset: CGSize = .zero

    /// Extra magnification on top of fit-to-view. `1` fits the whole map.
    var zoom: CGFloat = 1

    /// Pan in points, applied after scaling.
    var pan: CGSize = .zero

    /// Pit and area text is dropped below this on-screen scale, where it would render as illegible smudges rather than information.
    private let textVisibilityThreshold: Double = 0.14

    var body: some View {
        if fitsAspectRatio {
            // Nexus maps vary widely in shape, so the container follows the data rather than a fixed ratio.
            canvas.aspectRatio(aspect, contentMode: .fit)
        } else {
            canvas
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            draw(into: context, viewSize: size)
        }
    }

    private var aspect: CGFloat {
        guard map.size.x > 0, map.size.y > 0 else { return 1 }
        return map.size.x / map.size.y
    }

    // MARK: - Transform

    private func draw(into context: GraphicsContext, viewSize: CGSize) {
        let w = map.size.x
        let h = map.size.y
        guard w > 0, h > 0, viewSize.width > 0, viewSize.height > 0 else { return }

        let scale = Self.fitScale(mapSize: map.size, viewSize: viewSize, inset: fitInset) * zoom

        var canvas = context
        // Anchor the map's centre to the view's centre, so zoom magnifies about
        // the middle of what you're looking at rather than the top-left corner.
        canvas.translateBy(
            x: viewSize.width / 2 + pan.width,
            y: viewSize.height / 2 + pan.height
        )
        canvas.scaleBy(x: scale, y: scale)
        canvas.translateBy(x: -w / 2, y: -h / 2)

        // Nexus units are screen-oriented: y down, angles clockwise, so no axis flip is needed here. See the note in `PitMap.kt`.
        let showsText = scale > textVisibilityThreshold

        drawWalls(in: canvas)
        drawAreas(in: canvas, showsText: showsText)
        drawPits(in: canvas, showsText: showsText)
        drawArrows(in: canvas)
        drawLabels(in: canvas, showsText: showsText)
    }

    /// The scale at which the whole map fits `viewSize`, less `inset` on each side.
    ///
    /// Static and shared because `PitMapScreen` needs the identical number for its pan clamping.
    /// The inset is a parameter rather than something the caller pre-subtracts from `viewSize`,
    /// because the canvas still has to *draw* across the full surface and a map fitted into a smaller
    /// box but drawn on a smaller box too can't be panned to its margin when you zoom in.
    ///
    /// Per-axis, because the two are not the same problem: the side margin is the one you see on a portrait phone,
    /// where the map's own aspect ratio already leaves plenty of room above and below.
    static func fitScale(
        mapSize: MapPoint,
        viewSize: CGSize,
        inset: CGSize = .zero
    ) -> CGFloat {
        guard mapSize.x > 0, mapSize.y > 0 else { return 1 }
        let width = max(1, viewSize.width - inset.width * 2)
        let height = max(1, viewSize.height - inset.height * 2)
        return min(width / mapSize.x, height / mapSize.y)
    }

    /// Runs `body` in a context translated to the element's centre and rotated by its angle, handing back a rect centred on the origin.
    /// `GraphicsContext` is a value type, so the copy isolates the transform and there is nothing to restore afterwards.
    private func inElement(
        _ geometry: MapGeometry,
        _ context: GraphicsContext,
        _ body: (GraphicsContext, CGRect) -> Void
    ) {
        var layer = context
        layer.translateBy(x: geometry.position.x, y: geometry.position.y)
        if geometry.angle != 0 {
            layer.rotate(by: .degrees(geometry.angle))
        }
        // `position` is the centre, not the origin.
        let rect = CGRect(
            x: -geometry.size.x / 2,
            y: -geometry.size.y / 2,
            width: geometry.size.x,
            height: geometry.size.y
        )
        body(layer, rect)
    }

    // MARK: - Layers, back to front

    private func drawWalls(in context: GraphicsContext) {
        for wall in map.walls {
            inElement(wall.geometry, context) { layer, rect in
                layer.fill(Path(rect), with: .color(Color(.systemGray3)))
            }
        }
    }

    private func drawAreas(in context: GraphicsContext, showsText: Bool) {
        for area in map.areas {
            inElement(area.geometry, context) { layer, rect in
                let shape = Path(
                    roundedRect: rect,
                    cornerRadius: min(8, rect.width / 8)
                )
                layer.fill(shape, with: .color(Color(.systemGray5)))
                layer.stroke(
                    shape,
                    with: .color(Color(.systemGray3)),
                    lineWidth: 2
                )
                guard showsText, !area.label.isEmpty else { return }
                drawText(
                    area.label,
                    in: layer,
                    rect: rect,
                    // Fixed sizes are in map units, not points because this is geometry inside a scaled context,
                    // not typography, so Dynamic Type would fight the drawing rather than serve it.
                    size: 24,
                    weight: .medium,
                    color: .secondary
                )
            }
        }
    }

    /// One pit with its colours already decided.
    /// Resolved up front so the passes below cannot disagree about what a pit looks like.
    /// Splitting the draw into passes is only safe if every pass is reading the same answer.
    private struct StyledPit {
        let pit: PitBox
        let fill: Color
        let outline: Color
        let outlineWidth: CGFloat
        let status: TeamStatus?
        let textWeight: Font.Weight
        let textColor: Color

        /// Highlighted or status-bearing. Strokes after the plain pits, so where two borders meet the one that means something is on top.
        let isEmphasised: Bool
    }

    private func style(for pit: PitBox) -> StyledPit {
        let highlight = pit.team.flatMap { highlights[$0] }
        let status = pit.team.flatMap { statuses[$0] }
        let statusColor = status?.color
        let isAssigned = pit.team != nil

        // Status outranks the personal highlight on the outline: it is the thing that changes,
        // and a pit that is both keeps its fill colour so it stays findable either way.
        let outline = statusColor ?? highlight

        return StyledPit(
            pit: pit,
            // An unassigned pit stays visible but recessive. It's a landmark when you're counting down a row,
            // so hiding it would make the map harder to walk, not cleaner.
            fill: highlight?.opacity(0.28)
                ?? statusColor?.opacity(0.16)
                ?? (isAssigned
                    ? Color(.secondarySystemGroupedBackground)
                    : Color(.systemGray6)),
            outline: outline ?? Color(.systemGray3),
            outlineWidth: outline == nil ? 2 : 6,
            status: status,
            textWeight: (highlight ?? statusColor) == nil ? .semibold : .bold,
            textColor: isAssigned ? .primary : Color(.tertiaryLabel),
            isEmphasised: outline != nil
        )
    }

    private func drawPits(in context: GraphicsContext, showsText: Bool) {
        let styled = map.pits.map { style(for: $0) }

        // Four passes rather than one loop that fills, strokes and labels each pit before moving to the next.
        //
        // Pits sit edge to edge with no gutter. Filling and stroking in one pass let a neighbour's fill land on
        // the border of the pit next to it, and which neighbour won came down to the alphabet. That is why a
        // highlight read as sitting above the grid lines in some places and under them in others.
        for item in styled { fillPit(item, in: context) }
        for item in styled where !item.isEmphasised { strokePit(item, in: context) }
        for item in styled where item.isEmphasised { strokePit(item, in: context) }

        guard showsText else { return }
        for item in styled { labelPit(item, in: context) }
    }

    /// Shared by the fill and the border so the two stay concentric.
    private func cornerRadius(for rect: CGRect) -> CGFloat {
        min(6, rect.width / 10)
    }

    private func fillPit(_ item: StyledPit, in context: GraphicsContext) {
        inElement(item.pit.geometry, context) { layer, rect in
            layer.fill(
                Path(roundedRect: rect, cornerRadius: cornerRadius(for: rect)),
                with: .color(item.fill)
            )
        }
    }

    /// Strokes *inside* the pit's own bounds, `.strokeBorder` semantics rather than `.stroke`.
    /// `GraphicsContext.stroke` centres the line on the path, so the 6pt emphasis ring put 3pt of itself into the neighbouring pit.
    /// Insetting by half the width keeps every border within the pit it belongs to,
    /// and two adjacent borders then abut instead of overlapping.
    private func strokePit(_ item: StyledPit, in context: GraphicsContext) {
        inElement(item.pit.geometry, context) { layer, rect in
            let inset = item.outlineWidth / 2
            let bounds = rect.insetBy(dx: inset, dy: inset)
            guard bounds.width > 0, bounds.height > 0 else { return }

            layer.stroke(
                Path(
                    roundedRect: bounds,
                    cornerRadius: max(0, cornerRadius(for: rect) - inset)
                ),
                with: .color(item.outline),
                lineWidth: item.outlineWidth
            )
        }
    }

    private func labelPit(_ item: StyledPit, in context: GraphicsContext) {
        inElement(item.pit.geometry, context) { layer, rect in
            // With a status there are two lines, so the number shifts up to make room rather than the pair drifting off centre.
            // The offsets moved with the code's size: at 30 over 22 the pair spans roughly -25 to +25 of a 100-unit pit and sits centred.
            drawText(
                item.pit.team ?? item.pit.address,
                in: layer,
                rect: rect,
                at: CGPoint(x: 0, y: item.status == nil ? 0 : -rect.height * 0.15),
                size: 30,
                weight: item.textWeight,
                color: item.textColor
            )

            if let status = item.status {
                // Two-letter code
                drawText(
                    status.short,
                    in: layer,
                    rect: rect,
                    at: CGPoint(x: 0, y: rect.height * 0.17),
                    size: 22,
                    weight: .bold,
                    color: status.color
                )
            }
        }
    }

    private func drawArrows(in context: GraphicsContext) {
        for arrow in map.arrows {
            inElement(arrow.geometry, context) { layer, rect in
                let color = color(for: arrow.color)
                let headHeight = min(rect.height * 0.42, rect.width * 0.9)
                let headWidth = rect.width * 0.86
                let shaftWidth = max(rect.width * 0.16, 2)

                // At angle 0 a single arrow points up; a double arrow points up and down. The rotation is already applied by `inElement`.
                var shaft = Path()
                shaft.move(to: CGPoint(x: 0, y: rect.maxY - (arrow.isDoubleEnded ? headHeight : 0)))
                shaft.addLine(to: CGPoint(x: 0, y: rect.minY + headHeight))
                layer.stroke(
                    shaft,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: shaftWidth, lineCap: .round)
                )

                layer.fill(
                    head(tipY: rect.minY, baseY: rect.minY + headHeight, width: headWidth),
                    with: .color(color)
                )
                if arrow.isDoubleEnded {
                    layer.fill(
                        head(tipY: rect.maxY, baseY: rect.maxY - headHeight, width: headWidth),
                        with: .color(color)
                    )
                }
            }
        }
    }

    private func head(tipY: CGFloat, baseY: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: tipY))
        path.addLine(to: CGPoint(x: -width / 2, y: baseY))
        path.addLine(to: CGPoint(x: width / 2, y: baseY))
        path.closeSubpath()
        return path
    }

    private func drawLabels(in context: GraphicsContext, showsText: Bool) {
        guard showsText else { return }
        for label in map.labels where !label.text.isEmpty {
            inElement(label.geometry, context) { layer, rect in
                drawText(
                    label.text,
                    in: layer,
                    rect: rect,
                    size: 26,
                    weight: .semibold,
                    color: .secondary
                )
            }
        }
    }

    // MARK: - Helpers

    private func drawText(
        _ string: String,
        in context: GraphicsContext,
        rect: CGRect,
        at point: CGPoint = .zero,
        size: CGFloat,
        weight: Font.Weight,
        color: Color
    ) {
        var resolved = context.resolve(
            Text(string).font(.system(size: size, weight: weight))
        )
        // `ResolvedText.shading` is the Canvas-native way to colour text and
        // works on the iOS 16 floor, unlike `Text.foregroundStyle`, which is 17+.
        resolved.shading = .color(color)

        // Nexus's own renderer lets long area names spill; clipping to the
        // element instead keeps a wide label from crossing into the pit next to it and reading as that pit's number.
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.draw(resolved, at: point, anchor: .center)
    }

    /// Nexus constrains arrow colour to four values, so this is total.
    /// Compared with `==` rather than `switch` because Kotlin enums surface differently through SKIE
    /// than through bare Kotlin/Native, and equality behaves the same either way.
    private func color(for arrowColor: ArrowColor) -> Color {
        if arrowColor == ArrowColor.red { return .red }
        if arrowColor == ArrowColor.purple { return .purple }
        if arrowColor == ArrowColor.gray { return Color(.systemGray) }
        return .blue
    }
}
