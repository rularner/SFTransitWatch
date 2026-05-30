import Foundation

@MainActor
public class FavoritesManager: ObservableObject {
    @Published public var favoriteStops: [BusStop] = []
    @Published public var favoriteStopIds: Set<String> = []

    private let userDefaults: UserDefaults
    private let favoritesKey = "FavoriteStops"

    // Only the fields needed to identify a stop and re-fetch its arrivals.
    // Routes and isFavorite are intentionally excluded.
    private struct PersistedFavorite: Codable {
        let id: String
        let name: String
        let code: String
        let agency: String
        let latitude: Double
        let longitude: Double
    }

    public init(userDefaultsSuiteName: String? = nil) {
        let ud = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.userDefaults = ud
        loadFavorites()
        if SnapshotMode.isActive {
            favoriteStopIds = SnapshotMode.favoriteStopIDs
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFavoritesIfChanged() }
        }
    }

    private func reloadFavoritesIfChanged() {
        guard let data = userDefaults.data(forKey: favoritesKey),
              let persisted = try? JSONDecoder().decode([PersistedFavorite].self, from: data) else {
            if !favoriteStops.isEmpty { applyStops([]) }
            return
        }
        let newIds = Set(persisted.map(\.id))
        guard newIds != favoriteStopIds else { return }
        applyStops(persisted.map {
            BusStop(id: $0.id, name: $0.name, code: $0.code,
                    latitude: $0.latitude, longitude: $0.longitude, agency: $0.agency)
        })
    }

    public func toggleFavorite(_ stop: BusStop) {
        if favoriteStopIds.contains(stop.id) {
            favoriteStops.removeAll { $0.id == stop.id }
            favoriteStopIds.remove(stop.id)
        } else {
            favoriteStops.append(stop)
            favoriteStopIds.insert(stop.id)
        }
        saveFavorites()
    }

    public func removeFromFavorites(_ stop: BusStop) {
        favoriteStops.removeAll { $0.id == stop.id }
        favoriteStopIds.remove(stop.id)
        saveFavorites()
    }

    public func isFavorite(_ stopId: String) -> Bool {
        favoriteStopIds.contains(stopId)
    }

    public func getFavoriteStops(from allStops: [BusStop]) -> [BusStop] {
        allStops.filter { favoriteStopIds.contains($0.id) }
    }

    public func sortStopsWithFavoritesFirst(_ stops: [BusStop]) -> [BusStop] {
        var result = stops
        for i in 0..<result.count {
            result[i].isFavorite = favoriteStopIds.contains(result[i].id)
        }
        return result.sorted { $0.isFavorite && !$1.isFavorite }
    }

    public func clearAllFavorites() {
        favoriteStops.removeAll()
        favoriteStopIds.removeAll()
        saveFavorites()
    }

    private func applyStops(_ stops: [BusStop]) {
        favoriteStops = stops
        favoriteStopIds = Set(stops.map { $0.id })
    }

    private func loadFavorites() {
        guard let data = userDefaults.data(forKey: favoritesKey),
              let persisted = try? JSONDecoder().decode([PersistedFavorite].self, from: data) else { return }
        applyStops(persisted.map {
            BusStop(id: $0.id, name: $0.name, code: $0.code,
                    latitude: $0.latitude, longitude: $0.longitude, agency: $0.agency)
        })
    }

    private func saveFavorites() {
        let persisted = favoriteStops.map {
            PersistedFavorite(id: $0.id, name: $0.name, code: $0.code,
                              agency: $0.agency, latitude: $0.latitude, longitude: $0.longitude)
        }
        if let data = try? JSONEncoder().encode(persisted) {
            userDefaults.set(data, forKey: favoritesKey)
        }
    }
}
