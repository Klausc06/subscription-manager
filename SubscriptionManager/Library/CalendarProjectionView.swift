import Foundation
import SubscriptionCore
import SwiftUI
import UniformTypeIdentifiers

struct CalendarProjectionView: View {
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace

    @State private var document = CalendarProjectionDocument(data: Data())
    @State private var isExporting = false

    var body: some View {
        List {
            if workspace.calendarProjection.isEmpty {
                ContentUnavailableView {
                    Label("No Upcoming Renewals", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Renewals in your selected planning period appear here.")
                }
                .accessibilityIdentifier("calendar.projection.empty")
            } else {
                Section("Renewal Events") {
                    ForEach(workspace.calendarProjection) { event in
                        CalendarProjectionRow(event: event, locale: locale)
                            .accessibilityIdentifier("calendar.projection.row")
                    }
                }
            }
        }
        .navigationTitle("Calendar Preview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Export ICS", systemImage: "square.and.arrow.up") {
                    exportCalendar()
                }
                .disabled(workspace.calendarProjection.isEmpty)
                .accessibilityIdentifier("calendar.projection.export")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: CalendarProjectionDocument.calendarContentType,
            defaultFilename: "Subscription Renewals"
        ) { _ in }
        .task(id: locale.identifier) {
            workspace.loadCalendarProjection(locale: locale)
        }
    }

    private func exportCalendar() {
        guard let data = try? CalendarICSEncoder().encode(
            events: workspace.calendarProjection
        ) else {
            return
        }
        document = CalendarProjectionDocument(data: data)
        isExporting = true
    }
}

private struct CalendarProjectionRow: View {
    let event: CalendarProjectionEvent
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
            Text(formattedDate)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Reminders")
                Text(reminderDays)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: event.timeZoneIdentifier)
            ?? .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: event.startDate)
    }

    private var reminderDays: String {
        event.alarmOffsets
            .map { abs($0) }
            .sorted(by: >)
            .map { "\($0)d" }
            .joined(separator: ", ")
    }
}

private struct CalendarProjectionDocument: FileDocument {
    static let calendarContentType = UTType(filenameExtension: "ics") ?? .data
    static var readableContentTypes: [UTType] { [calendarContentType] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
