import XCTest
@testable import SideLingoCore

final class DictionaryPresentationTests: XCTestCase {
    func testMapsAllAvailableECDICTFieldsWithoutTruncation() {
        let lookup = DictionaryLookup(
            query: "relocated",
            lemma: "relocate",
            entry: DictionaryEntry(
                word: "relocate",
                phonetic: "ˌriːləʊˈkeɪt",
                definition: "move to a new place\nmove a service",
                translation: "v. 重新安置；搬迁\n迁移服务",
                pos: "v:100",
                collins: 2,
                oxford: true,
                tags: ["ielts", "cet6"],
                bncRank: 7342,
                frequencyRank: 5981,
                exchange: "d:relocated/p:relocated/i:relocating",
                detail: "{\"example\":\"We relocated the service.\"}",
                audio: "https://example.invalid/relocate.mp3"
            )
        )

        let presentation = DictionaryPresentation(lookup: lookup)

        XCTAssertEqual(presentation.heading, "relocated → relocate")
        XCTAssertEqual(presentation.phonetic, "/ˌriːləʊˈkeɪt/")
        XCTAssertEqual(presentation.partOfSpeech, "v:100")
        XCTAssertEqual(presentation.badges, [
            "Collins 2★", "Oxford 3000", "BNC #7342", "Contemporary #5981", "IELTS", "CET6",
        ])
        XCTAssertEqual(presentation.sections.map(\.title), [
            "中文释义", "English definition", "词形变化", "Detail", "Audio source",
        ])
        XCTAssertEqual(presentation.sections[0].value, "v. 重新安置；搬迁\n迁移服务")
        XCTAssertEqual(presentation.sections[1].value, "move to a new place\nmove a service")
        XCTAssertEqual(presentation.copyText, "relocate\nv. 重新安置；搬迁\n迁移服务")
        XCTAssertEqual(presentation.speechText, "relocate")
    }

    func testOmitsEmptyOptionalFields() {
        let lookup = DictionaryLookup(
            query: "word",
            lemma: "word",
            entry: DictionaryEntry(
                word: "word",
                phonetic: "",
                definition: "",
                translation: "词",
                pos: "",
                collins: nil,
                oxford: false,
                tags: [],
                bncRank: nil,
                frequencyRank: nil,
                exchange: "",
                detail: "",
                audio: ""
            )
        )

        let presentation = DictionaryPresentation(lookup: lookup)

        XCTAssertEqual(presentation.heading, "word")
        XCTAssertNil(presentation.phonetic)
        XCTAssertNil(presentation.partOfSpeech)
        XCTAssertTrue(presentation.badges.isEmpty)
        XCTAssertEqual(presentation.sections, [.init(title: "中文释义", value: "词")])
    }
}
