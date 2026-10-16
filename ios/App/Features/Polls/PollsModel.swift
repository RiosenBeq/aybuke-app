import SwiftUI
import Observation
import AppCore

/// Two pictures on their way to a "Which vibe?" poll: two variations of one
/// creation from the share composer, or two creations picked in My Works.
/// Never her original photo against its edit: friends would be voting on her.
struct PollDraft: Identifiable {
    let id = UUID()
    let a: UIImage
    let b: UIImage
    /// Each picture's marking: an AI-made side is labelled on the poll page,
    /// and a free cloud result keeps the free mark, as an export would.
    let provenanceA: Provenance
    let provenanceB: Provenance

    /// What each picture is, in a few words (its title in My Works: a look,
    /// an effect or her prompt), for Aybik's question ideas. Never sent with
    /// the pictures, and only when she asks for ideas.
    var hintA: String? = nil
    var hintB: String? = nil

    var aiLabels: PollAILabels {
        PollAILabels(a: provenanceA.carriesAIProvenance, b: provenanceB.carriesAIProvenance)
    }

    var hints: (a: String?, b: String?) { (hintA, hintB) }
}

/// "Your polls", opened from My Works or a `glowlit://poll/<id>` link.
struct PollsSheetRequest: Identifiable {
    let id = UUID()
    /// The poll to show first.
    var focus: String?
}

/// Her polls on this device: the ids, links, questions and last counts in
/// `UserDefaults.standard` and two small thumbnails per poll in Application
/// Support (kept out of backups). Nothing is synced or in the App Group; a
/// poll's data goes a day after it ends, and Delete my data removes it all.
@MainActor
@Observable
final class PollsModel {
    private(set) var shelf: PollShelf
    /// Polls she may still make today, as the server last said.
    private(set) var remainingToday: Int?
    private(set) var dailyCap: Int?
    private(set) var isRefreshing = false
    /// The last read didn't come through: the counts are the last ones seen.
    private(set) var refreshFailed = false

    @ObservationIgnored private let backend: PollsBackend?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var thumbnails: [String: UIImage] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// When her list last came back from the server.
    @ObservationIgnored private var lastRead: Date?
    /// Called with the live polls after a read changed them, so reminders follow.
    @ObservationIgnored var onLiveChange: (([PollRecord]) -> Void)?
    #if DEBUG
    @ObservationIgnored private(set) var fixture: String?
    #endif

    nonisolated static let storageKey = "polls.mine.v1"
    nonisolated static let explainerKey = "polls.explainerSeen.v1"

    init(backend: PollsBackend?, defaults: UserDefaults?) {
        self.backend = backend
        self.defaults = defaults
        let saved = defaults?.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(PollShelf.self, from: $0) }
        var shelf = saved ?? PollShelf()
        let gone = shelf.prune(now: Date())
        self.shelf = shelf
        if !gone.isEmpty {
            persist()
            Self.removeThumbnails(of: gone)
        }
    }

    /// A backend to talk to (demo and developer builds have none), or fixtures.
    var isAvailable: Bool {
        #if DEBUG
        if fixture != nil { return true }
        #endif
        return backend != nil
    }

    var records: [PollRecord] { shelf.records }
    var hasPolls: Bool { !shelf.isEmpty }

    /// The first poll's explainer was read (kept in memory where nothing is stored).
    var hasSeenExplainer: Bool {
        get { defaults?.bool(forKey: Self.explainerKey) ?? seenExplainer }
        set {
            seenExplainer = newValue
            defaults?.set(newValue, forKey: Self.explainerKey)
        }
    }
    @ObservationIgnored private var seenExplainer = false

    // MARK: Server

    func ensureSession() async throws {
        #if DEBUG
        if fixture != nil { return }
        #endif
        guard let backend else { throw AIServiceError.notConfigured }
        try await backend.ensureSession()
    }

    /// Reads her list and the day's allowance. Never makes a session, and
    /// keeps what it had when the read fails. Calls while one runs share it.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        guard let backend, !AppModel.staysOffServer else { return prune() }
        let task = Task { [weak self] in
            guard let self else { return }
            isRefreshing = true
            defer { isRefreshing = false }
            do {
                // A poll made or deleted while this read is on its way isn't on
                // (or still is on) the list it brings back.
                let started = Date()
                let list = try await backend.mine()
                lastRead = Date()
                let gone = shelf.merge(list, now: Date(), readStarted: started)
                remainingToday = list.remainingToday
                dailyCap = list.dailyCap
                refreshFailed = false
                persist()
                Self.removeThumbnails(of: gone)
                gone.forEach(forgetThumbnails)
                onLiveChange?(shelf.live(at: Date()))
            } catch PollError.noSession {
                // Nothing on the server for this device yet.
                refreshFailed = false
                prune()
            } catch {
                refreshFailed = !(error is CancellationError)
                prune()
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// My Works' row: a read only while a poll is live and the last one is a
    /// few minutes old (every read is an Edge Function call).
    func refreshIfStale(maxAge: TimeInterval = 300) async {
        guard !shelf.live(at: Date()).isEmpty else { return prune() }
        if let lastRead, Date().timeIntervalSince(lastRead) < maxAge { return }
        await refresh()
    }

    /// Makes the poll: both pictures through the export path off the main
    /// actor, then the server, which checks them for safety before anyone
    /// can see them. Keeps the link, the question and small copies here.
    func create(_ draft: PollDraft, question: String?, isPro: Bool) async throws -> PollRecord {
        let marks = (a: draft.provenanceA.showsMark(isPro: isPro), b: draft.provenanceB.showsMark(isPro: isPro))
        let (a, b) = (draft.a, draft.b)
        let pictures = await Task.detached(priority: .userInitiated) { () -> (a: (upload: Data, thumbnail: Data), b: (upload: Data, thumbnail: Data),
                                                                              small: [PollSide: UIImage])? in
            guard let a = ImageExporter.pollPicture(a, watermark: marks.a),
                  let b = ImageExporter.pollPicture(b, watermark: marks.b) else { return nil }
            var small: [PollSide: UIImage] = [:]
            small[.a] = ImageUtilities.decodedImage(from: a.thumbnail, maxPixel: PollPicture.thumbnailLongEdge)
            small[.b] = ImageUtilities.decodedImage(from: b.thumbnail, maxPixel: PollPicture.thumbnailLongEdge)
            return (a, b, small)
        }.value
        guard let pictures else { throw PollError.imageInvalid(side: nil) }
        let labels = draft.aiLabels
        let created: PollCreated
        #if DEBUG
        if let fixture {
            try await Task.sleep(for: .seconds(1))
            if let error = Self.fixtureError(fixture) { throw error }
            let id = "Fx\(UUID().uuidString.prefix(8))_Kq2Lm"
            created = PollCreated(pollID: id, shareURL: URL(string: PollID.shareBase + id)!,
                                  expiresAt: Date().addingTimeInterval(PollShelf.lifetime), remainingToday: 2)
            return finish(created, question: question, labels: labels, files: (pictures.a.thumbnail, pictures.b.thumbnail), small: pictures.small)
        }
        #endif
        guard let backend else { throw AIServiceError.notConfigured }
        let request = PollCreateRequest(question: question, pictureA: pictures.a.upload, pictureB: pictures.b.upload,
                                        locale: Self.language, aiSides: labels.sides)
        created = try await backend.create(request)
        return finish(created, question: question, labels: labels, files: (pictures.a.thumbnail, pictures.b.thumbnail), small: pictures.small)
    }

    private func finish(_ created: PollCreated, question: String?, labels: PollAILabels,
                        files: (a: Data, b: Data), small: [PollSide: UIImage]) -> PollRecord {
        shelf.add(created, question: question, ai: labels, now: Date())
        if let remaining = created.remainingToday { remainingToday = remaining }
        persist()
        let id = created.pollID
        for (side, image) in small { thumbnails[Self.thumbnailKey(id, side)] = image }
        #if DEBUG
        if fixture != nil { return shelf.record(id)! }
        #endif
        Task.detached(priority: .utility) {
            Self.saveThumbnail(files.a, id: id, side: .a)
            Self.saveThumbnail(files.b, id: id, side: .b)
        }
        return shelf.record(id) ?? PollRecord(id: id, shareURL: created.shareURL, question: question, createdAt: Date(),
                                              expiresAt: created.expiresAt, ai: labels)
    }

    /// Deletes it on the server, then here.
    func delete(_ id: String) async throws {
        #if DEBUG
        if fixture != nil {
            remove(id)
            return
        }
        #endif
        guard let backend else { throw AIServiceError.notConfigured }
        do {
            try await backend.delete(id)
        } catch PollError.noSession {
            // No session left: nothing on the server can be hers any more.
        }
        remove(id)
    }

    private func remove(_ id: String) {
        shelf.remove(id)
        persist()
        forgetThumbnails(id)
        Self.removeThumbnails(of: [id])
    }

    /// Delete my data: every poll this device kept, its thumbnails and the explainer's "seen".
    func reset() {
        shelf = PollShelf()
        remainingToday = nil
        dailyCap = nil
        refreshFailed = false
        lastRead = nil
        thumbnails = [:]
        defaults?.removeObject(forKey: Self.storageKey)
        defaults?.removeObject(forKey: Self.explainerKey)
        let directory = Self.directory
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
    }

    /// Ended polls' last counts stay a day, then go.
    func prune() {
        let gone = shelf.prune(now: Date())
        guard !gone.isEmpty else { return }
        persist()
        gone.forEach(forgetThumbnails)
        Self.removeThumbnails(of: gone)
    }

    private func persist() {
        guard let defaults else { return }
        if shelf.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(shelf) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// The app's language, as the contract spells it.
    static var language: String {
        Assist.languageCode(for: Bundle.main.preferredLocalizations.first ?? "en")
    }

    // MARK: Thumbnails

    /// The small copy of one side, read off the main actor once.
    func thumbnail(_ id: String, _ side: PollSide) async -> UIImage? {
        let key = Self.thumbnailKey(id, side)
        if let cached = thumbnails[key] { return cached }
        let url = Self.directory.appendingPathComponent(key)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImageUtilities.decodedImage(from: data, maxPixel: PollPicture.thumbnailLongEdge)
        }.value
        if let image { thumbnails[key] = image }
        return image
    }

    private func forgetThumbnails(_ id: String) {
        thumbnails[Self.thumbnailKey(id, .a)] = nil
        thumbnails[Self.thumbnailKey(id, .b)] = nil
    }

    private nonisolated static func thumbnailKey(_ id: String, _ side: PollSide) -> String { "\(id)-\(side.rawValue).jpg" }

    /// Application Support/Polls, out of backups.
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Polls", isDirectory: true)
    }

    private nonisolated static func saveThumbnail(_ data: Data, id: String, side: PollSide) {
        var directory = directory
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
        }
        // Pictures of her: the library's protection class, not the system default.
        try? data.write(to: directory.appendingPathComponent(thumbnailKey(id, side)),
                        options: [.atomic, ImageStore.fileProtection])
    }

    private nonisolated static func removeThumbnails(of ids: [String]) {
        guard !ids.isEmpty else { return }
        let directory = directory
        Task.detached(priority: .utility) {
            for id in ids {
                for side in PollSide.allCases {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(thumbnailKey(id, side)))
                }
            }
        }
    }
}

// MARK: - Messages

extension PollsModel {
    /// A blocked question: the policy's own words, except that a question
    /// about looks gets a poll's words (the edit message talks about photos).
    static func questionMessage(reason: String, category: PolicyCategory) -> String {
        guard category == .appearanceChange else { return L10n.core(reason) }
        return String(localized: "Ask about the vibe, not about how anyone looks.",
                      comment: "“Which vibe?” polls: her question rates or compares how someone looks. Kind, never blaming.")
    }

    /// Short and kind, never blame: what happened, and what she can do.
    func message(for error: Error) -> String {
        switch error {
        case PollError.tooLarge, PollError.imageInvalid:
            return String(localized: "We couldn't prepare these pictures. Try two others.")
        case PollError.imageBlocked:
            return String(localized: "These pictures can't be shared in a poll. Try two others.",
                          comment: "A poll's pictures didn't pass the safety check. Never blame her.")
        case PollError.contentBlocked(let category):
            if let category = category.flatMap(PolicyCategory.init(rawValue:)),
               case .blocked(let reason, _) = ContentPolicy.verdict(for: category) {
                return Self.questionMessage(reason: reason, category: category)
            }
            return String(localized: "Try a question about the vibe, like “Which one for Friday?”")
        case PollError.rateLimited(let retryAfter):
            if remainingToday == 0 || (retryAfter ?? 0) >= 3600 {
                return String(localized: "You've made today's polls. More tomorrow ✨")
            }
            return String(localized: "Lots of polls right now. Try again in a little while.")
        case PollError.cooldown(let until, let retryAfter):
            let end = until ?? Date().addingTimeInterval(retryAfter ?? 24 * 3600)
            let time = end.formatted(date: Calendar.current.isDateInToday(end) ? .omitted : .abbreviated, time: .shortened)
            return String(localized: "Polls are taking a little break until \(time). Your free tools still work.")
        case PollError.installBlocked:
            return String(localized: "Polls are turned off here for now. If you think this is a mistake, contact us.")
        case PollError.safetyUnavailable:
            return String(localized: "Our safety check couldn't look at your pictures just now, so nothing was shared. Try again in a moment.")
        case PollError.notFound:
            return String(localized: "This poll has ended or was removed.")
        case PollError.unauthorized, PollError.noSession, AIServiceError.unauthorized:
            return String(localized: "Your session expired. Please try again.")
        case AIServiceError.offline:
            return String(localized: "You're offline. Connect to the internet to share a poll.")
        case AIServiceError.timedOut:
            return String(localized: "This is taking too long. Check your connection and try again.")
        case AIServiceError.network, AIServiceError.insecureConnection:
            return String(localized: "Check your internet connection and try again.")
        default:
            return String(localized: "Something went wrong. Please try again.")
        }
    }
}

// MARK: - App

extension AppModel {
    /// Polls are offered from 13 (the server can't know her age, so the app
    /// keeps them from younger members) where a backend is set up.
    var offersPolls: Bool { allowsCloudAI && polls.isAvailable }

    /// Your polls, on top of everything, with `focus` shown first.
    func presentPolls(focus: String? = nil) {
        guard offersPolls else { return }
        pollsSheet = PollsSheetRequest(focus: focus)
    }

    /// A `glowlit://poll/<id>` link: her poll's results, after a fresh read
    /// when this device doesn't know it yet. Someone else's poll isn't shown.
    func openPoll(_ id: String) async {
        guard offersPolls else { return }
        if polls.shelf.record(id) == nil {
            guard !isCloudOffline else {
                return showToast("You're offline. Connect to the internet to see your poll.", style: .info)
            }
            await polls.refresh()
            // The read didn't come through: it may well be hers.
            if polls.shelf.record(id) == nil, polls.refreshFailed {
                return showToast("You're offline. Connect to the internet to see your poll.", style: .info)
            }
        }
        guard polls.shelf.record(id) != nil else {
            showToast("That poll isn't one of yours on this device, or it has ended.", style: .info)
            return
        }
        presentPolls(focus: id)
    }

    /// "Your poll ends in an hour", when poll reminders are on (never with her question).
    func notePollMade(_ record: PollRecord) {
        Task { await notifier.schedulePollReminder(id: record.id, expiresAt: record.expiresAt) }
    }

    func notePollDeleted(_ id: String) {
        notifier.cancelPollReminder(id: id)
    }
}

#if DEBUG
extension PollsModel {
    /// `-GLPollsFixture live|results|ended|takendown|empty|limit|blocked`:
    /// her polls (and the day's allowance) without the server; `limit` and
    /// `blocked` make a new poll fail the way the server would.
    func seedFixture(_ name: String, pictures: [UIImage]) {
        fixture = name
        let now = Date()
        func record(_ index: Int, question: String?, hoursLeft: Double, votes: PollVotes,
                    status: PollStatus = .live, ai: PollAILabels = PollAILabels()) -> PollRecord {
            let id = "Fixture\(index)_Kq2LmN0p".prefix(16)
            let expires = now.addingTimeInterval(hoursLeft * 3600)
            return PollRecord(id: String(id), shareURL: URL(string: PollID.shareBase + id)!, question: question,
                              createdAt: expires.addingTimeInterval(-PollShelf.lifetime), expiresAt: expires,
                              status: status, votes: votes, ai: ai, updatedAt: now)
        }
        var records: [PollRecord]
        switch name {
        case "live":
            records = [record(1, question: L10n.core(PollQuestion.presets[1]), hoursLeft: 22.6, votes: PollVotes(a: 2, b: 3))]
        case "ended":
            records = [record(1, question: L10n.core(PollQuestion.presets[0]), hoursLeft: -2, votes: PollVotes(a: 9, b: 5))]
        case "takendown":
            records = [record(1, question: L10n.core(PollQuestion.presets[2]), hoursLeft: 20, votes: PollVotes(a: 4, b: 6)),
                       record(2, question: nil, hoursLeft: 15, votes: PollVotes(a: 1, b: 0), status: .takenDown)]
        case "empty", "limit", "blocked":
            records = []
        default:
            records = [record(1, question: L10n.core(PollQuestion.presets[1]), hoursLeft: 18.4, votes: PollVotes(a: 7, b: 12),
                              ai: PollAILabels(a: true, b: true)),
                       record(2, question: L10n.core(PollQuestion.presets[3]), hoursLeft: 3.2, votes: PollVotes(a: 4, b: 4)),
                       record(3, question: nil, hoursLeft: -2.5, votes: PollVotes(a: 9, b: 5))]
        }
        shelf = PollShelf(records: records)
        remainingToday = name == "limit" ? 0 : max(0, 3 - records.filter { !$0.hasEnded(at: now) }.count)
        dailyCap = 3
        for (index, record) in shelf.records.enumerated() where !pictures.isEmpty {
            thumbnails[Self.thumbnailKey(record.id, .a)] = pictures[(index * 2) % pictures.count]
            thumbnails[Self.thumbnailKey(record.id, .b)] = pictures[(index * 2 + 1) % pictures.count]
        }
    }

    static func fixtureError(_ name: String) -> PollError? {
        switch name {
        case "limit": return .rateLimited(retryAfter: 9 * 3600)
        case "blocked": return .imageBlocked(sides: [.b])
        default: return nil
        }
    }
}
#endif
