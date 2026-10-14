import Foundation
import StoreKit

/// StoreKit's signed AppTransaction for this download, which the server needs
/// before it spends free credits: they belong to a genuine App Store install
/// (Apple's appTransactionID is the same for every download by one Apple
/// Account), not to an anonymous account. Sent as `X-App-Transaction` with
/// cloud jobs, balance reads, credit packs and rewarded ads.
///
/// `AppTransaction.shared` is read once and kept: StoreKit keeps it on the
/// device and up to date, and reading it never asks her anything. When it
/// doesn't come in time (offline, a StoreKit hiccup), requests go without it
/// and the server says so; only then, and only after she tapped something,
/// `refresh()` asks the App Store for a new one, which can show Apple's
/// sign-in prompt. TestFlight and App Review get Sandbox ones, which the
/// server accepts; the Xcode StoreKit configuration signs its own, which only
/// a local backend accepts (backend/README.md).
actor AppTransactionProvider {
    private var cached: String?
    private var loading: Task<String?, Never>?

    /// The JWS, waiting at most `timeout` for StoreKit. Nil if it has none yet.
    func jws(waitingAtMost timeout: Duration = .seconds(4)) async -> String? {
        if let cached { return cached }
        let task = loading ?? startLoading()
        return await Self.value(of: task, orNilAfter: timeout)
    }

    /// Asks the App Store for a fresh AppTransaction (it may ask her to sign
    /// in). For when the server said the one it got was missing or invalid.
    func refresh() async -> String? {
        do {
            let result = try await AppTransaction.refresh()
            cached = result.jwsRepresentation
        } catch {
            // Cancelled, offline or not signed in: keep what we had.
        }
        return cached
    }

    /// Delete my data: the next request reads it again.
    func reset() {
        cached = nil
    }

    private func startLoading() -> Task<String?, Never> {
        let task = Task { [weak self] () -> String? in
            let value = try? await AppTransaction.shared.jwsRepresentation
            await self?.finishLoading(value)
            return value
        }
        loading = task
        return task
    }

    private func finishLoading(_ value: String?) {
        if let value { cached = value }
        loading = nil
    }

    /// Whichever comes first: the task's value or the deadline. The task
    /// keeps going after the deadline and caches its value for next time.
    private static func value(of task: Task<String?, Never>, orNilAfter timeout: Duration) async -> String? {
        let gate = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            Task {
                let value = await task.value
                if gate.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Lets exactly one of two racing tasks resume a continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
