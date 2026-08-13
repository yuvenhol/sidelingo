import Foundation
import SwiftOpenAI
import XCTest
@testable import SideLingoCore

final class DeepSeekProviderProcessorTests: XCTestCase {
    private let primaryMarker = CompanionFramedProtocol.primaryMarker
    private let titleMarker = CompanionFramedProtocol.secondaryTitleMarker
    private let secondaryMarker = CompanionFramedProtocol.secondaryMarker
    private let endMarker = CompanionFramedProtocol.endMarker

    func testStreamsEverySafeSDKChunkForAllFieldsUsingCustomModelAndFramedPrompt() async throws {
        let chunks = try [
            makeChunk(content: "<<<SIDELINGO::PRI"),
            makeChunk(content: "MARY>>>\nNat"),
            makeChunk(content: "ural English"),
            makeChunk(content: "\n\(titleMarker)\nMEAN"),
            makeChunk(content: "ING CHECK\n\(secondaryMarker)\n自然"),
            makeChunk(content: nil),
            makeChunk(content: "英文\n\(endMarker)"),
        ]
        let service = FakeChatCompletionStreamingService(chunks: chunks)
        let processor = DeepSeekProviderProcessor(model: "deepseek-chat", streamingService: service)

        let stream = try await processor.stream(mode: .translate, text: "帮我确认一下。")
        let updates = try await collect(stream)

        XCTAssertEqual(
            updates,
            [
                CompanionOutputPartial(primary: "Nat"),
                CompanionOutputPartial(primary: "Natural English"),
                CompanionOutputPartial(
                    primary: "Natural English",
                    secondaryTitle: "MEAN"
                ),
                CompanionOutputPartial(
                    primary: "Natural English",
                    secondaryTitle: "MEANING CHECK"
                ),
                CompanionOutputPartial(
                    primary: "Natural English",
                    secondaryTitle: "MEANING CHECK",
                    secondary: "自然"
                ),
                CompanionOutputPartial(
                    primary: "Natural English",
                    secondaryTitle: "MEANING CHECK",
                    secondary: "自然英文"
                ),
            ]
        )
        XCTAssertFalse(updates.description.contains("<<<SIDELINGO::"))
        let streamCallCount = await service.streamCallCount()
        XCTAssertEqual(streamCallCount, 1)

        let submittedParameters = await service.submittedParameters()
        let parameters = try XCTUnwrap(submittedParameters)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any]
        )
        XCTAssertEqual(object["model"] as? String, "deepseek-chat")
        XCTAssertNil(object["response_format"])

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        let systemPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(systemPrompt.contains(primaryMarker))
        XCTAssertTrue(systemPrompt.contains(titleMarker))
        XCTAssertTrue(systemPrompt.contains(secondaryMarker))
        XCTAssertTrue(systemPrompt.contains(endMarker))
        XCTAssertLessThan(
            try XCTUnwrap(systemPrompt.range(of: primaryMarker)?.lowerBound),
            try XCTUnwrap(systemPrompt.range(of: titleMarker)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(systemPrompt.range(of: titleMarker)?.lowerBound),
            try XCTUnwrap(systemPrompt.range(of: secondaryMarker)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(systemPrompt.range(of: secondaryMarker)?.lowerBound),
            try XCTUnwrap(systemPrompt.range(of: endMarker)?.lowerBound)
        )
        XCTAssertTrue(systemPrompt.lowercased().contains("no markdown"))
        XCTAssertTrue(systemPrompt.lowercased().contains("strict order"))
        XCTAssertTrue(systemPrompt.lowercased().contains("markers on their own lines"))
        XCTAssertTrue(systemPrompt.lowercased().contains("must not contain marker text"))
        XCTAssertEqual(messages.last?["content"] as? String, "帮我确认一下。")
    }

    func testImproveStreamUsesTheSharedModeSpecificPrompt() async throws {
        let service = FakeChatCompletionStreamingService(chunks: try validChunks())
        let processor = DeepSeekProviderProcessor(model: "configured-model", streamingService: service)

        let stream = try await processor.stream(mode: .improve, text: "请 improve 这个 API message")
        _ = try await collect(stream)

        let submittedParameters = await service.submittedParameters()
        let parameters = try XCTUnwrap(submittedParameters)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(parameters), encoding: .utf8))
        XCTAssertTrue(encoded.lowercased().contains("improve"))
        XCTAssertTrue(encoded.contains("Chinese"))
        XCTAssertTrue(encoded.contains("mixed-language"))
        XCTAssertTrue(encoded.contains("technical identifiers"))
    }

    func testMissingFinalFramedFieldsIsAnInvalidProviderResponse() async throws {
        let service = FakeChatCompletionStreamingService(
            chunks: [try makeChunk(content: "\(primaryMarker)\nonly")]
        )
        let processor = DeepSeekProviderProcessor(model: "deepseek-chat", streamingService: service)

        do {
            let stream = try await processor.stream(mode: .translate, text: "Hello")
            _ = try await collect(stream)
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? ProviderProcessingError, .invalidResponse)
        }
    }

    private func collect(
        _ stream: AsyncThrowingStream<CompanionOutputPartial, Error>
    ) async throws -> [CompanionOutputPartial] {
        var updates: [CompanionOutputPartial] = []
        for try await update in stream {
            updates.append(update)
        }
        return updates
    }

    private func validChunks() throws -> [ChatCompletionChunkObject] {
        try [
            makeChunk(content: "\(primaryMarker)\nImproved"),
            makeChunk(content: "\n\(titleMarker)\nCHANGES"),
            makeChunk(content: "\n\(secondaryMarker)\nExplanation"),
            makeChunk(content: "\n\(endMarker)"),
        ]
    }

    private func makeChunk(content: String?) throws -> ChatCompletionChunkObject {
        var delta: [String: Any] = [:]
        if let content {
            delta["content"] = content
        }
        let object: [String: Any] = [
            "id": "chunk-id",
            "object": "chat.completion.chunk",
            "choices": [
                [
                    "index": 0,
                    "delta": delta,
                    "finish_reason": NSNull(),
                ]
            ],
        ]
        return try JSONDecoder().decode(
            ChatCompletionChunkObject.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

private actor FakeChatCompletionStreamingService: ChatCompletionStreaming {
    private let chunks: [ChatCompletionChunkObject]
    private var parameters: ChatCompletionParameters?
    private var calls = 0

    init(chunks: [ChatCompletionChunkObject]) {
        self.chunks = chunks
    }

    func streamedChat(
        parameters: ChatCompletionParameters
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        self.parameters = parameters
        calls += 1
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func submittedParameters() -> ChatCompletionParameters? { parameters }
    func streamCallCount() -> Int { calls }
}
