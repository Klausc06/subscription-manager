# TB-25 local release-gate audit

Date: 2026-07-29

## Completed local checks

| Check | Result | Evidence |
| --- | --- | --- |
| Core regression suite | Passed | `swift test --package-path Packages/SubscriptionCore` — 93 tests passed. |
| Menu-bar preference coverage | Passed | `swift test --package-path Packages/SubscriptionCore --filter UserPreferencesTests` — 6 tests passed. |
| Focused app coverage | Passed | iOS Simulator Xcode tests for `MacMenuBarPresentationTests`, `MacWindowRouterTests`, and `AppDependenciesTests`. |
| Full app unit-test target | Passed | 65 tests passed through XcodeBuildMCP on the isolated iOS 27 simulator, including CloudKit schema compatibility and entitlement fallback coverage. |
| iPad app unit-test target | Passed | The same `SubscriptionManagerTests` target passed on an iPad Air 11-inch (M4), iOS 27 simulator. |
| macOS build | Passed | `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`. |
| iOS Simulator build | Passed | `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' CODE_SIGNING_ALLOWED=NO`. |
| iOS Simulator production launch | Passed | XcodeBuildMCP built, installed, and launched the production app; the main library rendered and startup logs contained no app error. |
| Personal Team physical-device launch | Passed in local-only mode | The app was automatically signed with Personal Team `Z23GL5RZH7`, installed on device `00008150-000245CA1AB8401C`, and launched as `com.klausc06.SubscriptionManager`. The running process was observed as PID 2289, and the user independently confirmed that reopening no longer crashed. |
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

The Archived destination used a `SubscriptionLibraryScope` navigation value
while the root `NavigationStack` path accepted only `[UUID]`. The toolbar
button therefore remained on the current library instead of pushing the
Archived library. The path now uses `NavigationPath`, preserving UUID deep
links while also accepting the Archived destination. The direct-action UI test
was also corrected to return from the archived subscription detail before
asserting on the current-library row.

The production app could trap during startup in `CKContainer.default()`.
The main target's entitlement file existed but was not bound to the iOS device
or simulator build settings. Once the entitlement was applied, SwiftData
reported Cocoa error 134060 because the CloudKit-backed `SubscriptionRecord.id`
property did not have a default value. The target now binds the entitlement
file for both iOS SDKs, the model supplies a UUID default, and runtime
dependencies disable CloudKit and App Group adapters when those entitlements
are absent. This lets a Personal Team build run with local SwiftData storage
while full profiles continue to use CloudKit and the Widget snapshot.

## UI gate follow-up

The complete iOS Simulator run initially completed with 88 passed, 4 failed,
and 1 skipped test. The settings-resume test was stabilized for Form scrolling.
After the fixes above, the four previously problematic scenarios have focused
passing evidence:

- interrupted setup resume: passed;
- archive and restore: passed through XcodeBuildMCP;
- permanent delete confirmation: passed through XcodeBuildMCP;
- failed direct lifecycle actions: passed through XcodeBuildMCP after the
  test returned to the current library before asserting its row.

The two startup UI scenarios also passed after the CloudKit fixes:

- first-run preference defaults appear without prompting for Calendar access;
- a fresh Simplified Chinese launch reaches the empty subscription library.

A crash report for a separately launched
`SubscriptionManagerUITests-Runner` showed a missing `XCTest.framework`.
Running the same test through Xcode passed once after rebuilding and again via
`test-without-building`, confirming that the runner requires Xcode's injected
test environment and that XCTest must not be embedded into the product.

## Remaining external verification

- Real iPad and Mac acceptance, plus VoiceOver, Dynamic Type, keyboard
  navigation, and reduced-motion scenarios.
- Full App Group, Widget, private CloudKit, and EventKit convergence on devices
  signed by a paid/full Apple Developer team. The connected iPhone acceptance
  launch passed with Personal Team local-only storage, but a Personal Team
  provisioning profile cannot authorize this app's App Group capability.
  Calendar permission must remain user-initiated.
- Manual MenuBarExtra close/reopen/disable/explicit-quit and Login Items
  approval-state scenarios on macOS.
