import Foundation
import SwiftOpenAI
import XCTest
@testable import EnglishCompanionCore

final class DeepSeekProviderProcessorTests: XCTestCase {
    func testUsesSDKChatTypesCustomModelJSONModeAndProductPrompts() async throws {
        let service = FakeChatCompletionService(
            assistantContent: #"{"primary":"Natural English","secondaryTitle":"MEANING CHECK","secondary":"自然英文"}"#
        )
        let processor = DeepSeekProviderProcessor(model: "deepseek-chat", service: service)

        let output = try await processor.process(mode: .translate, text: "帮我确认一下。")

        XCTAssertEqual(output.primary, "Natural English")
        let submittedParameters = await service.submittedParameters()
        let parameters = try XCTUnwrap(submittedParameters)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any]
        )
        XCTAssertEqual(object["model"] as? String, "deepseek-chat")
        XCTAssertEqual(
            (object["response_format"] as? [String: Any])?["type"] as? String,
            "json_object"
        )

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        let systemPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(systemPrompt.contains("primary"))
        XCTAssertTrue(systemPrompt.contains("secondaryTitle"))
        XCTAssertTrue(systemPrompt.contains("secondary"))
        XCTAssertTrue(systemPrompt.contains("exactly"))
        XCTAssertEqual(messages.last?["content"] as? String, "帮我确认一下。")
    }

    func testTranslatePromptCoversEnglishToChineseAndSuggestedReply() async throws {
        let service = FakeChatCompletionService(
            assistantContent: #"{"primary":"中文翻译","secondaryTitle":"SUGGESTED REPLY","secondary":"Thanks, noted."}"#
        )
        let processor = DeepSeekProviderProcessor(model: "deepseek-chat", service: service)

        _ = try await processor.process(mode: .translate, text: "Please verify this after migration.")

        let submittedParameters = await service.submittedParameters()
        let parameters = try XCTUnwrap(submittedParameters)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(parameters), encoding: .utf8))
        XCTAssertTrue(encoded.contains("English input"))
        XCTAssertTrue(encoded.contains("Chinese translation"))
        XCTAssertTrue(encoded.contains("suggested English reply"))
    }

    func testImprovePromptCoversChineseAndMixedLanguageInput() async throws {
        let service = FakeChatCompletionService(
            assistantContent: #"{"primary":"Improved","secondaryTitle":"CHANGES","secondary":"Explanation"}"#
        )
        let processor = DeepSeekProviderProcessor(model: "deepseek-chat", service: service)

        _ = try await processor.process(mode: .improve, text: "请 improve 这个 API message")

        let submittedParameters = await service.submittedParameters()
        let parameters = try XCTUnwrap(submittedParameters)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(parameters), encoding: .utf8))
        XCTAssertTrue(encoded.contains("Chinese"))
        XCTAssertTrue(encoded.contains("mixed-language"))
        XCTAssertTrue(encoded.contains("technical identifiers"))
    }

    func testImproveUsesAnExplicitModePrompt() async throws {
        let service = FakeChatCompletionService(
            assistantContent: #"{"primary":"Improved","secondaryTitle":"CHANGES","secondary":"Explanation"}"#
        )
        let processor = DeepSeekProviderProcessor(model: "configured-model", service: service)

        _ = try await processor.process(mode: .improve, text: "Anything need?")

        let submittedParameters = await service.submittedParameters()
        let parameters = try XCTUnwrap(submittedParameters)
        let data = try JSONEncoder().encode(parameters)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(encoded.lowercased().contains("improve"))
    }

    func testMissingAssistantContentIsAnInvalidResponse() async {
        let processor = DeepSeekProviderProcessor(
            model: "deepseek-chat",
            service: FakeChatCompletionService(assistantContent: nil)
        )

        do {
            _ = try await processor.process(mode: .translate, text: "Hello")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? ProviderProcessingError, .invalidResponse)
        }
    }
}

private actor FakeChatCompletionService: ChatCompletionSubmitting {
    private let assistantContent: String?
    private var parameters: ChatCompletionParameters?

    init(assistantContent: String?) {
        self.assistantContent = assistantContent
    }

    func assistantContent(parameters: ChatCompletionParameters) async throws -> String? {
        self.parameters = parameters
        return assistantContent
    }

    func submittedParameters() -> ChatCompletionParameters? {
        parameters
    }
}
