import Foundation
@preconcurrency import CoreLocation

@MainActor
public class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published public var currentLocation: CLLocation?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isLocationEnabled = false
    @Published public var currentHeading: CLHeading?

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.headingFilter = 5

        if SnapshotMode.isActive {
            currentLocation = SnapshotMode.fixedLocation
        }
    }

    public func requestLocationPermission() {
        if SnapshotMode.isActive { return }
        locationManager.requestWhenInUseAuthorization()
    }

    public func startLocationUpdates() {
        if SnapshotMode.isActive {
            currentLocation = SnapshotMode.fixedLocation
            return
        }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        isLocationEnabled = true
    }

    public func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        isLocationEnabled = false
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
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                startLocationUpdates()
            case .denied, .restricted:
                isLocationEnabled = false
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            currentHeading = newHeading
        }
    }
}
