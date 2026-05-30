import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "org.larner.SFTransitWatch", category: "self-provision")

public enum SelfProvisionError: Error, Equatable {
    case networkError
    case serverRejected
}

public protocol SelfProvisionServiceProtocol {
    func provision(workerURL: String) async -> Result<Void, SelfProvisionError>
}

public final class SelfProvisionService: SelfProvisionServiceProtocol {
    private let privateKey: P256.Signing.PrivateKey
    private let session: URLSessionProtocol

    /// Returns nil when `SELF_PROVISION_PRIVATE_KEY` is absent or malformed in `Info.plist`.
    public static func makeFromBundle(session: URLSessionProtocol = URLSession.shared) -> SelfProvisionService? {
        guard
            let keyBase64 = Bundle.main.infoDictionary?["SELF_PROVISION_PRIVATE_KEY"] as? String,
            !keyBase64.isEmpty
        else {
            logger.error("self-provision key absent or empty in Info.plist")
            return nil
        }
        guard let keyData = Data(base64Encoded: keyBase64) else {
            logger.error("SELF_PROVISION_PRIVATE_KEY is not valid base64")
            return nil
        }
        guard let key = try? P256.Signing.PrivateKey(derRepresentation: keyData) else {
            logger.error("SELF_PROVISION_PRIVATE_KEY is not a valid P-256 DER private key")
            return nil
        }
        return SelfProvisionService(privateKey: key, session: session)
    }

    public init(privateKey: P256.Signing.PrivateKey, session: URLSessionProtocol = URLSession.shared) {
        self.privateKey = privateKey
        self.session = session
    }

    public func provision(workerURL: String) async -> Result<Void, SelfProvisionError> {
        logger.info("provision: starting, workerURL=\(workerURL, privacy: .public)")

        let jwt: String
        do {
            jwt = try buildJWT()
        } catch {
            logger.error("provision: JWT build failed: \(error, privacy: .public)")
            return .failure(.networkError)
        }

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
        request.httpBody = try? JSONEncoder().encode(["jwt": jwt])
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

    // MARK: - JWT

    private struct JWTPayload: Encodable {
        let iss: String
        let installId: String
        let platform: String
        let appVersion: String
        let iat: Int
        let exp: Int

        enum CodingKeys: String, CodingKey {
            case iss
            case installId = "install_id"
            case platform
            case appVersion = "app_version"
            case iat
            case exp
        }
    }

    private func buildJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = #"{"alg":"ES256","typ":"JWT"}"#

        let payload = JWTPayload(
            iss: "org.larner.SFTransitWatch",
            installId: Telemetry.shared.installId,
            platform: currentPlatform(),
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0",
            iat: now,
            exp: now + 60
        )
        let payloadData = try JSONEncoder().encode(payload)

        let encodedHeader = base64URLEncode(Data(header.utf8))
        let encodedPayload = base64URLEncode(payloadData)
        let signingInput = "\(encodedHeader).\(encodedPayload)"

        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        let encodedSig = base64URLEncode(signature.rawRepresentation)

        return "\(signingInput).\(encodedSig)"
    }

    private func currentPlatform() -> String {
        #if os(watchOS)
        return "watchos"
        #else
        return "ios"
        #endif
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
