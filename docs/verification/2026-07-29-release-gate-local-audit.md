# TB-25 local release-gate audit

Date: 2026-07-29

## Completed local checks

| Check | Result | Evidence |
| --- | --- | --- |
| Core regression suite | Passed | `swift test --package-path Packages/SubscriptionCore` — 93 tests passed. |
| Menu-bar preference coverage | Passed | `swift test --package-path Packages/SubscriptionCore --filter UserPreferencesTests` — 6 tests passed. |
| Focused app coverage | Passed | iOS Simulator Xcode tests for `MacMenuBarPresentationTests`, `MacWindowRouterTests`, and `AppDependenciesTests`. |
| Full app unit-test target | Passed | `xcodebuild test -enableCodeCoverage NO … -only-testing:SubscriptionManagerTests` on an isolated iOS 27 simulator. |
| macOS build | Passed | `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`. |
| iOS Simulator build | Passed | `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' CODE_SIGNING_ALLOWED=NO`. |
| Test-target compilation | Passed | `xcodebuild build-for-testing` for the iOS Simulator destination. |
| Copy catalog syntax | Passed | `jq -e . SubscriptionManager/Resources/Localizable.xcstrings`. |
| Secret scan | Passed | Source and hidden-file scan found no credentials; `secrets.json` and `Secrets.xcconfig` are ignored. |
| Production network-destination scan | Passed | Only GitHub Raw (catalog update) and Frankfurter (exchange rates) use `URLSession`; CloudKit and EventKit remain platform adapters. |

## Defect found and fixed during the gate

Opening the Add Subscription sheet a second time reused the fixed sheet item
identity and could retain the previous form's SwiftUI state. The app now uses a
fresh UUID item identity per presentation. UI helpers now wait for the specific
newly created service rather than any pre-existing row.

Committed as `30e41fa fix(app): reset add subscription sheet state`.

## UI execution limitation observed

The complete iOS Simulator run completed with 88 passed, 4 failed, and 1
skipped test before the form-identity fix. The settings resume test was
stabilized for Form scrolling. The three archive tests exposed the form reuse
defect and motivated the fix above.

After rebuilding, focused reruns finished their XCTest child processes but
Xcode 27 remained blocked while finalizing the test log / coverage record; no
final `.xcresult` was produced. Restarting the Simulator and disabling code
coverage did not remove the result-finalization hang. The final no-coverage
attempt emitted no failure summary before its XCTest child process exited, but
that remains insufficient to claim the scenarios passed. A newly created iOS
27 simulator reproduced the same behavior, so it is not isolated to the
original device's data or test session. This is a test-executor limitation,
not passing evidence. Re-run the three archive scenarios from Xcode or a clean
Simulator session before closing TB-25.

## Remaining external verification

- Real iPhone, iPad, and Mac acceptance, including VoiceOver, Dynamic Type,
  keyboard navigation, and reduced-motion scenarios.
- A signed-in private CloudKit and EventKit convergence pass on physical
  devices. The connected iPhone is visible to Xcode but currently has
  Developer Mode disabled, so it cannot run a development build until that
  device setting is enabled. Calendar permission must remain user-initiated.
- Manual MenuBarExtra close/reopen/disable/explicit-quit and Login Items
  approval-state scenarios on macOS.
