import Foundation
import XCTest
@testable import SideLingoCore

@MainActor
final class QuickPanelProcessingSessionTests: XCTestCase {
    func testTranslateDictionaryHitSkipsProviderAndRecordsLocalResult() async {
        let history = HistoryRecorderSpy()
        let provider = ControlledStreamingProcessor()
        let lookup = DictionaryLookup(
            query: "relocated",
            lemma: "relocate",
            entry: DictionaryEntry(
                word: "relocate",
                phonetic: "ˌriːləʊˈkeɪt",
                definition: "move to a new place",
                translation: "搬迁；重新安置",
                pos: "v:100",
                collins: 2,
                oxford: false,
                tags: ["ielts"],
                bncRank: 7342,
                frequencyRank: 5981,
                exchange: "d:relocated",
                detail: "",
                audio: ""
            )
        )
        let dictionary = DictionaryLookupStub(result: lookup)
        let session = QuickPanelProcessingSession(
            processor: provider,
            dictionary: dictionary,
            historyRecorder: history
        )

        session.submit(mode: .translate, text: "relocated")
        await waitUntil { session.state == .dictionary(lookup) }

        let startedTexts = await provider.startedTexts()
        XCTAssertEqual(startedTexts, [])
        XCTAssertTrue(session.isInputEditable)
        XCTAssertTrue(session.isCopyEnabled)
        XCTAssertEqual(history.records.map(\.source), ["relocated"])
        XCTAssertEqual(history.records.map(\.result), ["搬迁；重新安置"])
        XCTAssertEqual(history.records.map(\.kind), [.dictionary])
        XCTAssertEqual(history.records.map(\.dictionaryLemma), ["relocate"])
    }

    func testStaleDictionaryLookupCannotOverwriteNewerProviderResultOrHistory() async {
        let history = HistoryRecorderSpy()
        let provider = ControlledStreamingProcessor()
        let staleLookup = DictionaryLookup(
            query: "older",
            lemma: "old",
            entry: DictionaryEntry(
                word: "old",
                phonetic: "",
                definition: "",
                translation: "旧",
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
        let dictionary = BlockingDictionaryLookup(result: staleLookup)
        let session = QuickPanelProcessingSession(
            processor: provider,
            dictionary: dictionary,
            historyRecorder: history
        )

        session.submit(mode: .translate, text: "older")
        await dictionary.waitUntilStarted()
        session.submit(mode: .improve, text: "newer")
        await provider.waitUntilStarted(text: "newer")
        let newest = CompanionOutputPartial(
            primary: "newer result",
            secondaryTitle: "CHANGES",
            secondary: "detail"
        )
        await provider.yield(newest, text: "newer")
        await provider.finish(text: "newer")
        let expected = CompanionOutput(
            primary: "newer result",
            secondaryTitle: "CHANGES",
            secondary: "detail"
        )
        await waitUntil { session.state == .success(expected) }

        dictionary.release()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(session.state, .success(expected))
        XCTAssertEqual(history.records.map(\.source), ["newer"])
    }

    func testDictionaryEntryWithoutChineseTranslationFallsBackToProvider() async {
        let provider = ControlledStreamingProcessor()
        let lookup = DictionaryLookup(
            query: "english-only",
            lemma: "english-only",
            entry: DictionaryEntry(
                word: "english-only",
                phonetic: "",
                definition: "an English definition",
                translation: "   ",
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
        let session = QuickPanelProcessingSession(
            processor: provider,
            dictionary: DictionaryLookupStub(result: lookup)
        )

        session.submit(mode: .translate, text: "english-only")
        for _ in 0..<100 { await Task.yield() }

        let startedTexts = await provider.startedTexts()
        XCTAssertEqual(startedTexts, ["english-only"])
        session.cancel()
    }

    func testTranslateDictionaryMissFallsBackToProviderStream() async {
        let provider = ControlledStreamingProcessor()
        let dictionary = DictionaryLookupStub(result: nil)
        let session = QuickPanelProcessingSession(processor: provider, dictionary: dictionary)

        session.submit(mode: .translate, text: "not in dictionary")
        await provider.waitUntilStarted(text: "not in dictionary")
        let complete = CompanionOutputPartial(
            primary: "普通翻译",
            secondaryTitle: "SUGGESTED REPLY",
            secondary: "Thanks."
        )
        await provider.yield(complete, text: "not in dictionary")
        await provider.finish(text: "not in dictionary")

        let expected = CompanionOutput(
            primary: "普通翻译",
            secondaryTitle: "SUGGESTED REPLY",
            secondary: "Thanks."
        )
        await waitUntil { session.state == .success(expected) }
    }

    func testImproveBypassesDictionaryEvenWhenEntryExists() async {
        let provider = ControlledStreamingProcessor()
        let lookup = DictionaryLookup(
            query: "relocate",
            lemma: "relocate",
            entry: DictionaryEntry(
                word: "relocate",
                phonetic: "",
                definition: "move",
                translation: "搬迁",
                pos: "v:100",
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
        let session = QuickPanelProcessingSession(
            processor: provider,
            dictionary: DictionaryLookupStub(result: lookup)
        )

        session.submit(mode: .improve, text: "relocate")
        await provider.waitUntilStarted(text: "relocate")

        XCTAssertEqual(session.state, .streaming(CompanionOutputPartial()))
        session.cancel()
    }

    func testPublishesPartialFieldsAndCommitsOnlyAfterSuccessfulCompletion() async {
        let history = HistoryRecorderSpy()
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor, historyRecorder: history)

        XCTAssertTrue(session.isInputEditable)
        XCTAssertFalse(session.isCopyEnabled)
        session.submit(mode: .translate, text: "source")

        XCTAssertEqual(session.state, .streaming(CompanionOutputPartial()))
        XCTAssertFalse(session.isInputEditable)
        XCTAssertFalse(session.isCopyEnabled)
        await processor.waitUntilStarted(text: "source")

        let primaryStart = CompanionOutputPartial(primary: "Ready")
        await processor.yield(primaryStart, text: "source")
        await waitUntil { session.state == .streaming(primaryStart) }
        let primary = CompanionOutputPartial(primary: "Ready immediately")
        await processor.yield(primary, text: "source")
        await waitUntil { session.state == .streaming(primary) }
        XCTAssertFalse(session.isInputEditable)
        XCTAssertFalse(session.isCopyEnabled)
        XCTAssertTrue(history.records.isEmpty)

        let titleStart = CompanionOutputPartial(
            primary: "Ready immediately",
            secondaryTitle: "MEANING"
        )
        await processor.yield(titleStart, text: "source")
        await waitUntil { session.state == .streaming(titleStart) }
        let title = CompanionOutputPartial(
            primary: "Ready immediately",
            secondaryTitle: "MEANING CHECK"
        )
        await processor.yield(title, text: "source")
        await waitUntil { session.state == .streaming(title) }

        let secondaryStart = CompanionOutputPartial(
            primary: "Ready immediately",
            secondaryTitle: "MEANING CHECK",
            secondary: "忠实"
        )
        await processor.yield(secondaryStart, text: "source")
        await waitUntil { session.state == .streaming(secondaryStart) }
        let complete = CompanionOutputPartial(
            primary: "Ready immediately",
            secondaryTitle: "MEANING CHECK",
            secondary: "忠实回译"
        )
        await processor.yield(complete, text: "source")
        await waitUntil { session.state == .streaming(complete) }
        XCTAssertFalse(session.isCopyEnabled)
        XCTAssertTrue(history.records.isEmpty)

        await processor.finish(text: "source")
        let expected = CompanionOutput(
            primary: "Ready immediately",
            secondaryTitle: "MEANING CHECK",
            secondary: "忠实回译"
        )
        await waitUntil { session.state == .success(expected) }

        XCTAssertTrue(session.isInputEditable)
        XCTAssertTrue(session.isCopyEnabled)
        XCTAssertEqual(history.records.map(\.result), ["Ready immediately"])
        XCTAssertEqual(history.records.map(\.source), ["source"])
    }

    func testProtocolMarkerBearingPartialNeverReachesUIState() async {
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor)
        let rawMarker = CompanionFramedProtocol.primaryMarker

        session.submit(mode: .translate, text: "unsafe framing")
        await processor.waitUntilStarted(text: "unsafe framing")
        await processor.yield(
            CompanionOutputPartial(primary: "visible \(rawMarker) raw"),
            text: "unsafe framing"
        )
        await waitUntil {
            if case .error = session.state { return true }
            return false
        }

        XCTAssertFalse(String(describing: session.state).contains(rawMarker))
        XCTAssertEqual(session.state, .error("DeepSeek returned an invalid response."))
        XCTAssertFalse(session.isCopyEnabled)
    }

    func testFailureAfterAPartialResultRecordsNoHistory() async {
        let history = HistoryRecorderSpy()
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor, historyRecorder: history)

        session.submit(mode: .improve, text: "keep this input")
        await processor.waitUntilStarted(text: "keep this input")
        let primary = CompanionOutputPartial(primary: "temporary")
        await processor.yield(primary, text: "keep this input")
        await waitUntil { session.state == .streaming(primary) }
        await processor.fail(TestFailure(), text: "keep this input")
        await waitUntil {
            if case .error = session.state { return true }
            return false
        }

        guard case let .error(message) = session.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(session.isInputEditable)
        XCTAssertFalse(session.isCopyEnabled)
        XCTAssertTrue(history.records.isEmpty)
    }

    func testCancellationAfterAPartialResultReturnsToIdleAndRecordsNothing() async {
        let history = HistoryRecorderSpy()
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor, historyRecorder: history)

        session.submit(mode: .translate, text: "cancelled")
        await processor.waitUntilStarted(text: "cancelled")
        await processor.yield(CompanionOutputPartial(primary: "temporary"), text: "cancelled")
        await waitUntil {
            session.state == .streaming(CompanionOutputPartial(primary: "temporary"))
        }

        session.cancel()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.isInputEditable)
        XCTAssertFalse(session.isCopyEnabled)
        await processor.finish(text: "cancelled")
        await Task.yield()

        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(history.records.isEmpty)
    }

    func testNewerRequestWinsAndStaleStreamRecordsNothing() async {
        let history = HistoryRecorderSpy()
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor, historyRecorder: history)

        session.submit(mode: .translate, text: "older")
        await processor.waitUntilStarted(text: "older")
        await processor.yield(CompanionOutputPartial(primary: "old partial"), text: "older")
        await waitUntil {
            session.state == .streaming(CompanionOutputPartial(primary: "old partial"))
        }

        session.submit(mode: .translate, text: "newer")
        await processor.waitUntilStarted(text: "newer")
        let newest = CompanionOutputPartial(
            primary: "newer",
            secondaryTitle: "title",
            secondary: "detail"
        )
        await processor.yield(newest, text: "newer")
        await processor.finish(text: "newer")
        let expected = CompanionOutput(primary: "newer", secondaryTitle: "title", secondary: "detail")
        await waitUntil { session.state == .success(expected) }

        await processor.yield(
            CompanionOutputPartial(primary: "older", secondaryTitle: "title", secondary: "detail"),
            text: "older"
        )
        await processor.finish(text: "older")
        await Task.yield()

        XCTAssertEqual(session.state, .success(expected))
        XCTAssertEqual(history.records.map(\.source), ["newer"])
    }

    func testIncompleteSuccessfulStreamIsInvalidAndRecordsNoHistory() async {
        let history = HistoryRecorderSpy()
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor, historyRecorder: history)

        session.submit(mode: .translate, text: "incomplete")
        await processor.waitUntilStarted(text: "incomplete")
        await processor.yield(CompanionOutputPartial(primary: "only"), text: "incomplete")
        await processor.finish(text: "incomplete")
        await waitUntil {
            if case .error = session.state { return true }
            return false
        }

        XCTAssertTrue(history.records.isEmpty)
        XCTAssertFalse(session.isCopyEnabled)
    }

    func testFailureDoesNotExposeRawProviderJSONInUIState() async {
        let processor = ControlledStreamingProcessor()
        let session = QuickPanelProcessingSession(processor: processor)

        session.submit(mode: .translate, text: "raw error")
        await processor.waitUntilStarted(text: "raw error")
        await processor.fail(RawPayloadFailure(), text: "raw error")
        await waitUntil {
            if case .error = session.state { return true }
            return false
        }

        XCTAssertEqual(session.state, .error("Processing failed."))
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for processing state")
    }
}

private struct TestFailure: Error {}

private struct RawPayloadFailure: LocalizedError {
    var errorDescription: String? {
        #"{"error":{"message":"raw provider JSON"}}"#
    }
}

private actor ControlledStreamingProcessor: ProviderStreaming {
    typealias Continuation = AsyncThrowingStream<CompanionOutputPartial, Error>.Continuation

    private var continuations: [String: Continuation] = [:]

    func stream(
        mode: CompanionMode,
        text: String
    ) async throws -> AsyncThrowingStream<CompanionOutputPartial, Error> {
        var captured: Continuation?
        let stream = AsyncThrowingStream<CompanionOutputPartial, Error> { continuation in
            captured = continuation
        }
        continuations[text] = captured
        return stream
    }

    func startedTexts() -> [String] {
        continuations.keys.sorted()
    }

    func waitUntilStarted(text: String) async {
        while continuations[text] == nil {
            await Task.yield()
        }
    }

    func yield(_ partial: CompanionOutputPartial, text: String) async {
        await waitUntilStarted(text: text)
        continuations[text]?.yield(partial)
    }

    func finish(text: String) async {
        await waitUntilStarted(text: text)
        continuations[text]?.finish()
    }

    func fail(_ error: Error, text: String) async {
        await waitUntilStarted(text: text)
        continuations[text]?.finish(throwing: error)
    }
}

private final class BlockingDictionaryLookup: @unchecked Sendable, DictionaryLookupProviding {
    private let condition = NSCondition()
    private let result: DictionaryLookup?
    private var started = false
    private var released = false

    init(result: DictionaryLookup?) {
        self.result = result
    }

    func lookup(_ query: String) throws -> DictionaryLookup? {
        condition.lock()
        started = true
        condition.broadcast()
        while !released {
            condition.wait()
        }
        condition.unlock()
        return result
    }

    func waitUntilStarted() async {
        while true {
            let value = condition.withLock { started }
            if value { return }
            await Task.yield()
        }
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class DictionaryLookupStub: @unchecked Sendable, DictionaryLookupProviding {
    private let result: DictionaryLookup?

    init(result: DictionaryLookup?) {
        self.result = result
    }

    func lookup(_ query: String) throws -> DictionaryLookup? {
        result
    }
}

private final class HistoryRecorderSpy: @unchecked Sendable, HistoryRecording {
    private(set) var records: [HistoryRecord] = []
    func append(_ record: HistoryRecord) throws { records.append(record) }
}
