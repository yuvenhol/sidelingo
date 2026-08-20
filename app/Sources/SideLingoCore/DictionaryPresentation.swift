import Foundation

public struct DictionarySection: Equatable, Sendable {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

public struct DictionaryPresentation: Equatable, Sendable {
    public let heading: String
    public let phonetic: String?
    public let partOfSpeech: String?
    public let badges: [String]
    public let sections: [DictionarySection]
    public let copyText: String
    public let speechText: String

    public init(lookup: DictionaryLookup) {
        let entry = lookup.entry
        heading = lookup.query.caseInsensitiveCompare(entry.word) == .orderedSame
            ? entry.word
            : "\(lookup.query) → \(entry.word)"
        phonetic = Self.nonEmpty(entry.phonetic).map { value in
            if value.hasPrefix("/") && value.hasSuffix("/") { return value }
            return "/\(value)/"
        }
        partOfSpeech = Self.nonEmpty(entry.pos)

        var badges: [String] = []
        if let collins = entry.collins { badges.append("Collins \(collins)★") }
        if entry.oxford { badges.append("Oxford 3000") }
        if let rank = entry.bncRank { badges.append("BNC #\(rank)") }
        if let rank = entry.frequencyRank { badges.append("Contemporary #\(rank)") }
        badges.append(contentsOf: entry.tags.map { $0.uppercased() })
        self.badges = badges

        var sections: [DictionarySection] = []
        Self.append("中文释义", value: entry.translation, to: &sections)
        Self.append("English definition", value: entry.definition, to: &sections)
        Self.append("词形变化", value: entry.exchange, to: &sections)
        Self.append("Detail", value: entry.detail, to: &sections)
        Self.append("Audio source", value: entry.audio, to: &sections)
        self.sections = sections

        let translation = entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        copyText = translation.isEmpty ? entry.word : "\(entry.word)\n\(translation)"
        speechText = entry.word
    }

    private static func append(_ title: String, value: String, to sections: inout [DictionarySection]) {
        guard let value = nonEmpty(value) else { return }
        sections.append(DictionarySection(title: title, value: value))
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
