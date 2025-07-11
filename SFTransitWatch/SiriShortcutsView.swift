import SwiftUI
import IntentsUI

struct SiriShortcutsView: View {
    @StateObject private var siriManager = SiriManager()
    @State private var showingAddShortcut = false
    @State private var selectedShortcut: INShortcut?
    
    var body: some View {
        List {
            Section(header: Text("Siri Integration")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice Commands")
                        .font(.headline)
                    
                    Text("Use Siri to quickly check bus times and find nearby stops")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Available Shortcuts")) {
                Button(action: {
                    selectedShortcut = siriManager.createNearbyStopsShortcut()
                    showingAddShortcut = true
                }) {
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Find Nearby Stops")
                                .font(.headline)
                            Text("Locate bus stops near your current location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    selectedShortcut = siriManager.createRouteSpecificShortcut()
                    showingAddShortcut = true
                }) {
                    HStack {
                        Image(systemName: "bus.circle.fill")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text("Route-Specific Times")
                                .font(.headline)
                            Text("Check times for specific bus/train routes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle")
                            .foregroundColor(.green)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    // This would be for a specific stop - for demo we'll use a sample
                    selectedShortcut = siriManager.createBusArrivalShortcut(
                        for: "1",
                        stopName: "Market St & 4th St"
                    )
                    showingAddShortcut = true
                }) {
                    HStack {
                        Image(systemName: "clock.circle.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text("Check Bus Times")
                                .font(.headline)
                            Text("Get arrival times for a specific stop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle")
                            .foregroundColor(.orange)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Section(header: Text("Route-Specific Commands")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask for specific routes:")
                        .font(.headline)
                    
                    ForEach(SiriManager.routeSpecificCommands, id: \.self) { command in
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text(command)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Common Routes")) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(SiriManager.commonRoutes, id: \.self) { route in
                        Text(route)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("General Voice Commands")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try saying:")
                        .font(.headline)
                    
                    ForEach(SiriManager.siriCommands, id: \.self) { command in
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text(command)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("How It Works")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Add shortcuts to Siri")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("2. Say 'Hey Siri' followed by the command")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("3. For routes: 'Hey Siri, when is the next 38 bus'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("4. Get quick access to transit information")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Siri Shortcuts")
        .sheet(isPresented: $showingAddShortcut) {
            if let shortcut = selectedShortcut {
                AddShortcutView(shortcut: shortcut)
            }
        }
        .onAppear {
            siriManager.setupSiriShortcuts()
        }
    }
}

struct AddShortcutView: UIViewControllerRepresentable {
    let shortcut: INShortcut
    
    func makeUIViewController(context: Context) -> INUIAddVoiceShortcutViewController {
        let addVoiceShortcutViewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        addVoiceShortcutViewController.delegate = context.coordinator
        return addVoiceShortcutViewController
    }
    
    func updateUIViewController(_ uiViewController: INUIAddVoiceShortcutViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, INUIAddVoiceShortcutViewControllerDelegate {
        let parent: AddShortcutView
        
        init(_ parent: AddShortcutView) {
            self.parent = parent
        }
        
        func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
            controller.dismiss(animated: true)
        }
        
        func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    NavigationView {
        SiriShortcutsView()
    }
} 