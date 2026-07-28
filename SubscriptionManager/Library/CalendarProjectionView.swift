import Foundation
import SubscriptionCore
import SwiftUI
import UniformTypeIdentifiers

struct CalendarProjectionView: View {
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace

    @State private var document = CalendarProjectionDocument(data: Data())
    @State private var isExporting = false
    @State private var isImportConfirmationPresented = false
    @State private var importSnapshot: [CalendarProjectionEvent] = []

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

            CalendarImportStatusView(
                state: workspace.calendarImportState,
                onRetry: retryImport
            )
        }
        .navigationTitle("Calendar Preview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import to Calendar", systemImage: "calendar.badge.plus") {
                    presentImportConfirmation()
                }
                .disabled(
                    workspace.calendarProjection.isEmpty
                        || workspace.calendarImportState == .importing
                )
                .accessibilityIdentifier("calendar.projection.import")
            }
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
        .confirmationDialog(
            "Import Renewals to Calendar",
            isPresented: $isImportConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Import to Calendar") {
                importCalendar(importSnapshot)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will add the previewed renewal events to a dedicated Subscription Manager calendar."
            )
        }
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

    private func presentImportConfirmation() {
        importSnapshot = workspace.calendarProjection
        isImportConfirmationPresented = true
    }

    private func retryImport() {
        if importSnapshot.isEmpty {
            importSnapshot = workspace.calendarProjection
        }
        importCalendar(importSnapshot)
    }

    private func importCalendar(_ events: [CalendarProjectionEvent]) {
        Task {
            await workspace.importCalendarProjection(events)
        }
    }
}

private struct CalendarImportStatusView: View {
    let state: CalendarImportState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .notRequested:
            EmptyView()
        case .importing:
            Section("Calendar Import") {
                ProgressView("Importing Calendar Events")
                    .accessibilityIdentifier("calendar.import.importing")
            }
        case .imported:
            Section("Calendar Import") {
                Label(
                    "Calendar import completed.",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.green)
                .accessibilityIdentifier("calendar.import.complete")
            }
        case .accessDenied:
            retrySection(
                message: "Calendar access was not granted. You can still export an ICS file.",
                identifier: "calendar.import.denied"
            )
        case .unavailable:
            retrySection(
                message: "No writable Calendar source is available. You can still export an ICS file.",
                identifier: "calendar.import.unavailable"
            )
        case .partiallyImported:
            retrySection(
                message: "Some Calendar events could not be imported. Try again to add the missing events.",
                identifier: "calendar.import.partial"
            )
        }
    }

    private func retrySection(
        message: LocalizedStringKey,
        identifier: String
    ) -> some View {
        Section("Calendar Import") {
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry Calendar Import", action: onRetry)
                .accessibilityIdentifier(identifier)
        }
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
