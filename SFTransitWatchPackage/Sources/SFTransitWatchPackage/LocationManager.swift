import Foundation
@preconcurrency import CoreLocation

@MainActor
public class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published public var currentLocation: CLLocation?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isLocationEnabled = false
    // Heading (compass) is only available on iOS/watchOS. The macOS build of this
    // package exists purely so `swift test` can run the logic tests on the host,
    // so heading is compiled out there. CLHeading itself doesn't exist on macOS.
    #if !os(macOS)
    @Published public var currentHeading: CLHeading?
    #endif

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        #if !os(macOS)
        locationManager.headingFilter = 5
        #endif

        if SnapshotMode.isActive {
            currentLocation = SnapshotMode.fixedLocation
        }
    }

    public func requestLocationPermission() {
        if SnapshotMode.isActive { return }
        locationManager.requestWhenInUseAuthorization()
    }

    private var isAuthorized: Bool {
        #if os(macOS)
        return authorizationStatus == .authorizedAlways
        #else
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #endif
    }

    public func startLocationUpdates() {
        if SnapshotMode.isActive {
            currentLocation = SnapshotMode.fixedLocation
            return
        }
        guard isAuthorized else {
            requestLocationPermission()
            return
        }
        locationManager.startUpdatingLocation()
        #if !os(macOS)
        locationManager.startUpdatingHeading()
        #endif
        isLocationEnabled = true
    }

    public func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        #if !os(macOS)
        locationManager.stopUpdatingHeading()
        #endif
        isLocationEnabled = false
    }

    public func currentLocationOnce(timeout: TimeInterval) async -> CLLocation? {
        if SnapshotMode.isActive {
            return SnapshotMode.fixedLocation
        }
        guard isAuthorized else {
            return nil
        }
        if let currentLocation {
            return currentLocation
        }
        startLocationUpdates()
        defer { stopLocationUpdates() }

        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    return try await Task { @MainActor [weak self] () -> CLLocation? in
                        guard let self else { return nil }
                        let startTime = Date()
                        while Date().timeIntervalSince(startTime) < timeout {
                            try Task.checkCancellation()
                            if let location = self.currentLocation {
                                return location
                            }
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                        return nil
                    }.value
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            authorizationStatus = status
            if isAuthorized {
                startLocationUpdates()
            } else if status == .denied || status == .restricted {
                isLocationEnabled = false
            }
        }
    }

    #if !os(macOS)
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            currentHeading = newHeading
        }
    }
    #endif
}
