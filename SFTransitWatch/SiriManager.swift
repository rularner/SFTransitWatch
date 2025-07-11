import Foundation
import Intents
import IntentsUI

@MainActor
class SiriManager: ObservableObject {
    @Published var isSiriEnabled = false
    
    func setupSiriShortcuts() {
        // Check if Siri is available
        if #available(watchOS 9.0, *) {
            isSiriEnabled = true
        }
    }
    
    func createNearbyStopsShortcut() -> INShortcut? {
        guard let intent = createNearbyStopsIntent() else { return nil }
        return INShortcut(intent: intent)
    }
    
    func createBusArrivalShortcut(for stopId: String, stopName: String) -> INShortcut? {
        guard let intent = createBusArrivalIntent(stopId: stopId, stopName: stopName) else { return nil }
        return INShortcut(intent: intent)
    }
    
    func createRouteSpecificShortcut() -> INShortcut? {
        guard let intent = createRouteSpecificIntent() else { return nil }
        return INShortcut(intent: intent)
    }
    
    private func createNearbyStopsIntent() -> INIntent? {
        // Create a custom intent for finding nearby stops
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Find nearby bus stops"
        return intent
    }
    
    private func createBusArrivalIntent(stopId: String, stopName: String) -> INIntent? {
        // Create a custom intent for checking bus arrivals
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Check bus times for \(stopName)"
        return intent
    }
    
    private func createRouteSpecificIntent() -> INIntent? {
        // Create a custom intent for route-specific queries
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "When is the next [route] bus"
        return intent
    }
    
    func donateNearbyStopsIntent() {
        guard let intent = createNearbyStopsIntent() else { return }
        
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate nearby stops intent: \(error)")
            }
        }
    }
    
    func donateBusArrivalIntent(stopId: String, stopName: String) {
        guard let intent = createBusArrivalIntent(stopId: stopId, stopName: stopName) else { return }
        
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate bus arrival intent: \(error)")
            }
        }
    }
    
    func donateRouteSpecificIntent(route: String) {
        guard let intent = createRouteSpecificIntent() else { return }
        
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate route-specific intent: \(error)")
            }
        }
    }
    
    // Parse route from voice command
    func parseRouteFromCommand(_ command: String) -> String? {
        let patterns = [
            "when is the next (\\w+) bus",
            "when is the next (\\w+) train", 
            "when is the next (\\w+)",
            "next (\\w+) bus",
            "next (\\w+) train",
            "bus (\\w+) times",
            "train (\\w+) times"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(command.startIndex..., in: command)
                if let match = regex.firstMatch(in: command, options: [], range: range) {
                    if let routeRange = Range(match.range(at: 1), in: command) {
                        return String(command[routeRange]).uppercased()
                    }
                }
            }
        }
        
        return nil
    }
    
    // Get common routes for suggestions
    static let commonRoutes = [
        "38", "38R", "F", "14", "14R", "22", "N", "L", "K", "M", "T"
    ]
    
    // Siri voice commands that users can say
    static let siriCommands = [
        "Hey Siri, find nearby bus stops",
        "Hey Siri, check bus times",
        "Hey Siri, when is the next 38 bus",
        "Hey Siri, when is the next F train", 
        "Hey Siri, next 14 bus",
        "Hey Siri, bus 22 times",
        "Hey Siri, show me transit times",
        "Hey Siri, open SF Transit Watch"
    ]
    
    // Route-specific command examples
    static let routeSpecificCommands = [
        "Hey Siri, when is the next 38 bus",
        "Hey Siri, when is the next F train",
        "Hey Siri, next 14 bus",
        "Hey Siri, bus 22 times",
        "Hey Siri, when is the next N train",
        "Hey Siri, next L bus"
    ]
} 