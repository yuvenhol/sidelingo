import Foundation
import SwiftOpenAI

public final class CancellationSafeHTTPClient: HTTPClient, @unchecked Sendable {
    private let base: any HTTPClient
    private let cancelTransport: @Sendable () -> Void

    public init(
        base: any HTTPClient,
        cancelTransport: @escaping @Sendable () -> Void
    ) {
        self.base = base
        self.cancelTransport = cancelTransport
    }

    public func data(for request: HTTPRequest) async throws -> (Data, HTTPResponse) {
        try await base.data(for: request)
    }

    public func bytes(for request: HTTPRequest) async throws -> (HTTPByteStream, HTTPResponse) {
        let (stream, response) = try await base.bytes(for: request)
        switch stream {
        case let .bytes(bytes):
            return (.bytes(wrap(bytes)), response)
        case let .lines(lines):
            return (.lines(wrap(lines)), response)
        }
    }

    private func wrap<Element: Sendable>(
        _ source: AsyncThrowingStream<Element, Error>
    ) -> AsyncThrowingStream<Element, Error> {
        let cancelTransport = cancelTransport
        return AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    for try await element in source {
                        try Task.checkCancellation()
                        continuation.yield(element)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                relay.cancel()
                cancelTransport()
            }
        }
    }
}
