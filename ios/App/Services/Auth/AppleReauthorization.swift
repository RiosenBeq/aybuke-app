import AuthenticationServices
import UIKit

/// Asks Apple again for a one-time authorization code, so deleting a Sign in
/// with Apple account can revoke its token when the server never got one at
/// sign-in (Apple's code lasts five minutes and works once). No scopes: only
/// the code is needed.
final class AppleReauthorization: NSObject {
    enum Outcome {
        case code(String)
        case canceled
        /// Apple couldn't answer (no Apple ID here, or an error).
        case unavailable
    }

    /// Kept alive while Apple's sheet is up: the controller holds its delegate weakly.
    @MainActor private static var current: AppleReauthorization?
    private var continuation: CheckedContinuation<Outcome, Never>?

    @MainActor
    static func authorizationCode() async -> Outcome {
        let helper = AppleReauthorization()
        current = helper
        defer { current = nil }
        return await withCheckedContinuation { continuation in
            helper.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
            controller.delegate = helper
            controller.presentationContextProvider = helper
            controller.performRequests()
        }
    }

    private func finish(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

extension AppleReauthorization: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        finish(code.map(Outcome.code) ?? .unavailable)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish((error as? ASAuthorizationError)?.code == .canceled ? .canceled : .unavailable)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}
