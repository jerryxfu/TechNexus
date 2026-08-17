import ComposeApp
import SwiftUI

struct SettingsView: View {
    @State private var eventId = ""
    @State private var teamNumber = ""
    @State private var savedEventId = ""
    @State private var savedTeamNumber = ""
    @State private var isSaved = false
    @State private var resetTask: Task<Void, Never>?
    @State private var showEventPicker = false
    @AppStorage(LiveActivityPreference.key)
    private var liveActivityEnabled = true
    @FocusState private var focusedField: Field?

    private enum Field {
        case teamNumber
    }

    private var hasChanges: Bool {
        eventId != savedEventId || teamNumber != savedTeamNumber
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    liveActivitySection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .animation(.default, value: hasChanges)
            .animation(.default, value: isSaved)
        }
        .sheet(isPresented: $showEventPicker) {
            EventPickerView(currentEventId: eventId) { eventId = $0 }
        }
        .onAppear(perform: loadSettings)
        // task(id:) rather than onChange — one API that works on iOS 16.
        .task(id: liveActivityEnabled) {
            if !liveActivityEnabled {
                await ScheduleLiveActivityManager.shared.end()
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "General", icon: "gearshape")
            SettingsCard {
                EventPickerRow(eventId: eventId) {
                    focusedField = nil
                    showEventPicker = true
                }

                Divider().padding(.leading, 14)

                SettingsRow(
                    label: "Team Number",
                    placeholder: "e.g. 3990",
                    text: $teamNumber
                )
                .focused($focusedField, equals: .teamNumber)
                .keyboardType(.numberPad)
            }
            Text("The event determines which schedule is loaded.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Live Activity", icon: "bolt.fill")
            SettingsCard {
                Toggle(isOn: $liveActivityEnabled) {
                    Text("Show on Lock Screen")
                        .font(.subheadline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            Text(
                "Shows the current match and queue status on the Lock Screen and Dynamic Island."
            )
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if hasChanges {
            ToolbarItem(id: "discard", placement: .cancellationAction) {
                Button(action: discard) {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
        }
        if hasChanges || isSaved {
            ToolbarItem(id: "save", placement: .confirmationAction) {
                Button(action: save) {
                    saveIcon
                }
                .tint(isSaved ? .green : .accentColor)
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
                .fontWeight(.semibold)
        }
    }

    private var saveIcon: some View {
        Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down")
            .modifier(ReplaceSymbolTransition())
    }

    // MARK: - Actions

    private func loadSettings() {
        let settings = SettingsManager.shared.settings
        savedEventId = settings.getEventId()
        savedTeamNumber = settings.getTeamNumber()
        eventId = savedEventId
        teamNumber = savedTeamNumber
    }

    private func save() {
        guard hasChanges else { return }
        focusedField = nil

        let settings = SettingsManager.shared.settings
        settings.setEventId(eventId: eventId)
        settings.setTeamNumber(teamNumber: teamNumber)
        savedEventId = eventId
        savedTeamNumber = teamNumber
        isSaved = true

        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isSaved = false
        }
    }

    private func discard() {
        focusedField = nil
        eventId = savedEventId
        teamNumber = savedTeamNumber
    }
}

// MARK: - Subviews

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The availability check lives in a modifier, not around the `Image`.
/// Branching on `if #available` at the view level produces a different identity
/// per branch, so SwiftUI tears the image down and rebuilds it instead of
/// morphing — which silently kills the very symbol effect the branch exists to
/// apply. One `Image`, conditionally modified.
private struct ReplaceSymbolTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentTransition(.symbolEffect(.replace.byLayer.downUp))
        } else {
            content
        }
    }
}

/// Opens the picker rather than accepting free text. Event keys are not
/// something a user should have to know, and a typo used to mean a silent
/// failure that looked identical to the backend being down.
private struct EventPickerRow: View {
    let eventId: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Event")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
                Text(eventId)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(.system(.subheadline, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
}
