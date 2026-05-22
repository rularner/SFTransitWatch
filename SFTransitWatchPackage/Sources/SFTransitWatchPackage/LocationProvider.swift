import Foundation
import CoreLocation

/// Wraps CLLocationManager.requestLocation() as a single async call.
/// Throws if location services are disabled or authorization is denied.
/// BackgroundRefreshController wraps calls in try? so failures are silent.
@MainActor
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    public static func requestLocation() async throws -> CLLocation {
        let provider = LocationProvider()
        return try await provider.fetch()
    }

    private func fetch() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor [weak self] in
            guard let c = self?.continuation else { return }
            self?.continuation = nil
            c.resume(returning: locations[0])
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let c = self?.continuation else { return }
            self?.continuation = nil
            c.resume(throwing: error)
        }
    }
}
