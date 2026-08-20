import ComposeApp
import SwiftUI

/// The pit map, full screen, with pan and zoom.

/// This exists as a separate screen rather than an interactive map inline in the Pit tab
/// because pan and scroll are the same gesture. A draggable map inside the tab's `ScrollView` would steal
/// roughly half of every drag from the list and feel broken rather than unfinished.
struct PitMapScreen: View {
    let map: PitMap
    let highlights: [String: Color]
    var statuses: [String: TeamStatus] = [:]

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1

    /// Pan within the map's real bounds. Feeds the canvas transform, so the
    /// drawing re-resolves at this offset and text stays crisp.
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    /// Overscroll past those bounds, applied as a view `.offset` rather than folded into `pan`.
    /// This split is the whole reason the springback animates. `withAnimation` interpolates animatable values
    /// in the **view tree**; a value consumed inside a `Canvas` draw closure isn't one.
    /// Wrapping a `pan` assignment in `withAnimation` just re-runs the closure once at the final value, which is
    /// exactly the instant snap it was meant to smooth out. `.offset` is a real modifier, so SwiftUI can interpolate it.
    @State private var rubberBand: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 12

    /// Zoom applied when opening on a highlighted pit.
    /// Kept well below `maxZoom` so there is obvious room left to pinch. At 3 against a cap of 8
    /// there was under 3x of headroom on open, which reads as the gesture not working rather than as a limit.
    private let focusZoom: CGFloat = 2

    /// Margin between the map and the screen edge.
    /// Real layout, not a drawing parameter: the canvas is framed inside a view this much smaller on each side,
    /// and that same reduced size feeds the fit, the clamp and the centring. `fitScale` stays a pure fit,
    /// and "fit to screen" means exactly that.
    private let contentInset: CGFloat = 28

    /// Width of the inward fade at each edge. Sits inside `contentInset`, so
    /// there is visible margin outside the gradient rather than under it.
    private let edgeFade: CGFloat = 20

    /// The excess approaches this asymptotically and never reaches it, so a drag
    /// past the limit eases to a stop instead of hitting a wall.
    private let overshoot: CGFloat = 64

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let canvasSize = inset(proxy.size)

                ZStack {
                    PitMapCanvas(
                        map: map,
                        highlights: highlights,
                        statuses: statuses,
                        // The canvas fits the map itself. Letting the aspect-ratio modifier do it too would box the drawing
                        // inside this frame and leave the pan maths below computing against a size the canvas never received.
                        fitsAspectRatio: false,
                        zoom: zoom,
                        pan: pan
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .offset(rubberBand)
                    .clipped()

                    // Outside the offset so the vignette stays pinned while the map slides under it.
                    edgeShadow
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                // Two separate modifiers rather than `.simultaneously(with:)`.
                // Composing them into one recogniser lets the drag win the touch sequence outright,
                // which is the likeliest reason pinch stopped responding once overscroll was added.
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = clampZoom(committedZoom * value)
                        }
                        .onEnded { _ in
                            committedZoom = zoom
                            pan = clampPan(pan, in: canvasSize)
                            committedPan = pan
                            settle()
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            drag(by: value.translation, in: canvasSize)
                        }
                        .onEnded { _ in
                            committedPan = pan
                            settle()
                        }
                )
                .onTapGesture(count: 2) { reset() }
                .task {
                    // Opening on your own pit is the whole reason someone taps through to this screen at an event.
                    centreOnFirstHighlight(in: canvasSize)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pit map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reset()
                    } label: {
                        Label(
                            "Fit to screen",
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                    }
                    .disabled(zoom == 1 && pan == .zero)
                }
            }
        }
    }

    // MARK: - Geometry

    private func inset(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(1, size.width - contentInset * 2),
            height: max(1, size.height - contentInset * 2)
        )
    }

    private func drawnSize(in viewSize: CGSize) -> CGSize {
        guard map.size.x > 0, map.size.y > 0 else { return viewSize }
        let scale = PitMapCanvas.fitScale(mapSize: map.size, viewSize: viewSize) * zoom
        return CGSize(width: map.size.x * scale, height: map.size.y * scale)
    }

    // MARK: - Gestures

    /// Splits a drag into in-bounds pan and damped overscroll.
    private func drag(by translation: CGSize, in viewSize: CGSize) {
        let raw = CGSize(
            width: committedPan.width + translation.width,
            height: committedPan.height + translation.height
        )
        let clamped = clampPan(raw, in: viewSize)
        pan = clamped
        rubberBand = CGSize(
            width: damp(raw.width - clamped.width),
            height: damp(raw.height - clamped.height)
        )
    }

    /// Releases the overscroll. Only `rubberBand` moves, and only it can (see the note on that property).
    private func settle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            rubberBand = .zero
        }
    }

    /// Asymptotic: the excess approaches `overshoot` but never reaches it.
    private func damp(_ excess: CGFloat) -> CGFloat {
        guard excess != 0 else { return 0 }
        let magnitude = abs(excess)
        let sign: CGFloat = excess < 0 ? -1 : 1
        return sign * overshoot * (1 - 1 / (magnitude / overshoot + 1))
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    /// Keeps the map from being flung off screen.
    ///
    /// At `zoom == 1` the map already fits, so the allowance is zero and all the
    /// give comes from `rubberBand`. Past that, the slack in each axis is
    /// however much of the map overhangs, halved because the map is centred.
    private func clampPan(_ value: CGSize, in viewSize: CGSize) -> CGSize {
        let drawn = drawnSize(in: viewSize)
        let slackX = max(0, (drawn.width - viewSize.width) / 2)
        let slackY = max(0, (drawn.height - viewSize.height) / 2)
        return CGSize(
            width: min(max(value.width, -slackX), slackX),
            height: min(max(value.height, -slackY), slackY)
        )
    }

    private func reset() {
        // Only `rubberBand` is animatable here; the other three are read inside
        // the Canvas closure and would snap regardless of the wrapper.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            rubberBand = .zero
        }
        zoom = 1
        committedZoom = 1
        pan = .zero
        committedPan = .zero
    }

    // MARK: - Chrome

    /// A soft vignette so the map reads as sitting *under* the edge rather than being cut off by it.
    private var edgeShadow: some View {
        let edge = Color(.systemGroupedBackground)

        return ZStack {
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: edgeFade)
                .frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .bottom, endPoint: .top)
                .frame(height: edgeFade)
                .frame(maxHeight: .infinity, alignment: .bottom)
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: edgeFade)
                .frame(maxWidth: .infinity, alignment: .leading)
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .trailing, endPoint: .leading)
                .frame(width: edgeFade)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Opening position

    /// Zooms in and centres on the first highlighted team that actually has a pit at this event.
    /// Does nothing when no highlighted team is here.
    private func centreOnFirstHighlight(in viewSize: CGSize) {
        guard
            map.size.x > 0, map.size.y > 0,
            let pit = highlights.keys
                .compactMap({ map.pitFor(team: $0) })
                .first
        else { return }

        zoom = clampZoom(focusZoom)
        committedZoom = zoom

        let scale = PitMapCanvas.fitScale(mapSize: map.size, viewSize: viewSize) * zoom

        // The canvas anchors the map's centre to the view's centre, so the pan
        // needed is the pit's offset from that centre, scaled and negated.
        let offset = CGSize(
            width: -(pit.geometry.position.x - map.size.x / 2) * scale,
            height: -(pit.geometry.position.y - map.size.y / 2) * scale
        )
        pan = clampPan(offset, in: viewSize)
        committedPan = pan
    }
}
