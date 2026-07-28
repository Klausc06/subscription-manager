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

public enum CalendarReconciliationDecision: Equatable, Sendable {
    case calendarMissing
    case eventsMissing(count: Int)
}

public enum CalendarReconciliationCommand: Equatable, Sendable {
    case reconcile([CalendarProjectionEvent])
}

public enum CalendarReconciliationResult: Equatable, Sendable {
    case reconciled
    case needsDecision(CalendarReconciliationDecision)
    case unavailable
}

public enum CalendarReconciliationState: Equatable, Sendable {
    case notConfigured
    case reconciling
    case current
    case needsDecision(CalendarReconciliationDecision)
    case unavailable

    init(result: CalendarReconciliationResult) {
        switch result {
        case .reconciled:
            self = .current
        case .needsDecision(let decision):
            self = .needsDecision(decision)
        case .unavailable:
            self = .unavailable
        }
    }
}

@MainActor
public protocol CalendarProjectionImporter: Sendable {
    func importProjection(
        events: [CalendarProjectionEvent]
    ) async -> CalendarProjectionImportResult
}

@MainActor
public protocol CalendarProjectionReconciler: Sendable {
    func perform(
        _ command: CalendarReconciliationCommand
    ) async -> CalendarReconciliationResult
}
