import Foundation
import XCTest

/// Files outside the package that cross-checks read: the backend's shared
/// JSON, migrations, the app's string catalogs and AppConfig.json.
enum RepositoryFile {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // → AppCoreTests/
        .deletingLastPathComponent() // → Tests/
        .deletingLastPathComponent() // → AppCore/
        .deletingLastPathComponent() // → Packages/
        .deletingLastPathComponent() // → ios/
        .deletingLastPathComponent() // → repository root

    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    /// The file at `path` from the repository root. Missing, it skips the test
    /// only in a local run of the package on its own; with `CI` set (GitHub
    /// Actions sets it) it fails, so a moved folder can't turn a cross-check
    /// into a silent skip.
    static func url(_ path: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let message = "\(path) not found at \(url.path)"
            if let ci = environment["CI"], !ci.isEmpty { throw Missing(description: "\(message); CI never skips it") }
            throw XCTSkip(message)
        }
        return url
    }
}

final class RepositoryFileTests: XCTestCase {
    func testMissingFileFailsOnCIAndSkipsLocally() {
        let path = "backend/supabase/functions/_shared/moved-away.json"
        XCTAssertThrowsError(try RepositoryFile.url(path, environment: ["CI": "true"])) { error in
            XCTAssertTrue(error is RepositoryFile.Missing, "\(error)")
        }
        XCTAssertThrowsError(try RepositoryFile.url(path, environment: [:])) { error in
            XCTAssertTrue(error is XCTSkip, "\(error)")
        }
    }
}
