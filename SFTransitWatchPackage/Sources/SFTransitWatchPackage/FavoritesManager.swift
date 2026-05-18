import Foundation

@MainActor
public class FavoritesManager: ObservableObject {
    @Published public var favoriteStopIds: Set<String> = []
    /// Full stop objects, persisted so they're available without a live API call.
    @Published public var favoriteStops: [BusStop] = []

    private let userDefaults: UserDefaults
    private let favoritesKey = "FavoriteStopIds"
    private let favoriteStopsKey = "FavoriteStopObjects"

    public init(userDefaultsSuiteName: String? = nil) {
        self.userDefaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        loadFavorites()

        // SnapshotMode: seed favorites in-memory so the screenshot shows the Favorites section.
        if SnapshotMode.isActive {
            favoriteStopIds = SnapshotMode.favoriteStopIDs
        }
    }

    public func toggleFavorite(_ stop: BusStop) {
        if favoriteStopIds.contains(stop.id) {
            favoriteStopIds.remove(stop.id)
            favoriteStops.removeAll { $0.id == stop.id }
        } else {
            favoriteStopIds.insert(stop.id)
            favoriteStops.append(stop)
        }
        saveFavorites()
    }

    public func isFavorite(_ stopId: String) -> Bool {
        return favoriteStopIds.contains(stopId)
    }

    public func addToFavorites(_ stopId: String) {
        favoriteStopIds.insert(stopId)
        saveFavorites()
    }

    public func removeFromFavorites(_ stopId: String) {
        favoriteStopIds.remove(stopId)
        favoriteStops.removeAll { $0.id == stopId }
        saveFavorites()
    }

    public func getFavoriteStops(from allStops: [BusStop]) -> [BusStop] {
        return allStops.filter { favoriteStopIds.contains($0.id) }
    }

    public func sortStopsWithFavoritesFirst(_ stops: [BusStop]) -> [BusStop] {
        var sortedStops = stops

        for i in 0..<sortedStops.count {
            sortedStops[i].isFavorite = favoriteStopIds.contains(sortedStops[i].id)
        }

        return sortedStops.sorted { stop1, stop2 in
            if stop1.isFavorite != stop2.isFavorite {
                return stop1.isFavorite
            }
            return false
        }
    }

    private func loadFavorites() {
        // Full stop objects are authoritative when present (written by toggleFavorite).
        // Ignore an empty stops array — fall through to the ID-only key so that
        // addToFavorites (which only writes IDs) isn't silently shadowed by a stale
        // empty-array entry written during a previous clearAllFavorites or remove.
        if let data = userDefaults.data(forKey: favoriteStopsKey),
           let stops = try? JSONDecoder().decode([BusStop].self, from: data),
           !stops.isEmpty {
            favoriteStops = stops
            favoriteStopIds = Set(stops.map { $0.id })
            return
        }
        // Fall back to legacy ID-only storage (migrates automatically on next toggleFavorite).
        if let data = userDefaults.data(forKey: favoritesKey),
           let favorites = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favoriteStopIds = favorites
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteStopIds) {
            userDefaults.set(data, forKey: favoritesKey)
        }
        if let data = try? JSONEncoder().encode(favoriteStops) {
            userDefaults.set(data, forKey: favoriteStopsKey)
        }
    }

    public func clearAllFavorites() {
        favoriteStopIds.removeAll()
        favoriteStops.removeAll()
        saveFavorites()
    }
}
