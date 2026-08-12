public enum HistoryPresentation: Sendable {
    case userResult
    case demo
}

public enum HistoryPersistencePolicy {
    public static func record(
        _ record: HistoryRecord,
        presentation: HistoryPresentation,
        append: (HistoryRecord) throws -> Void
    ) rethrows {
        guard presentation == .userResult else { return }
        try append(record)
    }
}
