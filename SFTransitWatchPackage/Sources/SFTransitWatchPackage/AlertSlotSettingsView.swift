import SwiftUI

public struct AlertSlotSettingsView: View {
    public let slot: CommuteSlotsManager.Slot
    @ObservedObject public var alertSettings: AlertSettingsManager

    public init(slot: CommuteSlotsManager.Slot, alertSettings: AlertSettingsManager) {
        self.slot = slot
        self.alertSettings = alertSettings
    }

    public var body: some View {
        List {
            Section(header: Text("Travel Time")) {
                Stepper(
                    "Travel time: \(alertSettings.travelMinutes(for: slot)) min",
                    value: travelBinding,
                    in: 0...90
                )
                .font(.caption)
            }

            Section(header: Text("Alert Window")) {
                DatePicker(
                    "Earliest",
                    selection: windowStartBinding,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Latest",
                    selection: windowEndBinding,
                    displayedComponents: .hourAndMinute
                )
            }
            .font(.caption)

            if alertSettings.isAtStopSuppressed(for: slot) {
                Section {
                    HStack {
                        Text("Suppressed until midnight")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                        Button("Clear") {
                            alertSettings.clearAtStopSuppression(for: slot)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("\(slot.displayName) Alerts")
    }

    // MARK: - Bindings

    private var travelBinding: Binding<Int> {
        Binding(
            get: { alertSettings.travelMinutes(for: slot) },
            set: { alertSettings.setTravelMinutes($0, for: slot) }
        )
    }

    private var windowStartBinding: Binding<Date> {
        Binding(
            get: { date(from: alertSettings.windowStart(for: slot)) },
            set: { alertSettings.setWindowStart(components(from: $0), for: slot) }
        )
    }

    private var windowEndBinding: Binding<Date> {
        Binding(
            get: { date(from: alertSettings.windowEnd(for: slot)) },
            set: { alertSettings.setWindowEnd(components(from: $0), for: slot) }
        )
    }

    // MARK: - Helpers

    private func date(from dc: DateComponents) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour   = dc.hour   ?? 0
        comps.minute = dc.minute ?? 0
        return Calendar.current.date(from: comps) ?? .now
    }

    private func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: date)
    }
}

#Preview {
    NavigationStack {
        AlertSlotSettingsView(
            slot: .morning,
            alertSettings: AlertSettingsManager(userDefaultsSuiteName: nil)
        )
    }
}
