import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple, offered (never required) so her credits follow her to
/// other devices; Pro follows the Apple Account that bought it. Asks only for
/// an email, which she can hide. Shown only while `AppModel.offersSignIn`.
struct AppleSignInButton: View {
    var onSignedIn: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = AppleSignInNonce.make()
    @State private var isWorking = false

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = AppleSignInNonce.make()
            request.requestedScopes = [.email]
            request.nonce = AppleSignInNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                let nonce = nonce
                isWorking = true
                Task {
                    await app.signInWithApple(credential, nonce: nonce)
                    isWorking = false
                    if app.isSignedIn { onSignedIn?() }
                }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                app.showToast("Couldn't sign in with Apple. Please try again.", style: .error)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(.button)
        .overlay {
            if isWorking {
                ProgressView().tint(colorScheme == .dark ? Palette.ink : Palette.white)
            }
        }
        .disabled(!app.offersSignIn || isWorking)
        .opacity(app.offersSignIn ? 1 : 0.45)
    }
}

/// "Keep your credits on every device", shown after a purchase or from the
/// paywall's "Sign in" while Sign in with Apple is offered. "Not now" is as
/// easy to tap as signing in.
struct AccountPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: Platform.isMac ? "macbook.and.iphone" : "arrow.triangle.2.circlepath")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 72, height: 72)
                .background(Palette.blush, in: Circle())
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text(styled: "Keep your credits on *every device*", size: 23)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textPrimary)
                Text("Sign in with Apple and your credits come with you when you switch or add a device. Pro stays with the Apple Account you subscribed with.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                // Pro comes from the App Store purchases of the Apple Account, not from this sign-in.
                AccountPoint(symbol: "crown.fill", text: "Pro works wherever you use the same Apple Account")
                AccountPoint(symbol: "bolt.fill", text: "Credits never get stuck on an old device")
                AccountPoint(symbol: "eye.slash.fill", text: "Hide your email if you like")
                AccountPoint(symbol: "photo.on.rectangle", text: "Your photos stay on this device")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cardStyle()

            VStack(spacing: 10) {
                AppleSignInButton { dismiss() }
                Button("Not now") { dismiss() }
                    .buttonStyle(.secondary)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
        .background(AuroraBackground(intensity: 0.4).ignoresSafeArea())
        .presentationDetents([.large])
    }
}

private struct AccountPoint: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Palette.accent)
        }
    }
}

/// Apple's sign-in sheet without a button on screen, for Settings' "Bought
/// Pro or credits on another device? Sign in" row: the same email scope,
/// nonce and `AppModel.signInWithApple` as `AppleSignInButton`, one tap
/// sooner.
final class AppleSignInPrompt: NSObject {
    private enum Outcome {
        case signedIn(ASAuthorizationAppleIDCredential)
        case canceled
        case failed
    }

    /// Kept alive while Apple's sheet is up: the controller holds its delegate weakly.
    @MainActor private static var current: AppleSignInPrompt?
    private var continuation: CheckedContinuation<Outcome, Never>?

    @MainActor
    static func signIn(_ app: AppModel) async {
        guard current == nil else { return }
        let nonce = AppleSignInNonce.make()
        let prompt = AppleSignInPrompt()
        current = prompt
        let outcome = await withCheckedContinuation { continuation in
            prompt.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            request.nonce = AppleSignInNonce.sha256(nonce)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = prompt
            controller.presentationContextProvider = prompt
            controller.performRequests()
        }
        current = nil
        switch outcome {
        case .signedIn(let credential):
            await app.signInWithApple(credential, nonce: nonce)
        case .canceled:
            break
        case .failed:
            app.showToast("Couldn't sign in with Apple. Please try again.", style: .error)
        }
    }

    private func finish(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

extension AppleSignInPrompt: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(.signedIn(credential))
        } else {
            finish(.failed)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish((error as? ASAuthorizationError)?.code == .canceled ? .canceled : .failed)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

/// The nonce Apple signs into the identity token; the server checks it.
enum AppleSignInNonce {
    static func make(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
