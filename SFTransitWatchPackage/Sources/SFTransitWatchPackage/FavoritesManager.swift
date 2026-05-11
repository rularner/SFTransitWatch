import Foundation

@MainActor
public class FavoritesManager: ObservableObject {
    @Published public var favoriteStopIds: Set<String> = []

    private let userDefaults: UserDefaults
    private let favoritesKey = "FavoriteStopIds"

    public init(userDefaultsSuiteName: String? = nil) {
        self.userDefaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        loadFavorites()

        // SnapshotMode: seed favorites in-memory so the screenshot shows the Favorites section.
        if SnapshotMode.isActive {
            favoriteStopIds = SnapshotMode.favoriteStopIDs
        }
    }

    public func toggleFavorite(for stopId: String) {
        if favoriteStopIds.contains(stopId) {
            favoriteStopIds.remove(stopId)
        } else {
            favoriteStopIds.insert(stopId)
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
        if let data = userDefaults.data(forKey: favoritesKey),
           let favorites = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favoriteStopIds = favorites
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteStopIds) {
            userDefaults.set(data, forKey: favoritesKey)
        }
    }

    public func clearAllFavorites() {
        favoriteStopIds.removeAll()
        saveFavorites()
    }
}
