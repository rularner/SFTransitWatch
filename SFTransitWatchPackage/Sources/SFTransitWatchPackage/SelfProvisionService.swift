import Foundation
import CryptoKit

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
            !keyBase64.isEmpty,
            let keyData = Data(base64Encoded: keyBase64),
            let key = try? P256.Signing.PrivateKey(derRepresentation: keyData)
        else { return nil }
        return SelfProvisionService(privateKey: key, session: session)
    }

    public init(privateKey: P256.Signing.PrivateKey, session: URLSessionProtocol = URLSession.shared) {
        self.privateKey = privateKey
        self.session = session
    }

    public func provision(workerURL: String) async -> Result<Void, SelfProvisionError> {
        let jwt: String
        do {
            jwt = try buildJWT()
        } catch {
            return .failure(.networkError)
        }

        guard var components = URLComponents(string: workerURL) else {
            return .failure(.networkError)
        }
        components.path = "/self-provision"
        guard let url = components.url else { return .failure(.networkError) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["jwt": jwt])
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError)
            }
            guard http.statusCode == 200 else {
                return .failure(.serverRejected)
            }
            struct ProvisionResponse: Decodable { let token: String }
            let decoded = try JSONDecoder().decode(ProvisionResponse.self, from: data)
            ConfigurationManager.shared.setWorkerConfig(url: workerURL, token: decoded.token)
            return .success(())
        } catch {
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
