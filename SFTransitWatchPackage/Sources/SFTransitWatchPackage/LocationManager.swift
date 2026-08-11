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

        // Seed synchronously from CLLocationManager's own status as a best-effort default —
        // better than the .notDetermined default above, but NOT authoritative. CoreLocation
        // resolves authorizationStatus asynchronously via locationd; on a freshly-started
        // process the very first synchronous read of this property can itself still return a
        // stale value, corrected moments later through the delegate's authorization-change
        // callback below. Callers that need the authoritative status (like Siri intents,
        // which construct a fresh LocationManager per invocation and may run in a cold
        // process — see SiriIntents.swift) should use `awaitingAuthorization()` instead of
        // this initializer directly.
        authorizationStatus = locationManager.authorizationStatus

        if SnapshotMode.isActive {
            currentLocation = SnapshotMode.fixedLocation
        }
    }

    public func requestLocationPermission() {
        if SnapshotMode.isActive { return }
        locationManager.requestWhenInUseAuthorization()
    }

    /// Constructs a `LocationManager` and waits for the authoritative authorization status
    /// from CoreLocation's delegate callback (bounded, in case it never arrives) before
    /// returning, instead of trusting the synchronous best-effort seed in `init()`. Use this
    /// at call sites — like Siri intents — that check `isAuthorized`/call
    /// `currentLocationOnce()` immediately with no other suspension point beforehand, where a
    /// stale cold-process seed would otherwise be mistaken for the real status.
    public static func awaitingAuthorization() async -> LocationManager {
        let manager = LocationManager()
        await manager.waitForAuthorizationSettled()
        return manager
    }

    private func waitForAuthorizationSettled() async {
        guard !hasReceivedAuthorizationCallback else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            authorizationSettledContinuation = continuation
            // Bounded fallback in case the delegate callback never arrives: resumes and
            // clears the continuation itself, so if the callback (which does the same thing)
            // already ran first, this is a harmless no-op via the nil check.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.authorizationSettledContinuation?.resume()
                self.authorizationSettledContinuation = nil
            }
        }
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
            hasReceivedAuthorizationCallback = true
            authorizationSettledContinuation?.resume()
            authorizationSettledContinuation = nil
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
