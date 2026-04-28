import XCTest
@testable import SFTransitWatch_Watch_App

@MainActor
final class FavoritesManagerTests: XCTestCase {

    private var manager: FavoritesManager!

    override func setUp() async throws {
        // Use a fresh UserDefaults suite per test run to avoid cross-test pollution
        let suiteName = "FavoritesManagerTests-\(UUID().uuidString)"
        manager = FavoritesManager(userDefaultsSuiteName: suiteName)
    }

    func testInitiallyEmpty() {
        XCTAssertTrue(manager.favoriteStopIds.isEmpty)
    }

    func testToggleAddsFavorite() {
        manager.toggleFavorite(for: "stop-1")
        XCTAssertTrue(manager.isFavorite("stop-1"))
    }

    func testToggleRemovesFavorite() {
        manager.toggleFavorite(for: "stop-1")
        manager.toggleFavorite(for: "stop-1")
        XCTAssertFalse(manager.isFavorite("stop-1"))
    }

    func testAddToFavorites() {
        manager.addToFavorites("stop-2")
        XCTAssertTrue(manager.isFavorite("stop-2"))
    }

    func testRemoveFromFavorites() {
        manager.addToFavorites("stop-3")
        manager.removeFromFavorites("stop-3")
        XCTAssertFalse(manager.isFavorite("stop-3"))
    }

    func testClearAllFavorites() {
        manager.addToFavorites("stop-1")
        manager.addToFavorites("stop-2")
        manager.clearAllFavorites()
        XCTAssertTrue(manager.favoriteStopIds.isEmpty)
    }

    func testGetFavoriteStopsFiltersCorrectly() {
        let stops = makeStops()
        manager.addToFavorites(stops[0].id)
        let favorites = manager.getFavoriteStops(from: stops)
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites[0].id, stops[0].id)
    }

    func testSortStopsWithFavoritesFirst() {
        let stops = makeStops()
        manager.addToFavorites(stops[1].id) // favorite the second stop
        let sorted = manager.sortStopsWithFavoritesFirst(stops)
        XCTAssertTrue(sorted[0].isFavorite)
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

    func testPersistenceAcrossInstances() {
        let suiteName = "FavoritesManagerTests-persistence-\(UUID().uuidString)"
        let first = FavoritesManager(userDefaultsSuiteName: suiteName)
        first.addToFavorites("stop-persist")

        let second = FavoritesManager(userDefaultsSuiteName: suiteName)
        XCTAssertTrue(second.isFavorite("stop-persist"))
    }
}
