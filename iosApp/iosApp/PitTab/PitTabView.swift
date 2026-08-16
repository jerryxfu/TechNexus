import SwiftUI

struct PitTabView: View {
    @State private var showRobotDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RobotInfoCard {
                        showRobotDetail = true
                    }
                    /*
                    SectionTitle(title: "Pit Checklist", icon: "checklist")

                    SectionTitle(
                        title: "Battery Tracker",
                        icon: "minus.plus.batteryblock.stack"
                    )

                    // Placeholder for future pit content
                    Text("Pit tools coming soon")
                    */
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pit")
            .sheet(isPresented: $showRobotDetail) {
                RobotCheatSheetView()
            }
        }
    }
}

// MARK: - Robot Info Card

private struct RobotInfoCard: View {
    let onTap: () -> Void

    private let robot = RobotCheatSheet.defaultRobot

    var body: some View {
        // Plain on every version: the system supplies the press feedback,
        // so there's nothing to hand-roll and nothing to flash.
        cardButton.buttonStyle(.plain)
    }

    private var cardButton: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading) {
                    Text(robot.teamNumber)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    Text("Robot information card")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                        // Not .interactive(): that's what lit the card up
                        // white on touch, fighting the button's own feedback.
                        .glassEffect(
                            .regular,
                            in: .rect(cornerRadius: 16, style: .continuous)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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

// MARK: - Legacy card press style (pre-iOS 26 only)

#Preview {
    PitTabView()
}
