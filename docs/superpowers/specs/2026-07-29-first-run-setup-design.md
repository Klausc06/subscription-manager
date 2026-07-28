# TB-12 First-Run Setup Design

- Date: 2026-07-29
- Issue: #13 — Complete first-run setup with multiple presets
- Status: Approved for autonomous implementation

## Decision

Introduce a small, explicit `UserPreferences` domain value and a dedicated
`UserPreferencesRepository`. It owns the primary display currency, Calendar
projection horizon (six or twelve months), and whether first-run setup was
completed or skipped. This remains separate from `SubscriptionRepository`:
preferences exist before a subscription and must not change subscription
history.

The production adapter stores one SwiftData preferences record. The workspace
receives the adapter by injection and exposes a recoverable setup state.
Preference-load failures never discard or mutate subscriptions.

## Interaction

On an empty first launch, a dismissible setup sheet asks for a primary display
currency and six- or twelve-month projection horizon, with twelve preselected.
It then offers multi-selection from the bundled catalog. Each selected preset
opens the existing confirmation form; saving creates exactly one normal,
editable subscription. People may select no presets, enter a subscription
manually, skip setup, or return to setup from Settings.

The catalog selection is a local checklist over the loaded catalog. No setup
screen calls a network, Calendar, EventKit, authorization, or `.ics` API.

## Recovery boundaries

- SwiftUI observes `SubscriptionWorkspace`; it never accesses SwiftData or a
  Calendar adapter directly.
- Preference writes validate currency and horizon, then atomically persist.
  A failed write retains the prior observable setup state.
- Selected catalog IDs are ephemeral `@State`. A subscription is complete only
  after the existing creation command persists it, so reopening cannot repeat
  a saved creation.
- Existing people with subscriptions are not forced into onboarding; Settings
  remains available for their preferences.

## Verification

- Core tests cover defaults, empty/single/multiple preset setup, skip, resume,
  persistence failure, and no subscription mutation on preference failure.
- Adapter tests cover one-record persistence and reload.
- UI tests cover setup, confirmation for each selected preset, skip/resume,
  and settings values.
- Calendar test doubles assert zero authorization calls for every onboarding
  path.
