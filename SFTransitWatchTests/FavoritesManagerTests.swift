import XCTest
import SFTransitWatchPackage

@MainActor
final class FavoritesManagerTests: XCTestCase {

    private var manager: FavoritesManager!

    override func setUp() async throws {
        let suiteName = "FavoritesManagerTests-\(UUID().uuidString)"
        manager = FavoritesManager(userDefaultsSuiteName: suiteName)
    }

    func testInitiallyEmpty() {
        XCTAssertTrue(manager.favoriteStopIds.isEmpty)
    }

    func testToggleAddsFavorite() {
        let stop = makeStops()[0]
        manager.toggleFavorite(stop)
        XCTAssertTrue(manager.isFavorite(stop.id))
        XCTAssertEqual(manager.favoriteStops.count, 1)
        XCTAssertEqual(manager.favoriteStops[0].id, stop.id)
    }

    func testToggleRemovesFavorite() {
        let stop = makeStops()[0]
        manager.toggleFavorite(stop)
        manager.toggleFavorite(stop)
        XCTAssertFalse(manager.isFavorite(stop.id))
        XCTAssertTrue(manager.favoriteStops.isEmpty)
    }

    func testAddToFavorites() {
        let stop = makeStops()[1]
        manager.toggleFavorite(stop)
        XCTAssertTrue(manager.isFavorite(stop.id))
    }

    func testRemoveFromFavorites() {
        let stop = makeStops()[2]
        manager.toggleFavorite(stop)
        manager.removeFromFavorites(stop)
        XCTAssertFalse(manager.isFavorite(stop.id))
    }

    func testClearAllFavorites() {
        let stops = makeStops()
        manager.toggleFavorite(stops[0])
        manager.toggleFavorite(stops[1])
        manager.clearAllFavorites()
        XCTAssertTrue(manager.favoriteStopIds.isEmpty)
    }

    func testGetFavoriteStopsFiltersCorrectly() {
        let stops = makeStops()
        manager.toggleFavorite(stops[0])
        let favorites = manager.getFavoriteStops(from: stops)
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites[0].id, stops[0].id)
    }

    func testSortStopsWithFavoritesFirst() {
        let stops = makeStops()
        manager.toggleFavorite(stops[1])
        let sorted = manager.sortStopsWithFavoritesFirst(stops)
        XCTAssertTrue(sorted[0].isFavorite)
    }

    func testPersistenceAcrossInstances() {
        let suiteName = "FavoritesManagerTests-persistence-\(UUID().uuidString)"
        let stop = makeStops()[0]
        let first = FavoritesManager(userDefaultsSuiteName: suiteName)
        first.toggleFavorite(stop)

        let second = FavoritesManager(userDefaultsSuiteName: suiteName)
        XCTAssertTrue(second.isFavorite(stop.id))
        XCTAssertEqual(second.favoriteStops.count, 1)
        XCTAssertEqual(second.favoriteStops[0].name, stop.name)
    }

    // MARK: - External reload (WatchConnectivity sync)

    func testExternalWriteReloadsPublishedProperties() async throws {
        let suite = "FavoritesManagerTests-external-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = FavoritesManager(userDefaultsSuiteName: suite)

        XCTAssertTrue(mgr.favoriteStops.isEmpty)

        // Encode a stop and write directly, simulating WC delivery
        let stop = makeStops()[0]
        struct Persisted: Codable { let id, name, code, agency: String; let latitude, longitude: Double }
        let data = try JSONEncoder().encode([Persisted(id: stop.id, name: stop.name, code: stop.code,
                                                       agency: stop.agency, latitude: stop.latitude,
                                                       longitude: stop.longitude)])
        ud.set(data, forKey: "FavoriteStops")

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mgr.favoriteStops.count, 1)
        XCTAssertTrue(mgr.isFavorite(stop.id))
    }

    func testExternalClearReloadsPublishedProperties() async throws {
        let suite = "FavoritesManagerTests-clear-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        let mgr = FavoritesManager(userDefaultsSuiteName: suite)
        mgr.toggleFavorite(makeStops()[0])
        XCTAssertEqual(mgr.favoriteStops.count, 1)

        // External clear (e.g. watch cleared its favorites)
        ud.removeObject(forKey: "FavoriteStops")

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(mgr.favoriteStops.isEmpty)
    }

    func testRoutesAreNotPersisted() {
        let suiteName = "FavoritesManagerTests-routes-\(UUID().uuidString)"
        let stop = makeStops()[0] // has routes: ["38"]
        let first = FavoritesManager(userDefaultsSuiteName: suiteName)
        first.toggleFavorite(stop)

        let second = FavoritesManager(userDefaultsSuiteName: suiteName)
        XCTAssertTrue(second.isFavorite(stop.id))
        XCTAssertTrue(second.favoriteStops[0].routes.isEmpty,
                      "Routes should not be persisted — they come from live API data")
    }

    private func makeStops() -> [BusStop] {
        return [
            BusStop(id: "1", name: "Test Stop One", code: "1",
                    latitude: 37.7749, longitude: -122.4194,
                    routes: ["38"], agency: "SF"),
            BusStop(id: "2", name: "Test Stop Two", code: "2",
                    latitude: 37.7849, longitude: -122.4094,
                    routes: ["14"], agency: "SF"),
            BusStop(id: "3", name: "Test Stop Three", code: "3",
                    latitude: 37.7649, longitude: -122.4294,
                    routes: ["F"], agency: "SF")
        ]
    }
}
