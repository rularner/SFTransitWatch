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

        if SnapshotMode.isActive { return }

        do {
            try WCSession.default.updateApplicationContext(Self.buildPayload())
        } catch {
            print("WCSession updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    static func buildPayload() -> [String: Any] {
        let appGroup = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName)
        let agencies = appGroup?.string(forKey: EnabledAgencies.storageKey) ?? ""
        let morningId = appGroup?.string(forKey: CommuteSlotsManager.Slot.morning.storageKey) ?? ""
        let afternoonId = appGroup?.string(forKey: CommuteSlotsManager.Slot.afternoon.storageKey) ?? ""
        let favoritesData = UserDefaults.standard.data(forKey: "FavoriteStops") ?? Data()
        return [
            "transitKey": ConfigurationManager.shared.apiKey.trimmingCharacters(in: .whitespaces),
            "workerToken": ConfigurationManager.shared.workerToken,
            "workerBaseURL": ConfigurationManager.shared.workerBaseURL,
            "enabledAgencies": agencies,
            "commuteMorning": morningId,
            "commuteAfternoon": afternoonId,
            "favoriteStops": favoritesData,
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

    // MARK: - Receiving from watch

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applyWatchContext(applicationContext)
        }
    }

    // `appGroup` is injectable for testing; production always uses the real suite.
    func applyWatchContext(_ context: [String: Any],
                           appGroup: UserDefaults? = UserDefaults(suiteName: ConfigurationManager.appGroupSuiteName)) {
        let appGroup = appGroup

        if let agencies = context["enabledAgencies"] as? String {
            let current = appGroup?.string(forKey: EnabledAgencies.storageKey) ?? ""
            if agencies != current {
                appGroup?.set(agencies, forKey: EnabledAgencies.storageKey)
            }
        }

        let morningKey = CommuteSlotsManager.Slot.morning.storageKey
        if let morningId = context["commuteMorning"] as? String {
            let current = appGroup?.string(forKey: morningKey) ?? ""
            if morningId != current {
                morningId.isEmpty
                    ? appGroup?.removeObject(forKey: morningKey)
                    : appGroup?.set(morningId, forKey: morningKey)
            }
        }

        let afternoonKey = CommuteSlotsManager.Slot.afternoon.storageKey
        if let afternoonId = context["commuteAfternoon"] as? String {
            let current = appGroup?.string(forKey: afternoonKey) ?? ""
            if afternoonId != current {
                afternoonId.isEmpty
                    ? appGroup?.removeObject(forKey: afternoonKey)
                    : appGroup?.set(afternoonId, forKey: afternoonKey)
            }
        }

        if let favoritesData = context["favoriteStops"] as? Data {
            let current = UserDefaults.standard.data(forKey: "FavoriteStops") ?? Data()
            if favoritesData != current {
                UserDefaults.standard.set(favoritesData.isEmpty ? nil : favoritesData,
                                          forKey: "FavoriteStops")
            }
        }
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
