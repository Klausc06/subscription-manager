# Mac menu-bar extra implementation plan

**Goal:** Add an optional native macOS `MenuBarExtra` with focused,
workspace-backed actions and controlled launch-at-login.

## Task 1: Persist optional menu-bar mode

- Extend `UserPreferences`, workspace updates, SwiftData persistence, and
  preference tests with a default-off `menuBarModeEnabled` value.

## Task 2: Add a narrow workspace-backed presentation adapter

- Create a macOS-only presentation model that derives next renewal and monthly
  forecast through `SubscriptionWorkspace`.
- Add an app routing service for opening the main window and the existing Add
  Subscription flow.

## Task 3: Compose the native scene and settings

- Add conditional `MenuBarExtra`, explicit Quit, opening behavior, and settings
  toggle.
- Add a `SMAppService.mainApp` adapter with system-state/error presentation.

## Task 4: Test and verify

- Test preference persistence, adapter/routing behavior, and launch-item state.
- Run core tests plus macOS/iOS builds and record a verification matrix.
