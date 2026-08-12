import Foundation

public struct CompanionOutputPartial: Equatable, Sendable {
    public let primary: String?
    public let secondaryTitle: String?
    public let secondary: String?

    public init(
        primary: String? = nil,
        secondaryTitle: String? = nil,
        secondary: String? = nil
    ) {
        self.primary = primary
        self.secondaryTitle = secondaryTitle
        self.secondary = secondary
    }
}

public enum CompanionJSONLParsingError: Error, Equatable {
    case invalidResponse
}

public struct CompanionJSONLParser {
    private struct Record: Decodable {
        let field: String
        let value: String
    }

    private static let orderedFields = ["primary", "secondaryTitle", "secondary"]

    private var buffer = ""
    private var partial = CompanionOutputPartial()
    private var recordCount = 0

    public init() {}

    public mutating func append(_ chunk: String) throws -> [CompanionOutputPartial] {
        buffer.append(chunk)
        var updates: [CompanionOutputPartial] = []

        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let update = try consume(line) {
                updates.append(update)
            }
        }
        return updates
    }

    public mutating func finish() throws -> CompanionOutput {
        if !buffer.isEmpty {
            let finalLine = buffer
            buffer = ""
            _ = try consume(finalLine)
        }
        guard recordCount == Self.orderedFields.count,
              let primary = partial.primary,
              let secondaryTitle = partial.secondaryTitle,
              let secondary = partial.secondary else {
            throw CompanionJSONLParsingError.invalidResponse
        }
        return CompanionOutput(
            primary: primary,
            secondaryTitle: secondaryTitle,
            secondary: secondary
        )
    }

    private mutating func consume(_ rawLine: String) throws -> CompanionOutputPartial? {
        var line = rawLine
        if line.last == "\r" {
            line.removeLast()
        }
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard recordCount < Self.orderedFields.count,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["field", "value"],
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.field == Self.orderedFields[recordCount] else {
            throw CompanionJSONLParsingError.invalidResponse
        }

        switch recordCount {
        case 0:
            partial = CompanionOutputPartial(primary: record.value)
        case 1:
            partial = CompanionOutputPartial(
                primary: partial.primary,
                secondaryTitle: record.value
            )
        case 2:
            partial = CompanionOutputPartial(
                primary: partial.primary,
                secondaryTitle: partial.secondaryTitle,
                secondary: record.value
            )
        default:
            throw CompanionJSONLParsingError.invalidResponse
        }
        recordCount += 1
        return partial
    }
}
