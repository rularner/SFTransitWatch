import Foundation
import Testing
import CoreLocation
@testable import SFTransitWatchPackage

@Suite(.serialized)
@MainActor
struct LocationManagerAsyncTests {

    @Test func unauthorized_returnsNilImmediately() async {
        let manager = LocationManager()
        manager.authorizationStatus = .notDetermined
        let start = Date()
        let result = await manager.currentLocationOnce(timeout: 5)
        #expect(result == nil)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func authorizedWithExistingLocation_returnsImmediately() async {
        let manager = LocationManager()
        #if !os(macOS)
        manager.authorizationStatus = .authorizedWhenInUse
        #else
        manager.authorizationStatus = .authorizedAlways
        #endif
        manager.currentLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let start = Date()
        let result = await manager.currentLocationOnce(timeout: 5)
        #expect(result?.coordinate.latitude == 37.7749)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func authorizedNoLocationArrives_returnsNilAfterTimeout() async {
        let manager = LocationManager()
        #if !os(macOS)
        manager.authorizationStatus = .authorizedWhenInUse
        #else
        manager.authorizationStatus = .authorizedAlways
        #endif
        manager.currentLocation = nil
        let start = Date()
        let result = await manager.currentLocationOnce(timeout: 0.3)
        #expect(result == nil)
        #expect(Date().timeIntervalSince(start) >= 0.3)
    }

    @Test func authorizedLocationArrivesDuringWait_returnsPromptly() async {
        let manager = LocationManager()
        #if !os(macOS)
        manager.authorizationStatus = .authorizedWhenInUse
        #else
        manager.authorizationStatus = .authorizedAlways
        #endif
        manager.currentLocation = nil
        let expectedLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            manager.currentLocation = expectedLocation
        }

        let start = Date()
        let result = await manager.currentLocationOnce(timeout: 5)
        let elapsed = Date().timeIntervalSince(start)
        #expect(result?.coordinate.latitude == expectedLocation.coordinate.latitude)
        #expect(elapsed < 1)
    }
}
