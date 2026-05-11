import Foundation
import SFTransitWatchPackage

@MainActor
class PinnedStopsManager: ObservableObject {
    @Published var pinned: [BusStop] = []

    private let userDefaults: UserDefaults
    private let storageKey = "PinnedStops"

    init(userDefaultsSuiteName: String? = nil) {
        self.userDefaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        load()

        // SnapshotMode: seed pinned stops in-memory so the screenshot shows the Pinned section.
        if SnapshotMode.isActive {
            pinned = SnapshotMode.pinnedStops
        }
    }

    func pin(_ stop: BusStop) {
        guard !pinned.contains(where: { $0.id == stop.id }) else { return }
        pinned.append(stop)
        save()
    }

    func unpin(at offsets: IndexSet) {
        pinned.remove(atOffsets: offsets)
        save()
    }

    func unpin(id: String) {
        pinned.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BusStop].self, from: data) else {
            return
        }
        pinned = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pinned) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
