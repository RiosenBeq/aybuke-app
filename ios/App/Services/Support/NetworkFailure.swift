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
