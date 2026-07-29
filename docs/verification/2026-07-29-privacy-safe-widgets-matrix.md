# Privacy-safe widgets verification matrix

Date: 2026-07-29

## Covered behavior

| Scenario | Evidence | Result |
| --- | --- | --- |
| Current next renewal | `SubscriptionWorkspace.makeWidgetSnapshot()` derives the earliest eligible expected charge and writes a versioned local snapshot after the library reloads. | Covered by core build and snapshot-store test. |
| Empty library | An empty `WidgetSnapshot` is persisted and renders the localized empty state. | Covered by `WidgetPresentationBuilder` behavior and the Widget view. |
| Unavailable or malformed snapshot | The shared store rejects malformed or unsupported data; WidgetKit renders a predictable “open the app” state. | Covered by store version guard and build. |
| Stale snapshot | A snapshot older than 36 hours asks the person to refresh in the app; the timeline requests the next overnight refresh. | Covered by `RenewalWidgetEntry.isStale` and provider timeline. |
| Locked privacy | The amount is omitted for `.privacy` redaction and the remaining amount view is marked `privacySensitive()`. | Covered by `widgetPrivacyPresentationRedactsAmount`. |
| Stable destination | Widget URLs use `subscription-manager://subscriptions` or `subscription-manager://subscription/<UUID>`; the App registers the scheme and opens the matching navigation path. | Verified from generated `Info.plist` and iOS build. |
| Supported families | Accessory rectangular, small, and medium are declared by `RenewalWidget`. | Verified by iOS build. |
| Localization and VoiceOver | Widget empty, unavailable, stale, display-name, and description strings have English and Simplified Chinese translations. The view provides a combined accessibility label and uses dynamic type text styles. | Verified by iOS build. |

## Commands run

1. `swift test` in `Packages/SubscriptionCore` — 90 tests passed.
2. `xcodebuild ... -sdk iphonesimulator ... build CODE_SIGNING_ALLOWED=NO` — passed.
3. `xcodebuild ... -destination 'platform=macOS' ... build CODE_SIGNING_ALLOWED=NO` — passed.
4. `xcodebuild ... -destination 'platform=iOS Simulator,id=CA671619-CF06-4674-93D6-C2F234E81BEF' test` — App installation and 59 unit tests passed after extension metadata repair.
5. `xcodebuild -quiet ... -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testArchivesAndRestoresSubscription test` — passed.

## Release note

The App Group entitlement is configured as `group.com.klausc06.SubscriptionManager`. A device/archive build still requires this App Group to be enabled for the App ID in the Apple Developer account so the provisioning profile contains the new entitlement.
