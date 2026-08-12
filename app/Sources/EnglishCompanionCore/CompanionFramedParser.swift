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

public enum CompanionFramedProtocol {
    public static let markerPrefix = "<<<ENGLISH_COMPANION::"
    public static let primaryMarker = "<<<ENGLISH_COMPANION::PRIMARY>>>"
    public static let secondaryTitleMarker = "<<<ENGLISH_COMPANION::SECONDARY_TITLE>>>"
    public static let secondaryMarker = "<<<ENGLISH_COMPANION::SECONDARY>>>"
    public static let endMarker = "<<<ENGLISH_COMPANION::END>>>"

    public static func containsMarker(in partial: CompanionOutputPartial) -> Bool {
        [partial.primary, partial.secondaryTitle, partial.secondary]
            .compactMap { $0 }
            .contains { $0.contains(markerPrefix) }
    }
}

public enum CompanionFramedParsingError: Error, Equatable {
    case invalidResponse
}

public struct CompanionFramedParser {
    private enum Field {
        case primary
        case secondaryTitle
        case secondary
    }

    private enum State {
        case expectingPrimaryMarker
        case expectingLineBreak(Field)
        case reading(Field)
        case ended
    }

    private static let markers = [
        CompanionFramedProtocol.primaryMarker,
        CompanionFramedProtocol.secondaryTitleMarker,
        CompanionFramedProtocol.secondaryMarker,
        CompanionFramedProtocol.endMarker,
    ]

    private var state = State.expectingPrimaryMarker
    private var buffer = ""
    private var partial = CompanionOutputPartial()

    public init() {}

    public mutating func append(_ chunk: String) throws -> [CompanionOutputPartial] {
        buffer.append(chunk)
        var updates: [CompanionOutputPartial] = []

        while true {
            switch state {
            case .expectingPrimaryMarker:
                let marker = CompanionFramedProtocol.primaryMarker
                guard buffer.count >= marker.count else {
                    guard marker.hasPrefix(buffer) else { throw invalidResponse() }
                    return updates
                }
                guard buffer.hasPrefix(marker) else { throw invalidResponse() }
                buffer.removeFirst(marker.count)
                state = .expectingLineBreak(.primary)

            case let .expectingLineBreak(field):
                guard !buffer.isEmpty else { return updates }
                if buffer.hasPrefix("\r\n") || buffer.hasPrefix("\n") {
                    buffer.removeFirst()
                    state = .reading(field)
                } else if buffer == "\r" {
                    return updates
                } else {
                    throw invalidResponse()
                }

            case let .reading(field):
                if let markerStart = buffer.range(of: CompanionFramedProtocol.markerPrefix)?.lowerBound {
                    let candidate = String(buffer[markerStart...])
                    let completeMarkers = Self.markers.filter { candidate.hasPrefix($0) }
                    let possibleMarkers = Self.markers.filter { $0.hasPrefix(candidate) }
                    let expectedMarker = nextMarker(after: field)

                    if let marker = completeMarkers.first {
                        guard marker == expectedMarker,
                              markerStart > buffer.startIndex else {
                            throw invalidResponse()
                        }
                        let preceding = buffer.index(before: markerStart)
                        guard buffer[preceding] == "\n" || buffer[preceding] == "\r\n" else {
                            throw invalidResponse()
                        }

                        let content = String(buffer[..<preceding])
                        if let update = appendContent(content, to: field) {
                            updates.append(update)
                        }
                        complete(field)

                        let markerEnd = buffer.index(markerStart, offsetBy: marker.count)
                        buffer.removeSubrange(buffer.startIndex..<markerEnd)
                        if marker == CompanionFramedProtocol.endMarker {
                            state = .ended
                        } else {
                            state = .expectingLineBreak(fieldAfterMarker(marker))
                        }
                    } else {
                        guard possibleMarkers.contains(expectedMarker),
                              markerStart > buffer.startIndex else {
                            throw invalidResponse()
                        }
                        let preceding = buffer.index(before: markerStart)
                        guard buffer[preceding] == "\n" || buffer[preceding] == "\r\n" else {
                            throw invalidResponse()
                        }

                        let retainedStart = preceding
                        let content = String(buffer[..<preceding])
                        if let update = appendContent(content, to: field) {
                            updates.append(update)
                        }
                        buffer = String(buffer[retainedStart...])
                        return updates
                    }
                } else {
                    let retainedCount = possibleMarkerSuffixCount(in: buffer)
                    let safeCount = buffer.count - retainedCount
                    let safeEnd = buffer.index(buffer.startIndex, offsetBy: safeCount)
                    let content = String(buffer[..<safeEnd])
                    if let update = appendContent(content, to: field) {
                        updates.append(update)
                    }
                    buffer = String(buffer[safeEnd...])
                    return updates
                }

            case .ended:
                guard buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw invalidResponse()
                }
                return updates
            }
        }
    }

    public mutating func finish() throws -> CompanionOutput {
        _ = try append("")
        guard case .ended = state,
              let primary = partial.primary,
              let secondaryTitle = partial.secondaryTitle,
              let secondary = partial.secondary else {
            throw invalidResponse()
        }
        return CompanionOutput(
            primary: primary,
            secondaryTitle: secondaryTitle,
            secondary: secondary
        )
    }

    private func nextMarker(after field: Field) -> String {
        switch field {
        case .primary: CompanionFramedProtocol.secondaryTitleMarker
        case .secondaryTitle: CompanionFramedProtocol.secondaryMarker
        case .secondary: CompanionFramedProtocol.endMarker
        }
    }

    private func fieldAfterMarker(_ marker: String) -> Field {
        switch marker {
        case CompanionFramedProtocol.secondaryTitleMarker: .secondaryTitle
        case CompanionFramedProtocol.secondaryMarker: .secondary
        default: .primary
        }
    }

    private mutating func appendContent(
        _ content: String,
        to field: Field
    ) -> CompanionOutputPartial? {
        guard !content.isEmpty else { return nil }
        switch field {
        case .primary:
            partial = CompanionOutputPartial(primary: (partial.primary ?? "") + content)
        case .secondaryTitle:
            partial = CompanionOutputPartial(
                primary: partial.primary,
                secondaryTitle: (partial.secondaryTitle ?? "") + content
            )
        case .secondary:
            partial = CompanionOutputPartial(
                primary: partial.primary,
                secondaryTitle: partial.secondaryTitle,
                secondary: (partial.secondary ?? "") + content
            )
        }
        return partial
    }

    private mutating func complete(_ field: Field) {
        switch field {
        case .primary where partial.primary == nil:
            partial = CompanionOutputPartial(primary: "")
        case .secondaryTitle where partial.secondaryTitle == nil:
            partial = CompanionOutputPartial(primary: partial.primary, secondaryTitle: "")
        case .secondary where partial.secondary == nil:
            partial = CompanionOutputPartial(
                primary: partial.primary,
                secondaryTitle: partial.secondaryTitle,
                secondary: ""
            )
        default:
            break
        }
    }

    private func possibleMarkerSuffixCount(in text: String) -> Int {
        var retainedCount = 0
        let maximum = min(text.count, CompanionFramedProtocol.markerPrefix.count - 1)
        if maximum > 0 {
            for length in 1...maximum {
                let suffixStart = text.index(text.endIndex, offsetBy: -length)
                if CompanionFramedProtocol.markerPrefix.hasPrefix(text[suffixStart...]) {
                    retainedCount = length
                }
            }
        }

        if retainedCount > 0 {
            let suffixStart = text.index(text.endIndex, offsetBy: -retainedCount)
            if suffixStart > text.startIndex {
                let preceding = text.index(before: suffixStart)
                if text[preceding] == "\n" || text[preceding] == "\r\n" {
                    retainedCount += 1
                }
            }
        } else if text.hasSuffix("\r\n") {
            retainedCount = 1
        } else if text.hasSuffix("\n") || text.hasSuffix("\r") {
            retainedCount = 1
        }
        return retainedCount
    }

    private func invalidResponse() -> CompanionFramedParsingError {
        return .invalidResponse
    }
}
