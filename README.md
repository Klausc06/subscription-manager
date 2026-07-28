# Subscription Manager

A local-first, open-source subscription manager built natively for iOS 27,
iPadOS 27, and macOS 27.

The project is intentionally at the walking-skeleton stage. The current app
opens an empty SwiftData-backed library in English or Simplified Chinese and
keeps all application behavior behind `SubscriptionWorkspace`.

## Requirements

- Xcode 27
- Swift 6.4
- XcodeGen 2.46 or later

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Open the project

Generate the checked-in Xcode project after changing `project.yml`:

```sh
xcodegen generate
open SubscriptionManager.xcodeproj
```

The `SubscriptionManager` scheme supports iPhone, iPad, and My Mac
destinations from one multiplatform app target.

## Run tests

Run application tests from Xcode, or use:

```sh
xcodebuild \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  test
```

Run the platform-independent workspace behavior tests with:

```sh
swift test --package-path Packages/SubscriptionCore
```

## Architecture

- `SubscriptionCore` owns `SubscriptionWorkspace` and user-observable state.
- SwiftUI calls the workspace instead of coordinating persistence or system
  services directly.
- The app target supplies a local SwiftData repository.
- Future catalog, exchange-rate, Calendar, synchronization, and export
  integrations enter through injected adapters.
- Standard SwiftUI navigation and controls receive the current system
  appearance, including Liquid Glass, without decorative glass content cards.

See [ADR 0001](docs/adr/0001-subscription-workspace-boundaries.md) for the
dependency-boundary decision.

## Privacy

The walking skeleton performs no network request, creates no custom account,
and asks for no Calendar or other protected-resource permission. Signing
credentials, personal Xcode state, and generated build output are excluded
from version control.

## Contributing

Start from the first open `ready-for-agent` GitHub issue whose native blockers
are closed. Keep each change within one ticket, write the externally observable
test first, and run the affected platform builds before opening a pull request.

Application code is licensed under Apache-2.0. Original catalog metadata added
later will use CC0; third-party marks and assets are not covered by either
grant.

Validate the shipped catalog before publishing a data-only update:

```sh
swift run --package-path Packages/SubscriptionCore CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json
```

The catalog metadata dedication is recorded in
[`CATALOG_METADATA_LICENSE.md`](SubscriptionManager/Resources/CATALOG_METADATA_LICENSE.md).
