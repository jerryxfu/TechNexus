import ComposeApp
import SwiftUI

struct PitTabView: View {
    @State private var showRobotDetail = false

    /// Read here rather than inside `PitLocationSection` so a change in Settings
    /// re-runs the section's `.task(id:)` instead of leaving it showing the old
    /// event's map.
    @State private var eventKey = SettingsManager.shared.settings.getEventId()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RobotInfoCard {
                        showRobotDetail = true
                    }

                    PitLocationSection(eventKey: eventKey)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pit")
            .sheet(isPresented: $showRobotDetail) {
                RobotCheatSheetView()
            }
            .task(id: scenePhase) {
                // Settings commits on blur and on scene phase, so coming back to
                // the foreground is the moment a new Event ID becomes readable.
                guard scenePhase == .active else { return }
                eventKey = SettingsManager.shared.settings.getEventId()
            }
        }
    }
}

// MARK: - Robot Info Card

/// Deliberately a row rather than a card.
///
/// It used to be the only thing in this tab and was sized like it. Now that the
/// pit map sits below it, the robot sheet is the *secondary* thing here — a
/// reference you open occasionally, not the reason you came. Full card weight
/// made it compete with the map for the top of the screen.
private struct RobotInfoCard: View {
    let onTap: () -> Void

    private let robot = RobotCheatSheet.defaultRobot

    var body: some View {
        cardButton.buttonStyle(.plain)
    }

    private var cardButton: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(robot.teamNumber)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Robot information card")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                        // Not .interactive(): that's what lit the card up
                        // white on touch, fighting the button's own feedback.
                        .glassEffect(
                            .regular,
                            in: .rect(cornerRadius: 14, style: .continuous)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(
                            color: .black.opacity(0.1),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                }
            }
        }
    }
}

#Preview {
    PitTabView()
}
