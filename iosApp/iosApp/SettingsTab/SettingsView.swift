import ComposeApp
import SwiftUI

/// Settings apply as they're made. There is no Save button, for the same reason
/// the Settings app doesn't have one: nothing here is destructive, expensive, or only meaningful as a set.
///
/// The event picker commits on selection.
/// The team number commits when the field loses focus or the app leaves the foreground (never per keystroke),
/// or any future subscription built on it would fire four times.
struct SettingsView: View {
    @State private var eventId = ""
    @State private var teamNumber = ""

    /// Not shown anywhere. This exists only so `commitTeamNumber()` is idempotent:
    /// it's called from focus changes and scene phase changes, both of which fire
    /// on first appearance and on every backgrounding, and neither should write
    /// when nothing was typed.
    @State private var committedTeamNumber = ""

    @State private var showEventPicker = false
    @State private var showResetConfirmation = false

    @AppStorage(LiveActivityPreference.key)
    private var liveActivityEnabled = LiveActivityPreference.defaultValue

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedField: Field?

    private enum Field {
        case teamNumber
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    liveActivitySection
                    resetSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showEventPicker) {
            EventPickerView(currentEventId: eventId, onSelect: selectEvent)
        }
        .onAppear(perform: loadSettings)
        // task(id:) rather than onChange — one API that works on iOS 16.
        .task(id: focusedField) {
            if focusedField == nil { commitTeamNumber() }
        }
        .task(id: scenePhase) {
            if scenePhase != .active { commitTeamNumber() }
        }
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
            Text(
                "The event determines which schedule is loaded. Leave the team number empty for no highlighting."
            )
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

    /// The one control here that warrants a confirmation. Everything else applies silently because it's trivially reversible
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                Button {
                    focusedField = nil
                    showResetConfirmation = true
                } label: {
                    Text("Reset to defaults")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Restores the default event, clears your team number, and turns the Live Activity back on.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .confirmationDialog(
            "Reset all settings to their defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive, action: resetToDefaults)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
                .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        let settings = SettingsManager.shared.settings
        eventId = settings.getEventId()
        teamNumber = settings.getTeamNumber()
        committedTeamNumber = teamNumber
    }

    /// An atomic choice from a finite list, so it persists on selection. Waiting
    /// for a blur would never fire — dismissing a sheet isn't a focus change.
    private func selectEvent(_ selected: String) {
        eventId = selected
        SettingsManager.shared.settings.setEventId(eventId: selected)
    }

    private func commitTeamNumber() {
        // numberPad doesn't stop a paste, and a team number that isn't digits is
        // a subscription key waiting to fail. Cleaned on blur rather than while
        // typing, so the caret never jumps.
        let cleaned = teamNumber.filter(\.isNumber)
        if cleaned != teamNumber { teamNumber = cleaned }

        guard cleaned != committedTeamNumber else { return }
        SettingsManager.shared.settings.setTeamNumber(teamNumber: cleaned)
        committedTeamNumber = cleaned
    }

    private func resetToDefaults() {
        focusedField = nil

        let settings = SettingsManager.shared.settings
        settings.resetToDefaults()

        // Read back rather than assuming, the defaults live in Storage.kt.
        eventId = settings.getEventId()
        teamNumber = settings.getTeamNumber()
        committedTeamNumber = teamNumber

        // Held in @AppStorage, so it's outside resetToDefaults()' reach.
        liveActivityEnabled = LiveActivityPreference.defaultValue
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
