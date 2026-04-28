import SwiftUI

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Couldn't load")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message). Tap Retry to try again.")
    }
}

#if DEBUG
#Preview {
    ErrorStateView(message: "Couldn't reach 511.org") { }
}
#endif
