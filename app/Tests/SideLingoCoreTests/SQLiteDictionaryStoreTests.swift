import CSQLite
import Foundation
import XCTest
@testable import SideLingoCore

final class SQLiteDictionaryStoreTests: XCTestCase {
    func testPinnedRealDatabaseSupportsExactLemmaAndPhraseLookupWhenConfigured() throws {
        guard let path = ProcessInfo.processInfo.environment["SIDELINGO_ECDICT_PATH"] else {
            throw XCTSkip("Set SIDELINGO_ECDICT_PATH for the generated-data integration test")
        }
        let store = try SQLiteDictionaryStore(path: path)

        XCTAssertEqual(try store.lookup("relocate")?.entry.word, "relocate")
        XCTAssertEqual(try store.lookup("relocated")?.lemma, "relocate")
        XCTAssertEqual(try store.lookup("as-soon-as-possible")?.entry.word, "as soon as possible")
        XCTAssertFalse(try XCTUnwrap(store.lookup("relocate")?.entry.translation).isEmpty)
    }

    func testExactLookupIsCaseInsensitiveAndPreservesAllFields() throws {
        let fixture = try DictionaryDatabaseFixture(entries: [
            .init(
                word: "relocate",
                phonetic: "ˌriːləʊˈkeɪt",
                definition: "move to a new place",
                translation: "v. 重新安置；搬迁",
                pos: "v:100",
                collins: 2,
                oxford: true,
                tag: "cet6 ielts",
                bnc: 7342,
                frq: 5981,
                exchange: "d:relocated/p:relocated/3:relocates/i:relocating",
                detail: "{\"example\":\"We relocated the service.\"}",
                audio: ""
            )
        ])
        defer { fixture.remove() }

        let store = try SQLiteDictionaryStore(path: fixture.path)
        let result = try store.lookup("  RELOCATE  ")

        XCTAssertEqual(result?.query, "RELOCATE")
        XCTAssertEqual(result?.lemma, "relocate")
        XCTAssertEqual(result?.entry.word, "relocate")
        XCTAssertEqual(result?.entry.phonetic, "ˌriːləʊˈkeɪt")
        XCTAssertEqual(result?.entry.definition, "move to a new place")
        XCTAssertEqual(result?.entry.translation, "v. 重新安置；搬迁")
        XCTAssertEqual(result?.entry.pos, "v:100")
        XCTAssertEqual(result?.entry.collins, 2)
        XCTAssertEqual(result?.entry.oxford, true)
        XCTAssertEqual(result?.entry.tags, ["cet6", "ielts"])
        XCTAssertEqual(result?.entry.bncRank, 7342)
        XCTAssertEqual(result?.entry.frequencyRank, 5981)
        XCTAssertEqual(result?.entry.exchange, "d:relocated/p:relocated/3:relocates/i:relocating")
        XCTAssertEqual(result?.entry.detail, "{\"example\":\"We relocated the service.\"}")
        XCTAssertEqual(result?.entry.audio, "")
    }

    func testExactInflectionEntryResolvesItsExchangeLemma() throws {
        let fixture = try DictionaryDatabaseFixture(
            entries: [
                .init(
                    word: "relocate",
                    phonetic: "",
                    definition: "move",
                    translation: "搬迁",
                    pos: "v:100",
                    collins: 2,
                    oxford: false,
                    tag: "",
                    bnc: 0,
                    frq: 0,
                    exchange: "d:relocated/p:relocated",
                    detail: "",
                    audio: ""
                ),
                .init(
                    word: "relocated",
                    phonetic: "",
                    definition: "past tense of relocate",
                    translation: "relocate 的过去式",
                    pos: "",
                    collins: 0,
                    oxford: false,
                    tag: "",
                    bnc: 0,
                    frq: 0,
                    exchange: "0:relocate/1:dp/d:relocated",
                    detail: "",
                    audio: ""
                ),
            ],
            lemmas: ["relocated": "relocate"]
        )
        defer { fixture.remove() }

        let store = try SQLiteDictionaryStore(path: fixture.path)
        let result = try store.lookup("relocated")

        XCTAssertEqual(result?.query, "relocated")
        XCTAssertEqual(result?.lemma, "relocate")
        XCTAssertEqual(result?.entry.word, "relocate")
        XCTAssertEqual(result?.entry.translation, "搬迁")
    }

    func testMalformedExchangeLemmaFallsBackToLemmaTable() throws {
        let fixture = try DictionaryDatabaseFixture(
            entries: [
                .init(
                    word: "anchor",
                    phonetic: "",
                    definition: "a heavy object used to moor a vessel",
                    translation: "锚",
                    pos: "n:100",
                    collins: 2,
                    oxford: true,
                    tag: "cet4",
                    bnc: 0,
                    frq: 0,
                    exchange: "s:anchors",
                    detail: "",
                    audio: ""
                ),
                .init(
                    word: "anchored",
                    phonetic: "",
                    definition: "past tense",
                    translation: "已固定",
                    pos: "",
                    collins: 0,
                    oxford: false,
                    tag: "",
                    bnc: 0,
                    frq: 0,
                    exchange: "0:anchore/1:dp",
                    detail: "",
                    audio: ""
                ),
            ],
            lemmas: ["anchored": "anchor"]
        )
        defer { fixture.remove() }

        let result = try SQLiteDictionaryStore(path: fixture.path).lookup("anchored")

        XCTAssertEqual(result?.lemma, "anchor")
        XCTAssertEqual(result?.entry.word, "anchor")
    }

    func testAmbiguousNormalizedKeyFailsClosed() throws {
        let fixture = try DictionaryDatabaseFixture(entries: [
            .init(
                word: "resign",
                phonetic: "",
                definition: "quit a job",
                translation: "辞职",
                pos: "v:100",
                collins: 3,
                oxford: false,
                tag: "cet6",
                bnc: 0,
                frq: 100,
                exchange: "",
                detail: "",
                audio: ""
            ),
            .init(
                word: "re-sign",
                phonetic: "",
                definition: "sign again",
                translation: "重新签署",
                pos: "v:100",
                collins: 0,
                oxford: false,
                tag: "",
                bnc: 0,
                frq: 200,
                exchange: "",
                detail: "",
                audio: ""
            ),
        ])
        defer { fixture.remove() }

        XCTAssertNil(try SQLiteDictionaryStore(path: fixture.path).lookup("re.sign"))
    }

    func testNormalizedPhraseLookupHandlesPunctuationVariants() throws {
        let fixture = try DictionaryDatabaseFixture(entries: [
            .init(
                word: "keep me posted",
                phonetic: "",
                definition: "keep someone informed",
                translation: "随时告诉我最新进展",
                pos: "",
                collins: 0,
                oxford: false,
                tag: "",
                bnc: 0,
                frq: 0,
                exchange: "",
                detail: "",
                audio: ""
            )
        ])
        defer { fixture.remove() }

        let store = try SQLiteDictionaryStore(path: fixture.path)
        let result = try store.lookup("keep-me-posted")

        XCTAssertEqual(result?.query, "keep-me-posted")
        XCTAssertEqual(result?.lemma, "keep me posted")
        XCTAssertEqual(result?.entry.translation, "随时告诉我最新进展")
    }

    func testLemmaLookupReturnsBaseEntryAndPreservesQueryForm() throws {
        let fixture = try DictionaryDatabaseFixture(
            entries: [
                .init(
                    word: "relocate",
                    phonetic: "",
                    definition: "move to a new place",
                    translation: "搬迁",
                    pos: "v:100",
                    collins: 2,
                    oxford: false,
                    tag: "ielts",
                    bnc: 0,
                    frq: 0,
                    exchange: "",
                    detail: "",
                    audio: ""
                )
            ],
            lemmas: ["relocated": "relocate"]
        )
        defer { fixture.remove() }

        let store = try SQLiteDictionaryStore(path: fixture.path)
        let result = try store.lookup("relocated")

        XCTAssertEqual(result?.query, "relocated")
        XCTAssertEqual(result?.lemma, "relocate")
        XCTAssertEqual(result?.entry.word, "relocate")
    }
}

private struct FixtureEntry {
    let word: String
    let phonetic: String
    let definition: String
    let translation: String
    let pos: String
    let collins: Int
    let oxford: Bool
    let tag: String
    let bnc: Int
    let frq: Int
    let exchange: String
    let detail: String
    let audio: String
}

private final class DictionaryDatabaseFixture {
    let directory: URL
    let path: String

    init(entries: [FixtureEntry], lemmas: [String: String] = [:]) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidelingo-dictionary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("ecdict.sqlite").path

        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            throw SQLiteStoreError("fixture open failed")
        }
        defer { sqlite3_close(database) }
        let schema = """
        CREATE TABLE entries (
            word TEXT NOT NULL COLLATE NOCASE PRIMARY KEY,
            phonetic TEXT NOT NULL DEFAULT '',
            definition TEXT NOT NULL DEFAULT '',
            translation TEXT NOT NULL DEFAULT '',
            pos TEXT NOT NULL DEFAULT '',
            collins INTEGER NOT NULL DEFAULT 0,
            oxford INTEGER NOT NULL DEFAULT 0,
            tag TEXT NOT NULL DEFAULT '',
            bnc INTEGER NOT NULL DEFAULT 0,
            frq INTEGER NOT NULL DEFAULT 0,
            exchange TEXT NOT NULL DEFAULT '',
            detail TEXT NOT NULL DEFAULT '',
            audio TEXT NOT NULL DEFAULT '',
            normalized TEXT NOT NULL
        );
        CREATE TABLE lemmas (
            form TEXT NOT NULL COLLATE NOCASE PRIMARY KEY,
            lemma TEXT NOT NULL
        );
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError("fixture schema failed")
        }
        for entry in entries {
            let sql = """
            INSERT INTO entries VALUES (
                '\(entry.word)', '\(entry.phonetic)', '\(entry.definition)',
                '\(entry.translation)', '\(entry.pos)', \(entry.collins),
                \(entry.oxford ? 1 : 0), '\(entry.tag)', \(entry.bnc), \(entry.frq),
                '\(entry.exchange)', '\(entry.detail.replacingOccurrences(of: "'", with: "''"))',
                '\(entry.audio)', '\(entry.word.lowercased().filter { $0.isLetter || $0.isNumber })'
            );
            """
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteStoreError("fixture insert failed")
            }
        }
        for (form, lemma) in lemmas {
            let sql = "INSERT INTO lemmas VALUES ('\(form)', '\(lemma)');"
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteStoreError("fixture lemma insert failed")
            }
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
