import Foundation

public class ConfigurationManager {
    public static let shared = ConfigurationManager()

    private let userDefaults = UserDefaults(suiteName: "group.com.rularner.sftransitwatch")!

    private let apiKeyKey = "511_API_KEY"
    private let workerTokenKey = "WORKER_TOKEN"
    private let workerBaseURLKey = "WORKER_BASE_URL"

    // MARK: - API Key

    public var apiKey: String {
        get { userDefaults.string(forKey: apiKeyKey) ?? "" }
        set { userDefaults.set(newValue, forKey: apiKeyKey) }
    }

    public func setAPIKey(_ key: String) {
        apiKey = key
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
