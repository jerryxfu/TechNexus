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

    /// Zoom overscroll, for the same reason and by the same trick.
    ///
    /// `zoom` is hard-clamped and feeds the canvas, so it can't animate. This is the visual-only shrink applied past
    /// `minZoom`, as a `.scaleEffect`, a real modifier, so it springs. Text goes soft for the duration of the
    /// gesture, which only happens below the fit scale where nothing is legible anyway.
    @State private var zoomRubber: CGFloat = 1

    /// Below the fit scale, so extra margin is somewhere you can actually rest.
    /// The map's baseline breathing room is `fitInset`, which applies in every state.
    /// This is on top of that: pinch out past the fit and the map keeps shrinking, and it stays where you leave it.
    private let minZoom: CGFloat = 0.8
    private let maxZoom: CGFloat = 12

    /// What the toolbar's "fit to screen" targets: the whole map, inside `fitInset`.
    private let fitZoom: CGFloat = 1

    /// Margin between the map and the screen edge, in every state.
    ///
    /// Feeds the fit *and* the pan clamp, via `contentBox`, so the gap on the limiting axis is the same at fit as it is
    /// panned hard into a corner at 8x.
    ///
    /// Wider horizontally than vertically on purpose. On a portrait phone a landscape map is width-limited,
    /// so the sides are the only edges where the margin is what you actually see, above and below, the map's own aspect
    /// ratio already leaves far more room than any inset would.
    private let fitInset = CGSize(width: 28, height: 16)

    /// Zoom applied when opening on a highlighted pit.
    /// Kept well below `maxZoom` so there is obvious room left to pinch. At 3 against a cap of 8
    /// there was under 3x of headroom on open, which reads as the gesture not working rather than as a limit.
    private let focusZoom: CGFloat = 2

    /// Width of the inward darkening at each edge, when there is any.
    private let edgeFade: CGFloat = 64

    /// How black the void gets at the very edge, fully overscrolled.
    private let maxVoidOpacity: Double = 0.4

    /// An eased falloff rather than a straight ramp.
    ///
    /// A linear gradient from opaque to clear has a visible shoulder: the eye picks out the exact line where
    /// the slope starts, so the shadow reads as a band laid over the map rather than as depth.
    /// Stepping it down on roughly a square curve keeps the weight in the outer fifth and lets the remaining
    /// four fifths trail off into nothing.
    private static let voidFalloff = Gradient(stops: [
        .init(color: .black, location: 0),
        .init(color: .black.opacity(0.62), location: 0.18),
        .init(color: .black.opacity(0.34), location: 0.38),
        .init(color: .black.opacity(0.15), location: 0.60),
        .init(color: .black.opacity(0.04), location: 0.80),
        .init(color: .black.opacity(0), location: 1),
    ])

    /// The excess approaches this asymptotically and never reaches it, so a drag
    /// past the limit eases to a stop instead of hitting a wall.
    private let overshoot: CGFloat = 64

    /// The same, for zoom: pinching below `minZoom` approaches this much shrink and never reaches it.
    private let zoomOvershoot: CGFloat = 0.25

    // MARK: - Scroll indicators

    @State private var indicatorsVisible = false

    /// Cancels a stale hide without holding onto a `Task`. Every `scheduleHide` captures the counter's value
    /// and gives up if another gesture has bumped it since.
    @State private var indicatorToken = 0

    private let indicatorThickness: CGFloat = 3
    private let indicatorMargin: CGFloat = 2

    /// Kept clear at the far end of both tracks so the two thumbs can't meet in the corner.
    private let indicatorGutter: CGFloat = 10

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let viewSize = proxy.size

                ZStack {
                    PitMapCanvas(
                        map: map,
                        highlights: highlights,
                        statuses: statuses,
                        // The canvas fits the map itself. Letting the aspect-ratio modifier do it too would box the drawing
                        // inside this frame and leave the pan maths below computing against a size the canvas never received.
                        fitsAspectRatio: false,
                        fitInset: fitInset,
                        zoom: zoom,
                        pan: pan
                    )
                    .frame(width: viewSize.width, height: viewSize.height)
                    .scaleEffect(zoomRubber)
                    .offset(rubberBand)

                    // Outside the offset so both stay pinned while the map slides under them.
                    voidShadow
                    indicators(in: viewSize)
                }
                .frame(width: viewSize.width, height: viewSize.height)
                .clipped()
                .contentShape(Rectangle())
                // Two separate modifiers rather than `.simultaneously(with:)`.
                // Composing them into one recogniser lets the drag win the touch sequence outright.
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            magnify(to: committedZoom * value, in: viewSize)
                        }
                        .onEnded { _ in
                            committedZoom = zoom
                            pan = clampPan(pan, in: viewSize)
                            committedPan = pan
                            settle()
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            drag(by: value.translation, in: viewSize)
                        }
                        .onEnded { _ in
                            committedPan = pan
                            settle()
                        }
                )
                .onTapGesture(count: 2) { reset() }
                .task {
                    // Opening on your own pit is the whole reason someone taps through to this screen at an event.
                    centreOnFirstHighlight(in: viewSize)
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
                    .disabled(zoom == fitZoom && pan == .zero)
                }
            }
        }
    }

    // MARK: - Geometry

    /// The box the map is fitted *and* clamped inside: the viewport less `fitInset` on every side.
    ///
    /// One function because the fit, the pan clamp and the scroll indicators all need the identical number.
    /// Computing it separately in three places is how they end up disagreeing by a margin's width,
    /// the indicator parking early, or the opening centre landing off.
    private func contentBox(in viewSize: CGSize) -> CGSize {
        CGSize(
            width: max(1, viewSize.width - fitInset.width * 2),
            height: max(1, viewSize.height - fitInset.height * 2)
        )
    }

    private func drawnSize(in viewSize: CGSize) -> CGSize {
        guard map.size.x > 0, map.size.y > 0 else { return viewSize }
        let scale =
            PitMapCanvas.fitScale(
                mapSize: map.size,
                viewSize: viewSize,
                inset: fitInset
            ) * zoom
        return CGSize(width: map.size.x * scale, height: map.size.y * scale)
    }

    // MARK: - Gestures

    /// Splits a pinch into in-range zoom and damped sub-fit overscroll.
    ///
    /// `pan` is re-clamped **hard**, not fed to the rubber band. Zooming out shrinks the drawn map,
    /// which shrinks the slack, so a `pan` that was legal a frame ago can exceed it, but that's the geometry moving,
    /// not the user dragging past an edge, and it should pin to the edge rather than show resistance nobody asked for.
    private func magnify(to raw: CGFloat, in viewSize: CGSize) {
        zoom = clampZoom(raw)
        zoomRubber = raw < minZoom ? dampZoom(raw / minZoom) : 1
        pan = clampPan(pan, in: viewSize)
        showIndicators()
    }

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
        showIndicators()
    }

    /// Releases both overscrolls. Only these two move (see the note on `rubberBand`).
    private func settle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            rubberBand = .zero
            zoomRubber = 1
        }
        scheduleIndicatorHide()
    }

    /// Asymptotic: the excess approaches `overshoot` but never reaches it.
    private func damp(_ excess: CGFloat) -> CGFloat {
        guard excess != 0 else { return 0 }
        let magnitude = abs(excess)
        let sign: CGFloat = excess < 0 ? -1 : 1
        return sign * overshoot * (1 - 1 / (magnitude / overshoot + 1))
    }

    /// Same curve, expressed as a scale factor. `ratio` is how far below `minZoom` the pinch went, as a fraction;
    /// the result approaches `1 - zoomOvershoot` and never reaches it.
    private func dampZoom(_ ratio: CGFloat) -> CGFloat {
        let deficit = max(0, 1 - ratio)
        return 1 - zoomOvershoot * (1 - 1 / (deficit / zoomOvershoot + 1))
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    /// Keeps the map from being flung off screen.
    ///
    /// Measured against `contentBox`, not the raw viewport, so panning stops with `fitInset` of clean background still showing.
    /// That makes the margin a constant on the limiting axis in every state, the same at fit as it is
    /// panned hard into a corner at 8x, rather than something that exists until you zoom in and then vanishes.
    ///
    /// At or below `fitZoom` the map already fits that box, so the allowance is zero and all the give comes from `rubberBand`,
    /// which is what makes a drag at the sticky margin darken the void instead of moving anything. Past that,
    /// the slack in each axis is however much of the map overhangs, halved because the map is centred.
    private func clampPan(_ value: CGSize, in viewSize: CGSize) -> CGSize {
        let drawn = drawnSize(in: viewSize)
        let box = contentBox(in: viewSize)
        let slackX = max(0, (drawn.width - box.width) / 2)
        let slackY = max(0, (drawn.height - box.height) / 2)
        return CGSize(
            width: min(max(value.width, -slackX), slackX),
            height: min(max(value.height, -slackY), slackY)
        )
    }

    private func reset() {
        // Only `rubberBand` and `zoomRubber` are animatable here; the other three are read inside the Canvas closure
        // and would snap regardless of the wrapper.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            rubberBand = .zero
            zoomRubber = 1
        }
        zoom = fitZoom
        committedZoom = fitZoom
        pan = .zero
        committedPan = .zero
    }

    // MARK: - Chrome

    /// Darkness past the edge of the map, shown only while you are actually past it.
    ///
    /// Which edge darkens is the *opposite* of the direction you dragged. Pinching below `minZoom` opens a gap on all four at once.
    ///
    /// **The opacity is a modifier, not a colour.** Baking the value into `LinearGradient(colors:)` would
    /// rebuild the gradient once at the final value and snap it to nothing the instant `settle()` ran, while the map
    /// itself sprang back over a third of a second, the same trap as feeding an animated value into a `Canvas`.
    /// `.opacity` is animatable, so it interpolates alongside the `.offset` it is describing.
    private var voidShadow: some View {
        ZStack {
            LinearGradient(gradient: Self.voidFalloff, startPoint: .top, endPoint: .bottom)
                .frame(height: edgeFade)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(voidIntensity(rubberBand.height))

            LinearGradient(gradient: Self.voidFalloff, startPoint: .bottom, endPoint: .top)
                .frame(height: edgeFade)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(voidIntensity(-rubberBand.height))

            LinearGradient(gradient: Self.voidFalloff, startPoint: .leading, endPoint: .trailing)
                .frame(width: edgeFade)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(voidIntensity(rubberBand.width))

            LinearGradient(gradient: Self.voidFalloff, startPoint: .trailing, endPoint: .leading)
                .frame(width: edgeFade)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(voidIntensity(-rubberBand.width))
        }
        .allowsHitTesting(false)
    }

    /// How dark one edge is: its share of the pan overscroll, plus whatever sub-fit zoom overscroll is in play, capped.
    private func voidIntensity(_ excess: CGFloat) -> Double {
        let fromPan = max(0, excess) / overshoot
        let fromZoom = max(0, 1 - zoomRubber) / zoomOvershoot
        return Double(min(1, fromPan + fromZoom)) * maxVoidOpacity
    }

    // MARK: - Scroll indicators

    /// Where you are in the map, for orientation rather than for grabbing.
    ///
    /// Drawn rather than native: there is no `ScrollView` here, just a `Canvas` and a pan value,
    /// so `showsIndicators` has nothing to attach to. Each axis appears only when there is something to scroll in it,
    /// which means nothing at all at or below the fit scale, same as a `ScrollView` whose content fits.
    private func indicators(in viewSize: CGSize) -> some View {
        let drawn = drawnSize(in: viewSize)
        // The same box `clampPan` measures against, so a thumb reaches the end of
        // its track exactly when the map reaches its margin.
        let box = contentBox(in: viewSize)
        let hTrack = viewSize.width - indicatorMargin * 2 - indicatorGutter
        let vTrack = viewSize.height - indicatorMargin * 2 - indicatorGutter

        return ZStack {
            if let h = indicatorMetrics(
                content: drawn.width,
                viewport: box.width,
                pan: pan.width,
                track: hTrack
            ) {
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: h.thumb, height: indicatorThickness)
                    .offset(x: h.offset)
                    .frame(width: hTrack, height: indicatorThickness, alignment: .leading)
                    .padding(indicatorMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if let v = indicatorMetrics(
                content: drawn.height,
                viewport: box.height,
                pan: pan.height,
                track: vTrack
            ) {
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: indicatorThickness, height: v.thumb)
                    .offset(y: v.offset)
                    .frame(width: indicatorThickness, height: vTrack, alignment: .top)
                    .padding(indicatorMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .opacity(indicatorsVisible ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Thumb length and its offset along the track, or nil when this axis has nothing to show.
    ///
    /// The thumb parks at the end of its track during overscroll rather than compressing the way a `ScrollView`'s does,
    /// the void is already saying that, and saying it twice is noise.
    private func indicatorMetrics(
        content: CGFloat,
        viewport: CGFloat,
        pan: CGFloat,
        track: CGFloat
    ) -> (thumb: CGFloat, offset: CGFloat)? {
        let slack = (content - viewport) / 2
        guard slack > 0.5, track > 0 else { return nil }

        let thumb = min(track, max(24, track * (viewport / content)))
        // Pan runs +slack (showing the near edge) to -slack (the far edge).
        let progress = min(max((slack - pan) / (slack * 2), 0), 1)
        return (thumb, progress * (track - thumb))
    }

    private func showIndicators() {
        // Bumped every frame, not just on the transition: a gesture starting less than a beat after the last one
        // ended would otherwise inherit that one's pending hide and fade out mid-drag.
        indicatorToken += 1
        guard !indicatorsVisible else { return }
        withAnimation(.easeOut(duration: 0.12)) { indicatorsVisible = true }
    }

    private func scheduleIndicatorHide() {
        indicatorToken += 1
        let token = indicatorToken
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard token == indicatorToken else { return }
            withAnimation(.easeOut(duration: 0.35)) { indicatorsVisible = false }
        }
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

        let scale =
            PitMapCanvas.fitScale(
                mapSize: map.size,
                viewSize: viewSize,
                inset: fitInset
            ) * zoom

        // The canvas anchors the map's centre to the view's centre, so the pan
        // needed is the pit's offset from that centre, scaled and negated.
        let offset = CGSize(
            width: -(pit.geometry.position.x - map.size.x / 2) * scale,
            height: -(pit.geometry.position.y - map.size.y / 2) * scale
        )
        pan = clampPan(offset, in: viewSize)
        committedPan = pan

        // The screen opens zoomed in on one pit with no gesture behind it, which
        // is the single most disorienting moment this view has. Show where that is on the map, then get out of the way.
        showIndicators()
        scheduleIndicatorHide()
    }
}
