import ComposeApp
import SwiftUI

/// Draws a Nexus pit map.
///
/// Pure rendering — it owns no gesture state and no data loading. `zoom` and
/// `pan` are inputs so the caller decides whether the map is a static preview or
/// something you can move around.
///
/// ## Why zoom is a parameter and not `.scaleEffect`
///
/// Scaling the rendered view magnifies text as pixels. Feeding the zoom back
/// into the transform makes `Canvas` re-resolve every label at its new size, so
/// a team number is as crisp at 4× as at 1×. It costs a redraw per gesture
/// frame, which for a few hundred rectangles is not close to a problem.
struct PitMapCanvas: View {
    let map: PitMap

    /// Team number to colour, straight from `HighlightedTeamsStore`.
    var highlights: [String: Color] = [:]

    /// Extra magnification on top of fit-to-view. `1` fits the whole map.
    var zoom: CGFloat = 1

    /// Pan in points, applied after scaling.
    var pan: CGSize = .zero

    /// Pit and area text is dropped below this on-screen scale, where it would
    /// render as illegible smudges rather than information.
    private let textVisibilityThreshold: Double = 0.14

    var body: some View {
        Canvas { context, size in
            draw(into: context, viewSize: size)
        }
        // Nexus maps are portrait-ish and vary widely, so the container follows
        // the data rather than a fixed shape.
        .aspectRatio(aspect, contentMode: .fit)
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

        let fit = min(viewSize.width / w, viewSize.height / h)
        let scale = fit * zoom

        var canvas = context
        // Anchor the map's centre to the view's centre, so zoom magnifies about
        // the middle of what you're looking at rather than the top-left corner.
        canvas.translateBy(
            x: viewSize.width / 2 + pan.width,
            y: viewSize.height / 2 + pan.height
        )
        canvas.scaleBy(x: scale, y: scale)
        canvas.translateBy(x: -w / 2, y: -h / 2)

        // Nexus units are screen-oriented — y down, angles clockwise — so no
        // axis flip is needed here. See the note in `PitMap.kt`.
        let showsText = scale > textVisibilityThreshold

        drawWalls(in: canvas)
        drawAreas(in: canvas, showsText: showsText)
        drawPits(in: canvas, showsText: showsText)
        drawArrows(in: canvas)
        drawLabels(in: canvas, showsText: showsText)
    }

    /// Runs `body` in a context translated to the element's centre and rotated
    /// by its angle, handing back a rect centred on the origin.
    ///
    /// `GraphicsContext` is a value type, so the copy isolates the transform and
    /// there is nothing to restore afterwards.
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
                    // Fixed sizes are in map units, not points — this is
                    // geometry inside a scaled context, not typography, so
                    // Dynamic Type would fight the drawing rather than serve it.
                    size: 24,
                    weight: .medium,
                    color: .secondary
                )
            }
        }
    }

    private func drawPits(in context: GraphicsContext, showsText: Bool) {
        for pit in map.pits {
            let highlight = pit.team.flatMap { highlights[$0] }
            let isAssigned = pit.team != nil

            inElement(pit.geometry, context) { layer, rect in
                let shape = Path(
                    roundedRect: rect,
                    cornerRadius: min(6, rect.width / 10)
                )

                // An unassigned pit stays visible but recessive. It's a landmark
                // when you're counting down a row, so hiding it would make the
                // map harder to walk, not cleaner.
                let fill: Color =
                    highlight?.opacity(0.28)
                    ?? (isAssigned
                        ? Color(.secondarySystemGroupedBackground)
                        : Color(.systemGray6))

                layer.fill(shape, with: .color(fill))
                layer.stroke(
                    shape,
                    with: .color(highlight ?? Color(.systemGray3)),
                    lineWidth: highlight == nil ? 2 : 6
                )

                guard showsText else { return }
                drawText(
                    pit.team ?? pit.address,
                    in: layer,
                    rect: rect,
                    size: 30,
                    weight: highlight == nil ? .semibold : .bold,
                    color: isAssigned ? .primary : Color(.tertiaryLabel)
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

                // At angle 0 a single arrow points up; a double arrow points up
                // and down. The rotation is already applied by `inElement`.
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
        // element instead keeps a wide label from crossing into the pit next to
        // it and reading as that pit's number.
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.draw(resolved, at: .zero, anchor: .center)
    }

    /// Nexus constrains arrow colour to four values, so this is total.
    ///
    /// Compared with `==` rather than `switch` because Kotlin enums surface
    /// differently through SKIE than through bare Kotlin/Native, and equality
    /// behaves the same either way.
    private func color(for arrowColor: ArrowColor) -> Color {
        if arrowColor == ArrowColor.red { return .red }
        if arrowColor == ArrowColor.purple { return .purple }
        if arrowColor == ArrowColor.gray { return Color(.systemGray) }
        return .blue
    }
}
