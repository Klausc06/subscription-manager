# Authenticated App Intents verification matrix

| Surface | Evidence | Result |
| --- | --- | --- |
| Stable entities | UUID-backed `SubscriptionAppEntity` query reads the live `SubscriptionWorkspace`; display has service, plan, and category only | Pass |
| Add Subscription | Unit test proves the service returns exactly one workspace-created record | Pass |
| Authentication | Unit test asserts all three intents require local-device authentication | Pass |
| Shortcuts discovery | Xcode App Intents metadata export validates three `AppShortcut` phrases | Pass |
| Upcoming renewals | Workspace test excludes archived records and sorts the shared timeline | Pass |
| Monthly forecast | Intent refreshes and consumes the existing Insights exchange-rate adapter; unavailable rates return a recoverable dialog | Pass |
| No provider action | No intent imports provider APIs or Calendar/CloudKit adapters directly | Pass |
| iOS build | `xcodebuild build -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` | Pass |
| macOS build | `xcodebuild build -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO` | Pass |
| Core tests | `swift test --package-path Packages/SubscriptionCore` | Pass |

Physical-device Siri/Shortcuts invocation remains a final manual smoke after
the app is signed with the intended development team; it is not required for
the local simulator build or metadata validation.
