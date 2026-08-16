import SwiftUI

struct RobotCheatSheetView: View {
    private let robot: RobotCheatSheet
    private let defaultRowUnits: [MetricField: UnitSystem]
    @State private var globalUnitSystem: UnitSystem?
    @State private var rowUnitOverrides: [MetricField: UnitSystem] = [:]

    init(robot: RobotCheatSheet = .defaultRobot) {
        self.robot = robot
        self.defaultRowUnits = Self.makeDefaultRowUnits(from: robot)
        _globalUnitSystem = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HeaderCard(robot: robot)

                    UnitToggleRow(onApplyToAll: applyGlobalUnitSystem)

                    CheatSheetSection(title: "Core Specs") {
                        ForEach(
                            Array(robot.coreSpecRows.enumerated()),
                            id: \.element.id
                        ) { index, row in
                            coreSpecRow(
                                row,
                                showsDivider: index < robot.coreSpecRows.count
                                    - 1
                            )
                        }
                    }

                    CheatSheetSection(title: "Dimensions") {
                        ForEach(
                            Array(robot.dimensionRows.enumerated()),
                            id: \.element.id
                        ) { index, row in
                            unitSpecRow(
                                row,
                                showsDivider: index < robot.dimensionRows.count
                                    - 1
                            )
                        }
                    }

                    CheatSheetSection(title: "Capabilities") {
                        ForEach(
                            Array(robot.capabilities.enumerated()),
                            id: \.element.id
                        ) { index, capability in
                            CapabilityRow(
                                capability: capability,
                                showsDivider: index < robot.capabilities.count
                                    - 1
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Robot Info")
        }
    }

    // MARK: - Unit logic

    private func toggleRowUnit(_ field: MetricField) {
        let next = effectiveUnitSystem(for: field).toggled
        let baseline = globalUnitSystem ?? defaultRowUnits[field] ?? .imperial
        if next == baseline {
            rowUnitOverrides.removeValue(forKey: field)
        } else {
            rowUnitOverrides[field] = next
        }
    }

    private func effectiveUnitSystem(for field: MetricField) -> UnitSystem {
        rowUnitOverrides[field] ?? globalUnitSystem ?? defaultRowUnits[field]
            ?? .imperial
    }

    private func applyGlobalUnitSystem(_ system: UnitSystem) {
        globalUnitSystem = system
        rowUnitOverrides.removeAll()
    }

    private static func makeDefaultRowUnits(
        from robot: RobotCheatSheet
    ) -> [MetricField: UnitSystem] {
        var defaults: [MetricField: UnitSystem] = [:]
        for row in robot.coreSpecRows {
            if case .unit(let unitRow) = row {
                defaults[unitRow.field] = unitSystem(for: unitRow.value)
            }
        }
        for row in robot.dimensionRows {
            defaults[row.field] = unitSystem(for: row.value)
        }
        return defaults
    }

    private static func unitSystem(for value: RobotCheatSheet.UnitValue)
        -> UnitSystem
    {
        switch value {
        case .mass(let mass):
            return isImperialMass(mass.unit.symbol) ? .imperial : .metric
        case .length(let length):
            return isImperialLength(length.unit.symbol) ? .imperial : .metric
        case .speed(let speed):
            return isImperialSpeed(speed.unit.symbol) ? .imperial : .metric
        }
    }

    private static func isImperialMass(_ symbol: String) -> Bool {
        let s = symbol.lowercased()
        return s == "lb" || s == "lbs" || s == "oz"
    }

    private static func isImperialLength(_ symbol: String) -> Bool {
        let s = symbol.lowercased()
        return s == "in" || s == "ft" || s == "yd" || s == "mi"
    }

    private static func isImperialSpeed(_ symbol: String) -> Bool {
        let s = symbol.lowercased()
        return s.contains("ft/s") || s == "mph"
    }

    // MARK: - Row builders

    @ViewBuilder
    private func coreSpecRow(
        _ row: RobotCheatSheet.CoreSpecRow,
        showsDivider: Bool
    ) -> some View {
        switch row {
        case .text(let textRow):
            TextMetricRow(
                label: textRow.label,
                value: textRow.value,
                showsDivider: showsDivider
            )
        case .unit(let unitRow):
            unitSpecRow(unitRow, showsDivider: showsDivider)
        }
    }

    private func unitSpecRow(
        _ row: RobotCheatSheet.UnitSpecRow,
        showsDivider: Bool
    ) -> some View {
        let formatted = formattedValue(row.value, for: row.field)
        return UnitMetricRow(
            label: row.label,
            value: formatted.value,
            unit: formatted.unit,
            onUnitTap: { toggleRowUnit(row.field) },
            showsDivider: showsDivider
        )
    }

    // MARK: - Formatting

    private func formattedValue(
        _ value: RobotCheatSheet.UnitValue,
        for field: MetricField
    ) -> (value: String, unit: String) {
        switch value {
        case .mass(let mass): return formattedMass(mass, for: field)
        case .length(let length): return formattedLength(length, for: field)
        case .speed(let speed): return formattedSpeed(speed, for: field)
        }
    }

    private func formattedMass(
        _ value: Measurement<UnitMass>,
        for field: MetricField
    ) -> (value: String, unit: String) {
        switch effectiveUnitSystem(for: field) {
        case .imperial:
            return (formatNumber(value.converted(to: .pounds).value), "lb")
        case .metric:
            return (formatNumber(value.converted(to: .kilograms).value), "kg")
        }
    }

    private func formattedLength(
        _ value: Measurement<UnitLength>,
        for field: MetricField
    ) -> (value: String, unit: String) {
        switch effectiveUnitSystem(for: field) {
        case .imperial:
            return (formatNumber(value.converted(to: .inches).value), "in")
        case .metric:
            return (formatNumber(value.converted(to: .centimeters).value), "cm")
        }
    }

    private func formattedSpeed(
        _ value: Measurement<UnitSpeed>,
        for field: MetricField
    ) -> (value: String, unit: String) {
        switch effectiveUnitSystem(for: field) {
        case .imperial:
            return (
                formatNumber(value.converted(to: .frcFeetPerSecond).value),
                "ft/s"
            )
        case .metric:
            return (
                formatNumber(value.converted(to: .metersPerSecond).value), "m/s"
            )
        }
    }

    private func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number))
            ?? String(format: "%.1f", number)
    }
}

// MARK: - Subviews

private struct HeaderCard: View {
    let robot: RobotCheatSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(robot.teamNumber)
                .font(.title2.bold())
            Text(robot.robotName)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Quick reference for scouts")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CheatSheetSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: title)
            VStack(spacing: 0) {
                content
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct UnitToggleRow: View {
    let onApplyToAll: (UnitSystem) -> Void

    var body: some View {
        HStack(spacing: 8) {
            unitButton(.imperial)
            unitButton(.metric)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // Built the same way as UnitMetricRow's unit pill: everything lives inside
    // the label, so the pill *is* the button and presses animate. Styling the
    // outside of a Button decorates a container the button doesn't know about.
    private func unitButton(_ system: UnitSystem) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                Button { onApplyToAll(system) } label: {
                    Text(system.title)
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .tint(.secondary)
                .buttonStyle(.glass)
            } else {
                Button { onApplyToAll(system) } label: {
                    Text(system.title)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TextMetricRow: View {
    let label: String
    let value: String
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showsDivider {
                Divider().padding(.leading, 14)
            }
        }
    }
}

// match TextUnitRow's styling please
private struct UnitMetricRow: View {
    let label: String
    let value: String
    let unit: String
    let onUnitTap: () -> Void
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Text(value).fontWeight(.semibold)
                    Group {
                        if #available(iOS 26.0, *) {
                            Button(action: onUnitTap) {
                                Text(unit).font(.footnote)
                            }
                            .tint(.secondary)
                            .buttonStyle(.glass)
                        } else {
                            Button(action: onUnitTap) {
                                Text(unit)
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Color(.tertiarySystemFill),
                                        in: Capsule()
                                    )
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showsDivider {
                Divider().padding(.leading, 14)
            }
        }
    }
}

private struct CapabilityRow: View {
    let capability: RobotCheatSheet.Capability
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(capability.name)
                    .font(.subheadline.weight(.semibold))
                Text(capability.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showsDivider {
                Divider().padding(.leading, 14)
            }
        }
    }
}

#Preview {
    RobotCheatSheetView()
}
