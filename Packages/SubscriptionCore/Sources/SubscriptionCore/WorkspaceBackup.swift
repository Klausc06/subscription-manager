import Foundation
import Observation

extension SubscriptionWorkspace {
    public func makePortableBackup() -> PortableBackup? {
        do {
            let subscriptions = try repository.listSubscriptions()
            let preferences = try preferencesRepository?.loadPreferences()
                ?? currentPreferences
            return PortableBackup(
                preferences: preferences,
                subscriptions: subscriptions
            )
        } catch {
            return nil
        }
    }
    public func makePortableBackupExport() -> PortableBackupExport? {
        guard let backup = makePortableBackup() else { return nil }
        return PortableBackupExport(
            backup: backup,
            skippedRecordCount: (repository as? SkippedRecordReporting)?
                .skippedRecordCountAfterLastLoad ?? 0
        )
    }
    public func preparePortableBackupImport(
        _ data: Data
    ) throws -> PortableBackupMergePreview {
        let asOf = now()
        let backup = try PortableBackupValidator().decode(
            data,
            asOf: asOf
        )
        let localSubscriptions = try repository.listSubscriptions()
        let localPreferences = try preferencesRepository?.loadPreferences()
            ?? currentPreferences
        return try PortableBackupMergePlanner().makePreview(
            backup: backup,
            localSubscriptions: localSubscriptions,
            localPreferences: localPreferences,
            asOf: asOf
        )
    }
    public func applyPortableBackupImport(
        preview: PortableBackupMergePreview,
        selectedAdditionIDs: Set<UUID>,
        conflictResolutions: [UUID: PortableBackupConflictResolution],
        preferencesResolution: PortableBackupConflictResolution?
    ) throws {
        guard let portableBackupImportRepository else {
            throw PortableBackupImportError.unavailable
        }
        let merge = try PortableBackupMergePlanner().makeMerge(
            preview: preview,
            selectedAdditionIDs: selectedAdditionIDs,
            conflictResolutions: conflictResolutions,
            preferencesResolution: preferencesResolution
        )
        try portableBackupImportRepository.apply(merge)
        markLocalChangesForSync()
        loadLibrary()
        loadSetup(libraryIsEmpty: false)
        reloadRequestedConsumers()
    }
}
