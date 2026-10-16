import Foundation
import AppCore

/// The server side of rewarded ads (`functions/v1/ad-reward`): a single-use
/// token before each ad (for a credit, or for a one-time try of a Pro look or
/// style), and whether AdMob has confirmed it since. Uses the session she
/// already has (from her cloud jobs) and never signs up. Ad credits and tries
/// belong to the App Store install like the free credits, so the overview and
/// the tokens carry StoreKit's AppTransaction.
final class AdRewardBackend {
    private let config: BackendConfiguration
    private let auth: AuthSessionManager
    private let session: URLSession
    private let appTransactions: AppTransactionProvider
    private let entitlementProvider: () async -> String?

    init(config: BackendConfiguration, auth: AuthSessionManager, session: URLSession = .shared,
         appTransactions: AppTransactionProvider, entitlementProvider: @escaping () async -> String?) {
        self.config = config
        self.auth = auth
        self.session = session
        self.appTransactions = appTransactions
        self.entitlementProvider = entitlementProvider
    }

    /// Today's ads: how many are left, and the server's balance.
    func overview() async throws -> AdRewardStatus {
        let accessToken = try await token()
        let jws = await entitlementProvider()
        let request = try RequestFactory.adRewardOverview(config: config, accessToken: accessToken, entitlementJWS: jws,
                                                          appTransactionJWS: await appTransactions.jws())
        let (data, response) = try await session.mappedData(for: request)
        return try ResponseDecoder.decodeAdRewardStatus(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// A token for the ad that's about to show.
    func issueToken() async throws -> AdRewardToken {
        let accessToken = try await token()
        let jws = await entitlementProvider()
        let request = try RequestFactory.adRewardToken(config: config, accessToken: accessToken, entitlementJWS: jws,
                                                       appTransactionJWS: await appTransactions.jws())
        let (data, response) = try await session.mappedData(for: request)
        return try ResponseDecoder.decodeAdRewardToken(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// A token for an ad that pays a one-time try of a Pro look or style.
    func issueUnlockToken(for item: ProTryItem) async throws -> AdRewardToken {
        let accessToken = try await token()
        let jws = await entitlementProvider()
        let request = try RequestFactory.adRewardUnlockToken(for: item, config: config, accessToken: accessToken, entitlementJWS: jws,
                                                             appTransactionJWS: await appTransactions.jws())
        let (data, response) = try await session.mappedData(for: request)
        return try ResponseDecoder.decodeAdRewardToken(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func status(token rewardToken: String) async throws -> AdRewardStatus {
        let accessToken = try await token()
        let jws = await entitlementProvider()
        let request = try RequestFactory.adRewardStatus(token: rewardToken, config: config, accessToken: accessToken, entitlementJWS: jws)
        let (data, response) = try await session.mappedData(for: request)
        return try ResponseDecoder.decodeAdRewardStatus(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The ad closed before its reward: gives the token's place back. Best effort.
    func release(token rewardToken: String) async {
        guard let accessToken = try? await token(),
              let request = try? RequestFactory.releaseAdRewardToken(token: rewardToken, config: config, accessToken: accessToken)
        else { return }
        _ = try? await session.mappedData(for: request)
    }

    /// Whether this device has a session: no session, no rewarded ads (one is
    /// only ever created by a consented cloud job or a purchase).
    func hasSession() async -> Bool {
        await auth.userID != nil
    }

    private func token() async throws -> String {
        guard let accessToken = try await auth.existingAccessToken() else { throw AdRewardError.unauthorized }
        return accessToken
    }
}
