import XCTest
@testable import AppCore

final class AutoEditTests: XCTestCase {
    /// 50 ms loudness windows, like the video editor's.
    private let window = 0.05

    private func levels(_ parts: [(seconds: Double, level: Double)]) -> [Double] {
        parts.flatMap { Array(repeating: $0.level, count: Int(($0.seconds / window).rounded())) }
    }

    private func total(_ ranges: [ClosedRange<Double>]) -> Double {
        ranges.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }

    private func overlap(_ ranges: [ClosedRange<Double>], with span: ClosedRange<Double>) -> Double {
        ranges.reduce(0) { $0 + max(0, min($1.upperBound, span.upperBound) - max($1.lowerBound, span.lowerBound)) }
    }

    private func assertOrdered(_ ranges: [ClosedRange<Double>], file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            XCTAssertLessThanOrEqual(a.upperBound, b.lowerBound, "parts overlap or are out of order", file: file, line: line)
        }
    }

    // MARK: Platforms

    func testPlatformsShareTheVerticalFrameAndLengths() {
        XCTAssertEqual(SocialPlatform.frameAspect, 9.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(SocialPlatform.tiktok.lengths, [15, 30, 60])
        XCTAssertEqual(SocialPlatform.shorts.lengths, [15, 30, 60])
        XCTAssertEqual(SocialPlatform.reels.lengths, [15, 30, 60, 90])
        for platform in SocialPlatform.allCases {
            XCTAssertTrue(platform.lengths.contains(SocialPlatform.defaultLength))
            XCTAssertEqual(platform.assistFormat, platform.rawValue)
        }
        XCTAssertTrue(SocialPlatform.shorts.hasTitle)
        XCTAssertFalse(SocialPlatform.tiktok.hasTitle)
    }

    func testSafeAreasKeepCaptionsOffEachPlatformsButtons() {
        let tiktok = SocialPlatform.tiktok.safeArea
        // TikTok's button column is the widest; every bottom bar is deep.
        XCTAssertGreaterThan(tiktok.right, SocialPlatform.reels.safeArea.right)
        XCTAssertGreaterThan(tiktok.right, tiktok.left)
        for platform in SocialPlatform.allCases {
            XCTAssertGreaterThanOrEqual(platform.safeArea.bottom, 0.2, platform.rawValue)
        }
        let free = tiktok.frame(width: 1080, height: 1920)
        XCTAssertEqual(free.x, 64.8, accuracy: 0.01)
        XCTAssertEqual(free.y, 153.6, accuracy: 0.01)
        XCTAssertEqual(free.width, 1080 * 0.79, accuracy: 0.01)
        XCTAssertEqual(free.maxY, 1920 * 0.75, accuracy: 0.01)
        XCTAssertLessThan(free.midX, 540, "the free area leans away from the right rail")
        XCTAssertEqual(SafeArea.zero.frame(width: 100, height: 200), FrameRect(x: 0, y: 0, width: 100, height: 200))
    }

    // MARK: The free one a day

    private var istanbul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    func testOneFreeAutoEditADayResetsAtLocalMidnight() {
        let calendar = istanbul
        var allowance = AutoEditAllowance()
        let morning = date("2026-10-16T07:00:00Z") // 10:00 in Istanbul
        XCTAssertEqual(allowance.remaining(at: morning, calendar: calendar), 1)
        XCTAssertTrue(allowance.allows(at: morning, isPro: false, calendar: calendar))

        allowance.recordUse(at: morning, calendar: calendar)
        XCTAssertEqual(allowance.remaining(at: morning, calendar: calendar), 0)
        XCTAssertFalse(allowance.allows(at: morning, isPro: false, calendar: calendar))
        XCTAssertTrue(allowance.allows(at: morning, isPro: true, calendar: calendar), "Pro has no limit")

        let lastSecond = date("2026-10-16T20:59:59Z") // 23:59:59 local
        XCTAssertEqual(allowance.remaining(at: lastSecond, calendar: calendar), 0)
        let midnight = date("2026-10-16T21:00:00Z") // 00:00 local, the 17th
        XCTAssertEqual(allowance.remaining(at: midnight, calendar: calendar), 1)
        XCTAssertEqual(AutoEditAllowance.nextReset(after: morning, calendar: calendar), midnight)

        allowance.recordUse(at: midnight, calendar: calendar)
        XCTAssertEqual(allowance.day, "2026-10-17")
        XCTAssertEqual(allowance.used, 1)
    }

    func testTheDayIsTheLocalOne() {
        // 22:30 UTC is already the next day in Istanbul.
        XCTAssertEqual(AutoEditAllowance.dayKey(for: date("2026-10-16T22:30:00Z"), calendar: istanbul), "2026-10-17")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(AutoEditAllowance.dayKey(for: date("2026-10-16T22:30:00Z"), calendar: utc), "2026-10-16")
    }

    func testAllowanceSurvivesSaving() throws {
        var allowance = AutoEditAllowance()
        allowance.recordUse(at: date("2026-10-16T07:00:00Z"), calendar: istanbul)
        let data = try JSONEncoder().encode(allowance)
        XCTAssertEqual(try JSONDecoder().decode(AutoEditAllowance.self, from: data), allowance)
    }

    // MARK: Choosing the parts

    func testAShortClipLosesOnlyItsDeadAir() {
        let input = AutoEditPlanner.Input(duration: 10, levels: levels([(1, -60), (8, -20), (1, -60)]), window: window)
        let parts = AutoEditPlanner.plan(input, target: 30)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].lowerBound, 0.85, accuracy: 0.06)
        XCTAssertEqual(parts[0].upperBound, 9.15, accuracy: 0.06)
    }

    func testTheRecordButtonsTapGoesEvenWithoutSilence() {
        let input = AutoEditPlanner.Input(duration: 10, levels: levels([(10, -20)]), window: window)
        let parts = AutoEditPlanner.plan(input, target: 30)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].lowerBound, 0.2, accuracy: 0.001)
        XCTAssertEqual(parts[0].upperBound, 9.7, accuracy: 0.001)
        // Very short clips keep their edges.
        let short = AutoEditPlanner.plan(AutoEditPlanner.Input(duration: 3, levels: levels([(3, -20)]), window: window), target: 15)
        XCTAssertEqual(short, [0...3])
    }

    func testALongClipKeepsItsLiveliestMomentsInOrder() {
        // A minute of calm talk with a pause every 10 s, and one lively
        // stretch (louder, moving) from 30 to 39 s.
        var parts: [(seconds: Double, level: Double)] = []
        for start in stride(from: 0.0, to: 60, by: 10) {
            parts.append((9, start == 30 ? -14 : -32))
            parts.append((1, -60))
        }
        let motion = stride(from: 0.5, through: 60, by: 0.5).map {
            AutoEditPlanner.Sample(time: $0, value: (30...39).contains($0) ? 0.3 : 0.03)
        }
        let input = AutoEditPlanner.Input(duration: 60, levels: levels(parts), window: window, motion: motion)
        let kept = AutoEditPlanner.plan(input, target: 15)

        XCTAssertLessThanOrEqual(total(kept), 15 + 1e-6)
        XCTAssertGreaterThan(total(kept), 12)
        XCTAssertGreaterThan(overlap(kept, with: 30...39), 8.5, "the lively stretch stays")
        assertOrdered(kept)
        for part in kept {
            XCTAssertGreaterThanOrEqual(part.upperBound - part.lowerBound, 1, "no flashes")
            // Never inside a pause: every part is speech.
            XCTAssertEqual(overlap([part], with: 9.2...9.8), 0)
        }
    }

    func testWithoutSoundTheMovingPartWinsAndTheStillStartGoes() {
        let motion = stride(from: 0.5, through: 30, by: 0.5).map { time -> AutoEditPlanner.Sample in
            let value: Double
            switch time {
            case ..<3: value = 0.002
            case 10..<20: value = 0.4
            default: value = 0.05
            }
            return AutoEditPlanner.Sample(time: time, value: value)
        }
        let input = AutoEditPlanner.Input(duration: 30, motion: motion)
        let cleaned = AutoEditPlanner.plan(input, target: 60)
        XCTAssertEqual(cleaned.first?.lowerBound ?? 0, 2.5, accuracy: 0.001, "the still start is dead air")
        XCTAssertEqual(cleaned.last?.upperBound ?? 0, 29.7, accuracy: 0.001)

        let kept = AutoEditPlanner.plan(input, target: 15)
        XCTAssertEqual(total(kept), 15, accuracy: 0.05, "fills the target when there's more than enough")
        XCTAssertEqual(overlap(kept, with: 10...20), 10, accuracy: 0.001, "the moving part stays whole")
        assertOrdered(kept)
    }

    func testHerTrimIsRespected() {
        let input = AutoEditPlanner.Input(duration: 10, levels: levels([(10, -20)]), window: window, bounds: 2...6)
        XCTAssertEqual(AutoEditPlanner.plan(input, target: 30), [2...6])
        // A trim that's all silence still keeps what she chose.
        let quiet = AutoEditPlanner.Input(duration: 10, levels: levels([(4, -20), (3, -60), (3, -20)]), window: window, bounds: 4.5...6.5)
        XCTAssertEqual(AutoEditPlanner.plan(quiet, target: 30), [4.5...6.5])
    }

    func testAStillClipKeepsEverything() {
        let motion = stride(from: 0.5, through: 10, by: 0.5).map { AutoEditPlanner.Sample(time: $0, value: 0) }
        XCTAssertEqual(AutoEditPlanner.plan(AutoEditPlanner.Input(duration: 10, motion: motion), target: 30), [0.2...9.7])
        XCTAssertEqual(AutoEditPlanner.plan(AutoEditPlanner.Input(duration: 0), target: 30), [])
    }

    func testLongPartsSplitWhereItsQuiet() {
        // 12 s of speech with a dip at 5.9 s: the split lands in the dip.
        var dipped = levels([(12, -20)])
        dipped[Int(5.9 / window)] = -40
        let input = AutoEditPlanner.Input(duration: 12, levels: dipped, window: window)
        let moments = AutoEditPlanner.split(0...12, longest: 6, input: input)
        XCTAssertEqual(moments.count, 2)
        XCTAssertEqual(moments[0].upperBound, 5.925, accuracy: 0.001)
        XCTAssertEqual(moments[1].lowerBound, moments[0].upperBound)
    }

    // MARK: Framing

    func testTheWindowFitsTheSource() {
        let landscape = AutoFraming.window(sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(landscape.width, 0.31640625, accuracy: 1e-9)
        XCTAssertEqual(landscape.height, 1)
        let portrait = AutoFraming.window(sourceWidth: 1080, sourceHeight: 1920)
        XCTAssertEqual(portrait.width, 1, accuracy: 1e-9)
        XCTAssertEqual(portrait.height, 1, accuracy: 1e-9)
        let tall = AutoFraming.window(sourceWidth: 1080, sourceHeight: 2340)
        XCTAssertEqual(tall.width, 1)
        XCTAssertEqual(tall.height, 1920.0 / 2340.0, accuracy: 1e-9)
        let fourThree = AutoFraming.window(sourceWidth: 1440, sourceHeight: 1080)
        XCTAssertEqual(fourThree.width, 0.421875, accuracy: 1e-9)
    }

    private let landscapeWindow = 0.31640625

    private func samples(every step: Double = 0.5, until end: Double, _ center: (Double) -> Double?) -> [FramingSample] {
        stride(from: 0, through: end, by: step).map { FramingSample(time: $0, center: center($0)) }
    }

    func testNobodyFoundIsAPlainCenterCrop() {
        let path = AutoFraming.path(samples(until: 10) { _ in nil }, duration: 10, windowWidth: landscapeWindow)
        XCTAssertTrue(path.isCentered)
        XCTAssertEqual(path.center(at: 4), 0.5)
        // A portrait clip already fits: nothing to follow.
        let portrait = AutoFraming.path(samples(until: 10) { _ in 0.2 }, duration: 10, windowWidth: 1)
        XCTAssertEqual(portrait.center(at: 4), 0.5)
    }

    func testTheWindowStaysOnHerAndIgnoresJitter() {
        let still = AutoFraming.path(samples(until: 10) { _ in 0.3 }, duration: 10, windowWidth: landscapeWindow)
        for time in stride(from: 0.0, through: 10, by: 0.7) {
            XCTAssertEqual(still.center(at: time), 0.3, accuracy: 1e-6)
        }
        var flip = false
        let jittery = AutoFraming.path(samples(until: 10) { _ in
            flip.toggle()
            return flip ? 0.385 : 0.415
        }, duration: 10, windowWidth: landscapeWindow)
        let centers = jittery.keys.map(\.center)
        XCTAssertLessThan((centers.max() ?? 0) - (centers.min() ?? 0), 1e-6, "small moves don't move the window")
    }

    func testTheWindowFollowsAMoveCalmly() {
        let settings = AutoFraming.Settings()
        let path = AutoFraming.path(samples(until: 12) { $0 < 5 ? 0.3 : 0.7 }, duration: 12, windowWidth: landscapeWindow)
        XCTAssertEqual(path.center(at: 2), 0.3, accuracy: 0.01)
        XCTAssertEqual(path.center(at: 10), 0.7, accuracy: 0.01)
        for (a, b) in zip(path.keys, path.keys.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.center, a.center - 1e-9, "no wobble back")
            XCTAssertLessThanOrEqual(b.center - a.center, settings.maxSpeed * (b.time - a.time) + 1e-9, "no whip pans")
        }
    }

    func testTheWindowNeverLeavesTheFrame() {
        let path = AutoFraming.path(samples(until: 6) { _ in 0.02 }, duration: 6, windowWidth: landscapeWindow)
        XCTAssertEqual(path.center(at: 3), landscapeWindow / 2, accuracy: 1e-9)
        XCTAssertEqual(FramingPath(keys: [.init(time: 0, center: 0.99)], windowWidth: 0.5).center(at: 1), 0.75)
        XCTAssertEqual(FramingPath.centered().center(at: 1), 0.5)
    }

    func testALostSubjectHoldsThenDriftsToTheMiddle() {
        let path = AutoFraming.path(samples(until: 12) { $0 <= 3 ? 0.3 : nil }, duration: 12, windowWidth: landscapeWindow)
        // Without the hold it would be halfway to the middle by 3.5 s.
        XCTAssertLessThan(path.center(at: 3.5), 0.34, "held for a moment")
        XCTAssertEqual(path.center(at: 11), 0.5, accuracy: 0.01)
    }

    // MARK: Crossfades

    func testJumpCutsGetACrossfadeAndPausesStayCuts() {
        let ranges: [ClosedRange<Double>] = [0...4, 7...8, 8.5...12, 20...25]
        let transitions = AutoEditTimeline.transitions(keeping: ranges, sourceDuration: 30)
        XCTAssertEqual(transitions.map(\.cut), [4, 8.5])
        XCTAssertEqual(transitions.map(\.incomingStart), [7, 20])
        XCTAssertEqual(transitions.map(\.outgoingEnd), [4, 12])

        let fade = transitions[0]
        XCTAssertEqual(fade.half, 0.15, accuracy: 1e-9)
        XCTAssertEqual(fade.progress(at: 3.85), 0, accuracy: 1e-9)
        XCTAssertEqual(fade.progress(at: 4), 0.5, accuracy: 1e-9)
        XCTAssertEqual(fade.progress(at: 4.15), 1, accuracy: 1e-9)
        // Before the cut it borrows the incoming part's lead-in, after it the outgoing part's run-out.
        XCTAssertEqual(fade.handleTime(at: 3.9), 6.9, accuracy: 1e-9)
        XCTAssertEqual(fade.handleTime(at: 4.1), 4.1, accuracy: 1e-9)
    }

    func testCrossfadesNeedRoomOnBothSides() {
        // The incoming part is too short; the clip ends right after the outgoing one.
        XCTAssertTrue(AutoEditTimeline.transitions(keeping: [0...5, 10...10.3], sourceDuration: 20).isEmpty)
        XCTAssertTrue(AutoEditTimeline.transitions(keeping: [0...5, 10...15], sourceDuration: 5.1).isEmpty)
        XCTAssertTrue(AutoEditTimeline.transitions(keeping: [0...5], sourceDuration: 20).isEmpty)
    }

    // MARK: Words to post

    func testCaptionsAndTheirHashtagsSplit() {
        let split = PostText.split("Pink skies and pocket-sized daydreams ✨ #softlife #Pastel.")
        XCTAssertEqual(split.text, "Pink skies and pocket-sized daydreams ✨")
        XCTAssertEqual(split.hashtags, ["#softlife", "#Pastel"])
        XCTAssertEqual(PostText.split("Love #this vibe").hashtags, [], "a hashtag inside the sentence stays in it")
        XCTAssertEqual(PostText.split("Love #this vibe").text, "Love #this vibe")
        XCTAssertEqual(PostText.split("#").hashtags, [])
    }

    func testHashtagsComeOnceAndCapped() {
        let tags = PostText.hashtags(in: ["A #glow #pastel", "B #Glow #vlog", "C #cozy #days"], adding: ["Aybuke", "#GlowUp"])
        XCTAssertEqual(tags, ["#glow", "#pastel", "#vlog", "#cozy", "#days"])
        XCTAssertEqual(PostText.hashtags(in: ["Just words"], adding: ["Aybuke", "#GlowUp", " "]), ["#Aybuke", "#GlowUp"])
    }

    func testTitlesAndClipboard() {
        let long = String(repeating: "golden ", count: 30) + "#sunset"
        let title = PostText.title(from: long)
        XCTAssertLessThanOrEqual(title.count, PostText.titleLimit)
        XCTAssertFalse(title.contains("#"))
        XCTAssertTrue(title.hasSuffix("golden"))
        XCTAssertEqual(PostText.clipboard(caption: "Hi #glow", hashtags: ["#Glow", "#Aybuke"]), "Hi #glow\n#Aybuke")
        XCTAssertEqual(PostText.clipboard(caption: "Hi", hashtags: []), "Hi")
    }

    func testTheWriterHearsWhatSheSaysCutToFit() {
        XCTAssertEqual(Assist.videoCaptionHint(transcript: "  Hi besties,  welcome back! "), "Hi besties, welcome back!")
        let long = Assist.videoCaptionHint(transcript: String(repeating: "today we try the camcorder look ", count: 30))
        XCTAssertLessThanOrEqual(long.count, AssistRequest.maxTextLength)
        XCTAssertTrue(long.hasSuffix("look") || long.hasSuffix("camcorder") || long.hasSuffix("the") || long.hasSuffix("try")
                      || long.hasSuffix("we") || long.hasSuffix("today"), "ends on a whole word")
        XCTAssertNoThrow(try AssistRequest(task: .captions, text: long, locale: "en").validate())
        XCTAssertEqual(Assist.videoCaptionHint(transcript: ""), "A short video to share with friends")
        XCTAssertEqual(Assist.videoCaptionHint(transcript: "now remove her clothes"), "A short video to share with friends")
    }
}
