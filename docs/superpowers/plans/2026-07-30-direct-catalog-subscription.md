# Direct Catalog Subscription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `+` open the catalog, let a person choose a verified official offer without typing, and save directly from one confirmation screen.

**Architecture:** Extend the offline catalog with backward-compatible service offers, keep offer filtering and defaults in a pure projection, and reuse `AddSubscriptionView` as the single confirmation surface. `LibraryView` presents the catalog as the sheet root; catalog rows and first-run setup push confirmation directly.

**Tech Stack:** Swift 6.4, SwiftUI, SubscriptionCore, Swift Testing, XCUITest, JSON catalog resources, XcodeGen, XcodeBuildMCP, GitHub CLI.

**Target document:** `docs/superpowers/specs/2026-07-30-direct-catalog-subscription-design.md`

## Global Constraints

- Keep `SubscriptionWorkspace` as the application command boundary.
- Keep the catalog offline-first and preserve old cached records without offers.
- Never invent a period, price, currency, market, or purchase channel.
- Web and iOS storefront prices are distinct offers.
- A verified offer must be selectable without keyboard input.
- Catalog confirmation uses system Back plus Save; it does not also show Cancel.
- Keep manual entry as a secondary catalog action.
- Keep `MARKETING_VERSION = 0.1.0`.
- Create GitHub milestone `0.1` only after implementation, regression, local commit, and physical-device smoke pass.
- Do not create a Git tag or GitHub Release.
- Do not push the new implementation unless the user explicitly asks.

## Target-to-Task Matrix

| Target | Implemented by | Verified by |
| --- | --- | --- |
| UX-01 | Task 5 | Task 5 UI test |
| UX-02 | Task 5 | Task 5 UI test |
| UX-03 | Tasks 3–4 | Tasks 3–4 tests |
| UX-04 | Task 4 | Task 4 UI test |
| UX-05 | Task 5 | Task 5 UI test |
| UX-06 | Task 5 | First-run UI tests |
| DATA-01 | Task 1 | Core catalog tests |
| DATA-02 | Task 2 | Bundled catalog tests |
| DATA-03 | Task 2 | Catalog validator and fixtures |
| DATA-04 | Task 4 | Confirmation UI test |
| DATA-05 | Tasks 1–2 | Legacy decode and cache tests |
| TEST-01 | Tasks 1–3 | Focused unit suites |
| TEST-02 | Task 5 | Direct-path UI test |
| TEST-03 | Task 5 | No-keyboard save UI test |
| TEST-04 | Task 6 | Regression commands |
| TEST-05 | Task 6 | Physical-device install and launch |
| REL-01 | Task 6 | Build setting and GitHub milestone checks |

---

### Task 1: Add backward-compatible official offers to SubscriptionCore

**Targets:** DATA-01, DATA-05, TEST-01

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift`

**Interfaces:**
- Produces: `CatalogPurchaseChannel`, `CatalogOfferReviewStatus`, and `CatalogOffer`.
- Extends: `CatalogPreset.offers: [CatalogOffer]`.
- Preserves: decoding a `CatalogPreset` whose JSON has no `offers` key.
- Preserves: `CatalogPreset.suggestedInterval` as the offer-less fallback.

- [ ] **Step 1: Write failing model and validation tests**

Add tests that require a legacy preset to decode with an empty offer list, a
valid offer to round-trip, and duplicate or invalid offers to fail:

```swift
@Test("Legacy catalog presets decode without offers")
func legacyCatalogPresetsDecodeWithoutOffers() throws {
    let preset = try JSONDecoder().decode(
        CatalogPreset.self,
        from: Data("""
        {
          "id": "legacy",
          "serviceName": { "en": "Legacy", "zhHans": "旧服务" },
          "category": { "en": "Other", "zhHans": "其他" },
          "suggestedInterval": "monthly",
          "managementURL": null,
          "icon": "other",
          "assetProvenance": {
            "kind": "originalSymbol",
            "license": "CC0-1.0",
            "source": "legacy"
          }
        }
        """.utf8)
    )

    #expect(preset.offers.isEmpty)
}

@Test("Verified catalog offers round-trip with provenance")
func verifiedCatalogOffersRoundTrip() throws {
    let offer = CatalogOffer(
        id: "plus-monthly-us-web",
        planName: CatalogLocalizedText(en: "Plus", zhHans: "Plus"),
        price: Money(minorUnits: 2_000, currency: .usd),
        billingInterval: .monthly,
        market: "US",
        purchaseChannel: .web,
        sourceURL: try #require(URL(string: "https://example.com/pricing")),
        verifiedOn: "2026-07-30",
        reviewStatus: .verified
    )
    let preset = CatalogPreset(
        id: "example",
        serviceName: CatalogLocalizedText(en: "Example", zhHans: "示例"),
        category: CatalogLocalizedText(en: "Other", zhHans: "其他"),
        suggestedInterval: .monthly,
        managementURL: nil,
        icon: .other,
        offers: [offer]
    )

    let decoded = try JSONDecoder().decode(
        CatalogPreset.self,
        from: JSONEncoder().encode(preset)
    )
    #expect(decoded.offers == [offer])
}

@Test("Catalog rejects duplicate offer identifiers")
func catalogRejectsDuplicateOfferIdentifiers() {
    let offer = verifiedOffer(id: "duplicate")
    let preset = catalogPreset(offers: [offer, offer])

    #expect(throws: CatalogLoadError.self) {
        try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [preset]
        )
    }
}
```

Add focused invalid cases for zero price, non-HTTPS source URL, empty market,
empty verification date, and invalid billing interval. Assert
`CatalogLoadError.field == .offers`.

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter CatalogTests
```

Expected: compilation fails because `CatalogOffer`,
`CatalogPurchaseChannel`, `CatalogOfferReviewStatus`, `.offers`, and the new
initializer argument do not exist.

- [ ] **Step 3: Implement the offer types**

Add these public value types before `CatalogPreset`:

```swift
public enum CatalogPurchaseChannel: String, Codable, Equatable, Sendable {
    case web
    case ios = "iOS"
}

public enum CatalogOfferReviewStatus: String, Codable, Equatable, Sendable {
    case verified
    case reviewRequired
}

public struct CatalogOffer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let planName: CatalogLocalizedText
    public let price: Money
    public let billingInterval: BillingInterval
    public let market: String
    public let purchaseChannel: CatalogPurchaseChannel
    public let sourceURL: URL
    public let verifiedOn: String
    public let reviewStatus: CatalogOfferReviewStatus

    public init(
        id: String,
        planName: CatalogLocalizedText,
        price: Money,
        billingInterval: BillingInterval,
        market: String,
        purchaseChannel: CatalogPurchaseChannel,
        sourceURL: URL,
        verifiedOn: String,
        reviewStatus: CatalogOfferReviewStatus
    ) {
        self.id = id
        self.planName = planName
        self.price = price
        self.billingInterval = billingInterval
        self.market = market
        self.purchaseChannel = purchaseChannel
        self.sourceURL = sourceURL
        self.verifiedOn = verifiedOn
        self.reviewStatus = reviewStatus
    }
}
```

Add `case offers` to `CatalogValidationField`.

- [ ] **Step 4: Make `CatalogPreset` decoding additive**

Add `offers: [CatalogOffer]` to the initializer with default `[]`. Implement
explicit Codable conformance so missing JSON remains valid:

```swift
private enum CodingKeys: String, CodingKey {
    case id
    case serviceName
    case category
    case suggestedInterval
    case managementURL
    case icon
    case assetProvenance
    case offers
}

public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
        id: try container.decode(String.self, forKey: .id),
        serviceName: try container.decode(
            CatalogLocalizedText.self,
            forKey: .serviceName
        ),
        category: try container.decode(
            CatalogLocalizedText.self,
            forKey: .category
        ),
        suggestedInterval: try container.decode(
            BillingInterval.self,
            forKey: .suggestedInterval
        ),
        managementURL: try container.decodeIfPresent(
            URL.self,
            forKey: .managementURL
        ),
        icon: try container.decode(CatalogIcon.self, forKey: .icon),
        assetProvenance: try container.decodeIfPresent(
            CatalogAssetProvenance.self,
            forKey: .assetProvenance
        ),
        offers: try container.decodeIfPresent(
            [CatalogOffer].self,
            forKey: .offers
        ) ?? []
    )
}

public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(serviceName, forKey: .serviceName)
    try container.encode(category, forKey: .category)
    try container.encode(suggestedInterval, forKey: .suggestedInterval)
    try container.encodeIfPresent(managementURL, forKey: .managementURL)
    try container.encode(icon, forKey: .icon)
    try container.encode(assetProvenance, forKey: .assetProvenance)
    if !offers.isEmpty {
        try container.encode(offers, forKey: .offers)
    }
}
```

- [ ] **Step 5: Validate every offer**

Within `CatalogSnapshot.init`, validate unique trimmed IDs, positive money,
valid interval, HTTPS source, non-empty market, and `yyyy-MM-dd` verification
dates:

```swift
var offerIdentifiers = Set<String>()
for offer in preset.offers {
    let offerID = offer.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !offerID.isEmpty,
          offerIdentifiers.insert(offerID).inserted,
          offer.planName.isValid,
          offer.price.minorUnits > 0,
          offer.billingInterval.isValid,
          !offer.market.trimmingCharacters(
              in: .whitespacesAndNewlines
          ).isEmpty,
          offer.sourceURL.scheme?.lowercased() == "https",
          isValidCatalogVerificationDate(offer.verifiedOn)
    else {
        throw CatalogLoadError(
            presetID: identifier,
            field: .offers,
            message: "offer is invalid or duplicated"
        )
    }
}
```

Add this file-private helper:

```swift
private func isValidCatalogVerificationDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value) else {
        return false
    }
    return formatter.string(from: date) == value
}
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter CatalogTests
swift test --package-path Packages/SubscriptionCore
```

Expected: focused catalog tests pass and the full current core suite passes.

Commit:

```bash
git add Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift
git commit -m "feat(core): model verified catalog offers"
```

---

### Task 2: Ship the first verified service-offer batch

**Targets:** DATA-02, DATA-03, DATA-05, TEST-01

**Files:**
- Modify: `SubscriptionManager/Resources/catalog-v1.json`
- Modify: `SubscriptionManagerTests/BundledCatalogRepositoryTests.swift`

**Interfaces:**
- Consumes: `CatalogPreset.offers`.
- Produces: catalog version `4`, 106 services, and the verified offer IDs in
  the table below.
- Migrates: service preset `chatgpt-plus` to `chatgpt`.

- [ ] **Step 1: Write failing bundled-data expectations**

Add a test that loads the real resource and asserts:

```swift
@Test("Bundled catalog exposes verified first-batch offers")
@MainActor
func bundledCatalogExposesVerifiedFirstBatchOffers() throws {
    let snapshot = try BundledCatalogRepository().loadSnapshot()
    #expect(snapshot.catalogVersion == 4)
    #expect(snapshot.presets.count == 106)

    let chatGPT = try #require(
        snapshot.presets.first(where: { $0.id == "chatgpt" })
    )
    #expect(chatGPT.serviceName.en == "ChatGPT")
    #expect(chatGPT.offers.map(\.id) == [
        "go-monthly-us-web",
        "plus-monthly-us-web",
        "pro-5x-monthly-us-web",
        "pro-20x-monthly-us-web"
    ])
    #expect(
        chatGPT.offers.map(\.price.minorUnits)
            == [800, 2_000, 10_000, 20_000]
    )
    #expect(chatGPT.offers.allSatisfy {
        $0.billingInterval == .monthly
    })
    #expect(
        snapshot.presets.contains(where: { $0.id == "chatgpt-plus" })
            == false
    )
}
```

Add a second assertion that every offer in the bundled snapshot uses USD,
market `US`, a verified status, HTTPS source, and
`verifiedOn == "2026-07-30"`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodegen generate
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerTests/BundledCatalogRepositoryTests test
```

Expected: failure because the bundled catalog remains version 3 and has no
service offers.

- [ ] **Step 3: Replace ChatGPT Plus with the ChatGPT service**

Use this exact shape for ChatGPT and repeat it for the remaining matrix:

```json
{
  "id": "chatgpt",
  "serviceName": { "en": "ChatGPT", "zhHans": "ChatGPT" },
  "category": { "en": "Productivity", "zhHans": "效率" },
  "suggestedInterval": "monthly",
  "managementURL": "https://chatgpt.com/",
  "icon": "productivity",
  "assetProvenance": {
    "kind": "originalSymbol",
    "license": "CC0-1.0",
    "source": "chatgpt"
  },
  "offers": [
    {
      "id": "go-monthly-us-web",
      "planName": { "en": "Go", "zhHans": "Go" },
      "price": { "minorUnits": 800, "currency": "USD" },
      "billingInterval": "monthly",
      "market": "US",
      "purchaseChannel": "web",
      "sourceURL": "https://openai.com/chatgpt/pricing/",
      "verifiedOn": "2026-07-30",
      "reviewStatus": "verified"
    },
    {
      "id": "plus-monthly-us-web",
      "planName": { "en": "Plus", "zhHans": "Plus" },
      "price": { "minorUnits": 2000, "currency": "USD" },
      "billingInterval": "monthly",
      "market": "US",
      "purchaseChannel": "web",
      "sourceURL": "https://openai.com/chatgpt/pricing/",
      "verifiedOn": "2026-07-30",
      "reviewStatus": "verified"
    },
    {
      "id": "pro-5x-monthly-us-web",
      "planName": { "en": "Pro (5x)", "zhHans": "Pro（5x）" },
      "price": { "minorUnits": 10000, "currency": "USD" },
      "billingInterval": "monthly",
      "market": "US",
      "purchaseChannel": "web",
      "sourceURL": "https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro",
      "verifiedOn": "2026-07-30",
      "reviewStatus": "verified"
    },
    {
      "id": "pro-20x-monthly-us-web",
      "planName": { "en": "Pro (20x)", "zhHans": "Pro（20x）" },
      "price": { "minorUnits": 20000, "currency": "USD" },
      "billingInterval": "monthly",
      "market": "US",
      "purchaseChannel": "web",
      "sourceURL": "https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro",
      "verifiedOn": "2026-07-30",
      "reviewStatus": "verified"
    }
  ]
}
```

- [ ] **Step 4: Add every verified first-batch offer**

Set `catalogVersion` to `4`. Preserve all existing services and add or enrich
the following exact USD, US Web offers:

| Service ID | Offer ID | Plan | Interval | Minor units | Official source |
| --- | --- | --- | --- | ---: | --- |
| `claude` | `pro-monthly-us-web` | Pro | monthly | 2000 | `https://www.anthropic.com/pricing` |
| `claude` | `pro-yearly-us-web` | Pro | yearly | 20000 | `https://www.anthropic.com/pricing` |
| `claude` | `max-5x-monthly-us-web` | Max (5x) | monthly | 10000 | `https://www.anthropic.com/pricing` |
| `claude` | `max-20x-monthly-us-web` | Max (20x) | monthly | 20000 | `https://www.anthropic.com/pricing` |
| `google-ai` | `ai-plus-monthly-us-web` | Google AI Plus | monthly | 999 | `https://one.google.com/about/google-ai-plans/` |
| `google-ai` | `ai-pro-monthly-us-web` | Google AI Pro | monthly | 1999 | `https://one.google.com/about/google-ai-plans/` |
| `microsoft-365` | `personal-monthly-us-web` | Personal | monthly | 999 | `https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365` |
| `microsoft-365` | `personal-yearly-us-web` | Personal | yearly | 9999 | `https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365` |
| `microsoft-365` | `family-monthly-us-web` | Family | monthly | 1299 | `https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365` |
| `microsoft-365` | `family-yearly-us-web` | Family | yearly | 12999 | `https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365` |
| `microsoft-365` | `premium-monthly-us-web` | Premium | monthly | 1999 | `https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365` |
| `microsoft-365` | `premium-yearly-us-web` | Premium | yearly | 19999 | `https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365` |
| `youtube-premium` | `lite-monthly-us-web` | Premium Lite | monthly | 799 | `https://blog.youtube/news-and-events/introducing-premium-lite/` |
| `spotify` | `individual-monthly-us-web` | Individual | monthly | 1299 | `https://www.spotify.com/us/premium/` |
| `spotify` | `student-monthly-us-web` | Student | monthly | 699 | `https://www.spotify.com/us/premium/` |
| `spotify` | `duo-monthly-us-web` | Duo | monthly | 1899 | `https://www.spotify.com/us/premium/` |
| `spotify` | `family-monthly-us-web` | Family | monthly | 2199 | `https://www.spotify.com/us/premium/` |
| `netflix` | `ads-monthly-us-web` | Standard with ads | monthly | 899 | `https://help.netflix.com/en/node/22` |
| `netflix` | `standard-monthly-us-web` | Standard | monthly | 1999 | `https://help.netflix.com/en/node/22` |
| `netflix` | `premium-monthly-us-web` | Premium | monthly | 2699 | `https://help.netflix.com/en/node/22` |
| `disney-plus` | `ads-monthly-us-web` | With Ads | monthly | 1199 | `https://help.disneyplus.com/article/disneyplus-price` |
| `disney-plus` | `premium-monthly-us-web` | Premium | monthly | 1899 | `https://help.disneyplus.com/article/disneyplus-price` |
| `disney-plus` | `premium-yearly-us-web` | Premium | yearly | 18999 | `https://help.disneyplus.com/article/disneyplus-price` |
| `notion` | `plus-one-member-monthly-us-web` | Plus (1 member) | monthly | 1200 | `https://www.notion.com/pricing` |
| `notion` | `plus-one-member-yearly-us-web` | Plus (1 member) | yearly | 12000 | `https://www.notion.com/pricing` |
| `canva` | `pro-one-person-yearly-us-web` | Pro (1 person) | yearly | 18000 | `https://www.canva.com/pricing/` |

Every row uses:

```json
{
  "market": "US",
  "purchaseChannel": "web",
  "verifiedOn": "2026-07-30",
  "reviewStatus": "verified"
}
```

Create the new services with these names and categories:

```text
claude          Claude / Claude                    Productivity / 效率
google-ai       Google AI / Google AI              Productivity / 效率
microsoft-365   Microsoft 365 / Microsoft 365      Productivity / 效率
youtube-premium YouTube Premium / YouTube Premium  Video / 视频
disney-plus     Disney+ / Disney+                  Video / 视频
canva           Canva / Canva                      Productivity / 效率
```

Use the matching original CC0 symbol provenance and an official management
URL for each service. Keep the existing `canva-china` service separate.

- [ ] **Step 5: Validate the resource and verify GREEN**

Run:

```bash
jq -e . SubscriptionManager/Resources/catalog-v1.json
swift run --package-path Packages/SubscriptionCore CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerTests/BundledCatalogRepositoryTests test
```

Expected: valid JSON, `schema=1 version=4 presets=106`, and the focused test
passes.

- [ ] **Step 6: Commit the verified data**

```bash
git add SubscriptionManager/Resources/catalog-v1.json \
  SubscriptionManagerTests/BundledCatalogRepositoryTests.swift
git commit -m "feat(catalog): add verified official offers"
```

---

### Task 3: Build deterministic offer selection

**Targets:** UX-03, DATA-01, TEST-01

**Files:**
- Create: `SubscriptionManager/Catalog/CatalogOfferSelection.swift`
- Create: `SubscriptionManagerTests/CatalogOfferSelectionTests.swift`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj` through
  `xcodegen generate`

**Interfaces:**
- Produces: `CatalogOfferSelection.selectableOffers(in:)`.
- Produces: `CatalogOfferSelection.periods(in:)`.
- Produces: `CatalogOfferSelection.defaultOffer(in:)`.
- Produces: `CatalogOfferSelection.offers(in:periodRawValue:)`.
- All period selection uses `BillingInterval.rawValue`, avoiding a new
  `Hashable` requirement on `BillingInterval`.

- [ ] **Step 1: Write failing projection tests**

```swift
import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct CatalogOfferSelectionTests {
    @Test("Selection excludes offers that require review")
    func excludesReviewRequiredOffers() {
        let preset = preset(
            offers: [
                offer(id: "verified", interval: .monthly, status: .verified),
                offer(
                    id: "review",
                    interval: .yearly,
                    status: .reviewRequired
                )
            ]
        )
        #expect(
            CatalogOfferSelection.selectableOffers(in: preset).map(\.id)
                == ["verified"]
        )
    }

    @Test("Monthly is the deterministic default period")
    func monthlyIsDefault() throws {
        let preset = preset(
            offers: [
                offer(id: "annual", interval: .yearly),
                offer(id: "monthly", interval: .monthly)
            ]
        )
        #expect(
            CatalogOfferSelection.defaultOffer(in: preset)?.id
                == "monthly"
        )
        #expect(
            CatalogOfferSelection.periods(in: preset)
                == ["monthly", "yearly"]
        )
    }
}
```

Add tests for a monthly-only service, a selected yearly period filtering out
monthly offers, stable plan-name ordering, and an offer-less legacy service.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
xcodegen generate
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerTests/CatalogOfferSelectionTests test
```

Expected: compilation fails because `CatalogOfferSelection` does not exist.

- [ ] **Step 3: Implement the pure projection**

```swift
import Foundation
import SubscriptionCore

enum CatalogOfferSelection {
    static func selectableOffers(
        in preset: CatalogPreset
    ) -> [CatalogOffer] {
        preset.offers
            .filter { $0.reviewStatus == .verified }
            .sorted(by: offerOrder)
    }

    static func periods(in preset: CatalogPreset) -> [String] {
        let values = Set(
            selectableOffers(in: preset)
                .map(\.billingInterval.rawValue)
        )
        return values.sorted {
            periodRank($0) < periodRank($1)
        }
    }

    static func defaultOffer(in preset: CatalogPreset) -> CatalogOffer? {
        let offers = selectableOffers(in: preset)
        return offers.first(where: { $0.billingInterval == .monthly })
            ?? offers.first
    }

    static func offers(
        in preset: CatalogPreset,
        periodRawValue: String
    ) -> [CatalogOffer] {
        selectableOffers(in: preset).filter {
            $0.billingInterval.rawValue == periodRawValue
        }
    }

    private static func offerOrder(
        _ lhs: CatalogOffer,
        _ rhs: CatalogOffer
    ) -> Bool {
        let leftRank = periodRank(lhs.billingInterval.rawValue)
        let rightRank = periodRank(rhs.billingInterval.rawValue)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if lhs.price.minorUnits != rhs.price.minorUnits {
            return lhs.price.minorUnits < rhs.price.minorUnits
        }
        return lhs.id < rhs.id
    }

    private static func periodRank(_ rawValue: String) -> Int {
        switch rawValue {
        case BillingInterval.monthly.rawValue: 0
        case BillingInterval.yearly.rawValue: 1
        case BillingInterval.quarterly.rawValue: 2
        case BillingInterval.halfYearly.rawValue: 3
        case BillingInterval.weekly.rawValue: 4
        default: 5
        }
    }
}
```

- [ ] **Step 4: Verify GREEN and commit**

Run the focused test command again.

Expected: every offer-selection test passes.

Commit:

```bash
git add SubscriptionManager/Catalog/CatalogOfferSelection.swift \
  SubscriptionManagerTests/CatalogOfferSelectionTests.swift \
  SubscriptionManager.xcodeproj/project.pbxproj
git commit -m "feat(catalog): select verified service offers"
```

---

### Task 4: Turn confirmation into a no-typing official-offer form

**Targets:** UX-03, UX-04, DATA-04

**Files:**
- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/BillingScheduleSupport.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**
- Consumes: `CatalogOfferSelection` and `CatalogPreset.offers`.
- Adds: `AddSubscriptionView(..., showsCancellationAction: Bool = true)`.
- Adds accessibility identifiers:
  `subscription.form.offer-period`,
  `subscription.form.offer-plan`,
  `subscription.form.offer-provenance`,
  `subscription.form.offer-source`, and
  `subscription.form.adjust-charge`.
- Adds read-only identifiers:
  `subscription.form.selected-plan` and
  `subscription.form.selected-price`.
- Adds:
  `defaultNextRenewal(after:interval:calendar:) -> Date`.

- [ ] **Step 1: Write a failing offer-form UI test**

Add a launch path that reaches ChatGPT confirmation, then require:

```swift
let planPicker = app.buttons["subscription.form.offer-plan"]
XCTAssertTrue(planPicker.waitForExistence(timeout: 5))
planPicker.tap()
app.buttons["Pro (5x)"].tap()

XCTAssertTrue(
    app.descendants(matching: .any)["subscription.form.selected-plan"]
        .label.contains("Pro (5x)")
)
XCTAssertTrue(
    app.descendants(matching: .any)["subscription.form.selected-price"]
        .label.contains("$100")
)
XCTAssertTrue(
    app.staticTexts["subscription.form.offer-provenance"]
        .label.contains("US")
)
XCTAssertTrue(
    app.links["subscription.form.offer-source"].exists
)
```

The temporary navigation in this test may still use the current
`Use This Preset` action; Task 5 removes that step.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCatalogOfficialOfferPrefillsConfirmation test
```

Expected: failure because the offer controls do not exist.

- [ ] **Step 3: Initialize catalog-backed form state from the default offer**

Store the preset because offer controls need it after initialization:

```swift
private let catalogPreset: CatalogPreset?
```

Assign `catalogPreset = preset` in `AddSubscriptionView.init`, then compute:

```swift
let defaultOffer = preset.flatMap {
    CatalogOfferSelection.defaultOffer(in: $0)
}
let initialDate = Date()
_selectedOfferID = State(initialValue: defaultOffer?.id)
_selectedPeriodRawValue = State(
    initialValue: defaultOffer?.billingInterval.rawValue
        ?? preset?.suggestedInterval.rawValue
        ?? BillingInterval.monthly.rawValue
)
_plan = State(
    initialValue: defaultOffer?.planName.value(for: locale) ?? ""
)
_amountText = State(
    initialValue: defaultOffer.map {
        editableMoneyText($0.price, locale: locale)
    } ?? ""
)
_currency = State(initialValue: defaultOffer?.price.currency ?? .usd)
_intervalChoice = State(
    initialValue: BillingIntervalChoice(
        interval: defaultOffer?.billingInterval
            ?? preset?.suggestedInterval
            ?? .monthly
    )
)
_startDate = State(initialValue: initialDate)
_renewalAnchor = State(initialValue: initialDate)
_confirmedNextRenewal = State(
    initialValue: defaultNextRenewal(
        after: initialDate,
        interval: defaultOffer?.billingInterval
            ?? preset?.suggestedInterval
            ?? .monthly,
        calendar: .current
    )
)
```

Reuse the existing `editableMoneyText(_:locale:)` helper so the amount remains
locale-correct and parseable by `MoneyTextParser`.

Add the selection projections used by the view:

```swift
private var availablePeriods: [String] {
    guard let catalogPreset else { return [] }
    return CatalogOfferSelection.periods(in: catalogPreset)
}

private var offersForSelectedPeriod: [CatalogOffer] {
    guard let catalogPreset else { return [] }
    return CatalogOfferSelection.offers(
        in: catalogPreset,
        periodRawValue: selectedPeriodRawValue
    )
}

private var selectedOffer: CatalogOffer? {
    guard let selectedOfferID, let catalogPreset else { return nil }
    return CatalogOfferSelection.selectableOffers(in: catalogPreset)
        .first(where: { $0.id == selectedOfferID })
}
```

- [ ] **Step 4: Render the `Official Offer` section first**

For a preset with verified offers, render:

```swift
Section("Official Offer") {
    if availablePeriods.count > 1 {
        Picker(
            "Billing Period",
            selection: $selectedPeriodRawValue
        ) {
            ForEach(availablePeriods, id: \.self) { rawValue in
                Text(localizedBillingInterval(
                    BillingInterval(rawValue: rawValue) ?? .monthly
                ))
                .tag(rawValue)
            }
        }
        .accessibilityIdentifier("subscription.form.offer-period")
    } else if let selectedOffer {
        LabeledContent(
            "Billing Period",
            value: localizedBillingInterval(
                selectedOffer.billingInterval
            )
        )
    }

    Picker("Plan", selection: $selectedOfferID) {
        ForEach(offersForSelectedPeriod) { offer in
            Text(offer.planName.value(for: locale))
                .tag(Optional(offer.id))
        }
    }
    .accessibilityIdentifier("subscription.form.offer-plan")

    if let selectedOffer {
        LabeledContent(
            "Plan",
            value: selectedOffer.planName.value(for: locale)
        )
        .accessibilityIdentifier("subscription.form.selected-plan")

        LabeledContent(
            "Official Price",
            value: formattedMoney(selectedOffer.price)
        )
        .accessibilityIdentifier("subscription.form.selected-price")
        Text(
            "\(selectedOffer.market) · "
                + selectedOffer.purchaseChannel.localizedTitle
                + " · Verified \(selectedOffer.verifiedOn)"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(
            "subscription.form.offer-provenance"
        )
    }
}
```

Add localized purchase-channel titles and Simplified-Chinese string-catalog
entries.

- [ ] **Step 5: Make catalog fields read-only and actual-price editing secondary**

For catalog-backed confirmation:

```swift
LabeledContent("Service", value: serviceName)
LabeledContent("Category", value: category)
```

Do not render editable service, plan, category, amount, currency, or interval
controls until `Adjust Actual Charge` is expanded. The adjustment action
reveals only amount, currency, and interval; service and selected official
plan remain stable.

For an offer-less preset, keep the existing editable plan, amount, currency,
and interval controls visible so a legacy or not-yet-researched service is
still usable. Keep all existing date, status, management URL, notes,
validation, workspace save, and offer-less preset fallback behavior.

- [ ] **Step 6: Apply offer changes atomically**

When period changes, select the first offer in that period. When offer changes:

```swift
.onChange(of: selectedPeriodRawValue) { _, _ in
    selectedOfferID = offersForSelectedPeriod.first?.id
}
.onChange(of: selectedOfferID) { _, _ in
    applySelectedOffer()
}
```

Apply the selection in one function:

```swift
private func applySelectedOffer() {
    guard let offer = selectedOffer else { return }
    plan = offer.planName.value(for: locale)
    amountText = editableMoneyText(offer.price, locale: locale)
    currency = offer.price.currency
    intervalChoice = BillingIntervalChoice(
        interval: offer.billingInterval
    )
    if !renewalDatesWereEdited {
        confirmedNextRenewal = defaultNextRenewal(
            after: renewalAnchor,
            interval: offer.billingInterval,
            calendar: .current
        )
    }
}
```

Wrap each date picker in a `Binding` whose setter marks
`renewalDatesWereEdited = true`. Programmatic defaults assign the stored state
directly so they do not mark it edited.

Add the exact interval helper to `BillingScheduleSupport.swift`:

```swift
func defaultNextRenewal(
    after date: Date,
    interval: BillingInterval,
    calendar: Calendar
) -> Date {
    let component: Calendar.Component
    let value: Int
    switch interval {
    case .weekly:
        component = .day
        value = 7
    case .monthly:
        component = .month
        value = 1
    case .quarterly:
        component = .month
        value = 3
    case .halfYearly:
        component = .month
        value = 6
    case .yearly:
        component = .year
        value = 1
    case .custom(let count, let unit):
        switch unit {
        case .day:
            component = .day
            value = count
        case .week:
            component = .day
            value = count * 7
        case .month:
            component = .month
            value = count
        case .year:
            component = .year
            value = count
        }
    }
    return calendar.date(
        byAdding: component,
        value: value,
        to: date
    ) ?? date
}
```

- [ ] **Step 7: Show provenance and verify GREEN**

Add the selected offer's `sourceURL` as `Official Pricing Source` in the
optional section and show localized copy explaining regional, tax, and
storefront differences.

Run the focused UI test.

Expected: ChatGPT Pro (5x) fills plan, USD 100, monthly interval, US Web
provenance, and source link without keyboard entry.

- [ ] **Step 8: Commit the confirmation form**

```bash
git add SubscriptionManager/Library/AddSubscriptionView.swift \
  SubscriptionManager/Library/BillingScheduleSupport.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  SubscriptionManagerUITests/SubscriptionManagerUITests.swift
git commit -m "feat(app): prefill official subscription offers"
```

---

### Task 5: Remove both add-flow intermediate screens

**Targets:** UX-01, UX-02, UX-05, UX-06, TEST-02, TEST-03

**Files:**
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Delete: `SubscriptionManager/Catalog/CatalogPresetDetailView.swift`
- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj` through
  `xcodegen generate`

**Interfaces:**
- `LibraryView` presents `CatalogBrowserView` as the sheet root.
- `CatalogBrowserView` receives `onCancel` and `onSubscriptionCreated`.
- Catalog service rows push `AddSubscriptionView` directly.
- `AddSubscriptionView(showsCancellationAction: false)` relies on system Back.

- [ ] **Step 1: Rewrite the direct-path UI test first**

Update the bundled-catalog test so it requires the final path:

```swift
app.buttons["subscription.add"].tap()
XCTAssertTrue(
    app.navigationBars["Browse Catalog"].waitForExistence(timeout: 5)
)
XCTAssertFalse(app.buttons["subscription.add.catalog"].exists)

let search = app.searchFields.firstMatch
search.tap()
search.typeText("ChatGPT")
app.buttons["catalog.preset.chatgpt"].tap()

XCTAssertTrue(
    app.navigationBars["Confirm Subscription"]
        .waitForExistence(timeout: 5)
)
XCTAssertFalse(app.navigationBars["Catalog Details"].exists)
XCTAssertFalse(app.buttons["catalog.use-preset"].exists)
XCTAssertFalse(app.buttons["subscription.form.cancel"].exists)
XCTAssertTrue(app.buttons["subscription.form.save"].exists)
```

Select `Pro (5x)`, save without typing, and assert the library row contains
`ChatGPT`, `Pro (5x)`, and USD 100.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCreatesSubscriptionFromOfficialCatalogOffer test
```

Expected: the test fails because `+` still opens the manual form.

- [ ] **Step 3: Present the catalog at the sheet root**

Replace the sheet root in `LibraryView`:

```swift
case .addSubscription:
    NavigationStack {
        CatalogBrowserView(
            workspace: workspace,
            onSubscriptionCreated: {
                presentedSheet = nil
                workspace.loadLibrary(scope: .current)
            },
            onCancel: {
                presentedSheet = nil
            }
        )
    }
```

Keep `LibrarySheet` identity behavior unchanged.

- [ ] **Step 4: Add root cancel and secondary manual entry**

Extend `CatalogBrowserView` with `onCancel`. Add:

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", action: onCancel)
            .accessibilityIdentifier("catalog.cancel")
    }
}
```

Add one secondary catalog action:

```swift
Section {
    NavigationLink {
        AddSubscriptionView(
            workspace: workspace,
            showsCancellationAction: false,
            onSuccessfulSave: onSubscriptionCreated
        )
    } label: {
        Label("Add Manually", systemImage: "square.and.pencil")
    }
    .accessibilityIdentifier("catalog.add-manually")
}
```

- [ ] **Step 5: Push confirmation directly from every catalog row**

Replace `CatalogPresetDetailView` in `CatalogBrowserView` with:

```swift
NavigationLink {
    AddSubscriptionView(
        workspace: workspace,
        preset: preset,
        showsCancellationAction: false,
        onSuccessfulSave: onSubscriptionCreated
    )
} label: {
    CatalogPresetRow(preset: preset, locale: locale)
}
```

Conditionally render the form's cancellation toolbar:

```swift
if showsCancellationAction {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
            .accessibilityIdentifier("subscription.form.cancel")
    }
}
```

Keep Save as the confirmation action.

- [ ] **Step 6: Make first-run setup use the same direct confirmation**

Change its destination to:

```swift
AddSubscriptionView(
    workspace: workspace,
    preset: preset,
    showsCancellationAction: false,
    onSuccessfulSave: {
        confirmedPresetIDs.insert(presetID)
        navigationPath.removeAll()
    }
)
```

Update setup UI tests to remove both `catalog.use-preset` taps. Preserve
multi-selection, confirmed identity tracking, interruption, resume, and finish
behavior.

- [ ] **Step 7: Delete the obsolete detail view and regenerate**

Delete only:

```text
SubscriptionManager/Catalog/CatalogPresetDetailView.swift
```

Run:

```bash
xcodegen generate
rg -n "CatalogPresetDetailView|catalog.use-preset|Catalog Details" \
  SubscriptionManager SubscriptionManagerTests SubscriptionManagerUITests
```

Expected: no production or test references remain.

- [ ] **Step 8: Run focused direct-flow and setup tests**

Run:

```bash
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCreatesSubscriptionFromOfficialCatalogOffer \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testFirstRunConfirmsEachSelectedPresetBeforeFinishing \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testInterruptedSetupResumesWithoutDuplicatingConfirmedPreset \
  test
```

Expected: all three scenarios pass.

- [ ] **Step 9: Commit the direct navigation**

```bash
git add SubscriptionManager/Library/LibraryView.swift \
  SubscriptionManager/Catalog/CatalogBrowserView.swift \
  SubscriptionManager/Library/AddSubscriptionView.swift \
  SubscriptionManagerUITests/SubscriptionManagerUITests.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  SubscriptionManager.xcodeproj/project.pbxproj
git add -u SubscriptionManager/Catalog/CatalogPresetDetailView.swift
git commit -m "feat(app): open catalog directly from add"
```

---

### Task 6: Regress, install, commit, and establish milestone 0.1

**Targets:** TEST-04, TEST-05, REL-01

**Files:**
- Modify only if verification exposes a defect within this feature's scope.

**Interfaces:**
- Consumes: completed catalog offers and direct navigation.
- Produces: clean local commits, physical-device smoke evidence, and one open
  GitHub milestone named `0.1`.
- Does not produce: a remote code push, Git tag, or GitHub Release.

- [ ] **Step 1: Validate data and core behavior**

Run:

```bash
jq -e . SubscriptionManager/Resources/catalog-v1.json
jq -e . SubscriptionManager/Resources/Localizable.xcstrings
swift run --package-path Packages/SubscriptionCore CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json
swift test --package-path Packages/SubscriptionCore
git diff --check
```

Expected: catalog version 4 with 106 services, valid string catalog, all core
tests pass, and no whitespace errors.

- [ ] **Step 2: Run focused app and UI regression**

Run the catalog model tests, offer-selection tests, bundled repository tests,
direct add flow, alphabet index, manual add flow, and first-run setup tests.
Use separate Xcode invocations if the 300-second XcodeBuildMCP limit requires
it.

Expected:

- direct ChatGPT offer save passes;
- existing alphabet tap and drag passes;
- search hides the alphabet index;
- first-run setup resume passes;
- manual add remains usable;
- no `Catalog Details` or `Use This Preset` surface remains.

- [ ] **Step 3: Build the complete simulator app and check App Intents**

Before the first XcodeBuildMCP build, call `session_show_defaults`. Confirm the
project, scheme, and iPhone 17 Pro simulator, then call `build_run_sim`.

Expected build log contains:

```text
ExtractAppIntentsMetadata
Writing Metadata.appintents
BUILD SUCCEEDED
```

Take a simulator screenshot of:

1. the catalog opened directly from `+`;
2. ChatGPT confirmation with the offer picker and US Web provenance.

- [ ] **Step 4: Confirm version 0.1.0**

Run:

```bash
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager -showBuildSettings \
  | rg "MARKETING_VERSION = 0.1.0"
```

Expected: both app configurations retain `MARKETING_VERSION = 0.1.0`.

- [ ] **Step 5: Confirm the implemented state is committed**

Run:

```bash
git status --short
```

Expected: no output. If a regression step exposed a defect, return to the task
that owns the failing target, add a focused failing test there, make its
explicit file changes, rerun that task's verification, and commit before
continuing. Do not create an empty verification commit.

- [ ] **Step 6: Build for the registered physical iPhone**

Run:

```bash
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -configuration Debug \
  -destination 'platform=iOS,id=00008150-000245CA1AB8401C' \
  -derivedDataPath /tmp/subscription-manager-device-build \
  DEVELOPMENT_TEAM=Z23GL5RZH7 \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_ENTITLEMENTS='' \
  build -allowProvisioningUpdates -allowProvisioningDeviceRegistration
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Install, launch, and confirm processes**

Run:

```bash
xcrun devicectl device install app \
  --device 45FA0ADF-6F6D-5926-9115-A6421AA55115 \
  /tmp/subscription-manager-device-build/Build/Products/Debug-iphoneos/SubscriptionManager.app
xcrun devicectl device process launch \
  --device 45FA0ADF-6F6D-5926-9115-A6421AA55115 \
  com.klausc06.SubscriptionManager
xcrun devicectl device info processes \
  --device 45FA0ADF-6F6D-5926-9115-A6421AA55115 \
  --filter 'executable.path CONTAINS "SubscriptionManager"'
```

Expected: install and launch succeed; both the main app and widget extension
processes are present.

- [ ] **Step 8: Confirm clean local completion**

Run:

```bash
git status --short
git log -8 --oneline --decorate
```

Expected: clean worktree and all implementation commits local on
`feat/tb-23-app-intents`. Do not run `git push`.

- [ ] **Step 9: Create the GitHub milestone last**

Check for an existing milestone:

```bash
gh api 'repos/Klausc06/subscription-manager/milestones?state=all' \
  --jq '.[] | select(.title == "0.1") | [.number, .state, .title]'
```

If no result exists, create exactly one open milestone:

```bash
gh api repos/Klausc06/subscription-manager/milestones \
  --method POST \
  -f title='0.1' \
  -f state='open' \
  -f description='0.1 establishes the offline subscription library, official-offer catalog and direct add flow, renewal forecasts, payment history, insights, backup and restore, widgets, App Intents, and supported iPhone, iPad, and Mac surfaces.'
```

Verify:

```bash
gh api 'repos/Klausc06/subscription-manager/milestones?state=open' \
  --jq '.[] | select(.title == "0.1") | [.number, .state, .title]'
```

Expected: one open milestone named `0.1`. Do not create a tag, Release, or
push.

## Completion Report

Report completion against the target identifiers:

```text
UX-01...UX-06: pass/fail with UI evidence
DATA-01...DATA-05: pass/fail with catalog/test evidence
TEST-01...TEST-05: pass/fail with counts and device evidence
REL-01: marketing version and milestone URL/number
Local commits: hashes
Remote code push: not performed
```
