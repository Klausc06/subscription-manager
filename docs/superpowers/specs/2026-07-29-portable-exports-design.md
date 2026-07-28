# Portable exports design

**Status:** Approved for autonomous implementation from the accepted product
specification and the instruction to complete all non-interactive work.

## Goal

Produce an offline, deterministic, versioned JSON backup suitable for a later
round trip and a human-readable CSV convenience export. Neither format includes
CloudKit internals, EventKit identifiers, secrets, nor device data.

## Design

`SubscriptionWorkspace` gains a read-only export query that loads every
subscription from `SubscriptionRepository`, including archived records, and its
single `UserPreferences` value. Permanently deleted records are absent because
they are absent from the repository. The query has no mutation path and does
not depend on network, sync, EventKit, or catalog data.

`PortableBackup` lives in SubscriptionCore. Version 1 contains a schema name,
schema version, preferences, and subscriptions. Existing
`Codable` domain records preserve UUIDs, original `Money.minorUnits` plus
currency, billing schedule/time zone, lifecycle, payments, price history, and
archive state. The encoder uses ISO-8601 dates, sorted subscription UUIDs, and
preserved stored histories so equal logical content yields semantically
equivalent JSON.

`PortableCSVEncoder` emits UTF-8 RFC 4180-style records with a documented,
fixed header. One row represents each subscription; payment and price histories
are retained as canonical JSON cells to keep the convenience file inspectable
without losing data. Dates are ISO-8601 and money uses integer minor units plus
currency, never locale-formatted decimal strings. Fields quote commas, quotes,
and line breaks.

The app target wraps both `Data` values in FileDocument types and exposes native
export/share controls from Settings. It adds English and Simplified Chinese copy
and accessibility identifiers. No new service or account permission is needed.

## Verification

- Core tests decode JSON and parse CSV independently, including Unicode,
  commas, quotes, newlines, empty optional URL/notes, multiple currencies,
  archived subscriptions, payments, and price changes.
- Tests compare independently decoded logical backups from two unchanged
  exports, not byte snapshots.
- Simulator tests confirm export controls are reachable while offline and do
  not mutate library records.
