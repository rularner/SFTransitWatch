import Foundation
import os

private let logger = Logger(subsystem: "org.larner.SFTransitWatch", category: "self-provision")

public enum SelfProvisionError: Error, Equatable {
    case networkError
    case serverRejected
}

/// Which budget on the worker's `/self-provision` rate limiter a request should draw from —
/// see `PROVISION_PURCHASE_RATE_LIMIT` / `PROVISION_REFRESH_RATE_LIMIT` in the worker's index.ts.
/// Keeping these separate means other users' passive hourly refreshes sharing the same
/// carrier-CGNAT IP can't drain the budget a just-paid purchase needs to provision.
public enum ProvisionPurpose: String {
    case purchase
    case refresh
}

public protocol SelfProvisionServiceProtocol {
    func provision(workerURL: String, signedTransactionInfo: String, purpose: ProvisionPurpose) async -> Result<Void, SelfProvisionError>
}

public final class SelfProvisionService: SelfProvisionServiceProtocol {
    private let session: URLSessionProtocol

    public static func makeFromBundle(session: URLSessionProtocol = URLSession.shared) -> SelfProvisionService {
        SelfProvisionService(session: session)
    }

    public init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    public func provision(workerURL: String, signedTransactionInfo: String, purpose: ProvisionPurpose) async -> Result<Void, SelfProvisionError> {
        logger.info("provision: starting, workerURL=\(workerURL, privacy: .public), purpose=\(purpose.rawValue, privacy: .public)")

        guard var components = URLComponents(string: workerURL) else {
            logger.error("provision: could not parse workerURL as URLComponents: \(workerURL, privacy: .public)")
            return .failure(.networkError)
        }
        components.path = "/self-provision"
        guard let url = components.url else {
            logger.error("provision: URLComponents.url was nil after setting path")
            return .failure(.networkError)
        }

        logger.info("provision: sending POST to \(url.absoluteString, privacy: .public)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "signedTransactionInfo": signedTransactionInfo,
            "install_id": Telemetry.shared.installId,
            "platform": currentPlatform(),
            "app_version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0",
            "purpose": purpose.rawValue,
        ])
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                logger.error("provision: response was not HTTPURLResponse")
                return .failure(.networkError)
            }
            logger.info("provision: HTTP \(http.statusCode, privacy: .public)")
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                logger.error("provision: server rejected (HTTP \(http.statusCode, privacy: .public)): \(body, privacy: .public)")
                return .failure(.serverRejected)
            }
            struct ProvisionResponse: Decodable { let token: String }
            let decoded = try JSONDecoder().decode(ProvisionResponse.self, from: data)
            ConfigurationManager.shared.setWorkerConfig(url: workerURL, token: decoded.token)
            logger.info("provision: success, token stored")
            return .success(())
        } catch {
            logger.error("provision: network error: \(error, privacy: .public)")
            return .failure(.networkError)
        }
    }

    private func currentPlatform() -> String {
        #if os(watchOS)
        return "watchos"
        #else
        return "ios"
        #endif
    }
}
