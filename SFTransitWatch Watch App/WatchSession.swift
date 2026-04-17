import Foundation
import WatchConnectivity

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
        UserDefaults.standard.set(key, forKey: "511_API_KEY_FROM_PHONE")
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
