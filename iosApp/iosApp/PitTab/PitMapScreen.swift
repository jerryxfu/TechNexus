import ComposeApp
import SwiftUI

/// The pit map, full screen, with pan and zoom.
///
/// This exists as a separate screen rather than an interactive map inline in the
/// Pit tab because pan and scroll are the same gesture. A draggable map inside
/// the tab's `ScrollView` would steal roughly half of every drag from the list
/// and feel broken rather than unfinished.
struct PitMapScreen: View {
    let map: PitMap
    let highlights: [String: Color]
    var statuses: [String: TeamStatus] = [:]

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 8

    /// Breathing room between the map and the screen edge at zoom 1, so the
    /// outermost pits aren't flush against the bezel.
    private let contentInset: CGFloat = 20

    /// How far past the limit a drag may travel before it stops moving at all.
    ///
    /// Without this the drag ran unclamped and only snapped back on release,
    /// which reads as a glitch rather than a boundary — you drag, it follows,
    /// you let go, it jumps. Resistance while you're still dragging is what
    /// makes the edge feel like an edge.
    private let overshoot: CGFloat = 64

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                PitMapCanvas(
                    map: map,
                    highlights: highlights,
                    statuses: statuses,
                    // The canvas fits the map itself. Letting the aspect-ratio
                    // modifier do it too would box the drawing inside this frame
                    // and leave the pan maths below computing against a size the
                    // canvas never received.
                    fitsAspectRatio: false,
                    contentInset: contentInset,
                    zoom: zoom,
                    pan: pan
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(edgeShadow)
                .contentShape(Rectangle())
                .gesture(
                    // `MagnificationGesture` is deprecated in iOS 17 in favour of
                    // `MagnifyGesture`, which is 17+. Branching on availability
                    // would split this view's identity and reset the gesture
                    // mid-pinch, so the deprecated spelling stays until the
                    // deployment floor moves.
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = clampZoom(committedZoom * value)
                        }
                        .onEnded { _ in
                            committedZoom = zoom
                            pan = clampPan(pan, in: proxy.size)
                            committedPan = pan
                        }
                        .simultaneously(
                            with: DragGesture()
                                .onChanged { value in
                                    pan = resist(
                                        CGSize(
                                            width: committedPan.width + value.translation.width,
                                            height: committedPan.height + value.translation.height
                                        ),
                                        in: proxy.size
                                    )
                                }
                                .onEnded { _ in
                                    withAnimation(.interactiveSpring()) {
                                        pan = clampPan(pan, in: proxy.size)
                                    }
                                    committedPan = pan
                                }
                        )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.default) { reset() }
                }
                .task {
                    // Opening on your own pit is the whole reason someone taps
                    // through to this screen at an event.
                    centreOnFirstHighlight(in: proxy.size)
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
                        withAnimation(.default) { reset() }
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

    // MARK: - Gesture maths

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    /// Keeps the map from being flung off screen.
    ///
    /// At `zoom == 1` the map exactly fits, so there is nothing to pan and the
    /// allowance is zero. Past that, the slack in each axis is however much of
    /// the map now overhangs the view, halved because the map is centred.
    private func clampPan(_ value: CGSize, in viewSize: CGSize) -> CGSize {
        let drawn = drawnSize(in: viewSize)
        let slackX = max(0, (drawn.width - viewSize.width) / 2)
        let slackY = max(0, (drawn.height - viewSize.height) / 2)
        return CGSize(
            width: min(max(value.width, -slackX), slackX),
            height: min(max(value.height, -slackY), slackY)
        )
    }

    private func drawnSize(in viewSize: CGSize) -> CGSize {
        guard map.size.x > 0, map.size.y > 0 else { return viewSize }
        let scale =
            PitMapCanvas.fitScale(
                mapSize: map.size,
                viewSize: viewSize,
                inset: contentInset
            ) * zoom
        return CGSize(width: map.size.x * scale, height: map.size.y * scale)
    }

    /// Lets a drag past the limit, with resistance that grows the further it
    /// goes, so it eases to a stop instead of hitting a wall.
    private func resist(_ value: CGSize, in viewSize: CGSize) -> CGSize {
        let drawn = drawnSize(in: viewSize)
        return CGSize(
            width: resist(
                value.width,
                limit: max(0, (drawn.width - viewSize.width) / 2)
            ),
            height: resist(
                value.height,
                limit: max(0, (drawn.height - viewSize.height) / 2)
            )
        )
    }

    /// Asymptotic: the excess approaches `overshoot` but never reaches it.
    private func resist(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard abs(value) > limit else { return value }
        let excess = abs(value) - limit
        let damped = overshoot * (1 - 1 / (excess / overshoot + 1))
        return (value < 0 ? -1 : 1) * (limit + damped)
    }

    /// A soft vignette so the map reads as sitting *under* the screen edge
    /// rather than being cut off by it.
    private var edgeShadow: some View {
        let edge = Color(.systemGroupedBackground)
        let fade = 22.0

        return ZStack {
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
                .frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .bottom, endPoint: .top)
                .frame(height: fade)
                .frame(maxHeight: .infinity, alignment: .bottom)
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
                .frame(maxWidth: .infinity, alignment: .leading)
            LinearGradient(colors: [edge, edge.opacity(0)], startPoint: .trailing, endPoint: .leading)
                .frame(width: fade)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }

    private func reset() {
        zoom = 1
        committedZoom = 1
        pan = .zero
        committedPan = .zero
    }

    /// Zooms to a readable scale and centres on the first highlighted team that
    /// actually has a pit at this event.
    ///
    /// Silently does nothing when no highlighted team is here — which is the
    /// right outcome, not a missing case. Someone browsing another event's map
    /// should get the whole floor, not an arbitrary corner of it.
    private func centreOnFirstHighlight(in viewSize: CGSize) {
        guard
            map.size.x > 0, map.size.y > 0,
            let pit = highlights.keys
                .compactMap({ map.pitFor(team: $0) })
                .first
        else { return }

        let target: CGFloat = 3
        zoom = clampZoom(target)
        committedZoom = zoom

        let scale =
            PitMapCanvas.fitScale(
                mapSize: map.size,
                viewSize: viewSize,
                inset: contentInset
            ) * zoom

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
