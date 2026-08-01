# Round 2 Architecture and UX Challenge Review

**Review date:** 2026-07-31
**Reviewer role:** Independent architecture / UX challenger
**Verdict:** **REVISE**
**Scope:** Research recommendations and design boundaries only; no product
implementation is authorized by this review.

## Executive Verdict

The evidence is broad enough to choose a product direction. The central
direction is sound:

- edit through one explicit-save draft instead of read-only Detail → Actions →
  Edit;
- keep `SubscriptionWorkspace`, the existing recurrence rules, the
  Subscription Library source of truth, and native row actions;
- use one catalog snapshot for Browse, inline assistance, verified defaults,
  and later reconciliation;
- replace the range-filtered Upcoming presentation with a month overview plus
  an information-rich day agenda;
- remove decorative containers around controls that already have a boundary.

The current recommendation layer is **not yet internally safe enough to
approve unchanged**. It should be revised in six places:

1. **Preserve the existing full-swipe Delete → named confirmation behavior.**
   The Apple evidence explains which action full swipe invokes; it does not
   establish that Archive is more frequent than Delete. Reordering the actions
   would contradict the explicitly requested behavior and regress the already
   tested S5 path without supporting usage evidence. [CUR-003] [IOS-001]
   [IOS-004]
2. **Do not force an active subscription through two date steps.** Interval
   plus either Start Date or Next Renewal already determines the other value.
   A second required selection or automatic advance is extra work. Two
   independent dates are justified only for a trial: Trial Start and First
   Paid Charge. [CUR-005] [IOS-006] [IOS-007]
3. **Price editing needs one atomic domain command and one amount resolver.**
   Merely adding amount/currency fields to the current edit view would split a
   save across ordinary edit and `recordPriceChange`, and several current
   projections would continue displaying `originalAmount`.
4. **Do not introduce `Service → RegionalProduct → Offer` as three runtime
   entities yet.** The current `CatalogPreset` can be treated as the
   user-selectable regional product. Separate regional presets plus an
   optional family key and the existing offer collection satisfy the proven
   cases with less decoding, validation, migration, and UI state.
5. **Approve the month/day projection, not the renderer choice yet.**
   `UICalendarView` VoiceOver semantics, accessibility-size layout, and narrow
   split-view behavior remain untested. The research itself names these as
   fixture gaps. [IOS-012] [IOS-013]
6. **Do not claim R2-06 or the full R2-11 complete.** Current first-party
   evidence does not verify the requested 88VIP/JD PLUS/Sam's prices or most
   YouTube web variants. Those are mandatory research gates, not fields to
   fill from memory or third-party articles. [OFF-011] [OFF-013] [OFF-014]
   [OFF-021]

This is a revision of the proposed design boundary, not a rejection of the
research. No additional undirected competitor collection is needed before
design. The remaining research should be targeted at the explicit gaps below.

## Evidence Weight

The review applies the following hierarchy:

1. Current code and unchanged runtime establish what already exists.
2. Apple documentation establishes platform mechanics and constraints.
3. Official provider/store evidence establishes catalog facts.
4. Source-pinned repositories demonstrate possible implementations, not a
   product mandate.
5. Community reports establish pain points and vocabulary, not control
   selection or frequency.
6. A recommendation that is not directly established by those sources is
   labeled a design inference.

The strongest repeated findings are catalog-assisted entry, manual escape,
central recurrence, explicit destructive confirmation, month plus agenda, and
keeping unknown values unknown. The evidence is weaker for exact proprietary
edit behavior, archive-versus-delete frequency, and a particular calendar
renderer. [COM-001–COM-059] [IOS-001–IOS-018]

## Three Possible Design Boundaries

| Boundary | What changes | State/code surface | UX result | Decision |
| --- | --- | --- | --- | --- |
| **A — Patch current screens** | Make plan/category optional; add price fields to `EditSubscriptionView`; add typeahead and a calendar beside existing Detail/menu/range list | Lowest initial diff, but retains separate Add/Edit state, two price commands, and duplicated navigation | Fixes individual symptoms while preserving the hierarchy that caused them | **Reject** |
| **B — Thin feature-boundary replacement** | One draft-backed editor, one atomic workspace save, one catalog query seam, one amount timeline resolver, and one Upcoming month/day projection; preserve repository, lifecycle, recurrence, swipes, and exact reconciliation | Moderate and bounded; replaces feature state owners without replacing the domain | Fewest meaningful operations with explicit Save, history safety, and no second schedule/catalog store | **Recommend** |
| **C — Full domain redesign** | New `Service → RegionalProduct → Offer` graph, new catalog persistence/update pipeline, redesigned lifecycle/history, and custom cross-platform calendar | Largest migration and test surface; several fields have no current UI consumer | Potentially elegant long term, but solves unproven future requirements and delays the confirmed friction | **Defer** |

Boundary B is the smallest architecture that fixes the root state problems. It
is not a cosmetic patch, but it also does not replace stable domain behavior
merely because a larger model is possible.

## Minimum Architecture Recommendation

### 1. One editor draft, two presentation shells

Use one `SubscriptionDraft` and one set of field sections for manual Add,
catalog-backed confirmation, and Edit. The draft owns:

- service text and optional explicit catalog selection;
- plan and category as optional strings;
- desired next-charge amount and currency;
- billing interval;
- lifecycle-aware billing dates;
- optional management URL and notes;
- dirty state and validation state.

The shared field content must not force identical navigation chrome:

- **Add:** modal/root task with exactly `Cancel` and `Save`.
- **Edit from a library or agenda row:** pushed editable destination with the
  system `Back` affordance and `Save`; do not also show `Cancel`.
- Back with a clean draft exits immediately.
- Back/dismiss with a dirty draft asks to discard or continue editing.
- Save is the only persistence boundary.

This removes the duplicate Back/Cancel problem while retaining an explicit
commit. “Directly editable” must not be interpreted as per-field autosave.
Autosave would make linked dates, price history, validation, and partial
persistence harder to explain and recover. [IOS-009]

The ordinary facts should be visible before secondary navigation: service,
plan when known, next-charge amount/currency, interval, Start Date, Next
Renewal, status, and next charge. Plan/category/URL/notes never block Save.

Do not build one giant view. Share the draft and small semantic form sections;
keep Add/Edit containers and platform toolbar placement separate.

### 2. One atomic save for ordinary facts and price history

Current code has an important inconsistency:

- `SubscriptionSummary`, library rows, amount sorting, Detail, and the price
  change form read `originalAmount`;
- expected charges and exact catalog reconciliation separately derive an
  amount from `priceChanges`.

Adding editable price/currency without correcting that split can successfully
record history while still showing the old price in prominent UI.
The relevant current paths are
`SubscriptionCore.swift:203-220, 519-526, 825, 2571-2576`,
`CatalogOfferMatcher.swift:148-159`, `SubscriptionRow.swift:22`, and
`SubscriptionDetailView.swift:330`.

Introduce one pure domain operation:

```text
Subscription.amount(onBillingDay:)
```

It returns the last effective `PriceChange.amount` on or before the billing
day, otherwise `originalAmount`. Expected charges, catalog reconciliation,
summary/detail presentation, sorting, insights, exchange-rate quote discovery,
widgets, and the editor must use this same operation.

The editor should show the amount of the next scheduled charge, because that
is the decision-relevant recurring price. On Save:

1. validate and derive the final schedule;
2. compare the draft amount with `amount(on: finalNextRenewal)`;
3. when changed, append a `PriceChange` effective on the final Next Renewal;
4. if a price change already exists on that billing-local day, replace it as
   a correction instead of rejecting an ordinary same-day re-edit;
5. persist normal edits and the resulting price timeline with one repository
   update.

`originalAmount` remains the immutable baseline; confirmed charges remain
immutable facts. The ordinary editor does not ask for an effective date.
Historical/future-dated price-event editing can remain a later advanced
history capability.

This command must be atomic. Calling `editSubscription` and then
`recordPriceChange` is rejected because either half can fail.

### 3. One catalog source, two different matching operations

Browse Catalog and inline service assistance should query the same immutable
catalog snapshot. That does **not** mean partial search and exact association
should be one matcher:

- **Query:** ranks explicit localized names and aliases for display. A partial
  prefix/token such as `88` may return several visible candidates.
- **Exact reconciliation:** requires exact normalized identity plus amount,
  currency, and interval, and keeps its current `none / unique / ambiguous`
  safety behavior. [CUR-004]

Share normalization and index data, not decision semantics. Extending
`CatalogOfferMatcher.match` to fuzzy partial text would weaken its proven
safety contract.

The explicit selection lives in the draft as a preset ID and optional offer
ID. Selecting a result adopts facts in one reducer-like update. Editing the
service identity afterward clears the explicit selection; overriding price or
interval keeps the service identity but visibly marks the charge as a person
override.

Preserve both entry paths:

- `+` continues to open Browse Catalog, as already requested and implemented;
- “Add Manually” opens the same editor, where typing provides inline catalog
  assistance.

The competitive report's inference that inline matching should replace the
catalog entry surface is not strong enough to undo the established Browse
flow. One catalog query API can serve both without maintaining two indexes.

Inline results should be bounded (for example, the best 5–8) and show:

- regional product name;
- market/edition;
- plan and price/currency/interval when verified;
- “price required” when only the service or plan identity is verified.

Activation, not highlighting, adopts a result. No-match and service-only
results never block manual entry.

### 4. Treat `CatalogPreset` as the regional product for now

The full three-level catalog proposal is conceptually valid but premature.
The proven cases can be represented with a smaller additive change:

```text
CatalogPreset (one searchable regional edition)
  id
  optional familyID
  marketCode / edition label
  localized names + aliases
  stable categoryID
  management URL
  offers[]

CatalogOffer
  plan
  market/channel
  exact charge + currency + interval
  source URL + verified date + review state
```

Examples:

- `canva-international` and `canva-cn` are separate presets with
  `familyID = canva`;
- CapCut and 剪映 remain separate product identities even if the provider
  relationship is recorded in research metadata;
- YouTube variants within one market/channel remain offers under the
  corresponding regional preset;
- 88VIP, JD PLUS, and Sam's may remain searchable regional presets without a
  selectable price until official evidence is complete.

This gives search one family association without adding another decoded
collection, another ID join, and another selection level. Promote
`RegionalProduct` to a first-class runtime type only when a demonstrated
consumer needs independent regional-product lifecycle, shared management
metadata across catalogs, or update semantics that cannot be expressed by
separate presets.

Add a stable category identifier now; localized free-text category strings
should no longer define identity. `ai` becomes a first-class category and
icon. Category remains optional on a tracked manual subscription.

Do not copy every research field into the shipping runtime schema. Promotion,
tax, volatility, quote, and annual-equivalent details remain in the evidence
and review pipeline until a UI or validator consumes them. The first shipping
batch should contain exact standard recurring charges only. “From,”
annual-equivalent-only, conflicting, eligibility-sensitive, quote, and
non-renewing prices are not selectable defaults.

### 5. One active billing date input; two visible results

For an active subscription, interval plus one selected date is sufficient:

- editing Start Date derives the first recurrence after today as Next Renewal;
- editing Next Renewal derives the preceding Start Date;
- both values remain visible in the draft.

Therefore the focused date task should edit the field the person tapped:

1. open a native localized graphical date surface;
2. selecting a day immediately updates both draft values;
3. `Done` closes the date task;
4. form `Save` persists.

There is no automatic Start → Next transition for an active subscription,
because Next is no longer unfinished. An explicit second edit remains
available if the person chooses the other field.

A trial is different: Trial Start and First Paid Charge are independent.
Only that state may use `Next` to move between two required date facts. This
preserves the domain vocabulary and avoids pretending a trial date can be
derived from the paid interval.

Cancel in the date task restores its entry snapshot. Tapping blank space is
never a commit or persistence action.

### 6. Calendar replaces the range controls; agenda complements the calendar

Within Upcoming:

- remove Today / 30 Days / 90 Days;
- show a navigable month;
- select a day to update an agenda in the same surface;
- activate an agenda row to open the direct editor.

This is a replacement of the old Upcoming controls and flat range view. It is
not a replacement of the Subscription Library, and it should not add a new
Calendar/List segmented mode in this round. The Library already provides the
authoritative subscription list. Another mode toggle adds state and recreates
the visual/control hierarchy being removed.

The agenda is not optional. A seven-column day cell cannot safely show
service, amount, currency, expected/confirmed state, and several charges.
Cells show only a marker or count; the agenda shows full rows. Multiple
currencies must not be summed into a misleading day total unless an explicit,
dated conversion policy is active.

Default the selection to today, not silently to the nearest charged day. If
today is empty, show an explicit empty state and a small “next charge” cue.
Automatically selecting another date creates hidden state and can make the
calendar appear to describe today when it does not.

`UpcomingCalendarProjection` is a pure grouping of the existing timeline by
billing-local `DateComponents`. It owns no persistence and performs no
recurrence arithmetic.

Renderer approval remains conditional:

- first test `UICalendarView` with the three named runtime fixtures;
- use it on iPhone/iPad if VoiceOver, narrow split width, and accessibility
  size pass;
- evaluate HorizonCalendar only if the native fixture fails a required
  behavior;
- do not build both a UIKit wrapper and a custom SwiftUI iOS grid in parallel;
- adapt macOS from the same projection after the iPhone interaction is
  validated, rather than inventing a second calendar domain model.

### 7. Keep current swipe semantics and add non-gesture parity

Keep the current mapping:

- leading full swipe: Pin/Unpin;
- trailing partial swipe: Delete and Archive/Restore;
- trailing full swipe: request permanent deletion;
- deletion completes only after a named irreversible confirmation.

The full swipe does not itself delete data. It enters the same confirmation
boundary as tapping Delete, so the irreversible operation remains two
deliberate activations. [CUR-003] [IOS-004]

The Archive-first recommendation assumes Archive is the common operation, but
no competitor, community, or runtime evidence establishes that frequency.
Changing it would make S5 slower and silently change an interaction the person
explicitly requested and has already accepted.

Before removing the current catch-all detail menu, provide equivalent
non-gesture access:

- labeled VoiceOver custom actions on iOS;
- row context actions and keyboard commands on iPad/macOS;
- Archive and Delete remain absent from the editor itself.

Relocate the other commands by meaning, not into a new overflow:

- current price is an ordinary editor field and produces history at Save;
- Confirm Charge belongs on an eligible Upcoming/history row;
- recorded cancellation/reactivation belongs in a clearly labeled lifecycle
  section;
- payment history is read-only information below the ordinary fields.

Do not delete existing domain behavior merely to remove the menu. Remove the
menu only in the same batch that gives each retained behavior a semantic home.

## S1–S8 Interaction Budget

Counts follow the approved protocol. `A` is a non-text activation or completed
gesture, `F` is a focused field plus entered value, and `T` is a task-surface
transition. Counts include required date commitment; changing an already
correct verified offer adds one activation.

| Scenario | Target primary path | Budget | Information before secondary navigation | Recovery / safety |
| --- | --- | ---: | --- | --- |
| **S1 — Add verified known service** | `+` → search → verified result → one-date task → Done → Save | **≤6A + 1F / ≤3T**; +1A if changing the default offer | Regional service, selected plan, exact price/currency/interval, both derived dates, provenance | Change offer or continue manually; no silent identity adoption |
| **S2 — Add unknown service** | `+` → Add Manually → minimum fields → one-date task → Done → Save | **≤8A + 2F / ≤3T** | Service, price, currency, interval, Start and derived Next; plan/category may remain empty | No-match does not block; inline validation keeps draft |
| **S3 — Edit subscription** | row → editable draft → Save | **2A + changed-field inputs / 1T**; date edit adds 3A/1T | All ordinary facts, status, next charge, recent history | Back on dirty draft confirms discard; one atomic Save |
| **S4 — Archive** | partial trailing swipe → Archive | **2A / 0T** | Row identity and next charge remain visible during action | Durable Archived surface; optional Undo is supplemental |
| **S5 — Delete** | full trailing swipe → named permanent-delete confirmation | **2A / 1T** | Confirmation names the service and removed history | Cancel leaves all data unchanged; no full-swipe direct deletion |
| **S6 — Inspect upcoming** | Upcoming → select occupied day → agenda row | **3A / 1T** from Library; month movement +1A | Month distribution/counts plus selected-day service, amount, currency, state | Today action, explicit empty day, Library remains available |
| **S7 — Enter dates** | tap one date → select day → Done; Save when ready | **3A / 1T** to commit to draft; **+1A** to persist | Active field, selected value, derived counterpart, interval consequence | Date Cancel restores entry snapshot; no arbitrary tap-outside |
| **S8 — Match `88`** | type `88` → activate visible regional result | **1F + 1A / 0T** from the open manual editor | Name/aliases, market/edition, verified plan/price when available, or explicit “price required” | Typed manual text remains; ambiguous results never auto-attach |

These are design budgets, not claims about proprietary competitors. The final
fixture run must use one consistent rule for whether a prefilled date counts
as accepted. The current-product and iOS reports count S1/S3 transitions
differently, so their raw totals should not be compared until that fixture is
normalized.

## Must Fix / Should Fix / Later

### Must fix in the Round 2 implementation sequence

1. **Editor and validation:** R2-01, R2-02, and the ordinary-edit portion of
   R2-03. One shared draft, optional plan/category, price/currency/interval/
   date editing, explicit Save, and no duplicate Back/Cancel.
2. **Price correctness:** one amount-on-date function and one atomic edit +
   price-history save; update every projection that currently displays
   `originalAmount` as though it were the current/next price.
3. **Date completion:** R2-05 with one active date task and two independent
   trial dates; preserve the existing tested recurrence engine.
4. **Action semantics:** preserve current swipe order and confirmation; add
   VoiceOver/context/keyboard parity before removing the catch-all menu.
5. **Catalog query and minimum schema:** R2-04, R2-08, R2-09, and R2-10 with
   shared query normalization, regional presets, stable category IDs, AI, and
   offer/market-derived editable currency defaults.
6. **Verified catalog batch:** R2-06, R2-07, and R2-11 only to the extent
   supported by first-party evidence. Account-gated mandatory products remain
   open gates; they are not completed with guessed prices.
7. **Upcoming and hierarchy:** R2-12 month/day agenda on the primary iPhone/
   iPad surface after the native fixture passes, and R2-14 removal of redundant
   segmented-control containers.
8. **Traceability:** R2-13 remains a research/design artifact, not a runtime
   feature. Preserve the evidence manifest and explicit reuse/reject decisions.

These can be implemented as independently testable batches, but all “must”
items remain part of closing Round 2.

### Should fix immediately after the primary phone flow

- native macOS month rendering from the same calendar projection;
- lifecycle and history section polish, including contextual Confirm Charge;
- durable archive discovery plus supplemental `UndoManager` support;
- catalog evidence expiry/review tooling and a generated search index if
  measured query cost requires one;
- additional verified standard-renewal catalog batches;
- visual regression, VoiceOver order, Dynamic Type, split-view, RTL,
  non-Gregorian calendar, and keyboard-navigation coverage.

Accessibility alternatives for actions and the iPhone calendar fixture are
not deferred by this list; they are part of the relevant Must-fix acceptance.

### Later, only when evidence creates the need

- promote the optional catalog family key into a three-entity Service /
  RegionalProduct / Offer graph;
- show introductory, annual-equivalent, “from,” tax, quote, or
  eligibility-dependent prices as selectable products;
- adopt a third-party calendar package or build a fully custom shared
  cross-platform grid;
- advanced effective-date editing and correction of historical price events;
- statement/bank/import discovery, cancellation automation, or multi-channel
  notification systems;
- aggregate mixed-currency day totals without an explicit dated conversion
  policy.

## R2-01–R2-14 Coverage and Challenges

| Requirement | Review decision | Evidence / unresolved condition |
| --- | --- | --- |
| **R2-01** | Approve optional plan/category and five-fact save; clarify that one active date plus interval produces both visible dates | Current validation is the only blocker; no storage migration is required. [CUR-001] |
| **R2-02** | Approve direct draft-backed editor with explicit Save | Shared field content, not identical Add/Edit navigation chrome. [CUR-002] [IOS-009] |
| **R2-03** | Revise: remove the catch-all menu only after semantic relocation; preserve current full-swipe delete confirmation | Archive-first frequency claim is unsupported. Mac/VoiceOver parity is required. [CUR-003] [IOS-001–IOS-005] |
| **R2-04** | Approve inline assistance, but keep Browse Catalog and keep query separate from exact reconciliation | Reuse normalization/index data, not fuzzy matcher semantics. [CUR-004] [IOS-010] |
| **R2-05** | Revise: active subscriptions edit one anchor at a time; trials alone may need Next between two independent dates | Current bidirectional math already passes; only task completion changes. [CUR-005] [IOS-006–IOS-008] |
| **R2-06** | Open mandatory evidence gate | Requested 88VIP/JD/Sam's price sets remain officially unverified. Ship identity/known plan labels without guessed price or obtain reproducible account-context evidence. [OFF-011–OFF-014] |
| **R2-07** | Approve a reviewed standard-renewal batch, not a bulk copy of the offer matrix | Several rows are review-only, conflicting, “from,” or annual equivalents. [OFF-015–OFF-070] |
| **R2-08** | Approve offer-derived currency; a service-only regional preset may suggest its market currency but the person still confirms the actual charge | Never default from app language alone. [CUR-008] |
| **R2-09** | Approve stable AI category ID and icon | Do not make category required on tracked records. [CUR-009] |
| **R2-10** | Revise to separate regional presets plus optional family key before adding a third runtime entity | Canva/可画 and CapCut/剪映 are expressible without a three-level graph. [CUR-010] [OFF-004] [OFF-010] |
| **R2-11** | Partially evidenced; keep open for the requested complete set | US iOS Individual/Family are verified. Lite/Student/Two-person/annual web prices require official account/market checkout evidence. [CUR-011] [OFF-021] [OFF-022] |
| **R2-12** | Approve month plus selected-day agenda and removal of old range controls; renderer remains fixture-gated | Calendar is a projection, not a new store. Do not add a Calendar/List mode now. [CUR-012] [IOS-012] [IOS-013] |
| **R2-13** | Satisfied as research input, with disclosed X/小红书 and proprietary-runtime gaps | The gaps limit claims about preference/frequency, not the core architecture. [COM-001–COM-059] |
| **R2-14** | Approve direct native segmented control with no decorative outer container | Small, native, independently testable. [CUR-014] [IOS-014] [IOS-015] |

## Evidence Gaps That Still Matter

### Blocking before the corresponding feature can claim completion

1. **Authenticated first-party catalog evidence:** 88VIP's requested variants,
   JD PLUS current prices, Sam's ordinary/卓越 prices, and the unsupported
   YouTube web variants. Record market, eligibility/account context, renewal
   semantics, and exact channel. [OFF-011–OFF-014] [OFF-021]
2. **Calendar native fixture:** VoiceOver output/focus for decorated dates,
   accessibility text sizes, and narrow iPad split width on the supported OS.
3. **Price projection audit:** identify every consumer of `originalAmount` and
   prove it intends the historical baseline rather than next/effective price.
4. **Navigation discard fixture:** verify that the selected Edit presentation
   can provide one left-side affordance and reliably protect a dirty draft,
   including swipe-back and interactive dismissal.

### Important but non-blocking for the core boundary

- X/Twitter and 小红书 discussions were inaccessible; community frequency
  claims must not imply those communities were sampled. [COM-058] [COM-059]
- Proprietary competitor listings do not establish whether a row opens view
  or edit, exact date completion, or swipe ordering.
- No evidence establishes Archive as more frequent than Delete for this
  product.
- `OFF-001` supports ChatGPT Pro “from USD 100” but does not independently
  establish every requested USD 100/200 variant. Do not preserve a USD 200
  preset merely because it already exists.
- Canva 可画, QQ Music, and Baidu Netdisk evidence contains current-versus-
  description conflicts. Only the explicitly reviewed channel facts may ship.
  [OFF-010] [OFF-020] [OFF-032]

## Primary Risks and Required Countermeasures

| Risk | Failure mode | Countermeasure |
| --- | --- | --- |
| Direct editing becomes silent autosave | Partial schedule/history writes and unclear Back behavior | Value draft, dirty tracking, one Save, discard confirmation |
| Price field erases or hides history | `originalAmount` overwritten, or history changes while rows show stale price | Immutable baseline, amount-on-day resolver, atomic price-event upsert |
| Typeahead weakens exact matching | Partial text silently attaches the wrong identity | Explicit activation, separate query/reconciliation semantics, ambiguity remains visible |
| Catalog model grows before use | Three ID layers, joins, and migrations without a UI consumer | Regional preset as current boundary; optional family key; promotion trigger documented |
| Calendar becomes a second schedule store | List/calendar/widget disagree after edits | Pure projection over workspace timeline and billing-local date components |
| Native calendar is assumed accessible | Decorations or focus are silent/clipped | Runtime fixture before renderer approval; agenda contains full semantics |
| Removing the detail menu removes capabilities | Confirm Charge, lifecycle, or Mac actions become unreachable | Relocate by meaning and add context/keyboard/VoiceOver parity in the same batch |
| “More presets” becomes false data | Stale, conflicting, promotional, or account-dependent prices are selectable | Standard-renewal-only shipping gate, verified date/source, unknown remains unknown |

## Approval Conditions

The next synthesis/design draft can receive **APPROVE** when it:

1. selects Boundary B or demonstrates a smaller boundary with the same atomic
   state guarantees;
2. preserves full-swipe Delete → confirmation unless new product-specific
   evidence justifies changing it;
3. defines one-date active editing and two-date trial behavior;
4. makes ordinary price/currency editing atomic with history and unifies
   effective-amount projections;
5. treats partial query and exact reconciliation as separate operations over
   one catalog source;
6. either adopts the regional-preset model or proves why a first-class
   `RegionalProduct` is already consumed;
7. fixture-gates the calendar renderer while committing to month plus agenda;
8. keeps R2-06/R2-11 evidence gaps visibly open;
9. normalizes and reruns the S1–S8 counts using one counting rule;
10. relocates retained actions before deleting their only UI path.

Until those revisions are reflected in the synthesis and reviewed, functional
implementation should remain blocked.
