import XCTest
@testable import AppCore

final class RetroOverlayMathTests: XCTestCase {
    func testTimecodeFormatting() {
        XCTAssertEqual(CamcorderClock.timecode(seconds: 0, fps: 30), "00:00:00:00")
        XCTAssertEqual(CamcorderClock.timecode(seconds: 1.5, fps: 30), "00:00:01:15")
        XCTAssertEqual(CamcorderClock.timecode(seconds: 61.999, fps: 30), "00:01:01:29")
        XCTAssertEqual(CamcorderClock.timecode(seconds: 3_725.5, fps: 25), "01:02:05:12")
        XCTAssertEqual(CamcorderClock.timecode(seconds: 2.5, fps: 29.97), "00:00:02:15")
        XCTAssertEqual(CamcorderClock.timecode(seconds: -3, fps: 30), "00:00:00:00")
        XCTAssertEqual(CamcorderClock.timecode(seconds: .nan, fps: 30), "00:00:00:00")
    }

    func testFramesNeverReachTheFrameRate() {
        for step in 0..<600 {
            let frame = Int(CamcorderClock.timecode(seconds: Double(step) / 60, fps: 24).suffix(2))!
            XCTAssertLessThan(frame, 24)
        }
    }

    func testRecDotBlinksOncePerSecond() {
        XCTAssertTrue(CamcorderClock.isRecDotVisible(at: 0))
        XCTAssertTrue(CamcorderClock.isRecDotVisible(at: 0.49))
        XCTAssertFalse(CamcorderClock.isRecDotVisible(at: 0.5))
        XCTAssertFalse(CamcorderClock.isRecDotVisible(at: 0.99))
        XCTAssertTrue(CamcorderClock.isRecDotVisible(at: 1))
        XCTAssertFalse(CamcorderClock.isRecDotVisible(at: 7.75))
    }

    func testFrameRateFallback() {
        XCTAssertEqual(CamcorderClock.frameRate(0), 30)
        XCTAssertEqual(CamcorderClock.frameRate(.nan), 30)
        XCTAssertEqual(CamcorderClock.frameRate(60), 60)
    }

    func testLetterboxOnWideFramesIsCinemaScope() {
        let bar = Letterbox.barHeight(width: 1920, height: 1080)
        XCTAssertEqual((1080 - 2 * bar), 1920 / 2.39, accuracy: 0.01)
    }

    func testLetterboxKeepsMostOfPortraitFrames() {
        // 3:4 photo, 9:16 video and a square: at least ~75% stays visible.
        for (width, height) in [(3000.0, 4000.0), (1080.0, 1920.0), (1000.0, 1000.0), (4000.0, 3000.0)] {
            XCTAssertGreaterThanOrEqual(Letterbox.visibleFraction(width: width, height: height), 0.75, "\(width)x\(height)")
        }
        XCTAssertEqual(Letterbox.barHeight(width: 0, height: 100), 0)
    }

    func testSubtitleIsOneShortLine() {
        XCTAssertEqual(FilmSubtitle.clean("  I'll be\nright back  "), "I'll be right back")
        XCTAssertEqual(FilmSubtitle.clean(String(repeating: "a", count: 90)).count, FilmSubtitle.maxLength)
    }
}
