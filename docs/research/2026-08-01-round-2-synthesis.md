# Round 2 UX and Catalog Synthesis

**Date:** 2026-08-01
**Architecture / UX status:** Approved with conditions incorporated
**Evidence / catalog status:** REVISE — the normalized first-pass manifest
passes structurally; provisional second-pass evidence and the shipping
allowlist remain open pending independent re-audit
**Implementation boundary:** B — thin feature-boundary replacement
**Product priority:** minimum meaningful interaction, maximum useful
information, correctness before catalog breadth

## Decision

The product should keep its existing `Subscription Workspace`, repository,
Fixed Billing Schedule, lifecycle facts, exact catalog reconciliation, offline
catalog, native row actions, widgets, App Intents, EventKit adapter, and
platform design language.

The confirmed UX problems are caused by a small number of duplicated feature
boundaries rather than by a missing application architecture. The approved
change is therefore:

1. one draft value and shared semantic field sections for Add and Edit, while
   retaining context-specific navigation shells;
2. one atomic Workspace command for ordinary edits and price history;
3. one effective-amount resolver used by every consumer;
4. one catalog query seam that is intentionally separate from exact
   reconciliation;
5. one pure Upcoming month/day projection over the existing timeline;
6. one thin native calendar host on iOS/iPadOS, with a native grouped
   month-scoped fallback and a macOS renderer over the same projection.

This is a feature-boundary replacement, not a cosmetic patch. It is also not a
domain rewrite: no TCA/Redux layer, dependency-injection framework, third-party
search engine, third-party calendar, second repository, or runtime
`Service -> Edition -> Offer -> Price` entity graph is approved for this
round.

## Evidence Basis and Limits

The decision uses four evidence classes:

- 32 commit-pinned current-product records and ten current-run screenshots;
- 78 first-pass official catalog records, followed by an 84-record official
  gap pass for volatile and missing providers;
- 59 first-pass competitor/community records plus 52 second-pass community
  signals used as design supplements;
- 18 Apple interaction records plus a supported-OS runtime fixture for
  `UICalendarView`, compact `DatePicker`, narrow width, and accessibility text
  sizes.

The first-pass JSONL corpus is locally parseable, unique by evidence ID, and
hash-checked. Its four fragments are now merged into the normalized durable
187-record manifest documented in
`docs/research/2026-08-01-round-2-manifest-validation.md`; that is a structural
PASS, not approval of its price claims. The 84-record official gap pass,
52-record second community pass, and lightweight-architecture results remain
provisional/design supplements until they have durable manifests and an
independent claim audit. They do not authorize catalog prices.

The official evidence audit remains deliberately conservative. It found that
several provider pages expose historical, promotional, account-dependent,
channel-specific, annual-equivalent, or internally conflicting amounts.
Research breadth therefore increases the number of safe exclusions as well as
the number of selectable offers. Unknown remains unknown.

The architecture may proceed independently of catalog-price closure. R2-06,
R2-07, and R2-11 remain open evidence gates for their incomplete provider
sets. The official evidence audit's `FAIL` status is not converted into a pass
by this UX approval.

## Decision Evidence Matrix

The labels below distinguish observed facts from community signals and design
inferences. An inference is a product decision constrained by evidence, not a
claim that a source prescribed the exact control.

| Decision | Classification | Evidence and treatment |
| --- | --- | --- |
| Plan/category are optional; five save facts remain | Current-product fact plus design decision | Current blocking validator and storage compatibility [CUR-001]. Remove only the optional-field requirement. |
| Row opens a draft-backed editor with explicit Save | Current-product fact, Apple constraint, design inference | Read-only/action depth [CUR-002]; explicit-edit behavior [IOS-009]. Direct destination is the inference. |
| Keep full-swipe Delete -> confirmation | Existing behavior plus Apple fact | Current tested swipe path [CUR-003]; full-swipe mechanics and confirmation [IOS-001] [IOS-004]. |
| Typeahead activation is separate from exact reconciliation | Current-product fact plus Apple-supported inference | Exact matcher safety [CUR-004]; native search suggestions [IOS-010]. |
| Active date task edits one source; trial keeps two facts | Existing domain fact plus interaction inference | Bidirectional date math [CUR-005]; picker/completion evidence [IOS-006–IOS-008]. |
| Month plus mandatory agenda | Current-product gap, platform fact, community-supported inference | Flat range view [CUR-012]; native month mechanics [IOS-012] [IOS-013]; competitor/community corpus [COM-001–COM-059]. Renderer remains fixture-gated. |
| Direct segmented controls without outer decoration | Current visual fact plus Apple guidance | Nested boundaries [CUR-014]; segmented control and material guidance [IOS-014] [IOS-015]. |
| Preserve Workspace and add only thin feature boundaries | Repository/ADR fact plus architecture inference | ADR 0001, current code map [CUR-001–CUR-032], open-source implementations [COM-016–COM-025]. No source mandates the exact Swift types. |
| Catalog prices require exact standard-renewal facts | Official-provider fact and safety policy | Official records [OFF-001–OFF-078], open gates [OFF-011–OFF-015] [OFF-021] [OFF-022], and evidence audit AUD-01–AUD-07. |
| Community findings inform pain points, not control frequency | Research-method constraint | [COM-026–COM-059]; X/小红书 access gaps [COM-058] [COM-059]. |

Before any catalog import, the expanded evidence manifest must merge the
provisional second-pass fragments using the first-pass normalized
`accessed_at`, `verification_date`, excerpt hash, repository SHA, and commit
permalink fields; rerun JSONL parsing, required-field, uniqueness, and hash
checks; and re-open at least 10% of each workstream with every high-volatility
price row included. The research report must retain these `fact`,
`community-signal`, and `design-inference` classifications after merge.

## Global Product Constraints

- The Subscription Library remains authoritative. Calendar is only a
  projection.
- Service Name, price, actual charge currency, Fixed Billing Schedule interval,
  and one billing date are the minimum save facts.
- Plan, category, management URL, and notes are optional metadata and never
  block Save.
- `originalAmount` remains an immutable baseline. Confirmed Charges remain
  immutable historical facts.
- Effective Subscription Status is derived from Subscription Lifecycle; it is
  never edited as a stored enum.
- Start Date is a known paid-period start, not the first-ever purchase date.
- Renewal Anchor remains internal and is never exposed in Add, Edit, or
  user-facing copy.
- A destructive full swipe never deletes immediately. It enters the same named
  permanent-delete confirmation as the partial-swipe action.
- Region, locale, or device settings alone never invent a price, interval, or
  currency. A default must be an independently evidenced fact of the selected
  regional preset or verified offer.
- The runtime catalog never contains authentication tokens, cookies, account
  identifiers, or raw account-context responses.

## Recommended Experience

### 1. Add starts with Browse Catalog

On iPhone, `+` opens Browse Catalog directly. The catalog root contains search,
categories, the existing A-Z index, results, and an explicit Add Manually row.
The root task has one Close/Cancel affordance.

Activating a verified offer or Add Manually pushes the confirmation editor
inside the same task. The child editor has system Back and Save; it does not
also show Cancel. There is no catalog-detail interstitial, management-link
screen, suggested-cycle screen, or “Use This Preset” step.

Back from a clean child exits immediately. Back, interactive dismissal, or row
switching with a dirty draft presents Save, Discard, and Continue Editing as
appropriate. Save is the only persistence boundary. Opening the editor does
not automatically focus the keyboard.

### 2. Catalog offers, service-only presets, and manual entry are distinct

There are three explicit adoption paths:

1. **Verified offer:** activation adopts the evidenced service identity,
   regional edition, plan, exact price, actual charge currency, and interval.
   Activation is the person's explicit acceptance of those defaults.
2. **Service-only or name-only preset:** activation adopts only evidenced
   identity metadata. Price stays empty and the editor says “Price Required.”
   A separately evidenced default currency may be adopted by this activation;
   interval and date remain unselected unless independently verified.
3. **Manual entry:** no price, currency, interval, date, plan, or category is
   silently invented. The person supplies the five minimum facts and may leave
   optional metadata empty.

The service field provides a bounded list of deterministic localized-name,
alias, and prefix candidates. Selecting a candidate performs one visible
adoption update. Highlighting, typing, saving, or a fuzzy similarity score
never silently attaches identity.

Query and exact reconciliation share normalized catalog data but not decision
semantics:

- query ranks visible candidates and always permits manual continuation;
- exact reconciliation keeps its current `none / unique / ambiguous` behavior
  and requires exact identity, amount, currency, and interval facts.

If the person changes an adopted service name so it no longer exactly matches
the preset's formal localized name or aliases, Save replaces the stale
`catalog:*` Service Identity with a manual identity. Changing only price or
interval retains the catalog Service Identity. No new persisted override flags
or offer entity are needed: after reload, the editor derives “User-adjusted
price” or “User-adjusted schedule” by comparing the tracked facts with the
current preset's exact verified offers. Draft preset/offer IDs are task-local
selection state only. Core tests cover stale-name clearing; UI tests cover the
derived override marker after relaunch.

### 3. Required and optional fields

The minimum save facts are:

- Service Name;
- next-charge price;
- actual charge currency;
- positive Fixed Billing Schedule interval;
- either Start Date or Confirmed Next Renewal.

Plan, category, management URL, and notes are optional. Known values appear
compactly; missing optional values live under an Additional Details disclosure
and do not occupy the first screen.

For a selected Chinese regional offer, CNY is prefilled only when official
evidence binds that offer to CNY. For a selected US ChatGPT offer, USD is
prefilled because the offer evidence binds the price to USD. All adopted
currencies remain editable.

### 4. Tapping a subscription opens an editor

On compact iPhone layouts, a current Library row, Archived Library row,
Upcoming agenda row, or subscription deep link routes to the same editable
destination. There is no read-only Detail -> Actions -> Edit sequence and no
unlabeled top-right chevron.

The first screen preserves the current detail page's scanability. It shows:

- Service Name and known plan;
- effective next-charge amount and actual charge currency;
- interval;
- selected source date and derived counterpart;
- derived Effective Subscription Status;
- next charge;
- compact recent-history context when it exists.

Optional empty metadata is disclosed below the primary facts. Save on iPhone
commits atomically and returns to the source surface. Upcoming restores the
previous month and selected day.

Catalog-backed confirmation shows a compact provenance row without adding a
new screen: edition/market, purchase channel, and verification date are
visible under the adopted offer, with the official source link in Additional
Details. A saved catalog-backed editor shows the same regional identity and a
derived user-override marker when applicable. Service-only results show
edition/market plus Price Required and never display invented offer provenance.

On iPad and macOS, the selected row may remain visible beside the editor. A
single pending-selection coordinator handles dirty changes:

- clean draft: select immediately;
- dirty draft: keep the current editor and ask Save, Discard, or Cancel;
- Save or Discard: then commit the pending selection;
- Save failure or Cancel: keep the current selection and draft.

Archived rows open the same editor with an Archived status treatment. Restore
and permanent delete remain row/context/keyboard actions rather than editor
commands.

### 5. Lifecycle and history have semantic homes

The catch-all Actions menu is removed only after every retained capability has
another meaningful home:

- ordinary facts are directly editable;
- changing price automatically records price history;
- Effective Subscription Status is read-only;
- Recorded Cancellation and Reactivation live in a Lifecycle section and keep
  their existing fact-specific forms and Workspace commands;
- price and charge history is read-only and disclosed only when records exist;
- Archive, Restore, Pin, and permanent Delete remain row actions;
- In the final state, Confirm Charge appears on an Upcoming agenda item only
  when the occurrence is expected, not yet confirmed, and its scheduled date
  is today or earlier.

The current timeline clamps expected charges to today, so past-month
confirmation is not yet available. Batch B must add a range-aware month query
that emits an unconfirmed expected occurrence inside a requested past month,
then replaces it with the Confirmed Charge representation after confirmation.
A two-month-old unconfirmed occurrence is the required tracer test. Future
expected occurrences never show Confirm Charge.

Until that query and past-month agenda pass their tests, Batch A keeps one
temporary, labeled Confirm Charge entry in the editor's Payment History
section. The catch-all Actions menu may be removed, but the temporary entry is
removed only after the Batch B agenda becomes the proven replacement.

### 6. Active billing dates use one source and one derived counterpart

For an active subscription, interval plus either visible date determines the
other:

- editing Start Date derives the first recurrence strictly after today as
  Confirmed Next Renewal;
- editing Confirmed Next Renewal derives the preceding Start Date and internal
  Renewal Anchor.

The person may edit either field, but only the field they activated is the
source for that date task. The other updates immediately and remains visibly
derived. There is no mandatory Start -> Next sequence for active
subscriptions.

The date task uses an editor-local snapshot:

1. open the localized graphical/native date surface;
2. select a day and immediately see both draft values;
3. Done commits the date task to the editor draft;
4. Cancel restores the task-entry snapshot;
5. form Save persists the whole subscription.

Tapping blank space is never a commit action. A trial is different: Trial
Start and First Paid Charge are independent required facts and may use an
explicit Next step. Month-end, leap-year, time-zone, and local-noon behavior
continue to use the existing Fixed Billing Schedule rules.

### 7. Upcoming becomes month plus agenda

Today / 30 Days / 90 Days is removed rather than merely restyled. Upcoming
contains:

- a navigable month;
- lightweight charge markers or counts on days;
- a selected-day agenda with service, amount, currency, and expected/confirmed
  state;
- an explicit empty-day state and a small next-charge cue;
- direct navigation from an agenda row to the editor.

Today is initially selected even when it has no charge. The interface never
silently selects another day and describes it as today.

`UpcomingCalendarProjection` is a pure grouping of
`[UpcomingTimelineItem]` by billing-local date components. It preserves
`subscriptionID`, amount, currency, and expected/confirmed kind. It owns no
persistence and performs no recurrence arithmetic.

The Workspace query feeding that projection is month-range aware. Unlike the
current forward forecast, it may generate scheduled occurrences in a requested
past month, excludes occurrences already represented by a Confirmed Charge,
and respects lifecycle/cancellation boundaries. The existing
`confirmCharge(id:scheduledDate:chargedDate:amount:)` command remains the
mutation seam.

`CalendarProjectionEvent` remains an EventKit/ICS transport value and is not
reused as the Upcoming model.

On iOS/iPadOS, a thin `UICalendarView` host consumes the pure projection. Day
cells never attempt to carry full service semantics; the selected-day agenda
is mandatory. Production does not hard-code 336 points as a threshold. It
measures the container and tests intermediate widths between the observed
280-point failure and 336-point success. When the native month cannot fit,
including accessibility-size layouts, the surface switches to a month-scoped
grouped list that preserves month navigation and day distribution.

macOS consumes the same projection through a native month-scoped grouped list
first. Keyboard navigation, focus rings, localization, and later month-grid
enhancement are platform-specific presentation details, not a second store.

### 8. Row actions and non-gesture parity

Current row semantics remain:

- leading swipe: Pin/Unpin;
- trailing partial swipe: Delete plus Archive, or Delete plus Restore in the
  Archived Library;
- trailing full swipe: Delete -> named permanent-delete confirmation.

The confirmation uses Service Name without empty parentheses and describes
the irreversible removal of history. Cancel changes nothing.

Core actions also receive labeled VoiceOver custom actions on iOS and
context-menu/keyboard access on iPad and macOS. Existing Mac commands remain
the starting point and are not duplicated.

### 9. Visual simplification

Controls that already provide their own boundary are not placed inside a
second decorative pill or Section solely for decoration. Insights keeps its
Expected/Confirmed segmented control directly; long localized labels and
narrow widths may fall back to a Menu. Upcoming's range control is deleted.

The current typography, rows, native materials, color roles, spacing rhythm,
catalog presentation, and system icons remain the design system. This round
does not introduce a new brand, logo, custom icon family, or custom navigation
language.

## Minimum Technical Design

### Shared draft, separate shells

Use one value-type `SubscriptionDraft` and pure validation policy for shared
facts. Add retains catalog/verified-offer state; Edit retains existing
lifecycle/history context. Shared billing, schedule, and optional-details
sections render the same behavior without creating one conditional mega-view.

The draft and one route/dirty coordinator are the only new mutable feature
state owners. The Workspace remains the command and observable-state seam.

### Atomic amount and ordinary edit

Introduce one public pure resolver:

```swift
func amount(onBillingDay date: Date) -> Money
```

It returns the last Price Change effective on or before the billing-local day,
or `originalAmount` when none exists.

The atomic edit command follows this sequence:

1. validate and derive the final Fixed Billing Schedule;
2. compute `finalNextRenewal`;
3. compare the draft amount with
   `amount(onBillingDay: finalNextRenewal)`;
4. when changed, write a Price Change effective on `finalNextRenewal`;
5. when the same billing-local day already has a Price Change, replace it as a
   correction rather than creating a duplicate;
6. persist ordinary facts and the resulting price timeline in one repository
   transaction;
7. refresh requested Workspace consumers only after success.

`originalAmount` does not change. A failed save publishes validation or
persistence failure without partially changing history or selection.

The same batch migrates Library summaries, sorting, Detail/editor display,
Insights, exchange-rate quote discovery, widgets, menu-bar presentation,
App Intents, catalog reconciliation, Upcoming, and EventKit projection to the
single resolver. A mixed old/new amount interpretation is not an acceptable
intermediate state.

### Catalog runtime and evidence store

The shipping `CatalogSnapshot` remains a compact offline runtime value. A
`CatalogPreset` represents one searchable regional edition and owns its exact
offers. Add only fields with an active runtime consumer:

- stable category ID, including `ai`;
- optional family ID used only for search/display association;
- market/region and edition label;
- localized names and aliases;
- exact offers with market, purchase channel, review status, source reference,
  and verification date;
- optional independently evidenced default currency.

Raw provider responses, competing observations, detailed audit metadata, and
content-addressed snapshots remain in a separate research/evidence store. Raw
responses are sanitized before persistence. Runtime update packages never
contain tokens, cookies, account identifiers, or unused evidence fields.

Promotional phases, tax calculation, proration, usage billing, checkout IDs,
and a first-class regional-product entity remain deferred until a shipping
consumer requires them. Promotional or annual-equivalent values are not
misrepresented as standard recurring offers.

## Catalog Shipping Decisions

### Conditionally selectable after evidence-gate repair

The following examples are second-pass candidates, not approved shipping data.
They may move to the selectable allowlist only after a durable first-party
record proves exact charged amount/currency/cadence and standard-renewal
semantics, the sanitized raw response is content-addressed, and an independent
re-audit passes:

- ChatGPT Go, Plus, Pro 5x, and Pro 20x as offers under the ChatGPT service;
- 豆包 Standard/Enhanced/Advanced monthly and annual offers;
- 微信读书 CNY 19 monthly;
- YouTube Premium Individual US iOS USD 20.99 monthly;
- Apple Music Family and Student;
- MiniMax verified recurring tiers;
- 讯飞星火 standard recurring tiers;
- Coze High/Flagship recurring tiers;
- exact standard-renewal offers for Runway, ElevenLabs, Ideogram, HeyGen, and
  Leonardo;
- corrected iCloud+, Microsoft 365, Xbox Game Pass, and PlayStation Plus
  records.

Offer labels preserve market, purchase channel, tax/seat/eligibility caveats,
and charged cadence. A web price never inherits an iOS channel label, and an
iOS amount never becomes a universal provider price.

### Conflict or review queue

These remain non-selectable until an authority/recency rule and complete
charged cadence resolve the conflict:

- Apple Music Individual;
- Canva 可画 annual offers; monthly observations require split, normalized
  evidence and an independent audit before selection;
- 智谱清言 conflicting commerce and developer copy;
- QQ Music Super Member;
- WeChat Reading annual;
- ambiguous YouTube variants and Family cadence;
- Calm, Duolingo, Strava, and other ambiguous IAP mappings.

### Service-only or lead-only

These may be searchable identities but must say Price Required:

- 88VIP;
- JD PLUS;
- Sam's Club China;
- Tencent Yuanbao;
- Kimi observations whose labels or continuous-renewal semantics remain
  unproved, and any 秘塔 observations that have not passed the normalized
  OGD allowlist audit; only audited exact offers may move to the conditional
  selectable group;
- Qwen, Wenxin, Gamma, and unsupported Suno annual equivalents;
- unverified YouTube regional/web variants.

The historical CNY 888 88VIP amount, eligibility-bound CNY 88 promotion, a
commonly remembered JD CNY 99 amount, and remembered Sam's Club prices are not
shipping defaults without current first-party evidence.

## Multi-Currency Rule

Each subscription stores its actual charge currency. A later display/reporting
currency is a separate preference and uses one dated exchange-rate resolver.
Until reliable conversion exists, Insights and calendar totals group by
currency. They never add unrelated currency numbers or change only the symbol.

This round must already prevent cross-currency direct addition even if the
full display-currency setting ships in a later batch.

## Interaction Budget

Counting uses:

- `A`: activation or gesture, including scrolling and keyboard dismissal;
- `F`: focused field plus entered value;
- `T`: task-surface transition.

A prefilled date counts as accepted only after explicit acceptance.

| Scenario | Current baseline | Approved target | Recovery and information |
| --- | --- | --- | --- |
| S1 verified ChatGPT | `3A + 1F / 3T`, but the default date is not explicitly accepted | `<=6A + 1F / <=3T` | Service, edition, offer, exact amount/currency/interval, both dates, and provenance are visible; person can change offer or continue manually. |
| S2 unknown service | Surface path `4A + 2F / 2T`, then Save is blocked by plan/category | `<=8A + 2F / <=3T` | Minimum facts save; optional metadata remains empty; validation keeps the draft. |
| S3 edit facts | Unavailable; `3A / 3T` before editing and no amount/currency fields | `2A + changed inputs / 1T`; date edit adds `3A / 1T` | Direct editor, atomic Save, dirty Back recovery, current effective price/history visible. |
| S4 archive | `2A / 0T` | preserve `2A / 0T` | Archived surface retains data; non-gesture alternative exists. |
| S5 delete | `2A / 1T` full-swipe path | preserve `2A / 1T` | Named confirmation; Cancel changes nothing; no direct full-swipe deletion. |
| S6 inspect Upcoming | `3A / 2T`, no month/day distribution | `3A / 1T`; month move `+1A` | Month distribution plus selected-day agenda; empty day, dense day, and fallback paths specified. |
| S7 enter dates | `4A` when one edit derives both; `7A` when both edited; no completion feedback | `3A / 1T` to editor draft, then `+1A` form Save | Active source field, derived counterpart, Done/Cancel, no arbitrary tap-outside commit. |
| S8 match `88` | Unavailable after `2A + 1F / 2T` | from open editor `1F + 1A / 0T` | Candidate shows region and verified facts or Price Required; typed text remains on rejection. |

The target does not win by activation count alone. It must also improve
first-screen information, state clarity, failure recovery, and accessibility.

## Platform and Accessibility Release Gates

- iPhone compact and plus-size layouts in Simplified Chinese and English;
- real iPad split configurations, including widths between 280 and 336 points;
- default Dynamic Type through accessibility XXXL;
- VoiceOver calendar selection -> selected-day agenda reading order;
- localized date/count/selection speech in the product bundle;
- VoiceOver custom row actions and equivalent context/keyboard paths;
- macOS dirty selection, keyboard focus, context actions, and month-scoped
  Upcoming list;
- empty today, dense day, past-month Confirm Charge, month movement, and
  fallback layout;
- right-to-left layout where system controls support it;
- non-Gregorian Calendar identifiers for date derivation and month grouping;
- Reduce Motion, Reduce Transparency, and Increased Contrast;
- manual VoiceOver verification of selected-day state and localized
  day/count/selection speech;
- no optional metadata or off-screen validation blocks Save unexpectedly.

## Implementation Batches and Complexity Guardrails

### Batch A — direct editor, atomic amount, dates, and action relocation

This is a feature-boundary replacement. Expected surface: 10-16 production
and test files. New mutable owners are limited to `SubscriptionDraft` and one
route/dirty coordinator. New custom visual controls: zero. The batch should
delete the read-only-first and duplicate action paths while preserving
lifecycle commands.

If Batch A requires more than two new mutable state owners, more than one new
persistence command family, or more than roughly 500 net new non-test lines
without deleting an equivalent duplicate surface, implementation pauses for
architecture review.

Acceptance: S2 saves without optional metadata; S3 edits price/currency/
interval/date through one Save and one repository update; S4/S5 retain their
current gesture budgets; S7 has explicit Done/Cancel; stale catalog identity
clears on rename; price/interval overrides remain visibly derived after
relaunch; the temporary Payment History Confirm Charge route remains reachable.
Evidence artifacts: focused test logs plus current-run Add/Edit/date/lifecycle/
swipe screenshots under `docs/research/evidence/screenshots/round-2-batch-a/`.

### Batch B — Upcoming month plus agenda

Expected surface: 4-7 production and test files. New core type:
`UpcomingCalendarProjection`. New platform bridge: one
`UICalendarView` host. No new store, recurrence engine, or EventKit coupling.

If the iOS implementation needs both a UIKit bridge and a separate custom
SwiftUI grid, or exceeds roughly 700 net new non-test lines before macOS and
accessibility behavior pass, the renderer choice is re-reviewed.

Acceptance: month navigation, empty today, dense day, selected-day agenda,
two-month-old unconfirmed occurrence, confirmation replacement, multi-currency
separation, intermediate widths, AX XXXL fallback, zh-Hans VoiceOver, and the
macOS month-scoped list all pass. Only then is the temporary editor Confirm
Charge entry removed. Evidence artifacts live under
`docs/research/evidence/screenshots/round-2-batch-b/` with accessibility-tree
exports and fixture logs beside them.

### Batch C — catalog assistance and audited offer batch

Expected surface: 6-10 production/test files plus catalog data and evidence
artifacts. Runtime catalog and evidence store remain separate. There is no new
persistent catalog store and no first-class three-entity runtime graph.

Prices cannot enter this batch until OFF/OGD records are normalized, OFF-015
is corrected, complete sanitized response snapshots are retained, conflict
authority rules are documented, and an independent audit approves the exact
allowlist.

Acceptance: verified offer, service-only Price Required, ambiguous result,
manual continuation, alias activation, stale-name identity clearing,
user-override derivation, regional currency adoption, keyboard/VoiceOver
suggestion activation, offline snapshot fallback, and the exact matcher's
`none / unique / ambiguous` behavior pass. The normalized allowlist and its
independent audit are versioned evidence artifacts, not runtime raw responses.

### Batch D — display currency and complete platform/accessibility polish

Actual charge currency remains authoritative. Display-currency conversion is
added only with dated rates and explicit missing-rate behavior. Cross-currency
direct addition is prohibited before this batch as well as after it.

Acceptance: actual charge currency is unchanged by display preference; no
cross-currency direct sum is rendered; dated-rate conversion, missing/stale
rate behavior, Widget/App Intent/menu-bar consistency, and locale formatting
pass in unit and UI tests.

## Requirement Traceability

| Requirement | Approved response |
| --- | --- |
| R2-01 | Plan/category/URL/notes optional; five minimum facts retained. |
| R2-02 | Library, Archived, Upcoming, and deep links route to direct editor. |
| R2-03 | Catch-all menu removed only after semantic relocation; row actions remain external. |
| R2-04 | Bounded explicit typeahead over catalog; exact reconciliation remains separate. |
| R2-05 | Local date task with source/derived semantics and explicit Done/Cancel. |
| R2-06 | **OPEN evidence gate:** 88VIP/JD PLUS/Sam's remain service-only until current regional variants and exact prices pass first-party audit. [OFF-011–OFF-014] |
| R2-07 | **OPEN by affected offer:** AI/creation/ByteDance/Tencent expansion imports only an independently audited standard-renewal allowlist. [OFF-015–OFF-078] |
| R2-08 | Offer-bound default currency; actual and display currencies separated. |
| R2-09 | Stable `ai` category ID and localized AI category. |
| R2-10 | Regional editions are distinct presets with optional family association. |
| R2-11 | **OPEN evidence gate:** only audited US iOS Individual may ship now; Family, Student, Lite, two-person, annual, web, and other regions remain unresolved. [CUR-011] [OFF-021] [OFF-022] [OFF-077] |
| R2-12 | Range controls replaced by month plus mandatory selected-day agenda. |
| R2-13 | Research input is broad but manifest closure remains OPEN. Reuse native Form/swipes/calendar primitives [IOS-001–IOS-015]; adapt month+agenda and compact forms [COM-016–COM-025]; reject custom/fuzzy identity and over-scoped calendars [CUR-004] [IOS-016–IOS-018]; community frequency claims remain bounded [COM-026–COM-059]. |
| R2-14 | Redundant outer control containers removed; preserved controls receive narrow-width fallbacks. |

## Final Review Resolution

The independent unified-synthesis review returned `APPROVE WITH CONDITIONS`.
Its remaining conditions are incorporated here:

1. past-month navigation preserves Confirm Charge for overdue occurrences;
2. Archived rows route to the same editor while Restore/Delete remain external;
3. editing an adopted service name clears stale catalog identity, while
   price/interval overrides retain identity visibly;
4. raw evidence snapshots remain outside the runtime catalog and are sanitized.

No unresolved design ambiguity blocks the corrected Batch A implementation
plan. Evidence/catalog completion remains separately `REVISE — open` until
the normalized manifest, AUD-01–AUD-07 corrections, required recheck, and
independent re-audit pass.
