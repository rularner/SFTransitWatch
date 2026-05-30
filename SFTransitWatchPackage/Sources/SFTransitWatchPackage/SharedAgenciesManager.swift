import Foundation

/// Persists the set of enabled transit agencies to AppGroup UserDefaults so
/// both the iPhone app and Watch app read from the same store.
@MainActor
public class SharedAgenciesManager: ObservableObject {

    public nonisolated static let appGroupSuiteName = "group.org.larner.SFTransitWatch"

    @Published public private(set) var enabledCodes: Set<String>

    private let userDefaults: UserDefaults

    public init(userDefaultsSuiteName: String? = SharedAgenciesManager.appGroupSuiteName) {
        let ud = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.userDefaults = ud
        let stored = ud.string(forKey: EnabledAgencies.storageKey) ?? ""
        if stored.isEmpty {
            self.enabledCodes = Set(Agency.known.map(\.code))
        } else {
            self.enabledCodes = Set(EnabledAgencies.parse(stored))
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromDefaults() }
        }
    }

    private func reloadFromDefaults() {
        let stored = userDefaults.string(forKey: EnabledAgencies.storageKey) ?? ""
        let newCodes = stored.isEmpty ? Set(Agency.known.map(\.code)) : Set(EnabledAgencies.parse(stored))
        if newCodes != enabledCodes { enabledCodes = newCodes }
    }

    public func isEnabled(_ agencyCode: String) -> Bool {
        enabledCodes.contains(agencyCode)
    }

    public func toggle(_ agencyCode: String) {
        if enabledCodes.contains(agencyCode) {
            enabledCodes.remove(agencyCode)
        } else {
            enabledCodes.insert(agencyCode)
        }
        save()
    }

    public func setEnabled(_ codes: Set<String>) {
        enabledCodes = codes
        save()
    }

    /// Agency codes in `Agency.known` order, filtered to only enabled ones.
    /// Use this when passing to API calls.
    public var asArray: [String] {
        Agency.known.map(\.code).filter { enabledCodes.contains($0) }
    }

    private func save() {
        userDefaults.set(EnabledAgencies.format(asArray), forKey: EnabledAgencies.storageKey)
    }
}
