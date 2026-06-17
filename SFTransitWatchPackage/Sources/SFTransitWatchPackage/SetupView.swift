import SwiftUI

public struct SetupView: View {
    let canSubscribe: Bool
    let onSubscribe: () -> Void
    let onUseKey: () -> Void

    public init(canSubscribe: Bool, onSubscribe: @escaping () -> Void, onUseKey: @escaping () -> Void) {
        self.canSubscribe = canSubscribe
        self.onSubscribe = onSubscribe
        self.onUseKey = onUseKey
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text("SF Transit Watch")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Set up data access to see nearby stops.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("SF Transit Watch. Set up data access to see nearby stops.")

            VStack(spacing: 12) {
                if canSubscribe {
                    VStack(spacing: 4) {
                        Button("Subscribe", action: onSubscribe)
                            .buttonStyle(.borderedProminent)
                        Text("Access transit via SF Transit Watch Server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 4) {
                    Button("Use 511.org API Key", action: onUseKey)
                        .buttonStyle(.bordered)
                    Text("Free key from 511.org — set it up yourself")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#if DEBUG
#Preview("Can subscribe") {
    SetupView(canSubscribe: true, onSubscribe: {}, onUseKey: {})
}

#Preview("No subscription") {
    SetupView(canSubscribe: false, onSubscribe: {}, onUseKey: {})
}
#endif
