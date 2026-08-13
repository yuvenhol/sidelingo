import Foundation
import SwiftOpenAI
import XCTest
@testable import SideLingoCore

final class CancellationSafeHTTPClientTests: XCTestCase {
    func testCancellingStreamConsumerCancelsUnderlyingTransport() async throws {
        let cancellation = CancellationRecorder()
        let client = CancellationSafeHTTPClient(
            base: HangingHTTPClient(),
            cancelTransport: { cancellation.record() }
        )
        let request = HTTPRequest(
            url: URL(string: "https://api.deepseek.com/chat/completions")!,
            method: .post,
            headers: [:]
        )
        let (byteStream, _) = try await client.bytes(for: request)

        let consumer = Task {
            guard case let .lines(lines) = byteStream else { return }
            for try await _ in lines {}
        }
        for _ in 0..<10 { await Task.yield() }
        consumer.cancel()
        _ = await consumer.result

        for _ in 0..<20 where !cancellation.wasRecorded {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(cancellation.wasRecorded)
    }
}

private final class HangingHTTPClient: HTTPClient {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    func data(for request: HTTPRequest) async throws -> (Data, HTTPResponse) {
        (Data(), HTTPResponse(statusCode: 200, headers: [:]))
    }

    func bytes(for request: HTTPRequest) async throws -> (HTTPByteStream, HTTPResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            self.continuation = continuation
        }
        return (.lines(stream), HTTPResponse(statusCode: 200, headers: [:]))
    }
}

private final class CancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = false

    var wasRecorded: Bool {
        lock.withLock { recorded }
    }

    func record() {
        lock.withLock { recorded = true }
    }
}
