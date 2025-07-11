import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            BusStopListView()
                .navigationTitle("SF Transit")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
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