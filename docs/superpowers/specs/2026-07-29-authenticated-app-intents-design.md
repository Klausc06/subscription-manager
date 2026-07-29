# Authenticated App Intents design

**Status:** Approved implementation direction from issue #24, the accepted
product specification, and the user's standing instruction to finish
non-interactive work autonomously.

## Goal

Make the Subscription Library available through Siri, Spotlight, and
Shortcuts without creating a second data model, exposing financial data on a
locked device, or contacting a subscription provider.

## Surface

The app target owns one small App Intents layer:

- `Add Subscription` creates one manually entered Subscription Library record.
- `Show Upcoming Renewals` reports a bounded, date-sorted upcoming timeline.
- `Show Monthly Forecast` reports the current calendar month's expected total
  in the person's primary currency.

`SubscriptionAppEntity` contains only the stable subscription UUID, service
name, plan, category, and archived state needed for selection and
disambiguation. Its display representation uses service name with plan and
category as a subtitle; it never exposes an amount. An entity query resolves
UUIDs from the same `SubscriptionWorkspace` used by SwiftUI and supplies
current subscriptions as suggestions. Identical names remain separate stable
entities, so the system can ask the person to choose rather than guessing.

## Runtime and privacy

`SubscriptionIntentService` is a main-actor adapter around the already-live
`SubscriptionWorkspace`. The app registers it with `AppDependencyManager`
during app startup, and entity queries and intent handlers resolve that one
dependency. App Intents do not open a second SwiftData container, call
CloudKit directly, or reach Calendar.

All three intents use `IntentAuthenticationPolicy.requiresLocalDeviceAuthentication`.
That protects both a mutation and the dates/amounts in answers on the device
actually performing the action. The intents use background execution because
each can complete with a short result dialog; they do not open a screen merely
to perform the operation. The app's existing URL route remains the single
handoff path when a person chooses to open a returned subscription.

The service maps the workspace's existing validation and states to narrow,
localized, recoverable outcomes:

- Add asks for each required field and succeeds only when the workspace
  reports that exactly one new record was persisted.
- A missing selected UUID reports that the subscription is no longer in this
  library.
- An archived selected subscription reports that it must be restored in the
  app before it can appear in forecasts.
- Duplicate display names are returned as separate entities, letting the
  system disambiguate before the command runs.
- A forecast with no usable exchange-rate snapshot reports that it is
  unavailable and directs the person to retry in the app; no amount is
  fabricated.

The forecast refreshes and consumes the existing exchange-rate adapter through
the workspace, matching Insights behavior. No intent contacts a subscription
provider, records a provider cancellation, or starts a background account
workflow.

## Verification

- Core tests prove explicit workspace query methods, validated creation
  results, archived filtering, deterministic upcoming items, and unavailable
  forecasts.
- App tests inject a workspace-backed intent service and cover success,
  validation failure, missing/archived selections, ambiguous entity display,
  and authentication configuration.
- Xcode builds and iOS Simulator tests compile the App Intents metadata and
  exercise the application's existing deep-link route.
