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
        let stops = BusStop.sampleStops
        manager.addToFavorites(stops[0].id)
        let favorites = manager.getFavoriteStops(from: stops)
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites[0].id, stops[0].id)
    }

    func testSortStopsWithFavoritesFirst() {
        let stops = BusStop.sampleStops
        manager.addToFavorites(stops[1].id) // favorite the second stop
        let sorted = manager.sortStopsWithFavoritesFirst(stops)
        XCTAssertTrue(sorted[0].isFavorite)
    }

    func testPersistenceAcrossInstances() {
        let suiteName = "FavoritesManagerTests-persistence-\(UUID().uuidString)"
        let first = FavoritesManager(userDefaultsSuiteName: suiteName)
        first.addToFavorites("stop-persist")

        let second = FavoritesManager(userDefaultsSuiteName: suiteName)
        XCTAssertTrue(second.isFavorite("stop-persist"))
    }
}
