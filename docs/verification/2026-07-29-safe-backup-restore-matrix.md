# TB21 safe backup restore verification

Date: 2026-07-29

| Requirement | Evidence | Result |
| --- | --- | --- |
| Unsupported or malformed backup causes no mutation | `PortableBackupValidator` rejects malformed JSON, unknown schema/version, duplicate IDs, and invalid subscription facts before the workspace obtains an import command | Pass |
| Preview accurately classifies records | `validatorAndMergePlannerRejectAndClassify` covers additions, unchanged records, conflicts, retained local records, and unchanged preferences | Pass |
| Every conflict requires an explicit decision | `workspaceSubmitsResolvedPortableMergeOnce` proves incomplete decisions do not call the import repository | Pass |
| Failed commit rolls back fully | `failedPortableRestoreRollsBackEveryMutation` injects a SwiftData save failure and confirms original subscription and preferences remain, without the addition | Pass |
| Restore UI uses a native JSON-only flow | `testSettingsOffersPortableRestore` opens Settings, enters Restore Backup, and finds the JSON file selector on iPhone simulator | Pass |
| Local-only records are retained | Preview exposes `retainedLocalSubscriptionIDs`; atomic merge has only additions and explicitly selected replacements | Pass by core behavior |

## Commands run

```text
swift test --package-path Packages/SubscriptionCore
# 88 tests in 9 suites passed

xcodebuild test -quiet -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -only-testing:SubscriptionManagerTests/SwiftDataSubscriptionRepositoryTests/failedPortableRestoreRollsBackEveryMutation
# passed

xcodebuild test -quiet -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSettingsOffersPortableRestore
# passed
```
