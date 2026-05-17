import Foundation

@MainActor
public class ConfigurationManager {
    public static let shared = ConfigurationManager()

    /// The canonical App Group suite used by all shared storage in this project.
    public static let appGroupSuiteName = "group.org.larner.SFTransitWatch"

    private let userDefaults: UserDefaults

    private let apiKeyKey = "511_API_KEY"
    private let workerTokenKey = "WORKER_TOKEN"
    private let workerBaseURLKey = "WORKER_BASE_URL"

    private init() {
        guard let userDefaults = UserDefaults(suiteName: Self.appGroupSuiteName) else {
            fatalError("Failed to initialize UserDefaults with app group '\(Self.appGroupSuiteName)'. Verify entitlements.")
        }
        self.userDefaults = userDefaults
        migrateIfNeeded()
    }

    /// One-time migration from the old App Group and from UserDefaults.standard
    /// (where @AppStorage was inadvertently writing config values).
    private func migrateIfNeeded() {
        let sources: [UserDefaults?] = [
            UserDefaults(suiteName: "group.com.rularner.sftransitwatch"),
            .standard,
        ]
        for key in [apiKeyKey, workerTokenKey, workerBaseURLKey] {
            guard (userDefaults.string(forKey: key) ?? "").isEmpty else { continue }
            for source in sources.compactMap({ $0 }) {
                if let value = source.string(forKey: key), !value.isEmpty {
                    userDefaults.set(value, forKey: key)
                    break
                }
            }
        }
    }

    // MARK: - API Key

    public var apiKey: String {
        get { userDefaults.string(forKey: apiKeyKey) ?? "" }
        set { userDefaults.set(newValue, forKey: apiKeyKey) }
    }

    // MARK: - Worker Configuration

    public var workerToken: String {
        get { userDefaults.string(forKey: workerTokenKey) ?? "" }
        set { userDefaults.set(newValue, forKey: workerTokenKey) }
    }

    public var workerBaseURL: String {
        get { userDefaults.string(forKey: workerBaseURLKey) ?? "" }
        set { userDefaults.set(newValue, forKey: workerBaseURLKey) }
    }

    public var isWorkerConfigured: Bool {
        !workerToken.isEmpty && !workerBaseURL.isEmpty
    }

    public func setWorkerConfig(url: String, token: String) {
        workerBaseURL = url
        workerToken = token
    }

    public func clearWorkerConfig() {
        workerToken = ""
        workerBaseURL = ""
    }
}
