# Expo Hybrid Rebuild Blueprint

**Date:** 2026-08-11  
**Status:** Preprocessing — requirements locked from user directives this session  
**Source repo:** `/Users/klaus/Documents/New project/subscription-manager-recovery`  
**Native baseline HEAD:** `cf78bfbc6ed0fcca999c4eee95e0c662aeb65f6b` (+ preserve existing 18-file candidate; do not discard)

## User directives that govern this blueprint

1. Extract product requirements; prepare for an Expo rebuild.
2. Do **not** cut features. Combine Expo with native capabilities.
3. Private iCloud / CloudKit sync is **in product scope**. Earlier “暂时不做 / Round 3 不做扩展 / frozen” language was **schedule / that-round scope**, not a permanent product rejection.
4. Do not commit, push, or remote-mutate unless explicitly commanded.

Round 3’s “不做 iCloud…” and `docs/product-goal.md` “Future iCloud behavior is frozen” are **superseded for rebuild planning** by the user’s clarification: temporary deferral ≠ out of product.

## Product one-liner

Help a person know what they pay for, when the next charge is expected, and safely keep that record across iPhone, iPad, and Mac. The Subscription Library is the only source of truth; Calendar, widgets, intents, and menu bar are projections or command surfaces.

## Full capability inventory (all required)

| Area | Capability | Evidence / existing home |
| --- | --- | --- |
| Library CRUD | Catalog-assisted or manual add; direct editable summary; min facts: name, amount, CNY/USD/EUR, Fixed Billing Schedule + Start Date + Confirmed Next Renewal | `docs/product-goal.md`, `CONTEXT.md`, README |
| Lifecycle | Pin, archive, restore, recorded cancellation, reactivate, confirmed delete | README, CONTEXT |
| Upcoming | List + month/day Gregorian views; library remains authoritative | README, R2-12 / R3-07 |
| Catalog | Offline bundled catalog; market/channel/currency offers; evidence rules; editable after adopt | README, evidence-index, Round 2/3 research |
| Money | Cached FX snapshots; spending compare in CNY/USD/EUR | README |
| ICS | Permission-free preview/export | TB-17 design/matrix |
| Calendar | Explicit EventKit import + reconciliation | EventKit importer + matrices |
| Sync | Private CloudKit via named container; honest sync status; offline-first edits | TB-16 design; `CloudKitLibrarySyncMonitor.swift` |
| Backup | JSON/CSV export; portable JSON restore | Portable export/restore views |
| Surfaces | iOS widget, App Intents, Mac window, optional Mac menu bar | Widget / AppIntents / MacMenuBar* |
| Locale / appearance | EN + zh-Hans; system / light / dark | README, R3-09 |
| Architecture rule | All UI/commands go through a Workspace seam; adapters are injected | ADR 0001 |

Out of product (still true unless user changes later):

- Guessed prices / unverified “standard” offers
- Provider-side cancellation automation
- Alternate calendar systems
- Turning Calendar into a competing source of truth

Not “out of product”: iCloud sync expansion beyond today’s TB-16 — may be phased in delivery, but must be designed for, not deleted from scope.

## Architecture: Expo shell + native modules

```text
┌─────────────────────────────────────────────────────────────┐
│ Expo / React Native UI                                      │
│ Library · Add/Edit · Upcoming · Settings · i18n · theme     │
└───────────────────────────┬─────────────────────────────────┘
                            │ JS ↔ native bridge
┌───────────────────────────▼─────────────────────────────────┐
│ Domain Workspace (TS port of SubscriptionCore, preferred)   │
│ Commands / queries / projections / lifecycle invariants     │
└───────────────────────────┬─────────────────────────────────┘
                            │ adapter interfaces
┌──────────────┬────────────┴─────────┬──────────────┬────────┐
│ Persistence  │ Catalog / FX         │ Calendar     │ Sync   │
│ SwiftData or │ bundled JSON +       │ EventKit     │ private│
│ equivalent   │ Frankfurter cache    │ + ICS        │ CloudKit│
│ native module│                      │ native module│ monitor│
└──────────────┴──────────────────────┴──────────────┴────────┘
┌─────────────────────────────────────────────────────────────┐
│ Native extension targets (same app ID / entitlements)         │
│ Widget · App Intents · Mac menu bar extra                     │
└─────────────────────────────────────────────────────────────┘
```

### Layer rules

1. **UI never owns subscription facts.** Screens call Workspace commands and observe Workspace state (same idea as ADR 0001).
2. **Native modules implement adapters**, not business rules. EventKit, CloudKit status, widget snapshots, intents, menu bar all talk to Workspace or publish snapshots derived from Workspace.
3. **Library remains authoritative** whether iCloud is signed out, synchronizing, or current.
4. **Expo owns cross-platform presentation** where RN can express it; Apple-only surfaces stay native targets linked into the Expo continuous-native / prebuild app.

### Suggested package split (new Expo app)

| Package / target | Responsibility |
| --- | --- |
| `apps/mobile` (Expo) | Screens, navigation, forms, localization |
| `packages/domain` | Port of `SubscriptionCore` / Workspace |
| `packages/adapters-contracts` | Repository, Catalog, FX, Calendar, Sync, Export interfaces |
| `modules/native-persistence` | SwiftData (+ private CloudKit config) |
| `modules/native-calendar` | EventKit import/reconcile; optional ICS helpers |
| `modules/native-sync-monitor` | `CKAccountStatus` / `CKAccountChanged` → sync status |
| `targets/widget` | WidgetKit extension |
| `targets/intents` | App Intents |
| `targets/menubar` | macOS menu bar |

Keep the existing native repo as the **behavior oracle** until domain port + adapter contract tests match.

## iCloud / sync (required, not optional)

Preserve TB-16 semantics unless a later approved issue changes them:

- Container: `iCloud.com.klausc06.SubscriptionManager` (private DB only)
- Statuses: `localOnly` · `synchronizing` · `current` · `signedOut` · `requiresAttention`
- Local-first: never block a successful edit on CloudKit round-trip
- Monitor reports account/progress; does not query subscription records from CloudKit as a second library
- Settings / library show honest localized status (EN + zh-Hans)
- Two-device convergence matrix remains the physical acceptance gate

Delivery may still be staged (UI + local store first, then wire CloudKit), but the blueprint and contracts must include Sync from day one so Expo rebuild does not paint itself into a corner.

## Capability → implementation mapping

| Capability | Expo UI | Domain | Native module / target |
| --- | --- | --- | --- |
| Add / edit / list | Yes | Workspace commands | Persistence |
| Pin / archive / cancel / reactivate / delete | Yes | Lifecycle rules | Persistence |
| Upcoming month/day | Yes | Projection | — |
| Catalog browse / alphabet / offers | Yes | Catalog rules | Bundled assets + optional refresh |
| FX insights | Yes | Conversion | Network/cache adapter |
| ICS preview/export | Yes or share sheet | ICS builder | Optional native share |
| EventKit import/reconcile | Triggers + status UI | Mapping / reconcile commands | EventKit module |
| Private iCloud sync | Status UI | Reload on remote change | SwiftData+CloudKit + sync monitor |
| JSON/CSV backup | Yes | Serialize/deserialize | File pickers |
| Widget | — | Snapshot model | WidgetKit target |
| App Intents | — | Same commands | App Intents target |
| Mac menu bar | Thin or native chrome | Same Workspace | Menu bar target |

## Migration order (do not reorder casually)

1. **Freeze oracle:** keep current candidate; document behavior with existing tests as acceptance.
2. **Domain port:** `SubscriptionCore` → `packages/domain` with Workspace tests ported first.
3. **Persistence adapter:** local store parity; then enable private CloudKit configuration + sync monitor.
4. **Library UI slice:** list / summary-edit / add (catalog + manual).
5. **Upcoming + FX.**
6. **ICS + EventKit.**
7. **Widget + App Intents.**
8. **Mac window + menu bar.**
9. **Physical gates:** two-device CloudKit matrix; EventKit permission matrix; HIG / VoiceOver / Dynamic Type.

Each step must prove parity against the native oracle for that slice before expanding.

## Explicit non-goals for agents (until user says otherwise)

- Do not discard or reset the current 18-file native candidate.
- Do not treat Round 3 / product-goal “frozen iCloud” as rebuild exclusion.
- Do not cut Widget, Intents, Menu bar, EventKit, or CloudKit to “make Expo easier.”
- Do not commit/push without an explicit user command.

## Immediate next engineering action

Create the Expo app workspace beside or under this repo and scaffold `packages/domain` with Workspace command/query types copied from `Packages/SubscriptionCore`, then wire a no-op persistence adapter so UI can start against in-memory parity tests.
