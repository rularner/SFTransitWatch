import SwiftUI

public struct SiriShortcutsView: View {
    public init() {}

    public var body: some View {
        List {
            Section(header: Text("Hands-free")) {
                SiriPhraseRow(phrase: "What's my next bus in SF Transit Watch")
                SiriPhraseRow(phrase: "Check route arrivals in SF Transit Watch")
            }

            Section(header: Text("Say to Siri")) {
                SiriPhraseRow(phrase: "Find nearby stops in SF Transit Watch")
                SiriPhraseRow(phrase: "Check bus times in SF Transit Watch")
                SiriPhraseRow(phrase: "When is the next bus in SF Transit Watch")
                SiriPhraseRow(phrase: "Show nearby bus stops in SF Transit Watch")
                SiriPhraseRow(phrase: "Show arrivals in SF Transit Watch")
                SiriPhraseRow(phrase: "Nearby transit in SF Transit Watch")
            }

            Section(header: Text("How it works")) {
                Text("The hands-free phrases speak the answer out loud without opening the app. After saying the phrase, Siri will ask you to specify the route or direction if needed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("The other phrases open SF Transit Watch directly to the relevant screen. No setup required — they work as soon as the app is installed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Siri")
    }
}

private struct SiriPhraseRow: View {
    let phrase: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundColor(.blue)
            Text(phrase)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        SiriShortcutsView()
    }
}
