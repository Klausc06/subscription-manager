# Round 2 Current-Product Gap Audit

**Audit date:** 2026-07-30–31
**Code revision:** `9b0adccd79c5edc90cbe8db54b64abdffc46b0aa`
**Status:** Research evidence; no functional implementation

## Result

All 14 Round 2 requirements map to current code and observable behavior.
There are no unmapped requirements. The audit also found three capabilities
that are already implemented and should be preserved:

1. active billing dates already update in both directions;
2. library rows already support leading pin, trailing archive/delete, full
   trailing swipe, and permanent-delete confirmation;
3. a conservative post-save catalog reconciliation seam already adopts a
   unique verified offer when name or alias, current price, currency, and
   interval all match.

The next design therefore does not need a new recurrence engine, a custom
swipe engine, or a second catalog identity matcher. The principal gaps are
form validation, navigation hierarchy, visible typeahead, date-picker task
completion, catalog evidence and representation, calendar presentation, and
redundant visual containers.

## Method

- Read the current UI, domain, persistence seams, catalog schema, bundled
  catalog, and relevant tests.
- Used `rg`, `git log`, and `git blame` to distinguish old constraints from
  recently completed behavior.
- Validated the unchanged bundled catalog with the shipped
  `CatalogValidator`.
- Built and launched the unchanged app on the dedicated iOS simulator.
- Executed S1–S8 in Simplified Chinese using semantic runtime UI snapshots.
- Ran the complete core test suite, the app unit-test target, and six focused
  UI regressions that cover the audited paths.

Primary runtime:

- iPhone simulator `SubscriptionManager-ReleaseGate-iOS27`;
- iOS 27.0, portrait, Simplified Chinese, default Dynamic Type;
- project `SubscriptionManager.xcodeproj`;
- scheme `SubscriptionManager`, Debug;
- bundle `com.klausc06.SubscriptionManager`.

## Verification Baseline

| Check | Result |
| --- | --- |
| Debug build and launch | Passed; no build warnings |
| Shipped catalog validator | Passed: schema 1, catalog version 5, 106 presets |
| `swift test --package-path Packages/SubscriptionCore` | 156/156 passed |
| `SubscriptionManagerTests` on iOS simulator | 93/93 passed |
| Focused UI regressions | 6/6 passed in 200 seconds |

The focused UI set covered catalog-offer creation, Add date linkage, Edit date
linkage, edit persistence across relaunch, full-swipe delete confirmation, and
Upcoming-to-detail navigation.

## S1–S8 Unchanged-Build Baseline

Counting follows the approved Shared Comparison Protocol. Text entry records
field focuses separately from activation counts.

| Scenario | Observed shortest relevant path | Count | Baseline result |
| --- | --- | --- | --- |
| S1 — verified ChatGPT | Add → search `ChatGPT` → result → Save | 3 activations, 1 text entry / 7 characters, 3 transitions | **Available.** Verified Go is the deterministic default. Service, category, plan, price, currency, interval, and start date are visible; Next Renewal is below the initial fold. |
| S2 — unknown service with optional metadata empty | Add → Add Manually → enter service and amount → choose CNY → Save | 4 activations, 2 text entries / 11 characters, 2 transitions | **Unavailable.** Save produces required errors for both Plan and Category. |
| S3 — edit ChatGPT facts | Row → Actions → Edit | 3 activations, 3 transitions before editing | **Unavailable.** The edit form exposes name, plan, category, interval, dates, URL, and notes, but not original price or currency. |
| S4 — archive | Partial trailing swipe → Archive | 2 activations, no secondary screen | **Available.** The row leaves the current library and current forecasts. |
| S5 — permanent delete | Full trailing swipe → confirm Delete Permanently | 2 activations, 1 confirmation transition | **Available.** The partial-swipe path is 3 activations. Both retain explicit irreversible-action confirmation. |
| S6 — inspect upcoming month | Upcoming → Next 90 Days → charge row | 3 activations, 2 context transitions | **Partially available.** A charge date can open its subscription, but month navigation, day distribution, empty days, and dense days are unavailable. |
| S7 — enter linked dates | Open picker → select day → dismiss; repeat if editing both; Save | 4 activations when one edit derives both dates; 7 when both are explicitly edited | **Partially available.** Both directions calculate correctly. The compact picker stays open after day selection and provides no task-level Done/Next or automatic progression. |
| S8 — manual partial match | Add → Add Manually → type `88 VIP` | 2 activations, 1 text entry / 6 characters, 2 transitions | **Unavailable.** No catalog candidate appears; only system keyboard suggestions are visible. |

## R2-01–R2-14 Traceability

### R2-01 — Plan and category block a minimum record (CUR-001)

- `AddSubscriptionView` renders both fields and their validation messages for
  manual input.
- `SubscriptionWorkspace.validate` explicitly marks empty plan and category
  as required.
- `SubscriptionCreationInput` already stores these as strings, so empty
  values do not require a persistence migration.
- The existing “Incomplete monthly input” core test explicitly expects plan
  and category errors and must be updated.
- Missing test: a manual record with service, positive price, currency,
  interval, and valid dates saves with empty plan and category.

**Gap:** confirmed. This is a validation-policy change, not a storage-schema
change.

### R2-02 — Row selection opens read-only detail before editing (CUR-002, CUR-015–CUR-018)

- Each library row emits its subscription UUID through a `NavigationLink`
  (CUR-002), and the Subscriptions stack maps UUID destinations to
  `SubscriptionDetailView` (CUR-015).
- `SubscriptionDetailView` renders the subscription facts as
  `LabeledContent` values in a read-only `Form` (CUR-016).
- Editing requires opening the `Actions` menu (CUR-017), after which
  `EditSubscriptionView` is presented in a sheet (CUR-018).
- Existing edit UI tests encode Row → Actions → Edit and will become
  superseded.

**Gap:** confirmed. Ordinary editing starts after three activations and three
context changes.

### R2-03 — Ordinary actions are hidden and duplicated (CUR-003, CUR-017, CUR-019, CUR-020)

- The detail `Actions` menu contains Edit (CUR-017), plus Confirm Charge,
  Record Price Change, Record Cancellation, Archive, and Permanent Delete
  (CUR-019).
- Current-library rows already expose leading Pin/Unpin and trailing
  Archive/Delete using native `swipeActions`, with full swipe enabled
  (CUR-003).
- The destructive row action opens a permanent-delete confirmation with
  destructive and cancel choices instead of deleting immediately (CUR-020).
- The focused full-swipe UI test passed and proves both cancellation and final
  deletion.

**Gap:** partial. Preserve native row actions and confirmation. Research must
decide where history/lifecycle commands live after the catch-all menu is
removed; archive/delete need no new implementation family.

### R2-04 — Manual entry has no visible catalog assistance (CUR-004, CUR-021–CUR-023)

- “Add Manually” navigates to `AddSubscriptionView` without a catalog preset
  (CUR-021).
- Its manual service section renders a plain Service Name `TextField` and
  validation message (CUR-022); the S8 runtime pass showed no catalog
  candidate surface while typing.
- `CatalogSnapshot.search` searches localized service and category text only;
  it does not query explicit aliases (CUR-023).
- `CatalogOfferMatcher` already performs a safe exact reconciliation after
  create/edit using service or alias plus price, currency, and interval
  (CUR-004).
- Tests prove unique reconciliation, ambiguity rejection, and rejection of
  unlisted fuzzy text.

**Gap:** confirmed at input time. Reuse the existing matcher’s identity and
safety rules, but do not silently adopt from partial text. A visible candidate
query and explicit selection are missing.

### R2-05 — Date selection has unclear completion (CUR-005)

- Add and Edit each use two compact native `DatePicker` controls.
- Both binding directions call the shared `BillingDateEditState`; interval
  changes also recompute dates.
- Runtime observation and unit/UI tests confirm:
  Start Date derives the first upcoming renewal, and Next Renewal derives one
  preceding cycle.
- Selecting a calendar day leaves the native popover open. The current tests
  assert date values but do not assert a clear Done/Next/commit boundary.

**Gap:** the recurrence logic is complete; task progression and commit
communication are not.

### R2-06 — Chinese memberships lack verified variants (CUR-006)

- JD PLUS, Taobao 88VIP, and Sam’s Club China exist as generic service
  presets.
- All three have zero bundled offers, so none can prefill a verified plan,
  regional price, currency, or channel.
- The exact-offer repository test pins the current offer table and must be
  updated only after official evidence is accepted.

**Gap:** confirmed data gap; pricing facts come from Workstream 2, not this
audit.

### R2-07 — Chinese AI and consumer catalog coverage is thin (CUR-007, CUR-031, CUR-032)

- The shipped snapshot has 106 presets and 30 verified offers.
- All 30 offers are USD (CUR-007).
- Among the requested IDs for 豆包、剪映、即梦、QQ Music, only QQ Music is
  present, and it has no offers (CUR-031).
- Exactly one preset currently defines a non-empty `matchAliases` list
  (CUR-032).

**Gap:** confirmed inventory and evidence gap. The catalog validator is ready
to reject malformed additions, but the data cannot be expanded safely without
official-source research.

### R2-08 — Currency defaults do not consistently follow market (CUR-007, CUR-008, CUR-024)

- Add form initialization uses a default offer’s currency when present and
  otherwise falls back to USD (CUR-008).
- Applying a selected offer replaces plan, amount, currency, and interval with
  that offer’s facts (CUR-024).
- The pinned bundled inventory contains only USD offers and no CNY offer
  (CUR-007), so offer-derived currency cannot yet benefit a Chinese service.

**Gap:** partial. Preserve offer-derived currency. Decide a manual fallback
using product locale/preferences only when there is no selected offer; do not
infer a verified offer’s currency from language.

### R2-09 — AI is not a first-class category (CUR-009, CUR-025, CUR-026)

- ChatGPT, Claude, and Google AI are currently categorized as Productivity
  (CUR-009).
- `CatalogIcon` has no AI-specific case (CUR-025).
- Category IDs are derived from each preset’s English category string instead
  of a separate category registry (CUR-026).

**Gap:** confirmed. Taxonomy and icon representation need one coordinated
change so search, filtering, localization, and display do not diverge.

### R2-10 — Regional product identity is not visible (CUR-010, CUR-027–CUR-030)

- `CatalogOffer` stores `market` and `purchaseChannel` (CUR-027), while
  `CatalogPurchaseChannel` defines only Web and iOS (CUR-028).
- `CatalogPreset` stores one localized service name and category and has no
  explicit product-family or edition field (CUR-029).
- Catalog rows show only service and category, not market, edition, or offer
  availability (CUR-030).
- The pinned Canva preset contains one US yearly Web offer (CUR-010); with the
  current preset schema and row presentation, a 可画 edition is not
  distinguishable.

**Gap:** confirmed representation and presentation gap. Research must choose
between separate regional presets, product family + editions, or another
explicit model before data is added.

### R2-11 — YouTube Premium is represented by Lite only (CUR-011)

- The sole YouTube Premium offer is `Premium Lite`, USD 7.99 monthly, US Web.
- No personal, family, student, annual, channel-specific, or other regional
  offer is represented.

**Gap:** confirmed data gap. Absence is preferable to guessing until first
party evidence is available.

### R2-12 — Upcoming is a range-filtered flat list (CUR-012)

- `UpcomingView` hardcodes Today, Next 30 Days, and Next 90 Days.
- It loads a flat `upcomingTimeline` and renders each item as a navigation
  row.
- The workspace already returns the dated charge items needed to group by
  billing-local day; no new persistence model is required for a calendar
  presentation.
- Existing UI coverage proves a row opens detail, but there is no month,
  empty-day, dense-day, or selected-day-agenda test.

**Gap:** confirmed presentation gap. Calendar research should reuse the
existing timeline as the source of truth.

### R2-13 — No literal external-research marker exists in the pinned product/test tree (CUR-013)

- A literal pinned-tree search for `competitor`, `community`, `open-source`,
  and `open source` returns no matches in product-code or test paths.
- This narrow negative check does not prove that equivalent research is absent
  under every possible vocabulary. R2-13 therefore remains a research
  deliverable supplied by Workstreams 2–4 rather than a product-code defect.

**Gap:** research deliverable, not a product-code defect. Workstreams 2–4
provide this evidence before design.

### R2-14 — Segmented controls have redundant outer boundaries (CUR-014)

- Upcoming places its segmented Date Range picker inside an otherwise empty
  `List` `Section`.
- Insights does the same for Expected/Confirmed.
- The runtime hierarchy therefore gives the control both its own segmented
  boundary and a list-row/section container.
- No visual-regression or hierarchy test protects the desired single-boundary
  result.

**Gap:** confirmed visual hierarchy issue.

## Reuse and Architecture Opportunities

These are implementation-surface observations, not final design decisions.

1. **Keep `SubscriptionWorkspace` and schedule math.** The shared domain seam,
   `BillingDateEditState`, and `BillingDateResolver` are covered by passing
   tests and already satisfy the hard date rules.
2. **Unify Add and Edit draft state.** The two views duplicate service, plan,
   category, interval, custom interval, dates, URL, notes, validation display,
   and date bindings. One reusable form/draft component can support manual
   add, catalog confirmation, and edit without creating another persistence
   abstraction.
3. **Integrate current-price change into ordinary edit.** The existing edit
   command deliberately preserves `originalAmount`; the separate price-change
   command preserves history. The final design should let the person edit the
   current price in the primary form while internally recording the correct
   history command, rather than erasing financial history.
4. **Add a query seam, not a second matcher.** Extend catalog search to
   localized names and explicit aliases, rank transparent candidates, and
   require explicit adoption. Keep exact post-save reconciliation as the
   safety net.
5. **Use offer data for defaults.** Currency and interval adoption already
   work when an offer exists. Catalog expansion unlocks this behavior without
   per-service UI conditionals.
6. **Treat calendar as projection.** Group the existing upcoming timeline by
   day and month. Avoid adding a second schedule store.
7. **Prefer native swipe actions.** The desired staged/full-swipe behavior is
   already delivered in a small amount of SwiftUI code and has regression
   coverage.

## Tests That Encode Superseded Behavior

These tests are useful but their expected interaction will need revision:

- `incompleteMonthlyInputExposesFieldErrors` expects empty plan and category
  to fail.
- `testCreatesMonthlySubscriptionAndOpensItsDetail` always types plan and
  category, so it cannot prove the minimum-record rule.
- `testEditsBillingScheduleAndKeepsItAfterRelaunch` and
  `testEditFormLinksBillingDatesInBothDirections` require Actions → Edit.
- the compact-date helpers prove value changes but not explicit completion or
  focus progression.
- `testUpcomingExpectedChargeOpensItsSubscriptionDetail` covers the flat
  list, not month/day navigation.
- `bundledCatalogPinsExactVerifiedOfferTable` intentionally pins all current
  offers and must change alongside any researched catalog batch.

Tests to preserve unchanged:

- billing date resolver and both-direction linkage tests;
- full-swipe confirmation and archive/restore tests;
- exact/ambiguous catalog matcher tests;
- catalog validation, safe cached updates, library/calendar projection, and
  persistence tests.

## Audit Saturation

The final code/history passes added no new state owner beyond:

- `SubscriptionWorkspace` for domain operations and derived timelines;
- Add/Edit local form state;
- `CatalogSnapshot`/`CatalogOfferMatcher` for catalog search and association;
- `ScopedLibraryView`, `SubscriptionDetailView`, `UpcomingView`, and
  `InsightsView` for the affected presentation.

Every R2 item maps to at least one current file and an existing test or an
explicit missing-test statement. Additional current-code inspection is
unlikely to change the gap classification; the remaining uncertainty is
external product evidence and interaction choice, handled by Workstreams 2–4.
