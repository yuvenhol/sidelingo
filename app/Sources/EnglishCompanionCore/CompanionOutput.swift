import Foundation

public struct CompanionOutput: Decodable, Equatable, Sendable {
    public let primary: String
    public let secondaryTitle: String
    public let secondary: String

    public init(primary: String, secondaryTitle: String, secondary: String) {
        self.primary = primary
        self.secondaryTitle = secondaryTitle
        self.secondary = secondary
    }
}

public enum CompanionOutputDecodingError: Error, Equatable {
    case invalidObject
    case unexpectedFields
}

public enum CompanionOutputDecoder {
    public static func decode(_ content: String) throws -> CompanionOutput {
        guard let data = content.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CompanionOutputDecodingError.invalidObject
        }
        guard Set(object.keys) == ["primary", "secondaryTitle", "secondary"] else {
            throw CompanionOutputDecodingError.unexpectedFields
        }
        return try JSONDecoder().decode(CompanionOutput.self, from: data)
    }
}
