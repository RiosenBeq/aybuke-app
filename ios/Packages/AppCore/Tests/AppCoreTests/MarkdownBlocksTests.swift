import XCTest
@testable import AppCore

final class MarkdownBlocksTests: XCTestCase {
    func testParsesTheLegalSubset() {
        let markdown = """
        # Privacy Policy

        Last updated: 12 October 2026

        > **In short:** we never sell your data.
        > - Photos are deleted within an hour.

        ## 1. What we collect
        We collect very little
        and keep it short.

        - **Photos** you choose
        * Prompts you type
        1. Open Settings
        2) Tap Delete

        ---
        ### 1.1 Details
        """
        XCTAssertEqual(MarkdownBlock.parse(markdown), [
            .heading(level: 1, text: "Privacy Policy"),
            .paragraph("Last updated: 12 October 2026"),
            .quote([.paragraph("**In short:** we never sell your data."), .bullet("Photos are deleted within an hour.")]),
            .heading(level: 2, text: "1. What we collect"),
            .paragraph("We collect very little and keep it short."),
            .bullet("**Photos** you choose"),
            .bullet("Prompts you type"),
            .numbered(marker: "1.", text: "Open Settings"),
            .numbered(marker: "2.", text: "Tap Delete"),
            .rule,
            .heading(level: 3, text: "1.1 Details"),
        ])
    }

    func testHashWithoutSpaceIsText() {
        XCTAssertEqual(MarkdownBlock.parse("#hashtag and 2026. was a year"), [.paragraph("#hashtag and 2026. was a year")])
    }
}
