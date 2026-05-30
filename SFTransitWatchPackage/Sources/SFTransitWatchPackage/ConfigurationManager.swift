import Foundation

public class ConfigurationManager: @unchecked Sendable {
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
        seedWorkerBaseURLIfNeeded()
    }

    private func seedWorkerBaseURLIfNeeded() {
        guard let bundleHost = Bundle.main.infoDictionary?["WORKER_BASE_URL"] as? String,
              !bundleHost.isEmpty else { return }
        let bundleURL = "https://\(bundleHost)"
        let stored = userDefaults.string(forKey: workerBaseURLKey) ?? ""
        guard stored != bundleURL else { return }
        // A provisioned token means the URL was explicitly set via deep-link; leave it alone.
        let hasToken = !(userDefaults.string(forKey: workerTokenKey) ?? "").isEmpty
        guard !hasToken else { return }
        userDefaults.set(bundleURL, forKey: workerBaseURLKey)
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

    public var isConfigured: Bool {
        isWorkerConfigured || !apiKey.isEmpty
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
