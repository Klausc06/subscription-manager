# Catalog Alphabet Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a locale-aware, tappable and draggable alphabet index to the trailing edge of the catalog.

**Architecture:** A pure catalog-index projection groups the workspace's already-filtered presets into localized letter sections. `CatalogBrowserView` renders those sections inside its existing `List` and overlays a small SwiftUI index that scrolls through stable section anchors with `ScrollViewReader`.

**Tech Stack:** Swift 6.4, SwiftUI, Foundation string transforms, Swift Testing, XCUITest, App Intents metadata compilation.

## Global Constraints

- Preserve existing catalog loading, search, category, detail, confirmation, diagnostics, and update behavior.
- Use Mandarin transliteration for Simplified Chinese initials and `#` for unsupported leading characters.
- Show only letters represented by the current visible presets, ordered `A–Z` and then `#`.
- Hide the index while search is active or results are empty.
- Support tap, drag, VoiceOver buttons, pointer input, Dynamic Type, English, and Simplified Chinese.
- Keep the implementation in SwiftUI; do not add a UIKit bridge or dependency.
- Do not change App Intent actions, entities, shortcut phrases, or runtime handoff behavior.
- Commit and install locally; do not push.

---

### Task 1: Locale-aware catalog section projection

**Files:**
- Create: `SubscriptionManager/Catalog/CatalogAlphabetIndex.swift`
- Create: `SubscriptionManagerTests/CatalogAlphabetIndexTests.swift`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `[CatalogPreset]` and `Locale`.
- Produces: `CatalogIndexProjection.sections(for:locale:) -> [CatalogIndexSection]`.
- Produces: `CatalogIndexSection.id: String`, `title: String`, and `presets: [CatalogPreset]`.

- [ ] **Step 1: Write failing projection tests**

Add fixtures and tests that require Latin sorting, Mandarin transliteration,
`#` fallback, and represented-letter filtering:

```swift
import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct CatalogAlphabetIndexTests {
    @Test("Catalog index groups localized names by represented initial")
    func groupsLocalizedNames() {
        let sections = CatalogIndexProjection.sections(
            for: [
                preset(id: "b", en: "Baidu Netdisk", zhHans: "百度网盘"),
                preset(id: "a", en: "Apple Music", zhHans: "Apple Music"),
                preset(id: "symbol", en: "123 Cloud", zhHans: "123 云盘")
            ],
            locale: Locale(identifier: "en")
        )

        #expect(sections.map(\.id) == ["A", "B", "#"])
        #expect(sections[1].presets.map(\.id) == ["b"])
    }

    @Test("Simplified Chinese catalog names use Mandarin initials")
    func transliteratesChineseNames() {
        let sections = CatalogIndexProjection.sections(
            for: [
                preset(id: "zhihu", en: "Zhihu", zhHans: "知乎"),
                preset(id: "baidu", en: "Baidu", zhHans: "百度网盘")
            ],
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(sections.map(\.id) == ["B", "Z"])
        #expect(sections[0].presets.map(\.id) == ["baidu"])
    }
}
```

The private test fixture creates `CatalogPreset` values with monthly billing,
a generic productivity icon, and original-symbol provenance.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodegen generate
xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerTests/CatalogAlphabetIndexTests test
```

Expected: compilation fails because `CatalogIndexProjection` and
`CatalogIndexSection` do not exist.

- [ ] **Step 3: Implement the minimal projection**

Create:

```swift
import Foundation
import SubscriptionCore
import SwiftUI

struct CatalogIndexSection: Identifiable, Equatable {
    let id: String
    let presets: [CatalogPreset]
    var title: String { id }
}

enum CatalogIndexProjection {
    static func sections(
        for presets: [CatalogPreset],
        locale: Locale
    ) -> [CatalogIndexSection] {
        let grouped = Dictionary(grouping: presets) {
            initial(for: $0.serviceName.value(for: locale))
        }
        return grouped.map { initial, values in
            CatalogIndexSection(
                id: initial,
                presets: values.sorted {
                    $0.serviceName.value(for: locale).localizedCompare(
                        $1.serviceName.value(for: locale)
                    ) == .orderedAscending
                }
            )
        }
        .sorted { order(of: $0.id) < order(of: $1.id) }
    }

    private static func initial(for name: String) -> String {
        let transliterated = name.applyingTransform(
            .mandarinToLatin,
            reverse: false
        ) ?? name
        let folded = transliterated.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en")
        )
        guard let first = folded.first,
              first.isASCII,
              first.isLetter
        else { return "#" }
        return String(first).uppercased()
    }

    private static func order(of initial: String) -> Int {
        initial == "#" ? 26 : Int(initial.unicodeScalars.first!.value - 65)
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project and verify GREEN**

Run `xcodegen generate`, then repeat the focused Xcode test command.

Expected: both projection tests pass.

- [ ] **Step 5: Commit the projection**

```bash
git add SubscriptionManager/Catalog/CatalogAlphabetIndex.swift \
  SubscriptionManagerTests/CatalogAlphabetIndexTests.swift \
  SubscriptionManager.xcodeproj/project.pbxproj
git commit -m "feat(catalog): group presets by alphabet"
```

### Task 2: Tappable and draggable SwiftUI index

**Files:**
- Modify: `SubscriptionManager/Catalog/CatalogAlphabetIndex.swift`
- Modify: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `[CatalogIndexSection]`, `searchQuery`, and the existing filtered presets.
- Produces: `CatalogAlphabetIndex(letters:onSelect:)`.
- Produces accessibility IDs `catalog.alphabet-index`,
  `catalog.alphabet-index.<letter>`, and `catalog.section.<letter>`.

- [ ] **Step 1: Write failing focused UI coverage**

Extend `testCreatesEditableSubscriptionFromBundledCatalog` or add a focused
catalog-index test that:

```swift
let index = app.otherElements["catalog.alphabet-index"]
XCTAssertTrue(index.waitForExistence(timeout: 5))

let letterB = app.buttons["catalog.alphabet-index.B"]
XCTAssertTrue(letterB.exists)
letterB.tap()
XCTAssertTrue(
    app.staticTexts["catalog.section.B"].waitForExistence(timeout: 5)
)

let start = index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
let end = index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
start.press(forDuration: 0.2, thenDragTo: end)

let search = app.searchFields.firstMatch
search.tap()
search.typeText("Spotify")
XCTAssertFalse(index.exists)
```

Add a category-filter assertion that opens `catalog.category`, selects
`Cloud Storage`, and verifies the available index letters rebuild for that
filtered result set.

- [ ] **Step 2: Run the focused UI test and verify RED**

Run:

```bash
xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCatalogAlphabetIndex test
```

Expected: failure because `catalog.alphabet-index` is absent.

- [ ] **Step 3: Implement the index view**

Add a compact `CatalogAlphabetIndex` with a full-width button for each visible
letter and a zero-distance drag gesture. Convert `value.location.y` into a
clamped array index and call `onSelect` only when the selected letter changes:

```swift
struct CatalogAlphabetIndex: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var activeLetter: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Button {
                        select(letter)
                    } label: {
                        Text(letter)
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(letter)")
                    .accessibilityIdentifier("catalog.alphabet-index.\(letter)")
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.y / geometry.size.height
                        let raw = Int(fraction * CGFloat(letters.count))
                        let index = min(max(raw, 0), letters.count - 1)
                        select(letters[index])
                    }
            )
        }
        .frame(width: 28)
        .accessibilityIdentifier("catalog.alphabet-index")
    }

    private func select(_ letter: String) {
        guard activeLetter != letter else { return }
        activeLetter = letter
        onSelect(letter)
    }
}
```

Add a brief tint-backed active state and clear it after 600 milliseconds with
an ID-scoped task. Add English and Simplified Chinese translations for the
`Jump to %@` accessibility label.

- [ ] **Step 4: Render indexed sections in the existing catalog list**

In `CatalogBrowserView`, derive `sections` from the loaded presets, wrap the
list in `ScrollViewReader`, render one `Section` per projection section, give
its header `catalog.section.<letter>`, and overlay the index at `.trailing`.
Use:

```swift
if searchQuery.isEmpty && !sections.isEmpty {
    CatalogAlphabetIndex(letters: sections.map(\.id)) { letter in
        withAnimation(.snappy) {
            proxy.scrollTo(letter, anchor: .top)
        }
    }
    .padding(.trailing, 2)
}
```

The category control remains first and diagnostics remains last. Each section
uses its letter as the stable `id`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the projection tests, the new focused UI test, and
`testCreatesEditableSubscriptionFromBundledCatalog`.

Expected: all selected tests pass and each Xcode command completes under the
300-second tool limit.

- [ ] **Step 6: Commit the interaction**

```bash
git add SubscriptionManager/Catalog/CatalogAlphabetIndex.swift \
  SubscriptionManager/Catalog/CatalogBrowserView.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  SubscriptionManagerUITests/SubscriptionManagerUITests.swift
git commit -m "feat(catalog): add alphabet quick index"
```

### Task 3: Regression, App Intents gate, and physical-device smoke

**Files:**
- Modify only if verification exposes a defect in the catalog-index scope.

**Interfaces:**
- Consumes: the completed catalog index and existing App Intents metadata.
- Produces: passing regression evidence and a locally installed device build.

- [ ] **Step 1: Run data and core validation**

```bash
jq -e . SubscriptionManager/Resources/catalog-v1.json
jq -e . SubscriptionManager/Resources/Localizable.xcstrings
swift run --package-path Packages/SubscriptionCore CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json
swift test --package-path Packages/SubscriptionCore
git diff --check
```

Expected: catalog version 3 with 100 presets, valid string catalogs, 93 passing
core tests, and no whitespace errors.

- [ ] **Step 2: Run grouped app regressions**

Run focused catalog unit tests and the two focused catalog UI tests in separate
Xcode commands. Do not run the entire serial UI suite in one tool call.

Expected: each command succeeds before the 300-second client timeout.

- [ ] **Step 3: Validate the existing App Intents surface**

Build the iOS simulator app and inspect the build log for successful
`ExtractAppIntentsMetadata` and bilingual shortcut training for:

- Add a subscription;
- Show upcoming renewals;
- Show monthly forecast.

No intent type, entity, phrase, or runtime route changes are permitted in this
feature.

- [ ] **Step 4: Review and create the final local commit if needed**

Review the complete diff for behavior, accessibility, performance, and test
coverage. If verification required a scoped correction, commit it with:

```bash
git add SubscriptionManager/Catalog/CatalogAlphabetIndex.swift \
  SubscriptionManager/Catalog/CatalogBrowserView.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  SubscriptionManagerTests/CatalogAlphabetIndexTests.swift \
  SubscriptionManagerUITests/SubscriptionManagerUITests.swift
git commit -m "fix(catalog): stabilize alphabet index"
```

- [ ] **Step 5: Build and install on the registered iPhone**

Build with the previously verified Personal Team local-storage configuration:

```bash
xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -configuration Debug \
  -destination 'platform=iOS,id=00008150-000245CA1AB8401C' \
  -derivedDataPath /tmp/subscription-manager-device-build \
  DEVELOPMENT_TEAM=Z23GL5RZH7 CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_ENTITLEMENTS='' \
  build -allowProvisioningUpdates -allowProvisioningDeviceRegistration
```

Install and launch `com.klausc06.SubscriptionManager` with `devicectl`, then
confirm its process is running on device
`45FA0ADF-6F6D-5926-9115-A6421AA55115`.

- [ ] **Step 6: Confirm clean local state**

Run `git status --short` and `git log -3 --oneline`.

Expected: clean worktree, local feature commits present, and no remote push.
