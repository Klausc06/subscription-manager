# TB-06 Offline Catalog Design

- Date: 2026-07-29
- Issue: #7 — Add subscriptions from the bundled offline catalog
- Status: Approved for autonomous implementation

## Outcome

The app ships a useful bilingual starter catalog that works without networking.
A person can browse or search a preset, inspect it, then explicitly confirm
their own plan, Money, Fixed Billing Schedule, and Confirmed Next Renewal
before creating an ordinary Subscription.

## Boundaries

`CatalogPreset` is immutable bundled metadata, not a source of a person's
current subscription facts. `CatalogRepository` is a narrow injected adapter.
`SubscriptionWorkspace` owns catalog query state and converts a selected
preset plus a normal `SubscriptionCreationInput` into the existing creation
command. SwiftUI only reads workspace state and sends workspace commands.

The initial JSON has a `schemaVersion`, stable `id`, localized service names,
localized category, optional safe management URL, common Fixed Billing
Schedule interval, and a `CatalogIcon` category token. No third-party artwork
is shipped. `CatalogIcon` renders an original system symbol; service text is
always visible. Price, currency, renewal date, and plan are absent from a
preset and must be supplied in the confirmation form.

## Data and validation

The bundled repository decodes `CatalogSnapshot` from app resources, rejects
unsupported schema versions, duplicate IDs, empty localized values, invalid
HTTP(S) URLs, and invalid billing intervals. A rejected snapshot produces a
recoverable catalog state and never affects the Subscription Library.

Search folds case and diacritics, uses the supplied app locale to choose the
matching localized values, and matches service name plus category. Category
filtering happens before the sorted result is published. Results are ordered
by localized service name with the stable ID as a tie-breaker.

## Workspace behavior

`loadCatalog(locale:)`, `setCatalogSearchQuery(_:)`, and
`setCatalogCategory(_:)` republish a `CatalogState`. Selecting a preset makes
it available to the UI but does not create anything. `createSubscription`
continues to perform existing validation and persistence, with
`ServiceIdentity(rawValue: "catalog:<preset id>")` supplied by the workspace
only for catalog-originated creation. Manual creation retains its existing
`manual:<UUID>` identity and remains a first-class flow.

## UI

The Add Subscription screen gains two explicit paths: **Choose from Catalog**
and **Add Manually**. Catalog shows a searchable, category-filterable list,
then a preset detail. Continuing opens the existing creation form with only
safe defaults (service name, category, suggested billing interval, management
URL); plan, amount, currency, renewal anchor, and next renewal remain editable
and are not silently inferred. Cancel returns without changing the library.

All new visible copy and accessibility labels ship in English and Simplified
Chinese. The catalog is entirely local: no request, provider lookup, tracking,
or artwork download is introduced.

## Verification

- Core tests cover snapshot validation, bilingual localized search, category
  filtering, deterministic sort, and creation identity.
- App tests cover resource loading and rejected bundled data.
- UI tests cover offline browse/search, preset confirmation, a created
  subscription's ordinary editability, and neutral icon/service-name presence.
