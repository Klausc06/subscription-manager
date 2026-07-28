# Safe JSON backup restore design

**Status:** Approved implementation direction from the accepted product
specification and the user's standing instruction to complete non-interactive
work autonomously.

## Goal

Restore a TB20 JSON backup only after the person can inspect its effects and
explicitly resolve every difference. A restore adds or updates selected backup
records; it never removes a local record merely because that record is absent
from the backup.

## Design

### Validation and preview

`PortableBackupValidator` decodes JSON with an independent `JSONDecoder` and
rejects an unknown schema name, unsupported schema version, duplicate stable
subscription IDs, and records that do not satisfy the existing fixed-charge
domain invariants. Validation happens before any repository mutation.

`PortableBackupMergePlanner` compares each validated backup subscription with
the local library by UUID and produces a stable, ID-sorted preview:

- `addition`: no local record has the backup UUID;
- `unchanged`: the local and backup records are equal;
- `conflict`: both exist but differ.

The planner also compares preferences. An unchanged preference is reported as
such; otherwise it requires a separate explicit keep-local or use-backup
choice. Local subscriptions not included in the backup are reported as
retained local records and are never included in a mutation request.

### Explicit resolutions

Each conflict requires either `keepLocal` or `useBackup` before Apply is
enabled. Additions are selected by default and can be deselected. Unchanged
records have no mutation. The preference decision is explicit only when the
two values differ. The preview carries only immutable snapshots, so a user
cannot accidentally apply a preview after a different file has been selected.

### Atomic merge seam

Core exposes a `PortableBackupImportRepository` adapter that accepts a fully
resolved `PortableBackupMerge`. `SubscriptionWorkspace` owns validation,
planning, resolution checking, and visible import state; it delegates one
write command to this adapter only after the preview is approved.

The production SwiftData adapter creates one `ModelContext`, applies selected
creates and updates plus the selected preference value, then saves once. Any
error rolls back that context and is surfaced as a recoverable import failure.
No compensating sequence of individual repository saves is used. In-memory and
failure fixtures implement the same seam for behavioral tests.

After a successful commit, the workspace reloads its normal library state.
The existing CloudKit configuration observes the same persisted records; no
custom sync route is introduced. The app also asks the existing Calendar
reconciliation path to refresh projections after a successful restore.

### Native UI

Settings gains a Restore JSON Backup entry next to portable export. A native
`fileImporter` accepts only JSON. The app validates the chosen file and opens a
preview screen listing additions, unchanged records, conflicts, retained local
records, and the preference decision. Conflict rows use explicit local/backup
controls. Apply is destructive only in the sense of replacing the explicitly
chosen existing records, so the confirmation message states its exact count.

The UI has English and Simplified Chinese copy, stable accessibility
identifiers, error text, and no dependency on iCloud, Calendar authorization,
or network availability.

## Non-goals

- CSV import, partial JSON parsing, automatic conflict choice, and deleting
  local-only records are out of scope.
- Unknown future schemas are rejected rather than guessed or migrated.
- Calendar IDs, CloudKit metadata, and device data remain absent from backups
  and restore commands.

## Verification

- Core tests cover invalid JSON, schema/version rejection, duplicate IDs,
  invariant failure, additions, unchanged records, every conflict choice,
  retained local records, incomplete resolutions, rollback, and repeat import.
- The production adapter test injects a save failure and asserts that one
  atomic rollback preserves subscriptions and preferences.
- A TB20 export fixture is decoded through the validator and restored through
  the planner; repeating the same chosen merge produces no further changes.
- iPhone UI automation verifies the Settings entry, JSON-only importer
  availability, preview, conflict controls, disabled Apply state, and a
  successful apply path using a test fixture.
