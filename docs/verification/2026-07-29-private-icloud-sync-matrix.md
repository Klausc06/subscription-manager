# TB-16 Private iCloud Sync Verification Matrix

## Preconditions

- Use two devices or simulators signed into the same Apple ID.
- Provision `iCloud.com.klausc06.SubscriptionManager` for CloudKit and enable
  remote notifications with an Apple Developer Program administrator account.
- Install builds signed with the entitlement file in this repository; do not
  use the UI-test store arguments, which deliberately disable CloudKit.

## Scenarios

| Scenario | Action | Expected observable result |
| --- | --- | --- |
| Offline creation | Disable network on Device A, add a subscription, then re-enable network. | The record is immediately usable on A; status is local-only/offline, then the same UUID appears once on B after connectivity returns. |
| Concurrent scalar edit | Change the plan on A and category on B before either reconnects. | Both devices converge to CloudKit's last-writer-wins scalar values; no second subscription is created. |
| Append payment history | Add different confirmed payments on A and B. | Each confirmed charge retains its own stable occurrence identity and converges without a duplicate occurrence. |
| Append price history | Add a price change on A and a different effective-date change on B. | Both dated history entries converge; duplicate effective dates follow the existing local validation rule. |
| Permanent deletion | Delete a record on A and reconnect B. | The same stable record disappears on B; no replacement record appears. |
| Signed out | Sign out of iCloud, launch, and add/edit a subscription. | Library remains usable locally; Settings says iCloud Signed Out and no sign-in prompt is forced. |
| Account change | Change the iCloud account while the app is foregrounded. | Settings refreshes its account-derived status after `CKAccountChanged`; local content remains browsable. |
| Calendar independence | Deny Calendar access while iCloud is available, then repeat while signed out. | iCloud status does not request Calendar permission and Calendar availability does not change the sync status. |

## Local automated evidence

- `swift test --package-path Packages/SubscriptionCore`: 77 tests in 7 suites passed on 2026-07-29.
- `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerTests/AppDependenciesTests -quiet`: passed on 2026-07-29.
- `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`: passed on 2026-07-29.

The macOS build now correctly requests a provisioning profile because the app
declares CloudKit. It cannot be run locally until the named container and a
development team/profile are provisioned; that external account operation is
not represented as a passing verification result.
