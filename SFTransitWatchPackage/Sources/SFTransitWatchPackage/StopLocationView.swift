import SwiftUI
import CoreLocation

public struct StopLocationView: View {
    let stop: BusStop
    let currentLocation: CLLocation?

    public init(stop: BusStop, currentLocation: CLLocation?) {
        self.stop = stop
        self.currentLocation = currentLocation
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

    public var body: some View {
        VStack(spacing: 16) {
            Text("Stop Location")
                .font(.headline)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)

                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    .padding(20)

                VStack(spacing: 4) {
                    Text("N")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)

                VStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                }
                .rotationEffect(.degrees(bearing))

                VStack(spacing: 2) {
                    Text("\(Int(bearing))°")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(bearingLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
            }
            .frame(height: 200)
            .padding()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(distance)
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Stop")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(stop.code)
                        .font(.headline)
                        .monospacedDigit()
                }
            }
            .padding()
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
        currentLocation: CLLocation(latitude: 37.7858, longitude: -122.4064)
    )
    .padding()
}
