import Foundation
import XCTest
@testable import EnglishCompanionCore

@MainActor
final class QuickPanelProcessingSessionTests: XCTestCase {
    func testTransitionsLoadingToSuccessAndRecordsHistory() async throws {
        let history = HistoryRecorderSpy()
        let output = CompanionOutput(primary: "success", secondaryTitle: "title", secondary: "detail")
        let session = QuickPanelProcessingSession(
            processor: DelayedProcessor(result: .success(output), delayNanoseconds: 1_000_000),
            historyRecorder: history
        )

        XCTAssertTrue(session.isInputEditable)
        session.submit(mode: .translate, text: "source")
        XCTAssertEqual(session.state, .loading)
        XCTAssertFalse(session.isInputEditable)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(session.state, .success(output))
        XCTAssertTrue(session.isInputEditable)
        XCTAssertEqual(history.records.map(\.result), ["success"])
        XCTAssertEqual(history.records.map(\.source), ["source"])
    }

    func testFailureRecordsNoHistoryAndPreservesInputAtCaller() async throws {
        let history = HistoryRecorderSpy()
        let session = QuickPanelProcessingSession(
            processor: DelayedProcessor(result: .failure(TestFailure()), delayNanoseconds: 1_000_000),
            historyRecorder: history
        )
        let input = "keep this input"

        session.submit(mode: .improve, text: input)
        try await Task.sleep(nanoseconds: 20_000_000)

        guard case let .error(message) = session.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(input, "keep this input")
        XCTAssertTrue(history.records.isEmpty)
    }

    func testCancelReturnsToIdleAndIgnoresAProcessorThatFinishesLater() async throws {
        let history = HistoryRecorderSpy()
        let output = CompanionOutput(primary: "stale", secondaryTitle: "title", secondary: "detail")
        let session = QuickPanelProcessingSession(
            processor: DelayedProcessor(
                result: .success(output),
                delayNanoseconds: 15_000_000,
                ignoresCancellation: true
            ),
            historyRecorder: history
        )

        session.submit(mode: .translate, text: "source")
        session.cancel()
        XCTAssertEqual(session.state, .idle)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(history.records.isEmpty)
    }

    func testNewerRequestWinsAndOnlyItsSuccessIsRecorded() async throws {
        let history = HistoryRecorderSpy()
        let processor = TextDependentProcessor()
        let session = QuickPanelProcessingSession(processor: processor, historyRecorder: history)

        session.submit(mode: .translate, text: "older")
        session.submit(mode: .translate, text: "newer")
        try await Task.sleep(nanoseconds: 80_000_000)

        let expected = CompanionOutput(primary: "newer", secondaryTitle: "title", secondary: "detail")
        XCTAssertEqual(session.state, .success(expected))
        XCTAssertEqual(history.records.map(\.source), ["newer"])
    }
}

private struct TestFailure: Error {}

private struct DelayedProcessor: ProviderProcessing {
    let result: Result<CompanionOutput, Error>
    let delayNanoseconds: UInt64
    var ignoresCancellation = false

    func process(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        if ignoresCancellation {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        } else {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

private struct TextDependentProcessor: ProviderProcessing {
    func process(mode: CompanionMode, text: String) async throws -> CompanionOutput {
        if text == "older" {
            try? await Task.sleep(nanoseconds: 50_000_000)
        } else {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return CompanionOutput(primary: text, secondaryTitle: "title", secondary: "detail")
    }
}

private final class HistoryRecorderSpy: @unchecked Sendable, HistoryRecording {
    private(set) var records: [HistoryRecord] = []
    func append(_ record: HistoryRecord) throws { records.append(record) }
}
