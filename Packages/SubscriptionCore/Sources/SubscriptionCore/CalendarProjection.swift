import Foundation

public struct CalendarProjectionEvent: Equatable, Identifiable, Sendable {
    public let uid: String
    public let startDate: Date
    public let endDate: Date
    public let title: String
    public let notes: String
    public let managementURL: URL?
    public let alarmOffsets: [Int]
    public let timeZoneIdentifier: String

    public var id: String { uid }

    public init(
        uid: String,
        startDate: Date,
        endDate: Date,
        title: String,
        notes: String,
        managementURL: URL?,
        alarmOffsets: [Int],
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.uid = uid
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.notes = notes
        self.managementURL = managementURL
        self.alarmOffsets = alarmOffsets
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}
