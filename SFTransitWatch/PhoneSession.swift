import Foundation
import WatchConnectivity
import SFTransitWatchPackage

final class PhoneSession: NSObject, WCSessionDelegate {
    static let shared = PhoneSession()

    private var didStartObserving = false

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        startObservingDefaults()
    }

    func pushCurrentKey() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }

        // SnapshotMode: skip WCSession calls during snapshot runs.
        if SnapshotMode.isActive { return }

        do {
            try WCSession.default.updateApplicationContext(Self.buildPayload())
        } catch {
            print("WCSession updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    static func buildPayload() -> [String: Any] {
        let agencies = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName)?
            .string(forKey: EnabledAgencies.storageKey) ?? ""
        return [
            "transitKey": ConfigurationManager.shared.apiKey.trimmingCharacters(in: .whitespaces),
            "workerToken": ConfigurationManager.shared.workerToken,
            "workerBaseURL": ConfigurationManager.shared.workerBaseURL,
            "enabledAgencies": agencies,
        ]
    }

    static func payload(forKey key: String?) -> [String: Any] {
        let transitKey = key?.trimmingCharacters(in: .whitespaces) ?? ""
        return ["transitKey": transitKey]
    }

    private func startObservingDefaults() {
        guard !didStartObserving else { return }
        didStartObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func defaultsChanged() {
        pushCurrentKey()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation error: \(error.localizedDescription)")
            return
        }
        pushCurrentKey()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        pushCurrentKey()
    }
}
