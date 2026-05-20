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

        if let agencies = context["enabledAgencies"] as? String, !agencies.isEmpty {
            UserDefaults(suiteName: SharedAgenciesManager.appGroupSuiteName)?
                .set(agencies, forKey: EnabledAgencies.storageKey)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.applyContext(applicationContext)
        }
    }
}
