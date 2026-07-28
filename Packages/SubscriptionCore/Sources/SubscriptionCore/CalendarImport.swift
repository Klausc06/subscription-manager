public struct CalendarProjectionImportSummary: Equatable, Sendable {
    public let createdCount: Int
    public let updatedCount: Int

    public init(createdCount: Int, updatedCount: Int) {
        self.createdCount = createdCount
        self.updatedCount = updatedCount
    }
}

public enum CalendarProjectionImportResult: Equatable, Sendable {
    case imported(CalendarProjectionImportSummary)
    case accessDenied
    case unavailable
    case partialFailure(
        CalendarProjectionImportSummary,
        failedCount: Int
    )
}

public enum CalendarImportState: Equatable, Sendable {
    case notRequested
    case importing
    case imported(CalendarProjectionImportSummary)
    case accessDenied
    case unavailable
    case partiallyImported(
        CalendarProjectionImportSummary,
        failedCount: Int
    )

    init(result: CalendarProjectionImportResult) {
        switch result {
        case .imported(let summary):
            self = .imported(summary)
        case .accessDenied:
            self = .accessDenied
        case .unavailable:
            self = .unavailable
        case .partialFailure(let summary, let failedCount):
            self = .partiallyImported(summary, failedCount: failedCount)
        }
    }
}

public protocol CalendarProjectionImporter: Sendable {
    func importProjection(
        events: [CalendarProjectionEvent]
    ) async -> CalendarProjectionImportResult
}
