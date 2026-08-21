# Evidence Index

This file separates current repository authority from retained historical
research. It is an index, not a progress report, completion record, plan, or
verification matrix.

## Evidence rules

- **Current fact**: supported by current source, configuration, or a shipped
  resource in this repository.
- **Historical evidence**: a dated capture that supports what was observed at
  that time only.
- **Inference**: a reasoned interpretation that is labeled as such and is not
  promoted to a product or catalog fact.
- **Unresolved**: insufficient current primary-source evidence. Leave the value
  unknown or remove the claim; never fill it from memory, a search snippet, a
  community report, or another market/channel.

These are the status labels for every claim retained here. The current-source
table contains **Current facts**; dated artifacts and verdicts are **Historical
evidence**; volatile values described as needing re-verification are
**Unresolved**. This index retains no **Inference** as a product or catalog
fact.

Prices, plans, eligibility, markets, and purchase channels are volatile. A
current claim requires a fresh first-party source plus verification date,
market, locale, account context, and purchase channel. Community material is
discovery evidence only. The retained JSONL status `verified` means verified at
that record's date and context, not verified today.

The shipped bundled catalog contains only `verified` offers. An unresolved or
conflicting candidate is omitted from the bundle rather than retained as a
`reviewRequired` offer; that status remains part of the domain only for safely
rejecting incompatible or unverified external catalog data.

## Current repository authority

| Area | Current authority |
| --- | --- |
| Targets, deployment, entitlements, and resources | [`project.yml`](../project.yml), [`SubscriptionManager/SubscriptionManager.entitlements`](../SubscriptionManager/SubscriptionManager.entitlements), and [`SubscriptionManager/Info.plist`](../SubscriptionManager/Info.plist) |
| Domain behavior and workspace boundaries | [`Packages/SubscriptionCore/Sources/SubscriptionCore/`](../Packages/SubscriptionCore/Sources/SubscriptionCore/) and [ADR 0001](adr/0001-subscription-workspace-boundaries.md) |
| iPhone, iPad, and Mac presentation | [`SubscriptionManager/`](../SubscriptionManager/) |
| Widget behavior | [`SubscriptionManagerWidget/`](../SubscriptionManagerWidget/) |
| Bundled catalog | [`catalog-v1.json`](../SubscriptionManager/Resources/catalog-v1.json) and its [metadata license](../SubscriptionManager/Resources/CATALOG_METADATA_LICENSE.md) |
| Near-term product boundary | [Product Goal](product-goal.md) |

If a historical record conflicts with these current files, the current files
describe implemented behavior. The conflict still needs an approved issue
before code or product behavior changes.

## Retained immutable evidence artifacts

Issue #52 selected these artifacts to survive the documentation cleanup. Their
contents remain historical and must not be rewritten to make them look current.

### JSONL records

| Artifact | Retained role |
| --- | --- |
| [`2026-07-30-round-2-evidence-manifest.jsonl`](research/2026-07-30-round-2-evidence-manifest.jsonl) | Round 2 aggregate evidence manifest; dated source captures and dispositions. |
| [`official-catalog.jsonl`](research/evidence/official-catalog.jsonl) | Dated first-party catalog captures; old amounts require fresh re-verification before reuse. |
| [`current-product.jsonl`](research/evidence/current-product.jsonl) | Product/source observations pinned to an older repository commit; not current-source authority. |
| [`competitive-community.jsonl`](research/evidence/competitive-community.jsonl) | Store and community discovery material; not authorization or normative product evidence. |
| [`ios-interaction.jsonl`](research/evidence/ios-interaction.jsonl) | Dated Apple interaction research supporting platform principles and APIs. |
| [`2026-08-02-round-3-catalog-audit.jsonl`](research/evidence/2026-08-02-round-3-catalog-audit.jsonl) | Round 3 catalog audit snapshot; its prices and statuses are historical. |

The first five files are the Round 2 normalized aggregate manifest and its four
official-catalog, current-product, competitive/community, and iOS-interaction
workstream fragments. The aggregate schema captures identity, source and URL,
access context and date, market/locale/channel, excerpt hash, claim mapping,
repository provenance when applicable, and disposition; the fragments retain
workstream-specific field names. The Round 3 file uses catalog-audit rows with
service/offer context, evidence IDs, review status, and notes.

The dated review lineage must remain explicit:

- On 2026-07-30, the evidence audit was `FAIL`: parsing and hashes passed, but
  schemas, source support, and selectable-offer safety still required
  correction.
- On 2026-08-01, normalized first-pass structure was `PASS`, while the
  source/claim verdict remained `REVISE`. The synthesis also left catalog
  evidence `REVISE — open`; structural validity was not price approval.
- The 2026-08-02 Round 3 row statuses are a later historical audit snapshot,
  not independent proof that an external offer remains current.

The 2026-08-01 candidate-price passes and the ByteDance/Tencent follow-ups were
time-boxed discovery work; none of their amounts survives here. At that date,
88VIP, JD PLUS, and Sam's Club China were not importable from the available
first-party evidence, and Tencent Yuanbao remained unresolved. Those are dated
results, not permanent absence claims.

### Round 2 UI captures

Every image below is a historical UI observation, not a current acceptance
baseline:

1. [`01-library.jpg`](research/evidence/screenshots/round-2-current-ui/01-library.jpg)
2. [`02-browse-catalog.jpg`](research/evidence/screenshots/round-2-current-ui/02-browse-catalog.jpg)
3. [`03-manual-required-plan-category.jpg`](research/evidence/screenshots/round-2-current-ui/03-manual-required-plan-category.jpg)
4. [`04-read-only-detail.jpg`](research/evidence/screenshots/round-2-current-ui/04-read-only-detail.jpg)
5. [`05-actions-menu.jpg`](research/evidence/screenshots/round-2-current-ui/05-actions-menu.jpg)
6. [`06-edit-date-picker-no-done.jpg`](research/evidence/screenshots/round-2-current-ui/06-edit-date-picker-no-done.jpg)
7. [`07-upcoming-range-controls.jpg`](research/evidence/screenshots/round-2-current-ui/07-upcoming-range-controls.jpg)
8. [`08-insights-nested-segmented.jpg`](research/evidence/screenshots/round-2-current-ui/08-insights-nested-segmented.jpg)
9. [`09-swipe-archive-delete.jpg`](research/evidence/screenshots/round-2-current-ui/09-swipe-archive-delete.jpg)
10. [`10-swipe-pin.jpg`](research/evidence/screenshots/round-2-current-ui/10-swipe-pin.jpg)

## Approved first-party re-verification entry points

These URLs preserve the useful source locations selected by Issue #52. A URL's
presence here does not assert that a price, plan, API, or page is unchanged.

### Apple platform guidance

- <https://developer.apple.com/design/human-interface-guidelines/layout>
- <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- <https://developer.apple.com/design/human-interface-guidelines/sheets>
- <https://developer.apple.com/documentation/swiftui/view/sheet%28item%3Aondismiss%3Acontent%3A%29>
- <https://developer.apple.com/documentation/swiftui/view/presentationdetents%28_%3A%29>
- <https://developer.apple.com/documentation/swiftui/view/swipeactions%28edge%3Aallowsfullswipe%3Acontent%3A%29>
- <https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme%28_%3A%29>
- <https://developer.apple.com/documentation/uikit/uicalendarview>
- <https://developer.apple.com/documentation/swiftui/roundedrectangle>

These references support platform APIs and principles. They do not define
project-specific spacing, radii, calendar dimensions, or an “iOS 27 standard”
measurement.

### Current volatile catalog adjudications

The following checks were made on 2026-08-09 against the public Apple China
storefront in a `zh-CN` context without an account:

- Baidu Netdisk, China/iOS: the subscription card and in-app-purchase row both
  list the monthly auto-renewing Super Member at CNY 25. The CNY 30 amount in
  the developer-written description conflicts with those transaction surfaces
  and is treated as stale descriptive copy. The CNY 25 monthly offer remains
  `verified`: <https://apps.apple.com/cn/app/%E7%99%BE%E5%BA%A6%E7%BD%91%E7%9B%98/id547166701>.
- Canva China, China/iOS: the in-app-purchase list supports the CNY 30 monthly
  offer. It also lists same-named annual entries at CNY 298 and CNY 168, so the
  annual price cannot be mapped to a unique offer and is omitted from the
  bundled catalog; only the CNY 30 monthly offer is retained:
  <https://apps.apple.com/cn/app/id897446215>.
- WeChat Reading: the former CNY 228 annual candidate had no verified bundle
  status and has been removed rather than shipped as a pending offer.

### Catalog sources requiring current market/channel verification

- Anthropic: <https://support.anthropic.com/en/articles/11049762-choosing-a-claude-ai-plan>, <https://www.anthropic.com/pricing?subjects=claude&type=product>, <https://support.claude.com/en/articles/10185996-how-to-change-your-pro-plan-from-monthly-to-annual-billing>
- Baidu Netdisk web channels: <https://yun.baidu.com/buy/center>, <https://yun.baidu.com/disk/vipduty>
- YouTube: <https://support.google.com/youtube/answer/16475192>, <https://support.google.com/youtube/answer/11417260?hl=en>

The retained research supports plan or product taxonomy only where the dated
record says so. The old Claude `$240` figure was explicitly rejected as a
standard offer; no current Claude amount is asserted here. Baidu Netdisk web
prices and YouTube plan amounts remain unresolved without fresh first-party
evidence for the exact market and purchase channel; the Baidu China/iOS finding
above is limited to that channel. The same rule applies to 88VIP, JD PLUS,
Sam's Club, and every other offer. Historical AI-service candidate lists are
discovery scope only and do not authorize catalog additions.
