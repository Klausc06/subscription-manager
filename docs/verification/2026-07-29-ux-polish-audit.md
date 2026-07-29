# UX polish audit — first batch

Date: 2026-07-29

## Scope and evidence

- Exercised the first-run and localized add-form states in the production iOS
  Simulator. The app's complete UI test suite covered the remaining primary
  flows: empty library, detail, archive, restore, permanent deletion,
  preferences, export/restore entry points, upcoming, and insights.
- Built and launched the production iOS Simulator target on iPhone 17 Pro,
  iOS 27, and captured the initial first-run screen after it settled.
- A separate read-only adversarial review checked product copy, accessibility,
  data loss, and macOS behavior against the implementation and existing specs.

## Prioritized punch list

### Must fix

1. Portable restore needs an item-by-item conflict preview and an exact impact
   summary before users choose to overwrite local data. The current view shows
   only a coarse conflict choice; this conflicts with the safe restore spec.
2. macOS needs to present the first-run setup flow for an empty Subscription
   Library in `.needsSetup`, as the iOS root does.
3. macOS needs lifecycle status in its table and must not present a next
   renewal for cancelled, expired, or archived subscriptions as if it were an
   expected charge.

### Should fix

1. Localize the current bare `Selected`/`Not selected` accessibility values
   and App Intent receipts for Simplified Chinese.
2. Confirm macOS bulk archival with the selected count and the forecast
   consequence, then retain/report failed rows.
3. Surface export-destination write failures while keeping a user cancellation
   silent.

### Later

1. Replace free-form scheduled-date entry in Confirm Charge with valid upcoming
   occurrences, or explain eligibility next to the picker.
2. Add end-to-end UI coverage for restore conflict previews and macOS setup.

## Implemented first batch

- Renamed the form field to `Subscription Management URL` / `订阅管理网址`.
- Added a localized explanation that the URL opens the provider's billing,
  renewal, or cancellation page and never cancels a subscription automatically.
- Renamed the detail action to `Manage or Cancel Subscription` /
  `管理或取消订阅`.
- Added a Simplified Chinese UI regression assertion for the field and its
  explanatory copy.

## Focused regression

The added UI assertion first failed because the old field and explanation did
not exist. After the implementation, this passed:

```text
xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -derivedDataPath /private/tmp/subscription-manager-ux-derived test \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSimplifiedChineseAddFlowUsesLocalizedCopy
```

## Full regression

- `swift test --package-path Packages/SubscriptionCore` — 93 tests passed.
- Full `xcodebuild test` for the `SubscriptionManager` iOS Simulator scheme
  passed, including 65 app unit tests and the complete UI-test target.
- `git diff --check` and `jq -e . SubscriptionManager/Resources/Localizable.xcstrings`
  passed.
