import SwiftUI

public struct CommuteSlotPickerView: View {
    public let slot: CommuteSlotsManager.Slot
    public let allFavorites: [BusStop]
    public let slotsManager: CommuteSlotsManager
    @Environment(\.dismiss) var dismiss

    public init(slot: CommuteSlotsManager.Slot, allFavorites: [BusStop], slotsManager: CommuteSlotsManager) {
        self.slot = slot
        self.allFavorites = allFavorites
        self.slotsManager = slotsManager
    }

    var selectedStopId: String? {
        slotsManager.stopId(for: slot)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Clear Selection")) {
                    Button(role: .destructive) {
                        slotsManager.setStopId(nil, for: slot)
                        dismiss()
                    } label: {
                        Text("None")
                            .foregroundColor(.red)
                    }
                }

                if !allFavorites.isEmpty {
                    Section(header: Text("Your Favorites")) {
                        ForEach(allFavorites) { stop in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                        .font(.headline)
                                    Text("Stop \(stop.code)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if stop.id == selectedStopId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                slotsManager.setStopId(stop.id, for: slot)
                                dismiss()
                            }
                        }
                    }
                }

                if allFavorites.isEmpty {
                    Section {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No Favorites Yet")
                                .font(.headline)
                            Text("Mark some stops as favorites to assign them here.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("\(slot.displayName) Stop")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
#Preview {
    CommuteSlotPickerView(
        slot: .morning,
        allFavorites: BusStop.previewStops,
        slotsManager: CommuteSlotsManager(userDefaultsSuiteName: "preview")
    )
}
#endif
