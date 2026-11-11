import XCTest
@testable import KodiererCore

final class OptionDescriptionsTests: XCTestCase {
    /// Parsing, header skipping, case-insensitive lookup and merging.
    func testParseAndLookup() throws {
        let descriptions = OptionDescriptions.parse(text: """
        # comment line
        NAME\tDESCRIPTION\tCATEGORY\tMODULE\tSECTION
        KOMFORTSCHLIESSUNG_FB\tClose mirrors + windows + moon roof via key fob.\tComfort\tCAS\t3003
        ER_KEYOUT_AUTOVR\tUnlock doors when engine is stopped.
        """)
        XCTAssertEqual(descriptions.entries.count, 2)

        let entry = try XCTUnwrap(descriptions.entry(named: "komfortschliessung_fb"))
        XCTAssertEqual(entry.category, "Comfort")
        XCTAssertEqual(entry.module, "CAS")
        XCTAssertEqual(entry.section, "3003")
        XCTAssertEqual(entry.description, "Close mirrors + windows + moon roof via key fob.")

        let bare = try XCTUnwrap(descriptions.entry(named: "ER_KEYOUT_AUTOVR"))
        XCTAssertNil(bare.category)

        // Unknown names find nothing; merging keeps the first entry per name.
        XCTAssertNil(descriptions.entry(named: "NOPE"))
        let other = OptionDescriptions.parse(text: "KOMFORTSCHLIESSUNG_FB\tOther text.\tX\nNEW_ONE\tNew.\t")
        let merged = descriptions.merged(with: other)
        XCTAssertEqual(merged.entry(named: "KOMFORTSCHLIESSUNG_FB")?.description,
                       "Close mirrors + windows + moon roof via key fob.")
        XCTAssertNotNil(merged.entry(named: "NEW_ONE"))
        XCTAssertEqual(merged.entries.count, 3)
    }
}
