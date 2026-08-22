# Subscription Manager

A local-first, open-source subscription manager built natively for iPhone,
iPad, and Mac. The Subscription Library is the source of truth; Calendar,
widgets, App Intents, and the Mac menu-bar extra do not own competing state.

## Current capabilities

- Add a subscription from the bundled offline catalog or enter it manually,
  then edit its schedule, price, payment history, and lifecycle.
- Pin, archive, restore, record a cancellation, reactivate, or deliberately
  delete a tracked subscription.
- Review upcoming charges in list and month/day views and compare spending in
  CNY, USD, or EUR with cached exchange-rate snapshots.
- Preview or export a permission-free ICS file, or explicitly import and
  reconcile renewals with Apple Calendar.
- Export JSON or CSV and restore a portable JSON backup.
- Use the iOS widget and App Intents, or the native Mac window and optional
  menu-bar extra.
- Store the library in SwiftData, with the private CloudKit configuration when
  the signed app has the required iCloud entitlement.

The app ships in English and Simplified Chinese and supports system, light, and
dark appearance. The near-term product boundary is defined in
[Product Goal](docs/product-goal.md).

## Requirements

- Xcode with the iOS 27 and macOS 27 SDKs
- XcodeGen

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
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
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
- The app target supplies SwiftData, CloudKit-status, catalog, exchange-rate,
  Calendar, widget, preferences, and portable-backup adapters.
- Standard SwiftUI navigation and controls receive the current system
  appearance, including Liquid Glass, without decorative glass content cards.

See [ADR 0001](docs/adr/0001-subscription-workspace-boundaries.md) for the
dependency-boundary decision.

## Data and network boundaries

- The bundled catalog works offline. Catalog refreshes use the repository's
  published catalog, and spending conversion uses Frankfurter exchange rates.
- ICS preview and export do not require Calendar permission. Apple Calendar
  import is an explicit action and requires the system permission.
- iCloud uses the app's private CloudKit container; future iCloud feature work
  is frozen by the current [Product Goal](docs/product-goal.md).
- Signing credentials, personal Xcode state, and generated build output are
  excluded from version control.

See the [Evidence Index](docs/evidence-index.md) for source authority,
historical research artifacts, and rules for volatile external facts.

## Contributing

Repository work follows [AGENTS.md](AGENTS.md) and the binding
[Production Flow](docs/agents/production-flow.md). Keep each change within one
approved GitHub issue and do not expand its acceptance criteria opportunistically.

Application code is licensed under Apache-2.0. Original catalog metadata uses
CC0; third-party marks and assets are not covered by either grant.

Validate the shipped catalog before publishing a data-only update:

```sh
swift run --package-path Packages/SubscriptionCore CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json
```

The catalog metadata dedication is recorded in
[`CATALOG_METADATA_LICENSE.md`](SubscriptionManager/Resources/CATALOG_METADATA_LICENSE.md).
