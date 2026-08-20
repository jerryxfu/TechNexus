import SwiftUI

/// The dot and number pill for highlighted team.
/// The accessory slot is why this is generic: the bar puts a delete button inside the pill, and nothing else does.
struct HighlightedTeamPill<Accessory: View>: View {
    let team: String
    let color: Color

    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(team)
                .font(.system(size: 11, weight: .medium))

            accessory()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension HighlightedTeamPill where Accessory == EmptyView {
    init(team: String, color: Color) {
        self.init(team: team, color: color) { EmptyView() }
    }
}
