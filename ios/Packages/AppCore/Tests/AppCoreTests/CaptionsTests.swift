import XCTest
@testable import AppCore

final class CaptionLayoutTests: XCTestCase {
    func testShortTextStaysOnOneLine() {
        XCTAssertEqual(CaptionLayout.lines(for: "Hi everyone, welcome back!"), ["Hi everyone, welcome back!"])
        XCTAssertEqual(CaptionLayout.lineCount(for: "Hi everyone, welcome back!"), 1)
        XCTAssertEqual(CaptionLayout.lines(for: "  padded  "), ["padded"])
        XCTAssertEqual(CaptionLayout.lines(for: ""), [])
    }

    func testLongerTextSplitsIntoTwoBalancedLines() {
        let text = "Today I am trying the new pink hair look and I love it"
        let lines = CaptionLayout.lines(for: text)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.joined(separator: " "), text)
        XCTAssertTrue(lines.allSatisfy { $0.count <= CaptionLayout.lineWidth })
        // Balanced: neither line is a stub.
        XCTAssertLessThanOrEqual(abs(lines[0].count - lines[1].count), 8)
        // The top line is never the longer one by much (bottom-heavy pyramid).
        XCTAssertLessThanOrEqual(lines[0].count, lines[1].count + 4)
    }

    func testBreaksAfterPunctuationWhenNearlyAsEven() {
        let comma = CaptionLayout.lines(for: "I tried it on Monday morning, and it was amazing")
        XCTAssertEqual(comma, ["I tried it on Monday morning,", "and it was amazing"])
        // Without punctuation, balance wins.
        let lines = CaptionLayout.lines(for: "Honestly I think this is the best look so far")
        XCTAssertEqual(lines, ["Honestly I think this", "is the best look so far"])
    }

    func testLineRangesSkipTheBreakingSpace() {
        let text = "Today I am trying the new pink hair look and I love it"
        let ranges = CaptionLayout.lineRanges(for: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[1].lowerBound - ranges[0].upperBound, 1)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, text.utf16.count)
    }

    func testChineseAndJapaneseCountDoubleAndBreakBetweenCharacters() {
        XCTAssertEqual(CaptionLayout.width(of: "今日は"), 6)
        XCTAssertEqual(CaptionLayout.width(of: "abc"), 3)
        XCTAssertEqual(CaptionLayout.width(of: "💖"), 2)
        // 20 characters = 40 units: two lines of about ten.
        let text = "今日は新しいピンクの髪を試してみました。どう"
        let lines = CaptionLayout.lines(for: text)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.joined(), text)
        XCTAssertTrue(lines.allSatisfy { CaptionLayout.width(of: $0) <= CaptionLayout.lineWidth })
        // Closing punctuation never starts a line.
        XCTAssertFalse(lines[1].hasPrefix("。"))
    }

    func testKoreanBreaksOnlyAtSpaces() {
        let text = "오늘은 새로운 핑크 헤어 스타일을 해봤어요 정말 마음에 들어요"
        let lines = CaptionLayout.lines(for: text)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.joined(separator: " "), text)
    }

    func testAWordLongerThanALineGetsItsOwnLine() {
        let long = String(repeating: "a", count: 40)
        let lines = CaptionLayout.lines(for: "hey \(long) you")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1], long)
    }

    func testManualTextMayUseMoreLines() {
        let text = String(repeating: "lovely words ", count: 9).trimmingCharacters(in: .whitespaces)
        let lines = CaptionLayout.lines(for: text)
        XCTAssertGreaterThan(lines.count, 2)
        XCTAssertEqual(lines.joined(separator: " "), text)
        XCTAssertTrue(lines.allSatisfy { $0.count <= CaptionLayout.lineWidth })
    }
}

final class CaptionChunkerTests: XCTestCase {
    /// SpeechTranscriber-style runs: a leading space, punctuation attached.
    private func phrase(_ text: String, from start: Double, perWord: Double = 0.3) -> TranscriptPhrase {
        var time = start
        let pieces = text.split(separator: " ").enumerated().map { index, word -> TranscriptPiece in
            defer { time += perWord }
            return TranscriptPiece(text: (index == 0 ? "" : " ") + word, start: time, end: time + perWord)
        }
        return TranscriptPhrase(pieces: pieces)
    }

    func testShortSentencesBecomeOneCue() {
        let cues = CaptionChunker.cues(from: [phrase("Hi everyone, welcome back.", from: 0)])
        XCTAssertEqual(cues.map(\.text), ["Hi everyone, welcome back."])
        XCTAssertEqual(cues[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(cues[0].words?.map(\.text), ["Hi", "everyone,", "welcome", "back."])
    }

    func testLongSpeechSplitsIntoReadableCues() {
        let text = "So today I wanted to show you my new favorite look because honestly it is giving everything and I think you will love it too"
        let cues = CaptionChunker.cues(from: [phrase(text, from: 1)])
        XCTAssertGreaterThan(cues.count, 3)
        for cue in cues {
            XCTAssertLessThanOrEqual(cue.words?.count ?? 0, 7)
            XCTAssertLessThanOrEqual(CaptionLayout.lineCount(for: cue.text), 2)
            let spoken = (cue.words?.last?.end ?? 0) - (cue.words?.first?.start ?? 0)
            XCTAssertLessThanOrEqual(spoken, 3.5 + 0.001)
        }
        // Nothing lost, nothing repeated, in order, no overlaps.
        XCTAssertEqual(cues.map(\.text).joined(separator: " "), text)
        for (a, b) in zip(cues, cues.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start + 0.0001)
        }
    }

    func testSlowSpeechIsSplitByTime() {
        let cues = CaptionChunker.cues(from: [phrase("one two three four five six", from: 0, perWord: 1)])
        XCTAssertTrue(cues.allSatisfy { ($0.words?.last?.end ?? 0) - ($0.words?.first?.start ?? 0) <= 3.5 })
        XCTAssertGreaterThan(cues.count, 1)
    }

    func testPrefersBreakingAfterPunctuation() {
        let cues = CaptionChunker.cues(from: [phrase("I love this look so much. Do you like it too or not really?", from: 0, perWord: 0.25)])
        XCTAssertEqual(cues.first?.text, "I love this look so much.")
    }

    func testAPauseStartsANewCue() {
        var words = phrase("hello there", from: 0).words
        words += phrase("friend", from: 3).words.map { TranscriptWord(text: " " + $0.text, start: $0.start, end: $0.end) }
        let cues = CaptionChunker.cues(from: [TranscriptPhrase(words: words)])
        XCTAssertEqual(cues.map(\.text), ["hello there", "friend"])
    }

    func testReadingTimeAndBridging() {
        let cues = CaptionChunker.cues(from: [phrase("Hi.", from: 0, perWord: 0.2), phrase("Bye now.", from: 5)])
        // A one-word caption stays at least the minimum time.
        XCTAssertGreaterThanOrEqual(cues[0].end - cues[0].start, 0.8 - 0.001)
        // Close captions are bridged so they don't blink.
        let close = CaptionChunker.cues(from: [phrase("first part here.", from: 0), phrase("second part.", from: 1.1)])
        XCTAssertEqual(close[0].end, close[1].start, accuracy: 0.001)
    }

    func testDictationStylePunctuationRunsJoinTheWordBefore() {
        let pieces = [
            TranscriptPiece(text: "channel ", start: 2.1, end: 2.6),
            TranscriptPiece(text: "today", start: 3.2, end: 3.7),
            TranscriptPiece(text: ". ", start: 3.7, end: 3.7),
            TranscriptPiece(text: "I ", start: 3.7, end: 3.8),
            TranscriptPiece(text: "am", start: 3.8, end: 3.9),
        ]
        let phrase = TranscriptPhrase(pieces: pieces)
        XCTAssertEqual(phrase.words.map(\.text), ["channel ", "today.", " I ", "am"])
        let cues = CaptionChunker.cues(from: [phrase])
        XCTAssertEqual(cues.map(\.text), ["channel today. I am"])
        XCTAssertEqual(cues[0].words?.map(\.text), ["channel", "today.", "I", "am"])
    }

    func testShortSentencesShareACueButLongerOnesSplitAtTheirEnd() {
        let cues = CaptionChunker.cues(from: [phrase("Hi. I'm Ana and this is my morning routine for school days.", from: 0, perWord: 0.25)])
        XCTAssertEqual(cues.first?.text.hasPrefix("Hi. I'm Ana"), true)
        XCTAssertTrue(cues.allSatisfy { ($0.words?.count ?? 0) <= 7 })
    }

    func testSegmentsWithGlueFromSFSpeechRecognizer() {
        let text = "Hello there. How are you?"
        let ns = text as NSString
        let segments = ["Hello", "there", "How", "are", "you"].enumerated().map { index, word in
            (range: ns.range(of: word).location..<(ns.range(of: word).location + ns.range(of: word).length),
             start: Double(index) * 0.4, end: Double(index) * 0.4 + 0.35)
        }
        let phrase = TranscriptPhrase(text: text, segments: segments)
        XCTAssertEqual(phrase.words.map(\.text), ["Hello", " there.", " How", " are", " you?"])
        XCTAssertEqual(CaptionChunker.cues(from: [phrase]).map(\.text), ["Hello there. How are you?"])
    }

    func testJapaneseWordsJoinWithoutSpaces() {
        let tokens = ["今日", "は", "ピンク", "の", "髪", "を", "試し", "まし", "た", "。"]
        var time = 0.0
        let pieces = tokens.map { token -> TranscriptPiece in
            defer { time += 0.2 }
            return TranscriptPiece(text: token, start: time, end: time + 0.2)
        }
        let cues = CaptionChunker.cues(from: [TranscriptPhrase(pieces: pieces)])
        XCTAssertEqual(cues.map(\.text).joined(), "今日はピンクの髪を試しました。")
        // Not limited to 7 "words": Japanese has no spaces between them.
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].wordRanges?.count, 9)
    }

    func testTextWithoutWordTimesIsSpreadAndHasNoKaraoke() {
        let phrase = TranscriptPhrase(text: "this has no word times at all but still needs captions to read", start: 0, end: 6)
        XCTAssertFalse(phrase.hasWordTimes)
        let cues = CaptionChunker.cues(from: [phrase])
        XCTAssertGreaterThan(cues.count, 1)
        XCTAssertTrue(cues.allSatisfy { $0.words == nil })
        XCTAssertEqual(cues.last?.start ?? 0, 3, accuracy: 1.5)
    }
}

final class CaptionCueTests: XCTestCase {
    private let cue = CaptionCue(start: 1, end: 3, text: "Hi there, friend!", words: [
        CaptionWord(text: "Hi", start: 1, end: 1.3),
        CaptionWord(text: "there,", start: 1.4, end: 1.9),
        CaptionWord(text: "friend!", start: 2, end: 2.6),
    ])

    func testActiveWord() {
        XCTAssertEqual(cue.activeWordIndex(at: 0.9), 0)
        XCTAssertEqual(cue.activeWordIndex(at: 1.5), 1)
        XCTAssertEqual(cue.activeWordIndex(at: 2.9), 2)
        XCTAssertNil(CaptionCue(start: 0, end: 1, text: "x").activeWordIndex(at: 0.5))
    }

    func testWordRanges() {
        XCTAssertEqual(cue.wordRanges, [0..<2, 3..<9, 10..<17])
        var broken = cue
        broken.text = "something else"
        XCTAssertNil(broken.wordRanges)
    }

    func testFixingATypoKeepsWordTimes() {
        let fixed = cue.withText("Hi there, bestie!")
        XCTAssertEqual(fixed.words?.map(\.text), ["Hi", "there,", "bestie!"])
        XCTAssertEqual(fixed.words?[2].start, 2)
        XCTAssertEqual(fixed.wordRanges?.count, 3)
        XCTAssertNil(cue.withText("Hi there").words)
    }
}

final class CaptionTimelineTests: XCTestCase {
    private func cue(_ start: Double, _ end: Double, _ text: String = "words") -> CaptionCue {
        CaptionCue(start: start, end: end, text: text, words: [CaptionWord(text: text, start: start, end: end)])
    }

    func testUneditedClipKeepsTimes() {
        let cues = [cue(0.5, 2), cue(3, 4)]
        XCTAssertEqual(CaptionTimeline.remap(cues, keeping: [0...10]).map(\.start), [0.5, 3])
        XCTAssertEqual(CaptionTimeline.remap(cues, keeping: [0...10]).map(\.end), [2, 4])
    }

    func testTrimShiftsAndClips() {
        let remapped = CaptionTimeline.remap([cue(0.5, 2), cue(3, 4), cue(9, 9.5)], keeping: [1...8])
        XCTAssertEqual(remapped.count, 2)
        XCTAssertEqual(remapped[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(remapped[0].end, 1, accuracy: 0.0001)
        XCTAssertEqual(remapped[1].start, 2, accuracy: 0.0001)
        XCTAssertEqual(remapped[1].end, 3, accuracy: 0.0001)
    }

    func testSilenceCutsDropAndJoin() {
        // Kept: 0–2 and 4–6; 2–4 is cut.
        let ranges: [ClosedRange<Double>] = [0...2, 4...6]
        let remapped = CaptionTimeline.remap([cue(2.2, 3.8, "gone"), cue(1.5, 4.5, "across"), cue(5, 5.5, "after")], keeping: ranges)
        XCTAssertEqual(remapped.map(\.text), ["across", "after"])
        // 1.5–2 and 4–4.5 play back to back: 1.5–2.5 on the edited timeline.
        XCTAssertEqual(remapped[0].start, 1.5, accuracy: 0.0001)
        XCTAssertEqual(remapped[0].end, 2.5, accuracy: 0.0001)
        XCTAssertEqual(remapped[1].start, 3, accuracy: 0.0001)
        // Word times collapse into the kept part.
        XCTAssertEqual(remapped[0].words?[0].start ?? -1, 1.5, accuracy: 0.0001)
        XCTAssertEqual(remapped[0].words?[0].end ?? -1, 2.5, accuracy: 0.0001)
    }

    func testSliversAndBlankCuesAreDropped() {
        let remapped = CaptionTimeline.remap([cue(1.95, 2.5), CaptionCue(start: 0, end: 1, text: "  ")], keeping: [0...2, 4...6])
        XCTAssertTrue(remapped.isEmpty)
    }

    func testTimeMapsBothWays() {
        let ranges: [ClosedRange<Double>] = [1...3, 5...8]
        XCTAssertEqual(CaptionTimeline.outputTime(2, keeping: ranges), 1)
        XCTAssertEqual(CaptionTimeline.outputTime(6, keeping: ranges), 3)
        XCTAssertNil(CaptionTimeline.outputTime(4, keeping: ranges))
        XCTAssertEqual(CaptionTimeline.sourceTime(1, keeping: ranges), 2)
        XCTAssertEqual(CaptionTimeline.sourceTime(3, keeping: ranges), 6)
        XCTAssertEqual(CaptionTimeline.sourceTime(99, keeping: ranges), 8)
    }

    func testFindsTheCueAtATime() {
        let cues = [cue(0, 1), cue(1, 2), cue(2.5, 4), cue(3, 3.5)]
        XCTAssertEqual(CaptionTimeline.index(at: 0.5, in: cues), 0)
        XCTAssertEqual(CaptionTimeline.index(at: 1, in: cues), 1)
        XCTAssertNil(CaptionTimeline.index(at: 2.2, in: cues))
        XCTAssertEqual(CaptionTimeline.index(at: 3.2, in: cues), 3)
        XCTAssertEqual(CaptionTimeline.index(at: 3.7, in: cues), 2)
        XCTAssertNil(CaptionTimeline.index(at: 5, in: cues))
        XCTAssertNil(CaptionTimeline.index(at: 1, in: []))
    }
}

final class CaptionSRTTests: XCTestCase {
    func testSubRipText() {
        let cues = [
            CaptionCue(start: 3723.5, end: 3725, text: "Later one"),
            CaptionCue(start: 0.25, end: 2, text: "Today I am trying the new pink hair look and I love it"),
            CaptionCue(start: 2, end: 3, text: " "),
        ]
        XCTAssertEqual(CaptionSRT.text(for: cues), """
        1
        00:00:00,250 --> 00:00:02,000
        Today I am trying the new
        pink hair look and I love it

        2
        01:02:03,500 --> 01:02:05,000
        Later one

        """)
    }
}

final class CaptionLanguageTests: XCTestCase {
    private let available = ["en_US", "en_GB", "es_ES", "es_MX", "pt_BR", "pt_PT", "zh_CN", "zh_TW", "yue_CN", "ja_JP", "tr_TR"]

    func testPrefersTheAppLanguageThenTheDeviceLanguage() {
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["tr", "en-US"], available: available, region: "TR"), "tr_TR")
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["ru", "en-GB"], available: available, region: "GB"), "en_GB")
        XCTAssertNil(CaptionLanguage.bestMatch(preferred: ["ru"], available: available, region: nil))
    }

    func testRegionChoice() {
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["en"], available: available, region: "TR"), "en_US")
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["en"], available: available, region: "GB"), "en_GB")
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["es"], available: available, region: "MX"), "es_MX")
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["pt-BR"], available: available, region: "PT"), "pt_BR")
    }

    func testChineseMatchesItsScript() {
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["zh-Hans"], available: available, region: nil), "zh_CN")
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["zh-Hant-TW"], available: available, region: nil), "zh_TW")
        XCTAssertEqual(CaptionLanguage.bestMatch(preferred: ["zh-Hans"], available: ["zh_TW"], region: nil), nil)
    }
}
