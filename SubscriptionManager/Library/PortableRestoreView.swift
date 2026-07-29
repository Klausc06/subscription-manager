import Foundation
import SubscriptionCore
import SwiftUI
import UniformTypeIdentifiers

struct PortableRestoreView: View {
    let workspace: SubscriptionWorkspace

    @State private var isImporting = false
    @State private var preview: PortableBackupMergePreview?
    @State private var selectedAdditionIDs: Set<UUID> = []
    @State private var conflictResolutions:
        [UUID: PortableBackupConflictResolution] = [:]
    @State private var preferencesResolution: PortableBackupConflictResolution?
    @State private var errorMessage: String?
    @State private var isConfirmationPresented = false

    var body: some View {
        List {
            Section {
                Text("Choose a JSON backup to inspect it before any changes are made.")
                    .foregroundStyle(.secondary)
                Button("Choose JSON Backup", systemImage: "doc.badge.plus") {
                    isImporting = true
                }
                .accessibilityIdentifier("portable-restore.select-file")
            }

            if let preview {
                Section("Additions") {
                    ForEach(preview.additions) { subscription in
                        Toggle(subscription.serviceName, isOn: additionBinding(for: subscription.id))
                    }
                    if preview.additions.isEmpty {
                        Text("No new subscriptions in this backup.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !preview.conflicts.isEmpty {
                    Section("Conflicts") {
                        ForEach(preview.conflicts) { conflict in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(conflict.local.serviceName).font(.headline)
                                Picker(
                                    "Resolution",
                                    selection: resolutionBinding(for: conflict.id)
                                ) {
                                    Text("Keep Local").tag(PortableBackupConflictResolution.keepLocal)
                                    Text("Use Backup").tag(PortableBackupConflictResolution.useBackup)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                }

                if case .conflict = preview.preferences {
                    Section("Preferences") {
                        Picker("Resolution", selection: preferencesBinding) {
                            Text("Keep Local").tag(PortableBackupConflictResolution.keepLocal)
                            Text("Use Backup").tag(PortableBackupConflictResolution.useBackup)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if !preview.retainedLocalSubscriptionIDs.isEmpty {
                    Section("Retained Locally") {
                        Text("\(preview.retainedLocalSubscriptionIDs.count) local subscriptions are not in this backup and will be kept.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Apply Restore") {
                        isConfirmationPresented = true
                    }
                    .disabled(!canApply(preview))
                    .accessibilityIdentifier("portable-restore.apply")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Restore Backup")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            load(result)
        }
        .confirmationDialog(
            "Apply Backup Restore",
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Apply Restore") { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the selected additions and explicitly resolved conflicts will change.")
        }
    }

    private var preferencesBinding: Binding<PortableBackupConflictResolution> {
        Binding(
            get: { preferencesResolution ?? .keepLocal },
            set: { preferencesResolution = $0 }
        )
    }

    private func additionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedAdditionIDs.contains(id) },
            set: { isSelected in
                if isSelected { selectedAdditionIDs.insert(id) }
                else { selectedAdditionIDs.remove(id) }
            }
        )
    }

    private func resolutionBinding(
        for id: UUID
    ) -> Binding<PortableBackupConflictResolution> {
        Binding(
            get: { conflictResolutions[id] ?? .keepLocal },
            set: { conflictResolutions[id] = $0 }
        )
    }

    private func canApply(_ preview: PortableBackupMergePreview) -> Bool {
        preview.conflicts.allSatisfy { conflictResolutions[$0.id] != nil }
            && (preview.preferences == .unchanged || preferencesResolution != nil)
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
            let loadedPreview = try workspace.preparePortableBackupImport(
                Data(contentsOf: url)
            )
            preview = loadedPreview
            selectedAdditionIDs = Set(loadedPreview.additions.map(\.id))
            conflictResolutions = [:]
            preferencesResolution = nil
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = "This backup could not be restored. Choose a valid JSON backup."
        }
    }

    private func apply() {
        guard let preview else { return }
        do {
            try workspace.applyPortableBackupImport(
                preview: preview,
                selectedAdditionIDs: selectedAdditionIDs,
                conflictResolutions: conflictResolutions,
                preferencesResolution: preferencesResolution
            )
            self.preview = nil
            errorMessage = nil
        } catch {
            errorMessage = "Restore failed. Your library was not changed."
        }
    }
}
