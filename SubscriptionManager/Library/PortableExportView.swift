import Foundation
import SubscriptionCore
import SwiftUI
import UniformTypeIdentifiers

struct PortableExportView: View {
    let workspace: SubscriptionWorkspace

    @State private var jsonDocument = PortableExportDocument(data: Data())
    @State private var csvDocument = PortableExportDocument(data: Data())
    @State private var isExportingJSON = false
    @State private var isExportingCSV = false
    @State private var exportFailed = false
    @State private var skippedRecordCount = 0

    var body: some View {
        List {
            Section {
                Text(
                    "Create offline copies of your subscriptions and preferences. Exports include archived subscriptions, but never device Calendar identifiers or iCloud data."
                )
                .foregroundStyle(.secondary)
            }

            Section("Export Format") {
                Button("Export JSON Backup", systemImage: "internaldrive") {
                    exportJSON()
                }
                .accessibilityIdentifier("portable-export.json")

                Button("Export CSV", systemImage: "tablecells") {
                    exportCSV()
                }
                .accessibilityIdentifier("portable-export.csv")
            }

            if exportFailed {
                Section {
                    Text("Couldn’t create the export. Try again.")
                        .foregroundStyle(.red)
                }
            }

            if skippedRecordCount > 0 {
                Section {
                    Label(
                        "Skipped Records",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    Text(
                        "\(skippedRecordCount) unreadable subscription records were skipped during the export. The backup may be incomplete."
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Export Data")
        .fileExporter(
            isPresented: $isExportingJSON,
            document: jsonDocument,
            contentType: .json,
            defaultFilename: "Subscription Manager Backup"
        ) { _ in }
        .fileExporter(
            isPresented: $isExportingCSV,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Subscription Manager Export"
        ) { _ in }
    }

    private func exportJSON() {
        guard let export = workspace.makePortableBackupExport(),
              let data = try? PortableBackupEncoder().encode(export.backup)
        else {
            exportFailed = true
            return
        }
        jsonDocument = PortableExportDocument(data: data)
        exportFailed = false
        skippedRecordCount = export.skippedRecordCount
        isExportingJSON = true
    }

    private func exportCSV() {
        guard let export = workspace.makePortableBackupExport() else {
            exportFailed = true
            return
        }
        skippedRecordCount = export.skippedRecordCount
        csvDocument = PortableExportDocument(
            data: PortableCSVEncoder().encode(
                preferences: export.backup.preferences,
                subscriptions: export.backup.subscriptions
            )
        )
        exportFailed = false
        isExportingCSV = true
    }
}

private struct PortableExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

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
