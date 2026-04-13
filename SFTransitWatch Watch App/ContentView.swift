import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            BusStopListView()
                .navigationTitle("SF Transit")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
} 