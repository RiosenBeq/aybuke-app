import Foundation

/// Consent to cloud AI processing, kept only on this device: which version
/// of the consent sheet she accepted, when, and which processors it named.
/// It exists so the app asks again when the processing changes (EDPB
/// Guidelines 05/2020 ¶110), not as proof for the server.
public struct AIConsentRecord: Codable, Equatable, Sendable {
    public var version: Int
    public var acceptedAt: Date
    /// The processor names shown on the sheet she accepted.
    public var processors: [String]
    /// Her own answer to "A parent or guardian said yes"; nobody verifies it.
    public var guardianConfirmed: Bool

    public init(version: Int, acceptedAt: Date, processors: [String], guardianConfirmed: Bool = false) {
        self.version = version
        self.acceptedAt = acceptedAt
        self.processors = processors
        self.guardianConfirmed = guardianConfirmed
    }

    /// Stale after a manual `consentVersion` bump, and whenever the list of
    /// processors changes, so a forgotten bump can't skip asking again.
    public func isValid(currentVersion: Int, currentProcessors: [String]) -> Bool {
        version >= currentVersion && Set(processors) == Set(currentProcessors)
    }

    /// A stored record, or nil when there is none or it can't be read (an
    /// older format counts as no record: she is asked once more).
    public static func decode(_ data: Data?) -> AIConsentRecord? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AIConsentRecord.self, from: data)
    }
}
