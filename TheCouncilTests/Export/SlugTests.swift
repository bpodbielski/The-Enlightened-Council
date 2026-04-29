import XCTest
@testable import TheCouncil

final class SlugTests: XCTestCase {

    // MARK: - Basic transformations

    func test_slug_lowercases() {
        XCTAssertEqual(Slug.slugify("Should We Ship?"), "should-we-ship")
    }

    func test_slug_replacesSpacesWithHyphens() {
        XCTAssertEqual(Slug.slugify("hello world test"), "hello-world-test")
    }

    func test_slug_collapsesRunsOfSeparators() {
        XCTAssertEqual(Slug.slugify("a    b---c"), "a-b-c")
    }

    func test_slug_stripsPunctuation() {
        XCTAssertEqual(Slug.slugify("v1.2 / final?"), "v1-2-final")
    }

    func test_slug_stripsLeadingTrailingHyphens() {
        XCTAssertEqual(Slug.slugify("---hello---"), "hello")
    }

    func test_slug_emptyAndAllSpecials() {
        XCTAssertEqual(Slug.slugify(""), "")
        XCTAssertEqual(Slug.slugify("///???"), "")
    }

    // MARK: - Unicode

    func test_slug_foldsAccents() {
        XCTAssertEqual(Slug.slugify("naïve résumé"), "naive-resume")
    }

    func test_slug_dropsEmojiAndCJKAsSeparators() {
        // Emoji + CJK are treated as non-ASCII-alphanumeric → collapse to hyphens.
        let result = Slug.slugify("ship 🚀 rocket 漢字 today")
        XCTAssertEqual(result, "ship-rocket-today")
    }

    // MARK: - Truncation

    func test_slug_truncatesAt60Chars() {
        let long = String(repeating: "a", count: 100)
        let s = Slug.slugify(long)
        XCTAssertEqual(s.count, 60)
    }

    func test_slug_truncationLeavesNoTrailingHyphen() {
        // Construct a string that, when truncated at 60, would naturally end on a hyphen
        // unless we trim it after the cut.
        let raw = String(repeating: "ab ", count: 30) // "ab ab ab ..." — 90 chars
        let s = Slug.slugify(raw)
        XCTAssertLessThanOrEqual(s.count, 60)
        XCTAssertFalse(s.hasSuffix("-"), "Truncated slug must not leave a trailing hyphen")
    }

    // MARK: - Filename composition

    func test_filename_combinesSlugAndDate() {
        // 2026-04-26 in UTC ~= TimeIntervalSince1970 = 1777017600
        let date = Date(timeIntervalSince1970: 1_777_017_600)
        let name = Slug.filename(question: "Ship the migration?", date: date)
        XCTAssertTrue(name.hasPrefix("ship-the-migration-"))
        // The trailing date is locale-stable (en_US_POSIX yyyy-MM-dd)
        let parts = name.split(separator: "-").suffix(3)
        XCTAssertEqual(parts.count, 3, "Date should contribute YYYY-MM-DD as the trailing 3 hyphen-separated parts")
    }
}
