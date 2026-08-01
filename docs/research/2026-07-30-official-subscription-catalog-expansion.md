# Official Subscription Catalog Expansion — Round 2 / Workstream 2

**Research date:** 2026-07-31
**Scope:** official catalog and recurring-price evidence only
**Status:** independently audited and corrected research output; not a shipping
catalog and not authorization to edit `catalog-v1.json`

## Executive result

This pass assessed every mandatory named product and 50 additional high-value
services. After the independent evidence audit, the official fragment contains
78 evidence records: 45 `supports`, 6 `contradicts`, 15 `lead-only`, and 12
`not-verifiable`. Evidence disposition describes the relationship between a
source and its excerpt; it does **not** by itself make a price selectable.

The corrected selectable set contains only named standard-renewal offers with
an exact charge, currency, charged interval, market, and channel. The correction
adds independent ChatGPT Go, Plus, Pro 5x and Pro 20x records, and upgrades
iCloud+, Microsoft 365, Xbox Game Pass, and PlayStation Plus after successful
first-party rereads. It removes every `from`, annual-equivalent-only,
promotional-only, cadence-unknown, eligibility-dependent, or conflicting value
from the selectable table.

A safe catalog must model **market + channel + billing cadence + renewal
semantics + evidence state** as part of offer identity. Provider names alone
are not enough:

- Canva International and Canva 可画 have different products, channels,
  prices and tax wording.
- YouTube's official help confirms Individual, Family, Two-person, Student,
  annual/prepaid and Lite variants, while the public US App Store listing
  exposes only the current iOS Individual and Family prices.
- Chinese App Store listings often expose many historical or promotional IAP
  SKUs alongside the current auto-renew description. Only the plan/price pairs
  whose cadence and current recurring semantics are explicit should become
  selectable defaults.
- 88VIP, JD PLUS and Sam's Club name real membership products in public
  official pages, but their complete current purchase prices are account-,
  eligibility-, or app-flow-dependent. Those prices must remain review-only
  until a reproducible first-party purchase surface is captured.

## Method

1. Candidate discovery followed ecosystem/category priority: named products
   first, then fixed recurring subscriptions likely to be tracked by Chinese
   and international users.
2. Public pages were read through the agent-reach/Jina Reader route. When a
   provider page did not expose a channel price, the official regional Apple
   App Store listing was used.
3. A price is selectable only when the first-party page or store listing binds
   one named plan to a numeric standard-renewal charge, currency, charged
   interval, market and channel. Search snippets, press coverage, user reviews
   and remembered prices were not accepted.
4. A displayed monthly equivalent is never converted into an annual offer
   unless the source supplies the complete annual charge. A simple normalized
   total is recorded only when the source explicitly states the per-month
   amount is billed for a 12-month term.
5. Promotions, `from` prices, eligibility-sensitive values,
   prepaid/non-renewing products, enterprise quotes, legacy IAPs, cadence-
   unknown IAP labels and unresolved conflicts are excluded from the selectable
   matrix.
6. Each cited source has an `OFF-*` evidence record in
   `docs/research/evidence/official-catalog.jsonl`. Raw reader output remained
   under `/tmp`.

### Decision labels

- **Verified/selectable:** complete standard-renewal offer facts from a
  first-party source, suitable for a reviewed preset.
- **Verified/review-required:** first-party facts exist, but the value is
  qualified, promotional, eligibility-sensitive, cadence-incomplete, or not a
  complete charged total.
- **Contradicts:** the same first-party surface exposes incompatible current
  values or mappings; no affected price is selectable.
- **Not verifiable:** the public first-party surface does not expose a stable
  current recurring price without account/session/checkout context.
- **Enterprise/quote:** a real plan, but no fixed self-serve recurring price;
  never a price preset.

## Mandatory coverage matrix

| Mandatory product | Market / channel checked | Result | Catalog disposition | Evidence |
| --- | --- | --- | --- | --- |
| 88VIP — two current variants requested | China / Taobao web + official agreement | The official agreement says price follows the live opening flow. Alibaba publicly confirms an eligible-user RMB 88 entry point, but the requested two current variants and their second price were not reproducibly exposed. | Keep service + aliases; no two-price preset. Account-flow recheck required. | OFF-011, OFF-012 |
| JD PLUS | China / JD app + official help | Product and annual/quarterly renewal semantics are official; stable current public price was not exposed. | Service only; price not selectable. | OFF-013 |
| Sam's Club China — ordinary +卓越 | China / official App Store listing | Both membership concepts are present, but the listing does not publish a purchase price. | Preserve two plan names; price not selectable pending official checkout evidence. | OFF-014 |
| 豆包 | China / App Store | App is official and shows in-app purchase availability; no stable named consumer subscription price/cadence was exposed in the public listing. | Not selectable; do not infer a paid plan from “App 内购买”. | OFF-015 |
| 剪映 | China / App Store | 剪映会员 CNY 25/month and 剪映 SVIP CNY 59/month are exposed; listing also contains separate cloud storage subscriptions. | Selectable after treating membership and cloud storage as separate product families. | OFF-016 |
| 即梦 AI | China / App Store | Official auto-renew text: 即梦会员 CNY 69/month and CNY 659/year. The IAP list also contains old/one-time SKUs. | Selectable only from the auto-renew statement; ignore `[废弃]` and one-time points. | OFF-017 |
| 腾讯元宝 | China / App Store | Official app listing did not expose a stable paid recurring plan. | Not selectable; do not invent “Pro”. | OFF-018 |
| Tencent ordinary subscriptions | China / App Store | Tencent Video VIP, Super Video VIP and sports tiers have explicit monthly recurring prices. WeChat Reading has an explicit CNY 19 recurring monthly offer; its quarter/year values conflict with the IAP list. | Video/sports monthly tiers and WeChat Reading monthly are selectable; disputed quarter/year cards are not. | OFF-019, OFF-025, OFF-078 |
| QQ 音乐 multi-tier | China / App Store | Green Diamond is explicitly CNY 15/month. Super Member appears at both CNY 19/month and CNY 30/month on the same listing. | Only Green Diamond CNY 15/month is selectable. Super Member remains conflicting. | OFF-020, OFF-076 |
| ChatGPT complete paid tiers | US display / web | Go USD 8/month, Plus USD 20/month, Pro 5x USD 100/month and Pro 20x USD 200/month are separately evidenced. Go/Plus/Pro have no annual billing. Business is USD 25/user/month or USD 240/user/year, minimum two users. | All stated fixed tiers are selectable; Enterprise remains quote-only. | OFF-001, OFF-002, OFF-071, OFF-072, OFF-073 |
| First-batch international AI | International / web | Claude Pro and Team monthly have exact charges; Claude Max is only a starting value. Perplexity exposes annual monthly equivalents without annual totals. Cursor Pro/Teams have exact monthly charges. | Claude Pro/Team and Cursor are selectable. Claude Max and Perplexity stay review-required. | OFF-003, OFF-028, OFF-029, OFF-074, OFF-075 |
| Canva International | US / web | Pro USD 180/year; Business USD 250/year/person; Enterprise quote. Tax excluded. | Distinct international product family. | OFF-004 |
| Canva 可画 China | China / App Store | Listing text and IAP menu conflict on monthly and annual values. | No price selectable until the authoritative current SKU is identified. | OFF-010 |
| YouTube Premium variants | US / official help + App Store | Official help confirms Individual, Family, Two-person, Student, annual/prepaid and Lite. The US App Store explicitly binds Individual to USD 20.99/month; Family USD 34.99 lacks a cadence in the captured label. Public web checkout was session-bound. | Only iOS Individual is selectable. Family and all web variants require channel-specific cadence/price evidence. | OFF-021, OFF-022, OFF-077 |

## Verified/selectable offer matrix

This is the only price table eligible for a reviewed shipping batch. Every row
has an explicit catalog decision and a complete standard-renewal charge tuple.
Grouped plan rows preserve a one-to-one plan-to-price mapping. Tax text records
source semantics; it is not a tax calculation.

| Service / exact plan(s) | Market · channel | Exact standard-renewal charge | Charged interval | Catalog decision / caveat | Evidence |
| --- | --- | --- | --- | --- | --- |
| ChatGPT Go | US display · web | USD 8 | 1 month | Selectable; no annual plan | OFF-001 |
| ChatGPT Plus | US display · web | USD 20 | 1 month | Selectable; no annual plan | OFF-071 |
| ChatGPT Pro 5x | US display · web | USD 100 | 1 month | Selectable; independent tier; no annual plan | OFF-072 |
| ChatGPT Pro 20x | US display · web | USD 200 | 1 month | Selectable; independent highest-usage tier; no annual plan | OFF-073 |
| ChatGPT Business standard seat | Most countries · web | USD 25/user | 1 month | Selectable; minimum 2 users | OFF-002 |
| ChatGPT Business standard seat | Most countries · web | USD 240/user | 1 year | Selectable; source displays USD 20/user/month billed annually; minimum 2 users | OFF-002 |
| Claude Pro | US display · web | USD 20 | 1 month | Selectable | OFF-003 |
| Claude Pro | US display · web | USD 200 | 1 year | Selectable | OFF-003 |
| Claude Team standard seat | US display · web | USD 25/seat | 1 month | Selectable | OFF-074 |
| Canva International Pro | US display · web | USD 180 | 1 year | Selectable; tax excluded | OFF-004 |
| Canva International Business | US display · web | USD 250/person | 1 year | Selectable; tax excluded | OFF-004 |
| 剪映会员 / 剪映 SVIP | CN · Apple App Store | CNY 25 / CNY 59 | 1 month | Selectable; two exact plan mappings | OFF-016 |
| 即梦会员 | CN · Apple App Store | CNY 69 | 1 month | Selectable | OFF-017 |
| 即梦会员 | CN · Apple App Store | CNY 659 | 1 year | Selectable | OFF-017 |
| 腾讯视频 VIP / 超级影视 VIP / 腾讯体育 VIP / 体育超级 VIP | CN · Apple App Store | CNY 25 / CNY 35 / CNY 25 / CNY 60 | 1 month | Selectable; four exact plan mappings | OFF-019 |
| QQ 音乐绿钻豪华版 | CN · Apple App Store | CNY 15 | 1 month | Selectable; Super Member excluded | OFF-020 |
| YouTube Premium Individual | US · Apple App Store | USD 20.99 | 1 month | Selectable; iOS channel only | OFF-021, OFF-022 |
| 爱奇艺黄金 / 白金 / 星钻 VIP | CN · Apple App Store | CNY 25 / CNY 35 / CNY 45 | 1 month | Selectable; three exact plan mappings | OFF-023 |
| 优酷黄金 VIP | CN · Apple App Store | CNY 25 | 1 month | Selectable | OFF-024 |
| 优酷黄金 VIP | CN · Apple App Store | CNY 238 | 1 year | Selectable | OFF-024 |
| 微信读书付费会员 | CN · Apple App Store | CNY 19 | 1 month | Selectable; quarter/year cards excluded | OFF-025 |
| 哔哩哔哩大会员 | CN · Apple App Store | CNY 15 | 1 month | Selectable | OFF-026 |
| 网易云音乐音乐包 / 黑胶 VIP / 黑胶 SVIP | CN · Apple App Store | CNY 8 / CNY 15 / CNY 28 | 1 month | Selectable; three exact plan mappings | OFF-027 |
| Cursor Pro / Teams | US display · web | USD 20 / USD 40 per user | 1 month | Selectable; two exact plan mappings | OFF-029 |
| 酷狗豪华 VIP / 超级 VIP / 听书 VIP | CN · Apple App Store | CNY 15 / CNY 20 / CNY 8 | 1 month | Selectable; three exact plan mappings | OFF-030 |
| WPS 会员 | CN · Apple App Store | CNY 9 | 1 month | Selectable; preserve exact IAP label | OFF-031 |
| WPS 会员 | CN · Apple App Store | CNY 69 | 1 year | Selectable; preserve exact IAP label | OFF-031 |
| WPS 超级会员 | CN · Apple App Store | CNY 21 | 1 month | Selectable; preserve exact IAP label | OFF-031 |
| 芒果 TV 会员 | CN · Apple App Store | CNY 22 / CNY 63 / CNY 218 | 1 month / 3 months / 1 year | Selectable; three exact cadence mappings | OFF-033 |
| CapCut Standard / Pro | US · Apple App Store | USD 9.99 / USD 19.99 | 1 month | Selectable; distinct from 剪映 | OFF-034 |
| CapCut Pro | US · Apple App Store | USD 89.99 | 1 year | Selectable | OFF-034 |
| Figma Professional full seat | US display · web | USD 16 | 1 month | Selectable | OFF-035 |
| Adobe Creative Cloud Pro | US · web | USD 69.99 | 1 month | Selectable; annual commitment billed monthly; promo excluded | OFF-036 |
| Dropbox Plus / Standard / Advanced | US display · web | USD 9.99 / USD 15 per user / USD 24 per user | 1 month | Selectable; three exact plan mappings | OFF-039 |
| Todoist Pro | US display · web | USD 60/user | 1 year | Selectable | OFF-040 |
| Todoist Business | US display · web | USD 96/user | 1 year | Selectable; local tax may apply | OFF-040 |
| Zoom Workplace Pro | US display · web | USD 16.99/user | 1 month | Selectable; annual display-equivalent excluded | OFF-041 |
| Slack Pro / Business+ | US display · web | USD 8.75/user / USD 18/user | 1 month | Selectable; promo and annual display-equivalents excluded | OFF-042 |
| Spotify Individual / Student / Duo / Family | US · web | USD 12.99 / USD 6.99 / USD 18.99 / USD 21.99 | 1 month | Selectable; standard post-intro renewals; eligibility still applies | OFF-043 |
| Google One Basic 100 GB / Google AI Plus 2 TB / Google AI Pro 5 TB | US display · web | USD 1.99 / USD 9.99 / USD 19.99 | 1 month | Selectable; three exact plan mappings | OFF-045 |
| Coursera Plus | US display · web | USD 59 | 1 month | Selectable | OFF-046 |
| Coursera Plus | US display · web | USD 399 | 1 year | Selectable | OFF-046 |
| Netflix Standard / Premium | US · Apple App Store | USD 19.99 / USD 26.99 | 1 month | Selectable; iOS channel | OFF-048 |
| Disney+ Basic | US · Apple App Store | USD 11.99 | 1 month | Selectable; Premium excluded | OFF-049 |
| HBO Max Basic with Ads / Standard / Premium | US · Apple App Store | USD 10.99 / USD 18.49 / USD 22.99 | 1 month | Selectable; three exact plan mappings | OFF-050 |
| Hulu / Hulu No Ads | US · Apple App Store | USD 11.99 / USD 18.99 | 1 month | Selectable; two exact plan mappings | OFF-051 |
| Paramount+ Essential | US · Apple App Store | USD 8.99 | 1 month | Selectable; Premium excluded | OFF-052 |
| Audible Plus / Premium Plus | US · Apple App Store | USD 7.99 / USD 15.99 | 1 month | Selectable; two exact plan mappings | OFF-053 |
| Headspace | US · Apple App Store | USD 12.99 | 1 month | Selectable | OFF-056 |
| Headspace | US · Apple App Store | USD 69.99 | 1 year | Selectable | OFF-056 |
| Discord Nitro Basic | US · Apple App Store | USD 2.99 | 1 month | Selectable | OFF-058 |
| Discord Nitro | US · Apple App Store | USD 9.99 | 1 month | Selectable | OFF-058 |
| Discord Nitro | US · Apple App Store | USD 99.99 | 1 year | Selectable | OFF-058 |
| MasterClass Individual / Duo / Family | US · Apple App Store | USD 119.99 / USD 179.99 / USD 239.99 | 1 year | Selectable; three exact plan mappings | OFF-059 |
| iCloud+ 50 GB / 200 GB / 2 TB / 6 TB / 12 TB | US display · web | USD 0.99 / USD 2.99 / USD 9.99 / USD 29.99 / USD 59.99 | 1 month | Selectable; five exact storage mappings | OFF-063 |
| Microsoft 365 Personal / Family / Premium | US · web | USD 9.99 / USD 12.99 / USD 19.99 | 1 month | Selectable; three exact plan mappings | OFF-064 |
| Microsoft 365 Personal / Family / Premium | US · web | USD 99.99 / USD 129.99 / USD 199.99 | 1 year | Selectable; three exact plan mappings | OFF-064 |
| Xbox Game Pass Essential / Premium / Ultimate / PC | US · web | USD 9.99 / USD 14.99 / USD 22.99 / USD 13.99 | 1 month | Selectable; regular renewal after any intro | OFF-067 |
| PlayStation Plus Premium | US · web | USD 19.99 / USD 54.99 / USD 159.99 | 1 month / 3 months / 12 months | Selectable; three exact cadence mappings | OFF-068 |
| PlayStation Plus Extra | US · web | USD 16.99 / USD 43.99 / USD 134.99 | 1 month / 3 months / 12 months | Selectable; three exact cadence mappings | OFF-068 |
| PlayStation Plus Essential | US · web | USD 10.99 / USD 27.99 / USD 79.99 | 1 month / 3 months / 12 months | Selectable; three exact cadence mappings | OFF-068 |

## Additional-service coverage and saturation

The expansion floor was 30 additional services. This pass assessed 50:

| Category | Additional services assessed | Verified recurring result | Not-verifiable / review-only result |
| --- | --- | --- | --- |
| AI / creation | Claude, Perplexity, Cursor, CapCut, Adobe Firefly/Creative Cloud, Midjourney, Poe | Claude Pro/Team, Cursor, CapCut and Adobe standard renewal | Claude Max and Perplexity are review-only; Midjourney pricing required login; Poe exposed no stable captured price |
| Productivity / cloud | Figma, GitHub, Grammarly, Dropbox, Todoist, Zoom, Slack, Google One, Notion, 1Password, iCloud+, Microsoft 365 | Figma, Dropbox, Todoist, Zoom monthly, Slack monthly, Google One, iCloud+ and Microsoft 365 | GitHub and Grammarly are review-only; Notion and 1Password still lack reproducible complete prices |
| China video / music | Tencent Video, iQIYI, Youku, Bilibili, NetEase Cloud Music, Kugou, Mango TV | All seven | None for their primary auto-renew tiers; legacy IAP variants remain review-only |
| China reading / cloud | WeChat Reading, WPS, Baidu Netdisk | All three | Conflicting current-vs-description prices require review flags |
| International music / media | Spotify, Apple Music, Netflix, Disney+, HBO Max, Hulu, Paramount+, Prime Video, Audible, Kindle Unlimited | Spotify, Netflix, Disney+ Basic, HBO Max, Hulu, Paramount+ Essential and Audible | Apple Music conflicts internally; Prime Video is only an add-on; Kindle Unlimited lacks a stable price |
| Learning / reading | Coursera, Medium, Duolingo, MasterClass | Coursera and MasterClass | Medium and Duolingo remain review-only |
| Wellness / fitness | Calm, Headspace, Strava | Headspace | Calm conflicts internally; Strava cadence mapping is incomplete |
| Gaming / social | Discord Nitro, Xbox Game Pass, PlayStation Plus, Nintendo Switch Online | Discord Nitro, Xbox Game Pass and PlayStation Plus | Nintendo Switch Online still lacks numeric output |

The independent rerun changed four services from `not-verifiable` to
selectable: iCloud+, Microsoft 365, Xbox Game Pass and PlayStation Plus. That is
substantial new catalog coverage, so the earlier claim that further collection
would mostly repeat known facts is withdrawn. The **model dimensions** appear
stable—market, channel, plan, cadence, renewal semantics and review state—but
the **candidate facts are not saturated**. Continue targeted rereads of
high-value official pages and account-gated Chinese retail memberships rather
than treating one failed reader response as a durable absence.

## Not-verifiable, conflicting and non-selectable items

| Product / candidate | Decision | Why it is not selectable | Evidence / required follow-up |
| --- | --- | --- | --- |
| 88VIP requested two-tier set | Not verifiable | Live opening flow controls price; RMB 88 is eligibility-dependent and does not prove the complete pair. | OFF-011, OFF-012; capture an official eligible-account API/CLI response with exact tier labels and renewal terms. |
| JD PLUS | Not verifiable | Official help confirms cadences but exposes no stable current purchase price. | OFF-013; capture official member-center checkout response with account context. |
| Sam's Club ordinary / 卓越 | Not verifiable | Official listing names the memberships but publishes no price. | OFF-014; obtain an official public membership page or machine-readable purchase response. |
| 豆包 paid consumer plan | Not verifiable | “App 内购买” is not a named recurring plan with price and cadence. | OFF-015; recheck official billing help or named subscription card. |
| 腾讯元宝 paid consumer plan | Not verifiable | No recurring paid plan is exposed. | OFF-018; recheck only after Tencent publishes one. |
| Canva 可画 monthly/annual | Contradicts | Listing prose and current IAP menu disagree. | OFF-010; identify the authoritative current SKU before any preset. |
| QQ Music Super Member | Contradicts | The same listing shows CNY 19/month and CNY 30/month. | OFF-076; identify segment/current SKU. |
| WeChat Reading quarter/year | Contradicts | Prose says CNY 228/year while the current IAP list shows CNY 168; quarter/year recurring status is unresolved. | OFF-078; retain only OFF-025 monthly. |
| Baidu Netdisk Super Member | Contradicts | Store card says CNY 25/month while description says CNY 30/month. | OFF-032; no price until reconciled. |
| Apple Music | Contradicts | Current section says USD 11.99/month while a stale-looking FAQ says USD 10.99/month. | OFF-044; document an authoritative-section/recency rule and reread. |
| Calm Premium | Contradicts | Listing prose and generic IAP values conflict. | OFF-055; obtain a named current subscription card. |
| YouTube Family and other web variants | Review-required | Family USD 34.99 has no captured cadence; Lite, Student, Two-person and annual/prepaid lack channel-specific prices. | OFF-021, OFF-077; capture official market/account checkout output. |
| Claude Max | Review-required | Only a qualified starting value is published. | OFF-075; capture one exact tier/charge tuple. |
| Perplexity Pro / Max annual | Review-required | Only monthly display equivalents are captured, not annual totals. | OFF-028; capture complete annual charges. |
| GitHub Team / Enterprise | Review-required | Captured prices apply only to the first 12 months. | OFF-037; capture standard post-promotion renewal. |
| Grammarly Pro | Review-required | Displayed USD 12 is not bound to a complete charged annual total. | OFF-038; capture charge cadence and total. |
| Adobe intro offer | Review-required | USD 34.99/month is a three-month promotion, not standard renewal. | OFF-079; only OFF-036 standard renewal is selectable. |
| Zoom annual display | Review-required | USD 14.16/user/month is an annual equivalent without a captured annual total. | OFF-080; monthly OFF-041 remains selectable. |
| Slack annual displays | Review-required | USD 7.25 and USD 15 are annual equivalents without captured annual totals. | OFF-081; monthly OFF-042 remains selectable. |
| Medium annual values | Review-required | Captured annual prices are discounted; standard renewal is absent. | OFF-047; capture renewal terms. |
| Disney+ Premium | Review-required | USD 18.99 and USD 189.99 are not bound to cadences in the captured IAP labels. | OFF-082; Basic monthly OFF-049 remains selectable. |
| Paramount+ Premium | Review-required | USD 13.99 is not bound to a cadence in the captured IAP label. | OFF-083; Essential monthly OFF-052 remains selectable. |
| Duolingo Super | Review-required | Multiple generic IAP values lack unambiguous plan/cadence mapping. | OFF-054; capture named current subscription cards. |
| Strava | Review-required | Generic USD 11.99 and USD 79.99 labels do not bind cadence. | OFF-057; capture explicit month/year labels. |
| ChatGPT Enterprise / Canva Enterprise | Enterprise/quote | Sales-assisted price, not a fixed self-serve offer. | OFF-004 and official plan-family pages; keep identity only. |
| Notion / Poe / 1Password | Not verifiable | Public reader output still omits stable complete numeric offers. | OFF-060, OFF-061, OFF-062; recheck official billing/help endpoints. |
| Prime membership / Kindle Unlimited | Not verifiable | Prime Video IAP is only an add-on; Kindle output lacks a stable price. | OFF-065, OFF-066; use official membership billing help. |
| Nintendo Switch Online | Not verifiable | Official output still exposes no numeric price. | OFF-069; recheck regional official store API. |
| Midjourney | Not verifiable | Pricing remains login-gated. | OFF-070; capture a reproducible account-context response. |

## Catalog data-model recommendation

### 1. Keep `CatalogPreset` as the current regional-product boundary

The three-runtime-entity Service → RegionalProduct → Offer graph is
conceptually valid but premature. The proven cases fit the existing boundary
with a smaller additive change:

```text
CatalogPreset (one searchable regional edition)
  id
  optional familyID
  marketCode / edition label
  localized names + aliases
  stable categoryID
  management URL
  offers[]

CatalogOffer
  plan
  market / channel
  exact charge + currency + interval
  source URL + verified date + review state
```

Use separate `canva-international` and `canva-cn` presets with optional
`familyID = canva`. Keep CapCut and 剪映 separate product identities. Keep
YouTube variants as offers under the corresponding regional preset. Keep
88VIP, JD PLUS and Sam's searchable without a selectable price.

Promote `RegionalProduct` to a first-class runtime type only when a demonstrated
consumer needs an independent regional lifecycle, shared management metadata,
or update semantics that separate presets cannot express.

### 2. Make offer identity channel-specific

An offer key should include at least:

`presetID + market + channel + plan + interval + priceSemantics`

`youtube-premium-us-ios/individual/1-month/standard-renewal` is not the same
offer as a US web checkout or student plan. Channel is identity-bearing data.

### 3. Keep nonstandard price facts out of selectable `offers[]`

Only `standardRenewal` with an exact charged total enters selectable
`offers[]`. `introductory`, `annualEquivalent`, `from`,
`eligibilityDependent`, `prepaidNonRenewing`, `quote`, `unknown`, and
conflicting facts remain research/review metadata until corrected.

Do not flatten an annual monthly display-equivalent into a monthly charge.
Store the complete annual total and interval when available; otherwise disable
selection.

### 4. Evidence is first-class offer metadata

Every selectable offer should reference:

- canonical source URL;
- evidence ID;
- verified date;
- source market/locale/account context;
- last checked date and next review date;
- a reason when selection is disabled.

High-volatility AI, streaming and Chinese App Store prices should receive
shorter review windows than stable annual plans.

### 5. Unknown remains unknown

A discovered regional preset may ship as a searchable identity with no offer.
This is safer than inventing a generic CNY/USD monthly price and still supports
manual entry: the person supplies their actual charge.

## S1–S8 relevance

Workstream 2 directly supplies fixtures for:

- **S1:** independent ChatGPT Go, Plus, Pro 5x, Pro 20x and Business offers
  have complete market/currency/interval facts and can test adopting a verified
  known service without collapsing Pro tiers.
- **S8:** `88`, `88VIP`, `淘宝会员` and localized aliases can surface the
  regional preset without copying an unverified or eligibility-dependent
  price. Selection must visibly say that price requires manual entry.

For S2–S7, this research constrains defaults: selecting a verified offer may
populate price/currency/interval, while selecting a service-only result must
not invent them. Dates remain person-supplied schedule facts.

## Light architecture / less-code opportunities

1. **One immutable regional-preset catalog:** `CatalogPreset` plus `offers[]`
   can feed search, Add confirmation, Edit matching, widgets and review without
   introducing a third runtime entity or per-screen lookup tables.
2. **One offer adoption reducer:** a single operation copies only verified
   offer facts into Add/Edit draft state; manual overrides remain separate
   user facts.
3. **Generated indexes:** localized names, aliases and optional `familyID` can
   be derived into a search index at build time; no hand-coded `88` or regional
   conditionals in SwiftUI.
4. **Data-driven review gates:** `reviewState` and `availableUntil` suppress
   stale presets without deleting service identity or adding bespoke product
   code.
5. **Money/cadence primitives:** one `Money` + `BillingInterval` model avoids
   strings such as “$17/mo billed annually” being parsed independently by
   multiple surfaces.

## Risks

- Official App Store IAP menus can retain legacy or segmented SKUs. The
  description's auto-renew section and a current subscription card are
  stronger than an undifferentiated IAP list.
- Region inference from IP or page locale can silently change prices.
  Verification must store market, locale and account context.
- Promotions can look like the standard price. The standard renewal value is
  the preset; introductory terms are secondary metadata.
- “From” and annual-equivalent prices cannot safely populate an exact monthly
  charge without user confirmation.
- Enterprise quotes and eligibility-dependent retail memberships are real
  plans but are not fixed-price catalog offers.
- A static catalog will stale. Shipping a verified price requires an owner,
  review cadence and a reversible disable path.

## Follow-up validation queue

The independent audit reran every original `OFF-*` command and reopened all
supporting, conflicting and not-verifiable records. The correction then
recollected seven first-party pages: ChatGPT Go, Plus and Pro; iCloud+;
Microsoft 365; Xbox Game Pass; and PlayStation Plus. The latter four rereads
changed the catalog outcome, so future audits must treat a failed reader
response as an access-session observation, not proof that a provider publishes
no price.

1. Obtain account-context evidence for 88VIP, JD PLUS and YouTube web variants;
   report the exact market/eligibility blocker before any login-based retrieval.
2. Reconcile Canva 可画, QQ Music Super Member, WeChat Reading quarter/year,
   Apple Music, Calm and Baidu Netdisk conflicts.
3. Capture complete annual charges for Perplexity, Zoom and Slack annual
   displays before considering those values selectable.
4. Reopen all high-volatility AI and streaming sources on a short review
   cadence, including both independent ChatGPT Pro tiers.
5. Validate the eventual shipping catalog with schema rules: complete offer
   identity, positive minor-unit price, supported ISO currency, explicit
   interval, canonical source and non-expired evidence.
6. Record the final reviewed preset batch separately from this research report;
   do not copy review-required, conflicting or not-verifiable rows into
   shipping data.

## Independent-audit finding closure

| Finding | Official-catalog status after correction |
| --- | --- |
| AUD-01 — ChatGPT aggregate source omitted prices and USD 200 | **Closed for this workstream.** OFF-001 now covers Go; OFF-071 covers Plus; OFF-072 and OFF-073 independently cover Pro 5x USD 100 and Pro 20x USD 200. Both Pro records state that annual billing is unavailable. |
| AUD-02 — evidence facts were mixed with selectable decisions | **Closed.** The selectable matrix has an explicit decision column and only exact standard-renewal charge tuples. Qualified, promotional and incomplete totals moved to review-only records. |
| AUD-03 — unresolved App Store conflicts | **Closed for catalog decisions.** Green Diamond, WeChat Reading monthly, YouTube Individual, Disney+ Basic and Paramount+ Essential were split from their unsafe siblings. Canva 可画, QQ Super, WeChat Reading quarter/year, Apple Music, Calm and Baidu remain non-selectable. |
| AUD-04 — four sources were incorrectly marked unavailable | **Closed.** OFF-063, OFF-064, OFF-067 and OFF-068 have new access times, excerpts, hashes and selectable conclusions. The saturation claim is withdrawn. |
| AUD-05 — compound CUR claims | **Open outside this workstream.** It concerns `current-product.jsonl`; this owner did not edit another workstream's fragment. |
| AUD-06 — fragment key vocabulary differs | **Open at deterministic merge.** This fragment remains internally consistent; the synthesis owner must normalize all fragments to one output schema rather than editing only one contributor in isolation. |
| AUD-07 — mutable-tree CUR commands | **Open outside this workstream.** It concerns current-product evidence commands. |

## Evidence coverage ledger

The ledger makes the 78-record accounting explicit and ensures every report
reference resolves:

- `supports` (45): OFF-001, OFF-002, OFF-003, OFF-004, OFF-016, OFF-017,
  OFF-019, OFF-020, OFF-022, OFF-023, OFF-024, OFF-025, OFF-026, OFF-027,
  OFF-029, OFF-030, OFF-031, OFF-033, OFF-034, OFF-035, OFF-036, OFF-039,
  OFF-040, OFF-041, OFF-042, OFF-043, OFF-045, OFF-046, OFF-048, OFF-049,
  OFF-050, OFF-051, OFF-052, OFF-053, OFF-056, OFF-058, OFF-059, OFF-063,
  OFF-064, OFF-067, OFF-068, OFF-071, OFF-072, OFF-073, OFF-074.
- `contradicts` (6): OFF-010, OFF-032, OFF-044, OFF-055, OFF-076, OFF-078.
- `lead-only` (15): OFF-012, OFF-021, OFF-028, OFF-037, OFF-038, OFF-047,
  OFF-054, OFF-057, OFF-075, OFF-077, OFF-079, OFF-080, OFF-081, OFF-082,
  OFF-083.
- `not-verifiable` (12): OFF-011, OFF-013, OFF-014, OFF-015, OFF-018,
  OFF-060, OFF-061, OFF-062, OFF-065, OFF-066, OFF-069, OFF-070.

Before handoff, the fragment is checked for JSON parsing, unique IDs, required
fields, allowed dispositions, excerpt SHA-256 equality, canonical URL/command
agreement, non-future access times, and bidirectional report references.
