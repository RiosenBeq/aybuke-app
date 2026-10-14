import Foundation
import AppCore

/// One mapping from transport errors to the messages she sees, shared by the
/// AI services and the account session.
enum NetworkFailure {
    static func map(_ error: Error) -> Error {
        if error is CancellationError || error is AIServiceError { return error }
        guard let urlError = error as? URLError else {
            return AIServiceError.network(String(localized: "Check your internet connection and try again."))
        }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return AIServiceError.offline
        case .timedOut:
            return AIServiceError.timedOut
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return AIServiceError.insecureConnection
        default:
            return AIServiceError.network(String(localized: "Check your internet connection and try again."))
        }
    }

    /// A dropped or slow connection rather than a refusal, so the message can
    /// say she's offline instead of that something failed.
    static func isTransient(_ error: Error) -> Bool {
        switch map(error) as? AIServiceError {
        case .offline, .timedOut, .network: return true
        default: return false
        }
    }
}

extension URLSession {
    /// `data(for:)` with errors mapped by `NetworkFailure`.
    func mappedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await data(for: request)
        } catch {
            throw NetworkFailure.map(error)
        }
    }
}
