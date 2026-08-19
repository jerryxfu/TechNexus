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

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 8

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                PitMapCanvas(
                    map: map,
                    highlights: highlights,
                    zoom: zoom,
                    pan: pan
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
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
                                    pan = CGSize(
                                        width: committedPan.width + value.translation.width,
                                        height: committedPan.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    pan = clampPan(pan, in: proxy.size)
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
            .padding(8)
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
        let fit = min(viewSize.width / map.size.x, viewSize.height / map.size.y)
        let scale = fit * zoom
        return CGSize(width: map.size.x * scale, height: map.size.y * scale)
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

        let fit = min(viewSize.width / map.size.x, viewSize.height / map.size.y)
        let scale = fit * zoom

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
