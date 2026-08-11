import Foundation
@preconcurrency import CoreLocation

@MainActor
public class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published public var currentLocation: CLLocation?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isLocationEnabled = false
    private var hasReceivedAuthorizationCallback = false
    private var authorizationSettledContinuation: CheckedContinuation<Void, Never>?
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

        // Seed synchronously from CLLocationManager's own status rather than waiting on
        // the delegate's didChangeAuthorization callback. A freshly-constructed instance
        // (e.g. one made per Siri intent invocation in SiriIntents.swift) calls
        // currentLocationOnce() immediately with no suspension point beforehand, so the
        // delegate never gets a run-loop turn to fire before the isAuthorized check runs —
        // leaving authorizationStatus stuck at its .notDetermined default and making
        // currentLocationOnce() report "unauthorized" even when access was actually granted.
        authorizationStatus = locationManager.authorizationStatus

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
            group.addTask { [weak self] in
                // Wrapping the polling loop in a nested unstructured `Task` here isn't
                // just style: marking the `group.addTask` closure itself `@MainActor`
                // hits a Swift 6 region-isolation-checker compiler bug ("pattern that
                // the region-based isolation checker does not understand how to check")
                // — confirmed by an actual build attempt, not assumed. This nested Task
                // sidesteps that, but a nested unstructured Task is invisible to
                // `group.cancelAll()` unless we explicitly wire it up: `cancelAll()`
                // only marks *this* addTask closure as cancelled, it does not call
                // `.cancel()` on the inner Task by itself. `withTaskCancellationHandler`
                // below is what makes that real: when this outer task is cancelled,
                // `onCancel` fires and explicitly cancels `pollTask`, which makes its
                // `Task.checkCancellation()` actually throw and end the loop.
                guard let self else { return nil }
                let pollTask = Task { @MainActor () -> CLLocation? in
                    while true {
                        try Task.checkCancellation()
                        if let location = self.currentLocation {
                            return location
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
                return await withTaskCancellationHandler {
                    (try? await pollTask.value) ?? nil
                } onCancel: {
                    pollTask.cancel()
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
