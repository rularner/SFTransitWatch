import Foundation
import WatchConnectivity
import SFTransitWatchPackage

final class WatchSession: NSObject, WCSessionDelegate {
    static let shared = WatchSession()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pushCurrentState()
        }
    }

    func pushCurrentState() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isCompanionAppInstalled else { return }
        do {
            try WCSession.default.updateApplicationContext(Self.buildPayload())
        } catch {
            print("WatchSession updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    static func buildPayload() -> [String: Any] {
        let appGroup = UserDefaults(suiteName: SharedAgenciesManager.appGroupSuiteName)
        let agencies = appGroup?.string(forKey: EnabledAgencies.storageKey) ?? ""
        let morningId = appGroup?.string(forKey: CommuteSlotsManager.Slot.morning.storageKey) ?? ""
        let afternoonId = appGroup?.string(forKey: CommuteSlotsManager.Slot.afternoon.storageKey) ?? ""
        let favoritesData = UserDefaults.standard.data(forKey: "FavoriteStops") ?? Data()
        return [
            "enabledAgencies": agencies,
            "commuteMorning": morningId,
            "commuteAfternoon": afternoonId,
            "favoriteStops": favoritesData,
        ]
    }

    private func applyContext(_ context: [String: Any]) {
        let key = (context["transitKey"] as? String) ?? ""
        // Write to both stores: App Group (for SettingsView) and standard (for
        // TransitAPI's @AppStorage reactive updates).
        ConfigurationManager.shared.apiKey = key
        UserDefaults.standard.set(key, forKey: "511_API_KEY_FROM_PHONE")

        let token = (context["workerToken"] as? String) ?? ""
        let url = (context["workerBaseURL"] as? String) ?? ""
        ConfigurationManager.shared.setWorkerConfig(url: url, token: token)

        let appGroup = UserDefaults(suiteName: SharedAgenciesManager.appGroupSuiteName)

        if let agencies = context["enabledAgencies"] as? String, !agencies.isEmpty {
            appGroup?.set(agencies, forKey: EnabledAgencies.storageKey)
        }

        let morningKey = CommuteSlotsManager.Slot.morning.storageKey
        if let morningId = context["commuteMorning"] as? String {
            morningId.isEmpty
                ? appGroup?.removeObject(forKey: morningKey)
                : appGroup?.set(morningId, forKey: morningKey)
        }
        let afternoonKey = CommuteSlotsManager.Slot.afternoon.storageKey
        if let afternoonId = context["commuteAfternoon"] as? String {
            afternoonId.isEmpty
                ? appGroup?.removeObject(forKey: afternoonKey)
                : appGroup?.set(afternoonId, forKey: afternoonKey)
        }

        if let favoritesData = context["favoriteStops"] as? Data, !favoritesData.isEmpty {
            UserDefaults.standard.set(favoritesData, forKey: "FavoriteStops")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applyContext(applicationContext)
        }
    }
}
