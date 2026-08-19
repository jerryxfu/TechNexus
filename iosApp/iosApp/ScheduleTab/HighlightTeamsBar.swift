import SwiftUI

struct HighlightTeamsBar: View {
    @Binding var highlightedTeams: [String: Color]
    @State private var showingEntry = false
    @State private var newTeamNumber = ""
    @State private var selectedColor: Color = .yellow

    private let highlightColors: [Color] = [
        .yellow, .green, .orange, .pink, .cyan, .purple,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Highlighted Teams")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    withAnimation { showingEntry.toggle() }
                } label: {
                    Image(systemName: showingEntry ? "xmark" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if !highlightedTeams.isEmpty {
                teamPillsList
            }

            if showingEntry {
                entryRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    private var teamPillsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(
                    highlightedTeams.sorted(by: { $0.key < $1.key }),
                    id: \.key
                ) { pair in
                    let team = pair.key
                    let teamColor: Color = pair.value
                    HStack(spacing: 4) {
                        Circle()
                            .fill(teamColor)
                            .frame(width: 9, height: 9)
                        Text(team)
                            .font(.system(size: 11, weight: .medium))
                        Button {
                            withAnimation {
                                _ = highlightedTeams.removeValue(forKey: team)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(teamColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var entryRow: some View {
        HStack(spacing: 6) {
            TextField("Team #", text: $newTeamNumber)
                .font(.system(size: 12))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

            ForEach(highlightColors, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(
                                Color.primary,
                                lineWidth: selectedColor == color ? 2 : 0
                            )
                    )
                    .onTapGesture { selectedColor = color }
            }

            Spacer()

            Button("Add") {
                let trimmed = newTeamNumber.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                withAnimation {
                    highlightedTeams[trimmed] = selectedColor
                    showingEntry = false
                }
                newTeamNumber = ""
            }
            .font(.system(size: 13, weight: .medium))
            .disabled(
                newTeamNumber.trimmingCharacters(in: .whitespaces).isEmpty
            )
            .padding(.trailing, 4)
        }
    }
}
