# Apple-Platform Editing, Date, Swipe, Search, and Calendar Research

**Research date:** 2026-07-31
**Workstream:** 4 — Apple-platform interaction and calendar research
**Status:** Research recommendation only; no implementation is authorized
**Evidence fragment:** `docs/research/evidence/ios-interaction.jsonl`

## Decision Summary

The recommended direction is a shared, draft-backed Add/Edit flow with native
platform controls and explicit persistence boundaries:

1. Opening a library row goes directly to an editable form. The form edits a
   draft; **Save** commits it and **Cancel/Back** either discards it or confirms
   the loss of unsaved changes. A read-only page followed by an Edit sheet is
   rejected. [IOS-009]
2. The library uses a leading Pin/Unpin swipe and a trailing
   Archive-then-Delete swipe. Pin and Archive may be the first, full-swipe
   actions because they are reversible. Permanent Delete is never the
   full-swipe action and always presents a named destructive confirmation.
   [IOS-001] [IOS-004]
3. Start Date and Next Renewal are edited in one focused date task with an
   explicit **Next/Done** action. Selecting a day updates the form draft;
   **Done** closes the date task; the form's **Save** is the only persistence
   boundary. No result depends on tapping blank space. [IOS-006] [IOS-007]
4. Service matching is an inline result list below the Service Name field.
   Choosing a verified result adopts its identity and offer data; a clearly
   labeled manual path preserves the typed text. This is preferable to
   converting the whole form into a screen-level search interface. [IOS-010]
5. Upcoming uses a month-plus-day-agenda projection. Use `UICalendarView`
   wrapped for SwiftUI on iPhone/iPad and a native SwiftUI month renderer on
   macOS, both driven by one date-indexed projection model. Full charge details
   stay in the selected-day agenda; day cells show only an indicator or count.
   [IOS-012] [IOS-013]
6. A segmented `Picker` supplies its own visual boundary. Place it directly in
   the content hierarchy without another pill, capsule, glass, or decorative
   card. [IOS-014] [IOS-015]

These are research conclusions, not restatements of the user's suggested
controls.

## Requirement Boundary

| Kind | What is fixed | What remains a design choice |
| --- | --- | --- |
| User-identified problems | Read-only-before-edit is an extra layer; ordinary actions are hidden; date completion is unclear; Upcoming lacks a month/day picture; segmented controls have redundant containers. | The exact edit presentation, gesture mapping, date picker style, calendar implementation, and control placement. |
| User-suggested controls | Direct editing, swipe-only archive/delete, inline typeahead, focused date editor, embedded calendar/agenda, and unwrapped segmented controls. | Each suggestion was compared rather than treated as the answer. |
| Research candidates | Draft form, autosaving hybrid, view-then-edit; compact/graphical/focused date flows; SwiftUI/UIKit/custom search; native/custom/open-source calendars. | Product review still chooses the final design and delivery boundary. |

## Method and Counting

Sources are limited to Apple documentation, Apple Support, WWDC material, and
commit-pinned source. Public pages were read through Jina Reader; GitHub
repositories were inspected through `gh` shallow clones in `/tmp`. No
screenshots, browser clicking, or extensions were used.

The S1–S8 counts below are static-flow estimates against the approved fixtures.
They are suitable for comparing alternatives, but the final synthesis should
replace estimates with fixture measurements on the named OS/device matrix.

- **A** — non-text activation: tap, click, swipe completion, keyboard
  activation, or VoiceOver activation.
- **F** — required field focus plus entered value; character counts are noted
  separately.
- **T** — transition or focus context that replaces the current task surface.
- Counts exclude visual scanning and do not add A and F into a single score.

## Native Swipe Actions and Library Semantics

SwiftUI makes both edge and full-swipe behavior explicit. The trailing edge is
the default, `allowsFullSwipe` defaults to `true`, and a full swipe invokes the
first action for that edge. Action order therefore encodes safety, not merely
appearance. [IOS-001]

Apple Mail demonstrates the staged model: a slow left drag reveals actions, a
full left swipe runs the rightmost action, and the opposite direction reveals
other actions. Mail also provides non-swipe paths such as selection, context
menus, and controls inside a message. [IOS-002]

### Alternatives

| Alternative | Primary count | Discoverability and safety | Accessibility and platform fit | Estimated implementation surface | Decision |
| --- | ---: | --- | --- | --- | --- |
| Leading Pin; trailing Archive first and Delete second | S4 1A by full swipe; S5 3A (reveal, Delete, confirm) | Reversible frequent actions are fastest. Delete is visible after a staged swipe but cannot fire from a full swipe. | Add named `.accessibilityAction`s; expose equivalent context-menu/keyboard commands on iPad/Mac. Native list behavior adapts across Apple platforms. | Small: about 2–4 view/test files, no domain-model change | **Recommend** |
| Current order: Delete first, Archive second, full swipe enabled | S4 2A; S5 2A | Full swipe leads directly to a delete confirmation, while the common reversible action takes more work. Safe only because deletion is deferred to confirmation. | Native, but action priority conflicts with use frequency. | Already present | Reject ordering |
| Disable all full swipes | S4 2A; S5 3A | Safest mechanically but gives up the native fast path even for Pin/Archive. | Predictable and accessible, but slower for frequent use. | Small | Viable fallback if usability testing shows accidental archives |
| Catch-all row overflow menu | 2–3A per action | More discoverable than a hidden gesture but recreates the reported hierarchy and mixes reversible, destructive, and lifecycle actions. | Keyboard-friendly; poor information hierarchy on iPhone. | Small | Reject as primary path |

### Recommended mapping

- **Leading edge:** Pin/Unpin first, `allowsFullSwipe: true`.
- **Trailing edge:** Archive (or Restore in Archived) first, then Delete.
  `allowsFullSwipe: true` is acceptable only because the first action is
  reversible and Archived provides a durable recovery path.
- **Delete:** tapping the red destructive action opens a confirmation that
  names the subscription and explains that schedule, notes, lifecycle, and
  payment history are removed. [IOS-004]
- **Recovery:** Archived is the durable recovery surface. Register with the
  environment `UndoManager` where it exists, but do not make recovery depend
  on it because the environment value can be absent. [IOS-005]
- **No transient-only undo:** Apple warns against time-boxed controls for
  people who need longer to process or navigate. A short-lived toast must not
  be the sole recovery path. [IOS-003]
- **Gesture alternative:** preserve labeled partial-swipe buttons, add explicit
  VoiceOver actions, and mirror actions in a row context menu and keyboard
  commands on pointer/keyboard platforms. Apple explicitly recommends simple
  familiar gestures and alternatives to gesture-only core actions. [IOS-003]

## Direct Editing Versus an Edit Mode

SwiftUI `EditMode` is primarily a list-state mechanism: built-in lists change
behavior for deletion, moving, and multi-selection. It does not establish a
need for a separate mode before ordinary form controls become editable.
[IOS-009]

### Alternatives

| Alternative | S3 task shape | Visible before secondary navigation | State and failure recovery | Architecture | Decision |
| --- | --- | --- | --- | --- | --- |
| Direct draft-backed form | Row → editable form; price, currency, interval, Start Date, Next Renewal, status, and next charge are present | All ordinary editable facts and schedule consequence | Save commits once; Cancel discards; Back with changes asks to discard or continue editing; validation remains inline | Replace duplicate Add/Edit state with one editor state owner and configuration | **Recommend** |
| Read-mostly detail with individual inline field activation and autosave | Row → detail; tap a field to edit just that field | High information density | Fewer explicit Save taps, but linked date changes and partial write failures become harder to explain or roll back | Requires per-field command, error, and undo states | Viable only for a later Mac inspector, not primary iPhone flow |
| Read-only detail → Actions → Edit sheet | Row → detail → menu → sheet | Detail is rich, but no ordinary field is editable | Explicit Cancel/Save, but adds two command layers before work starts | Duplicated detail/editor presentation | Reject; it is the confirmed R2-02/R2-03 problem |

The direct editor is not “always-live persistence.” It is an editable
destination backed by a value draft. This keeps the one-transition access of
direct editing while retaining an explicit, testable save boundary.

Lifecycle and payment history should remain readable sections below the
ordinary fields or in a history destination. “Confirm Charge,” “Record Price
Change,” and “Record Cancellation” are domain events, not ordinary field
edits; merging them into field mutation would obscure their semantics.

### Estimated architecture surface

- One `SubscriptionDraft`/editor state owner shared by Add and Edit.
- One validation and schedule-recalculation path.
- View configuration differentiates Add, verified-offer confirmation, and
  Edit without duplicating field state.
- Approximate scope: 6–10 production/test files and 500–1,000 changed source
  lines. This is a feature-boundary replacement, not a cosmetic refactor.
- `SubscriptionWorkspace` remains the command/query seam, consistent with ADR
  0001; no view writes persistence or Calendar directly.

## Date Entry, Completion, and Linked Schedule

Apple's picker guidance says date-component order follows device language or
location. The app must not impose a fixed month/day/year order. It also says
the compact style confirms after a person taps outside its modal editor—the
same boundary the reported problem finds unclear. [IOS-006]

SwiftUI's basic `DatePicker` binds a `Date` and documents the iOS compact flow
as opening a calendar whose bound value updates when that calendar is
dismissed. [IOS-007] `FocusState` can move focus programmatically and can
dismiss the keyboard by setting focus to `nil`. [IOS-008]

### Three implementation families

| Family | Operations for S7 | Completion clarity | Density / accessibility / platforms | Custom surface | Decision |
| --- | ---: | --- | --- | --- | --- |
| One focused date editor using native graphical/compact `DatePicker`, with Start and Next steps plus toolbar Next/Done | 4–5A, 1T | Selection updates the draft immediately; Next/Done is explicit; form Save persists | Native locale, keyboard, pointer, Dynamic Type, and VoiceOver behavior; sheet on iPhone, popover/inspector on larger layouts | Medium: one shared editor and schedule summary | **Recommend** |
| Inline graphical picker below the active row | 3–4A, 0T | Immediate and visible; no dismissal ambiguity | Consumes substantial vertical space; two graphical pickers are too dense at accessibility sizes | Low–medium | Viable when one date is edited at a time |
| Two compact date pickers with outside-tap dismissal | 6A, 2T | The outside tap is the effective confirmation, so commit state remains unclear | Space-efficient and native, but reproduces R2-05 | Low | Reject for paired required dates |
| Wheel or custom component selectors | 5+A | Can provide Done, but obscures calendar context and risks fixed ordering | Wheels support keyboard entry; custom month/day wheels risk localization errors | Medium–high | Reject unless a future time-of-day use case demands wheels |

### Recommended linked-date representation

The focused editor shows this schedule relationship as content, not hidden
state:

`Billing interval → Start Date → Next Renewal`

- Show the selected billing interval above the two dates.
- When Start Date changes, calculate and immediately display the first
  recurrence after today as Next Renewal.
- When Next Renewal changes, display the derived preceding Start Date.
- Present a short inline consequence, for example “Next Renewal updated to
  2026-08-31,” using the person's localized date format.
- Do not silently invent dates when required schedule facts are absent.
- In first-time Add, after choosing Start Date, **Next** may advance to Next
  Renewal because it is the only unfinished required date.
- In Edit, do not auto-advance after every date choice; a person may be
  correcting one existing value. Keep explicit Next/Done.
- **Done** commits only to the form draft and dismisses the date task.
  **Save** persists the whole subscription. Cancel in the date task restores
  the date-editor snapshot; Cancel in the form restores the persisted record.
- Keyboard Done sets focus to `nil`; sheet/popover dismissal is never the
  persistence trigger.

This uses native localized controls while making the product's recurrence
semantics explicit.

## Inline Catalog Matching

SwiftUI can display dynamic search suggestions and associate a completion
string with each result. Choosing a completion normally replaces the search
text. [IOS-010] UIKit's `UISearchController` instead coordinates a search bar
with a results controller and updates results while typing. [IOS-011]

### Three implementation families

| Family | S8 | Information and ambiguity | Accessibility / platforms | Architecture | Decision |
| --- | ---: | --- | --- | --- | --- |
| Inline `TextField` plus a native result section in the same form | 1F (`88`, 2 characters) + 1A | Result rows can show localized service, region, plan/price summary, verification state, and “Continue manually as 88” together | Natural form reading order; arrow/Return and VoiceOver labels must be added; pure SwiftUI on iPhone/iPad/Mac | Reuses a catalog index and the shared Add/Edit draft | **Recommend** |
| Navigation-level `.searchable` plus `.searchSuggestions` | 1F + 1A, but activates a search context | Excellent for a dedicated catalog browser; adopting a result then returning to the form adds a mode/transition | Strong native keyboard and suggestion behavior across platforms | Low custom UI, separate browse and form states | Viable for Browse Catalog, not the primary manual field |
| UIKit `UISearchController` with results controller | 1F + 1A plus bridge context | Full control over a separate results surface; too much hierarchy for one field | Native on iOS/iPad/Catalyst, no native macOS path; wrapper coordination required | Highest controller and bridge surface | Reject for this form |

Recommended result behavior:

- Match normalized localized names and explicit aliases by deterministic
  prefix/token rules; do not silently attach identity through broad fuzzy
  matching.
- Keep manual entry visible as a peer choice, not an empty-results fallback.
- Do not replace the typed text merely because a row is highlighted. Adoption
  occurs only on activation.
- A result row states region and verified offer distinctions before adoption.
- On adoption, populate service identity, selected offer, price, currency,
  interval, and source metadata in one draft update. Preserve user-entered
  dates unless the person accepts a replacement.
- Announce the result count and adopted service to VoiceOver; support
  Up/Down/Return/Escape on hardware keyboards.

## Upcoming Calendar and Day Agenda

Apple describes `UICalendarView` as a calendar for displaying/selecting dates
and attaching date decorations. It takes `Calendar`, `Locale`, time zone, and
date components; it deliberately does not handle date-time selection.
[IOS-012] WWDC22 emphasizes `DateComponents` as the correct representation for
a calendar day and shows standalone selection and decoration APIs. [IOS-013]

### Implementation families and source audit

| Family | Month + agenda capability | iPhone/iPad | Native Mac | Accessibility / localization | Maintenance and code | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| `UICalendarView` wrapper + SwiftUI selected-day agenda | Decorations/counts in month; full rows in agenda | Native, compact, pointer-aware, date-component based | No; UIKit only (Catalyst is not the repo's native macOS target) | System calendar/locale behavior; decoration meaning and VoiceOver order still require fixture verification | Medium wrapper, no dependency | **Recommend for iPhone/iPad** |
| Pure SwiftUI `LazyVGrid` month + agenda | Complete control over counts, totals, empty and dense days | Works, but seven columns become tight at accessibility text sizes | Yes | Must implement locale week starts, non-Gregorian calendars, RTL, keyboard movement, focus, labels, and Dynamic Type | High custom/test surface | **Recommend only for native macOS renderer** |
| HorizonCalendar + app agenda | Flexible month layouts; agenda remains app code | Strong SwiftUI/UIKit bridge, RTL, Foundation calendars | No; package declares iOS only | Source implements VoiceOver scrolling and page announcements; explicit accessibility-test support | Active, Apache-2.0, sizable dependency | Best fallback if native calendar cannot meet visual density [IOS-016] |
| KVKCalendar | Includes month and event-list modules | Broad feature set | Catalyst only | Custom localization; only one accessibility-related source match in audit | Active, MIT, UIKit controller wrapper; much larger than the use case | Reject as over-scoped [IOS-018] |
| FSCalendar | Custom month view; agenda remains app code | Mature UIKit component | No | No accessibility/VoiceOver references found in source/README audit | MIT Objective-C/UIKit, latest cloned commit dated 2024-01-02 | Reject for new work [IOS-017] |

### Recommended calendar/agenda behavior

- One shared `UpcomingCalendarProjection` indexes immutable display values by
  local calendar day. It reads from Subscription Library state; it never
  becomes a second source of truth.
- The month initially selects the nearest day with a charge in the visible
  month, otherwise today. This avoids an empty agenda without inventing data.
- Empty day: no marker. One charge: one marker. Dense day: a count badge such
  as `3`, not three tiny dots. Color is supplemental, never the only meaning.
- Selecting a day updates the agenda in place. The agenda row exposes service,
  plan when known, price/currency, expected/confirmed state, and next charge;
  activating it opens the editable subscription.
- iPhone: calendar above a vertically scrolling agenda. At accessibility text
  sizes, keep amounts out of the seven-column day cells.
- iPad split view: month and agenda can share two columns while preserving the
  selected day.
- macOS: month grid and agenda side-by-side; support arrow-key day movement,
  Return to open, and a visible focus ring.
- VoiceOver day labels need localized date, charge count, and selection state.
  Full charge information follows in agenda rows. A native fixture must verify
  whether custom `UICalendarView.Decoration` content contributes useful
  semantics; do not claim this from the API reference alone.
- Changing months is one activation/gesture. Preserve the selected day when it
  remains visible; otherwise select the closest valid day without moving the
  library's schedule.

### Why not calendar-only

A calendar cell cannot safely carry service, price, currency, expected versus
confirmed state, and multiple charges at Dynamic Type sizes. A calendar-only
replacement increases ambiguity. The day agenda is the accessible,
information-rich half of the interaction, not a secondary convenience.

### Architecture surface

- Shared date-indexed projection and selection state: about 3–5 files.
- iOS/iPad `UIViewRepresentable` wrapper and coordinator: about 2–4 files.
- Native macOS grid renderer: about 3–5 files.
- UI, VoiceOver, localization, and schedule tests: about 5–8 files.
- Total estimate: 8–14 production/test files and 800–1,600 source lines. This
  replaces the Upcoming feature boundary while preserving
  `SubscriptionWorkspace` and the Subscription Library source of truth.

## Segmented Controls and Liquid Glass

Apple positions a segmented control as a grouping for closely related choices
with visible selection state. On iOS it is suitable for related subviews; on
macOS a main-content view switch is better represented by a tab view, while a
segmented control fits a toolbar or inspector. [IOS-014]

Current Liquid Glass guidance says standard controls adopt the current
appearance automatically, recommends removing custom control backgrounds,
and warns against crowded or layered glass controls. [IOS-015]

| Alternative | Hierarchy | Adaptation | Decision |
| --- | --- | --- | --- |
| Direct `.pickerStyle(.segmented)` in page/form content | The control has exactly one boundary | Native sizing, selection semantics, current appearance, and accessibility | **Recommend** for Expected/Confirmed |
| Segmented control in a standard toolbar/inspector on Mac | Clear functional placement without a custom capsule | Matches macOS placement guidance | Viable platform adaptation |
| Menu/popup when labels no longer fit | Less glanceable but avoids truncation | Useful at narrow split widths or localization expansion | Viable responsive fallback |
| Segmented control inside a custom capsule/card/glass container | Nested visual boundaries make equal controls compete | Risks overlapping materials and hard-coded metrics | Reject |

Do not add a heading merely to repeat the two labels; Apple notes that textual
segment labels can stand without introductory text. Keep labels as parallel
noun phrases and test Simplified Chinese and English widths. [IOS-014]

## S1–S8 Comparison

The proposed counts use the recommended unified editor and calendar. Character
counts are separate: `ChatGPT` is 7 characters and `88` is 2.

| Scenario | Unchanged static baseline | Recommended estimate | Information / ambiguity / recovery |
| --- | --- | --- | --- |
| S1 Add verified known service | 6A + 1F / 2T: Add, search, choose preset, open/select/dismiss date, Save | 5–6A + 1F / 2T: Add, choose inline verified result, date task, select date(s), Done, Save | Verified region/offer and derived schedule stay visible in one draft; no blank-space commit |
| S2 Add unknown service | **Unavailable**: Add → Add Manually is 2A/2T before entry; empty plan/category block Save | About 7A + 2F / 2T; plan/category require 0F | Manual path remains explicit; only service and price require typing when currency/interval are selected controls |
| S3 Edit subscription | **Unavailable** after 3A/2T (row, Actions, Edit); current editor has no price/currency controls | 6–8A + 1F / 2T depending on whether both linked dates are directly changed | All ordinary facts visible; draft Cancel/Save and discard confirmation recover unsaved work |
| S4 Archive | 2A/0T: partial swipe then Archive; a full trailing swipe targets Delete first | 1A/0T: full swipe Archive | Archived is durable recovery; optional system Undo where supported |
| S5 Delete | Best path 2A/1T: full swipe reaches delete dialog, then confirm | 3A/1T: reveal, Delete, named confirmation | One extra activation is intentionally retained for irreversible deletion |
| S6 Inspect upcoming | 2A/1T: Upcoming tab, timeline row; no month distribution | 3A/1T: Upcoming, select day, agenda row | One extra activation yields month distribution, dense-day count, and selected-day context |
| S7 Enter dates | 6A/2T: open/select/arbitrary-dismiss twice | 4–5A/1T: open editor, select Start, optional Next, select Next, Done | Active field, derived value, and draft/persistence boundary are explicit |
| S8 Match `88` | **Unavailable** | 1F (`88`) + 1A / 0T | Variants appear inline; choosing one adopts verified facts without retyping; manual text remains available |

The S5 and S6 recommendations deliberately do not minimize raw taps at the
expense of irreversible-action safety or month-level information.

## Cross-Platform and Accessibility QA Gate

Before a design is approved for implementation, validate each viable
alternative with the approved fixtures:

1. **iPhone portrait, zh-Hans, default Dynamic Type:** complete S1–S8; verify
   date order follows locale, no nested segmented background, and dense days
   remain understandable.
2. **Accessibility text size:** form labels wrap without clipping; calendar
   cells carry only date/count; full information stays in agenda rows.
3. **VoiceOver:** rotor/actions expose Pin, Archive, and Delete; confirmation
   reads the subscription name; focus moves Start → Next only when intended;
   day labels announce date/count/selection; result adoption is announced.
4. **iPad split view and hardware keyboard:** autocomplete supports
   Up/Down/Return/Escape; confirmation anchors correctly; month/agenda
   selection remains stable while resizing.
5. **Native macOS and English:** direct editor uses keyboard shortcuts and
   discard confirmation; the custom month renderer supports arrow navigation;
   long English segment labels adapt to a menu/tab rather than clip.

Also test Reduce Transparency, Reduce Motion, Increased Contrast, both light
and dark appearances, non-Gregorian user calendars, Monday/Sunday week starts,
right-to-left layout, daylight-saving boundaries, and billing time zones.
[IOS-003] [IOS-012] [IOS-015]

## Rejected Directions and Counterexample

The strongest counterexample to the recommendation is a fully custom SwiftUI
month grid shared across iPhone, iPad, and Mac. It would avoid UIKit bridging
and give precise control over dense-day counts. It was not selected as the
primary renderer because recreating calendar conventions, RTL, keyboard
navigation, Dynamic Type, focus, and VoiceOver behavior produces the largest
custom and test surface. It remains the native macOS solution because
`UICalendarView` has no AppKit/SwiftUI macOS equivalent with date decorations.

Other rejected directions:

- **Autosave every field:** lowest explicit-save count, but linked schedule
  mutations and partial failures become harder to understand and undo.
- **Compact paired DatePickers:** native and small, but Apple documents
  outside-tap confirmation, which reproduces the reported ambiguity.
- **FSCalendar/KVKCalendar adoption:** broad nominal feature coverage does not
  outweigh iOS/UIKit scope, wrapper cost, and weaker accessibility evidence.
- **Nested pill around segmented Picker:** duplicates a control boundary and
  conflicts with current system-control/Liquid Glass guidance.

## Evidence Saturation and Open Questions

The last source families did not change the main alternatives:

- Apple's current Liquid Glass guidance strengthened the case for system
  controls and removing decorative outer backgrounds.
- HorizonCalendar established a credible accessible open-source fallback.
- FSCalendar and KVKCalendar added breadth but reinforced the maintenance,
  platform, and accessibility costs of adopting a large calendar dependency.
- The UIKit search-controller family did not improve the single-field manual
  Add flow over native inline SwiftUI results.

No major implementation family remains unexplored for this decision. Three
questions require a throwaway runtime fixture before implementation approval,
because documentation alone does not settle them:

1. VoiceOver output and focus order for `UICalendarView` custom decorations.
2. `UICalendarView` layout at the project's accessibility text sizes and
   narrow iPad split widths.
3. Exact compact `DatePicker` dismissal/focus behavior on the supported OS
   build.

These questions may alter renderer details or the date presentation style, but
are unlikely to change the shared draft, explicit completion, month-plus-agenda,
or one-boundary segmented-control recommendations.

## Evidence Index

| ID | Source |
| --- | --- |
| IOS-001 | Apple SwiftUI `swipeActions(edge:allowsFullSwipe:content:)` |
| IOS-002 | Apple iPhone User Guide, Mail staged/full swipe behavior |
| IOS-003 | Apple HIG Accessibility |
| IOS-004 | Apple SwiftUI `confirmationDialog` |
| IOS-005 | Apple SwiftUI environment `undoManager` |
| IOS-006 | Apple HIG Pickers |
| IOS-007 | Apple SwiftUI `DatePicker` |
| IOS-008 | Apple SwiftUI `FocusState` |
| IOS-009 | Apple SwiftUI `EditMode` |
| IOS-010 | Apple SwiftUI `searchSuggestions` |
| IOS-011 | Apple UIKit `UISearchController` |
| IOS-012 | Apple UIKit `UICalendarView` |
| IOS-013 | Apple WWDC22 “What's new in UIKit” |
| IOS-014 | Apple HIG Segmented controls |
| IOS-015 | Apple “Adopting Liquid Glass” |
| IOS-016 | Airbnb HorizonCalendar, commit `cf15e05d8c3a3545678fdce07ec150dfa3a21e99` |
| IOS-017 | FSCalendar, commit `df53e79c324ea5f9e3dcb03b35b2b324de901205` |
| IOS-018 | KVKCalendar, commit `330086ba06c747c8ad15d332ef1094e91398af10` |
