import Foundation
import SwiftOpenAI
import XCTest
@testable import EnglishCompanionCore

final class DeepSeekProviderProcessorTests: XCTestCase {
    func testStreamsSDKChunkDeltaContentUsingCustomModelAndJSONLPrompt() async throws {
        let chunks = try [
            makeChunk(content: #"{"field":"pri"#),
            makeChunk(content: "mary\",\"value\":\"Natural English\"}\n"),
            makeChunk(content: "{\"field\":\"secondaryTitle\",\"value\":\"MEANING CHECK\"}\n"),
            makeChunk(content: nil),
            makeChunk(content: #"{"field":"secondary","value":"自然英文"}"#),
        ]
        let service = FakeChatCompletionStreamingService(chunks: chunks)
        let processor = DeepSeekProviderProcessor(model: "deepseek-chat", streamingService: service)

        let stream = try await processor.stream(mode: .translate, text: "帮我确认一下。")
        let updates = try await collect(stream)

        XCTAssertEqual(
            updates,
            [
                CompanionOutputPartial(primary: "Natural English"),
                CompanionOutputPartial(
                    primary: "Natural English",
                    secondaryTitle: "MEANING CHECK"
                ),
                CompanionOutputPartial(
                    primary: "Natural English",
                    secondaryTitle: "MEANING CHECK",
                    secondary: "自然英文"
                ),
            ]
        )
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
        let primaryRecord = #"{"field":"primary","value":"..."}"#
        let titleRecord = #"{"field":"secondaryTitle","value":"..."}"#
        let secondaryRecord = #"{"field":"secondary","value":"..."}"#
        XCTAssertTrue(systemPrompt.contains("JSONL"))
        XCTAssertTrue(systemPrompt.contains(primaryRecord))
        XCTAssertTrue(systemPrompt.contains(titleRecord))
        XCTAssertTrue(systemPrompt.contains(secondaryRecord))
        XCTAssertLessThan(
            try XCTUnwrap(systemPrompt.range(of: primaryRecord)?.lowerBound),
            try XCTUnwrap(systemPrompt.range(of: titleRecord)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(systemPrompt.range(of: titleRecord)?.lowerBound),
            try XCTUnwrap(systemPrompt.range(of: secondaryRecord)?.lowerBound)
        )
        XCTAssertTrue(systemPrompt.lowercased().contains("no markdown"))
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

    func testInvalidCompletedJSONLIsAnInvalidProviderResponse() async throws {
        let service = FakeChatCompletionStreamingService(
            chunks: [try makeChunk(content: #"{"field":"primary","value":"only"}"#)]
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
            makeChunk(content: "{\"field\":\"primary\",\"value\":\"Improved\"}\n"),
            makeChunk(content: "{\"field\":\"secondaryTitle\",\"value\":\"CHANGES\"}\n"),
            makeChunk(content: "{\"field\":\"secondary\",\"value\":\"Explanation\"}\n"),
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
