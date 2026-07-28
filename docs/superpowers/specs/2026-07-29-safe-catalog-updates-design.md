# TB-07 Safe Catalog Updates Design

- Date: 2026-07-29
- Issue: #8 — Accept safe read-only catalog updates
- Status: Approved for autonomous implementation

## Decision

The app will fetch one JSON document from a fixed HTTPS GitHub raw-content
URL, validate it completely in memory, then atomically replace a cache file.
The active catalog is always selected in this order: valid cached snapshot,
valid bundled snapshot. A request, decode, validation, cache-write, or stale
version failure leaves the already active snapshot unchanged. No catalog
operation reads or mutates a Subscription record.

The alternative of merging remote rows into the bundled list was rejected:
it makes removal and provenance ambiguous. The alternative of accepting a
remote URL or user-provided location was rejected because it expands the
network trust boundary. The fixed source and whole-snapshot replacement give
one auditable data path.

## Data contract

`CatalogSnapshot` gains a monotonically increasing `catalogVersion` in
addition to its existing schema-version compatibility field. Every preset
gains machine-readable `CatalogAssetProvenance`: `kind` is
`originalSymbol`, `license` is `CC0-1.0`, and `source` is the catalog's
stable identifier. Validation rejects a snapshot with a non-positive catalog
version, malformed or duplicate stable IDs, missing English or Simplified
Chinese text, unsupported interval, a non-HTTP(S) management URL, or unsafe
asset provenance. These errors name the preset ID and field for CI diagnostics.

The bundled catalog starts at version 1. A remote payload activates only when
its catalog version is greater than the active one and its schema version is
supported. A same or older valid snapshot is ignored, not cached. The active
version and source (`bundled` or `cached`) are exposed through workspace
catalog state for diagnostics.

## Boundaries and flow

`CatalogRepository` remains a synchronous read boundary for the active
snapshot. `CatalogUpdateSource` is a separate injected asynchronous adapter
that can only return raw `Data` from the fixed request. The app target owns
the URLSession-backed source and the application-support cache. Core owns
validation, update decisions, and the observable catalog diagnostics. SwiftUI
asks `SubscriptionWorkspace` to refresh; it never contacts URLSession or the
file system directly.

On refresh, the workspace obtains candidate data, asks the repository to
validate and activate it, then reloads the already selected snapshot and
republishes the current locale, search, and category filter. A refresh failure
keeps the existing list visible and publishes a localized non-blocking status;
the person can continue browsing offline.

## UI and privacy

Catalog shows its active version and source in a compact diagnostics footer.
A manual "Check for Catalog Updates" action performs the one fixed HTTPS
request. The action is optional; normal app launch and bundled browsing make
no network request. New copy ships in English and Simplified Chinese. No
provider executable code, assets, arbitrary URL schemes, tracking, or account
data are accepted.

## Verification

- Core tests cover valid newer activation, stale rejection, corrupt payload,
  duplicate ID, unsupported interval, unsafe URL/provenance, cache fallback,
  and the fact that subscription repositories receive no mutation commands.
- App tests use an injected source and temporary cache; they never call the
  network.
- A repository validator executable validates the bundled document and a
  remote-fixture document, printing `preset=<id> field=<field>` on failure.
- UI tests confirm visible source/version, manual refresh status, and that an
  update does not change an existing subscription.
