import SwiftUI
import CoreLocation

/// Picks the heading angle to display: prefers `trueHeading` (accounts for
/// magnetic declination) when it is ≥ 0, falls back to `magneticHeading`.
/// `trueHeading` is negative when CoreLocation hasn't produced a calibrated value.
func effectiveHeadingDegrees(trueHeading: Double, magneticHeading: Double) -> Double {
    trueHeading >= 0 ? trueHeading : magneticHeading
}

public struct StopLocationView: View {
    let stop: BusStop
    let currentLocation: CLLocation?
    let currentHeading: CLHeading?
    let isHeadingEnabled: Bool

    public init(stop: BusStop, currentLocation: CLLocation?, currentHeading: CLHeading?, isHeadingEnabled: Bool) {
        self.stop = stop
        self.currentLocation = currentLocation
        self.currentHeading = currentHeading
        self.isHeadingEnabled = isHeadingEnabled
    }

    private var bearing: Double {
        guard let currentLocation = currentLocation else { return 0 }
        let lat1 = currentLocation.coordinate.latitude * .pi / 180
        let lat2 = stop.latitude * .pi / 180
        let dlon = (stop.longitude - currentLocation.coordinate.longitude) * .pi / 180

        let y = sin(dlon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private var distance: String {
        guard let currentLocation = currentLocation else { return "—" }
        let distanceMeters = stop.distance(to: currentLocation)
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters))m"
        } else {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
    }

    private var bearingLabel: String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((bearing + 11.25) / 22.5) % 16
        return directions[index]
    }

    private var headingDegrees: Double? {
        guard let h = currentHeading else { return nil }
        return effectiveHeadingDegrees(trueHeading: h.trueHeading, magneticHeading: h.magneticHeading)
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)

                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    .padding(14)

                VStack(spacing: 4) {
                    Text("N")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 6)

                VStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                }
                .rotationEffect(.degrees(bearing))

                VStack(spacing: 1) {
                    Text("\(Int(bearing))°")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(bearingLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .rotationEffect(.degrees(headingDegrees ?? 0))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
            }
            .frame(height: 120)
            .padding(.horizontal, 8)
            .rotationEffect(.degrees(-(headingDegrees ?? 0)))
            .animation(.easeOut(duration: 0.15), value: headingDegrees)

            if isHeadingEnabled && headingDegrees == nil {
                Text("Compass unavailable")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(distance)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Stop")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(stop.code)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

#Preview {
    StopLocationView(
        stop: BusStop(
            id: "15552",
            name: "Castro Station",
            code: "15552",
            latitude: 37.7395,
            longitude: -122.4348,
            agency: "SF"
        ),
        currentLocation: CLLocation(latitude: 37.7858, longitude: -122.4064),
        currentHeading: nil,
        isHeadingEnabled: false
    )
    .padding()
}
