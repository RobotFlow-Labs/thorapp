import Foundation

public struct RegistryValidationService: Sendable {
    private let certificateService: RegistryCertificateService

    public init(certificateService: RegistryCertificateService = RegistryCertificateService()) {
        self.certificateService = certificateService
    }

    public func validate(profile: RegistryProfile, password: String?) async -> RegistryValidationReport {
        var stages: [RegistryValidationStage] = []
        stages.append(configurationStage(for: profile, password: password))

        if profile.scheme == .https {
            stages.append(certificateStage(for: profile))
        }

        stages.append(await endpointStage(for: profile, password: password))

        let overall = stages.max(by: { $0.status.rank < $1.status.rank })?.status ?? .unknown
        return RegistryValidationReport(
            profileID: profile.id,
            endpoint: profile.endpointLabel,
            status: overall,
            stages: stages
        )
    }

    private func configurationStage(for profile: RegistryProfile, password: String?) -> RegistryValidationStage {
        if profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RegistryValidationStage(name: "Configuration", status: .fail, message: "Registry host is required.")
        }

        if let username = profile.username, !username.isEmpty, (password ?? "").isEmpty {
            return RegistryValidationStage(name: "Credentials", status: .warning, message: "Username is set, but no password is stored in Keychain.")
        }

        return RegistryValidationStage(name: "Configuration", status: .pass, message: "Registry profile fields look valid.")
    }

    private func certificateStage(for profile: RegistryProfile) -> RegistryValidationStage {
        guard let path = profile.caCertificatePath else {
            return RegistryValidationStage(name: "Certificate Trust", status: .pass, message: "No custom CA imported; relying on existing system trust.")
        }

        switch certificateService.trustState(for: URL(fileURLWithPath: path)) {
        case .trusted:
            return RegistryValidationStage(name: "Certificate Trust", status: .pass, message: "Custom CA is trusted on this Mac.")
        case .untrusted(let reason):
            return RegistryValidationStage(name: "Certificate Trust", status: .warning, message: reason ?? "Custom CA is present but not trusted yet.")
        case .missing:
            return RegistryValidationStage(name: "Certificate Trust", status: .fail, message: "Managed certificate file is missing.")
        }
    }

    private func endpointStage(for profile: RegistryProfile, password: String?) async -> RegistryValidationStage {
        guard let url = profile.v2URL else {
            return RegistryValidationStage(name: "Registry Endpoint", status: .fail, message: "Registry URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        if let username = profile.username, !username.isEmpty, let password, !password.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return RegistryValidationStage(name: "Registry Endpoint", status: .fail, message: "Registry did not return an HTTP response.")
            }

            switch httpResponse.statusCode {
            case 200 ..< 300:
                return RegistryValidationStage(name: "Registry Endpoint", status: .pass, message: "Registry API responded with HTTP \(httpResponse.statusCode).")
            case 401:
                if let username = profile.username, !username.isEmpty, let password, !password.isEmpty {
                    return RegistryValidationStage(name: "Registry Endpoint", status: .fail, message: "Registry rejected the stored credentials (HTTP 401).")
                }
                return RegistryValidationStage(name: "Registry Endpoint", status: .warning, message: "Registry is reachable but requires authentication (HTTP 401).")
            default:
                return RegistryValidationStage(name: "Registry Endpoint", status: .fail, message: "Registry responded with unexpected HTTP \(httpResponse.statusCode).")
            }
        } catch {
            return RegistryValidationStage(name: "Registry Endpoint", status: .fail, message: error.localizedDescription)
        }
    }
}
