# Mac menu-bar extra design

**Status:** Approved implementation direction from issue #25, the accepted
product specification, and the user's standing instruction to finish
non-interactive work autonomously.

## Goal

Let a Mac user optionally keep the private Subscription Library available
after closing its main window, with an explicit Quit action and no alternate
persistence or background account service.

## Design

`menuBarModeEnabled` is a local `UserPreferences` value, defaults to `false`,
and is persisted through the existing workspace preference command. The macOS
scene observes that preference and conditionally supplies a native
`MenuBarExtra`. Disabling the toggle removes that scene and restores ordinary
window-app behavior.

The extra's menu is a narrow presentation of the live
`SubscriptionWorkspace`: it loads the current library, derives the earliest
eligible renewal from the existing widget snapshot, and refreshes the current
month's expected Insights before presenting a forecast. It does not query
SwiftData, CloudKit, Calendar, or exchange rates directly. Empty and
unavailable values are explicit, localized menu rows.

`Quick Add` and `Open App` invoke a single app routing service. Quick Add
opens the existing Add Subscription sheet, preserving all normal validation
and editable-record behavior. Open App brings the main window forward. Closing
that window is intentionally non-destructive while menu-bar mode is enabled;
the extra contains a separate `Quit Subscription Manager` command that calls
the standard application termination action.

The Settings toggle also exposes opt-in launch at login. It uses
`SMAppService.mainApp`, has no helper app, starts disabled, reflects the
system's registration state, and surfaces a recoverable failure/approval state
instead of claiming that registration succeeded.

## Verification

- Core and SwiftData tests cover the additive preference value and default.
- App tests inject a workspace-backed menu-bar presentation adapter and prove
  renewal/forecast content and quick-add routing.
- macOS build plus focused menu scenarios verify closing, reopening, disabling,
  explicit quit, and launch-at-login state transitions.
