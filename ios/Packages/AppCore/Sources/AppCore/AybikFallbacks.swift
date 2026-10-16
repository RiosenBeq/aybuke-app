import Foundation

// What the app says on its own when Aybik (the server's writing help) can't:
// under 13, without the cloud AI opt-in or a session, offline, or when the
// server answers 503. English here, translated at runtime with `L10n.core`
// (scripts/export-core-strings.py registers them); TranslationTests keep every
// language within the policy and, for card text, within each slot's length.

/// Hand-written options for the share composer's "Write it for me": about
/// the moment or the vibe, never about how anyone looks.
public enum CardLines {
    public static func lines(for slot: ShareTextSlot) -> [String] {
        switch slot {
        case .storyLine: return storyLines
        case .coverMasthead: return mastheads
        case .coverHeadline: return headlines
        case .stripCaption: return stripCaptions
        }
    }

    public static var all: [String] { ShareTextSlot.allCases.flatMap(lines(for:)) }

    static let storyLines = [
        storyLine("Collecting little moments like this one"),
        storyLine("Today felt like a good song"),
        storyLine("Soft light, big plans"),
        storyLine("Saving this day for later"),
        storyLine("Main character of my own cozy movie"),
    ]

    static let mastheads = [
        masthead("VIBES"),
        masthead("DREAMY"),
        masthead("BESTIES"),
        masthead("SPARKLE"),
        masthead("WEEKEND"),
    ]

    static let headlines = [
        headline("The weekend issue"),
        headline("Soft days, big dreams"),
        headline("Golden hour special"),
        headline("The bestie edition"),
        headline("Plot twist: a good day"),
    ]

    static let stripCaptions = [
        stripCaption("Best day ever"),
        stripCaption("Booth buddies"),
        stripCaption("Making memories"),
        stripCaption("Little moments"),
        stripCaption("Weekend mode"),
    ]

    // Markers for scripts/export-core-strings.py, one per slot (each has its length).
    static func storyLine(_ english: String) -> String { english }
    static func masthead(_ english: String) -> String { english }
    static func headline(_ english: String) -> String { english }
    static func stripCaption(_ english: String) -> String { english }
}

/// Settings › Help: common questions with short answers, shown under Ask
/// Aybik and in its place when Aybik can't answer (and under 13, where the
/// app never asks the server). Every answer matches the app as it is.
public struct HelpTopic: Equatable, Sendable, Identifiable {
    public let id: String
    public let question: String
    public let answer: String
    /// About cloud AI, credits, Pro or polls: not shown under 13.
    public let needsCloudAI: Bool

    public static let all: [HelpTopic] = [
        HelpTopic(id: "credits", question: question("When do my free credits come back?"),
                  answer: answer("Free credits come back every day. Tap your credit balance on Explore to see how many you have and when the next ones arrive. Pro comes with monthly credits instead."),
                  needsCloudAI: true),
        HelpTopic(id: "free", question: question("What can I do for free?"),
                  answer: answer("Every tool that runs on your device is free and never uses credits: retro effects, Retro Cam and Photo Booth, Adjust, Crop, Cut out, Text & Stickers, Collage, the video editor and Quick fix."),
                  needsCloudAI: false),
        HelpTopic(id: "polls", question: question("How do I delete a poll?"),
                  answer: answer("Open My Works and tap Your polls at the top. Pick the poll and tap Delete. Every poll also ends by itself after 24 hours, and then it's deleted."),
                  needsCloudAI: true),
        HelpTopic(id: "training", question: question("Are my photos used to train AI?"),
                  answer: answer("No, never. Photos you send for an AI edit are deleted from our servers within an hour, and your creations stay on your device."),
                  needsCloudAI: true),
        HelpTopic(id: "blocked", question: question("Why was my request blocked?"),
                  answer: answer("Aybuke keeps every edit kind and safe, so some requests can't be made. Try describing a color, a background, an outfit or a vibe instead."),
                  needsCloudAI: true),
        HelpTopic(id: "cancel", question: question("How do I cancel Pro?"),
                  answer: answer("Go to Settings › Membership › Manage subscription. Pro is billed through your Apple Account, so Apple takes care of canceling it."),
                  needsCloudAI: true),
        HelpTopic(id: "aybik", question: question("Who is Aybik?"),
                  answer: answer("Aybik is our AI helper. It writes ideas, captions and answers from your words, never your photos, and only after you've turned on cloud AI. Its answers can be wrong."),
                  needsCloudAI: true),
        HelpTopic(id: "delete", question: question("How do I delete my data?"),
                  answer: answer("Go to Settings › Privacy. Delete all creations removes the pictures saved in the app. Delete my data & account also deletes your account, credits and polls from our servers."),
                  needsCloudAI: false),
        HelpTopic(id: "support", question: question("How do I contact support?"),
                  answer: answer("Go to Settings › About › Contact support. We're happy to help."),
                  needsCloudAI: false),
    ]

    /// The topics she can read: all of them, or the on-device ones under 13.
    public static func topics(cloudAI: Bool) -> [HelpTopic] {
        all.filter { cloudAI || !$0.needsCloudAI }
    }

    /// The topics her question is closest to, best first (words of her
    /// question in the topic's question or answer), at most `limit`; empty
    /// when none share a word. `localize` reads them in her language.
    public static func matching(_ text: String, in topics: [HelpTopic], localize: (String) -> String = { $0 },
                                limit: Int = 3) -> [HelpTopic] {
        let items = topics.map { topic in
            LookFinder.Item(kind: .look, id: topic.id, name: localize(topic.question), about: localize(topic.answer),
                            words: [topic.question])
        }
        let ids = LookFinder.localMatches(for: text, in: items, limit: limit, perKind: limit).map(\.id)
        return ids.compactMap { id in topics.first { $0.id == id } }.prefix(limit).map { $0 }
    }

    // Markers for scripts/export-core-strings.py.
    static func question(_ english: String) -> String { english }
    static func answer(_ english: String) -> String { english }
}
