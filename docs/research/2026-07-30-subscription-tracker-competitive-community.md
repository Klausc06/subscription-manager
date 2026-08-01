# Subscription Tracker Competitive, Open-Source, and Community Research

**Research date:** 2026-07-31
**Workstream:** Round 2, Workstream 3
**Requirements covered:** R2-01–R2-14, with primary emphasis on R2-01–R2-05,
R2-08–R2-10, R2-12–R2-14
**Evidence fragment:** `docs/research/evidence/competitive-community.jsonl`

## Executive finding

The evidence does not support copying one tracker. It supports a composed
pattern:

1. one catalog-assisted Add flow with a manual continuation path;
2. one direct editable workspace for Add and Edit;
3. native row actions for archive, pin, and confirmed permanent deletion;
4. a month calendar plus selected-day agenda, backed by one shared schedule
   projection;
5. market-specific catalog offers and aliases rather than guessed global
   defaults.

The strongest negative result is equally important: hard-coded service prices,
categories, currencies, and recurrence defaults are common in small
open-source trackers and are exactly the wrong implementation to reuse. Those
shortcuts make a demo fast but silently manufacture facts for real people.

Community items below are reports and preferences, not population estimates.
Individual items are coded `anecdotal`; a pattern is called `repeated` only
when at least three independent discussions support it.

## Method and source boundaries

- Product features and maintenance status come from official App Store
  listings retrieved through Apple's Search/Lookup API. A current version date
  is evidence of maintenance, not evidence that every described interaction is
  polished.
- Implementation claims come from source read at a fixed Git commit. README
  claims and screenshots were not used to establish implementation facts.
- Community discussions were retrieved through public APIs/readers. They
  establish vocabulary, pain points, workarounds, and preferences only.
- No screenshots, browser clicking, or browser extensions were used for
  evidence retrieval.
- The OpenCLI health check reported logged-in adapters for Reddit, X,
  小红书, and B站, but actual calls could not connect to the Chrome extension.
  Reddit and X search CLIs also failed (Reddit unavailable without the
  extension; Twitter search returned HTTP 404 twice). Reddit discovery used
  the search API result corpus; B站 used its public search API; V2EX used its
  public topic and reply APIs. 小红书 and X are therefore explicit access gaps,
  not silently omitted sources.
- Raw response bodies remained under `/tmp`.

## Competitor cohort

All 15 products were maintained at the time of research. Listings were checked
on 2026-07-31; the dates below are the listing's
`currentVersionReleaseDate`.

| Product | Platform / type | Last listed update | Officially described relevant behavior | What can be reused or rejected |
| --- | --- | ---: | --- | --- |
| [Rocket Money](https://apps.apple.com/us/app/rocket-money-bills-budgets/id1130616675) | iOS; linked-account finance | 2026-07-28 | Automatically identifies recurring charges, unifies them in a recurring list, shows upcoming bills, and offers cancellation assistance. | Reuse the action-oriented recurring overview; reject bank linking as a prerequisite for a local-first manual tracker. |
| [Bobby](https://apps.apple.com/us/app/bobby-track-subscriptions/id1059152023) | iOS; manual subscription tracker | 2025-12-09 | Choose from hundreds of existing subscriptions or create a custom one; provides at-a-glance upcoming bills and due notifications. | Strong support for catalog-first plus manual escape and high-yield list rows. The listing does not establish its exact edit model. |
| [Orbit](https://apps.apple.com/us/app/subscription-manager-orbit/id6692620188) | iOS; local-first tracker | 2026-07-18 | Imports from screenshots, CSVs, or statements; shows yearly spend, trial/renewal alerts, a visual calendar, widgets, and 30+ languages/currencies; says data stays on device. | Reuse calendar visibility and import as a later enhancement; do not let import displace the minimum manual path. |
| [Subscription Manager – Bills](https://apps.apple.com/us/app/subscription-manager-bills/id1259029889) | iOS; manual tracker | 2026-05-16 | Tracks name, purpose, amount, cycle, currency, dates and notes; supports archive, categories, reminders, widgets, Siri, sorting and filtering. It explicitly does not cancel subscriptions. | Reuse a clear distinction between tracking and provider-side management. Its broad field set must not become required input. |
| [Subscriptions – Track Expenses](https://apps.apple.com/us/app/subscriptions-track-expenses/id1577082754) | iPhone/iPad/macOS; SwiftUI tracker | 2026-07-12 | Vast preset selection, categories/dates/tags/accounts, 160+ currencies, analytics, reminders, widgets, iCloud, App Store template search, and price history. | Reuse App Store/catalog discovery and history separation. Avoid treating category, tag, or account metadata as minimum facts. |
| [SubManager](https://apps.apple.com/us/app/submanager-subscriptions/id1632853914) | Apple ecosystem; local/iCloud tracker | 2026-07-24 | Renewal reminders, spending insights, currency conversion, widgets, Shortcuts, searchable App Store icons, price history, archive, and JSON/CSV exchange. | Reuse archive/history as secondary lifecycle capabilities and cross-surface data reuse. |
| [Subo](https://apps.apple.com/us/app/subscription-manager-subo/id6741823650) | iOS; local/iCloud manual tracker | 2026-07-15 | One overview, next-renewal ordering, trial and renewal reminders, templates, multiple currencies, categories/payment methods, finite terms, and widgets. | Reuse calm overview and explicit finite-plan model; category and payment method remain optional metadata. |
| [Hiatus](https://apps.apple.com/us/app/hiatus-subscriptions-bills/id977040079) | iOS; linked-account finance | 2026-07-29 | Consolidates spending, identifies subscriptions and rate increases, budgets, and offers recommendations. | Rate-change detection supports keeping price history outside the minimum edit facts; linked accounts are not the default architecture here. |
| [Copilot Money](https://apps.apple.com/us/app/copilot-track-budget-money/id1447330651) | Web/iPhone/iPad/Mac; linked-account finance | 2026-07-23 | Detects recurring charges, auto-categorizes, provides alerts, cash flow, budgets and one consolidated financial view. | Reuse automatic recognition only as a future import/enrichment seam; inferred category must remain reviewable. |
| [Monarch](https://apps.apple.com/us/app/monarch-budget-track-money/id1459319842) | iOS/web; linked-account finance | 2026-07-23 | Shows subscriptions and bills in either calendar or list view with notifications; dashboard is customizable around upcoming expenses. | Strong evidence for list/calendar parity, not calendar-only replacement. |
| [PocketGuard](https://apps.apple.com/us/app/pocketguard-budget-planner-app/id949414211) | iOS; linked-account finance | 2026-06-29 | Automatically identifies bills and subscriptions from linked accounts, incorporates them in monthly budget, and supports rate negotiation. | Reuse “upcoming obligations affect available money” as information hierarchy; avoid coupling core forecasts to account sync. |
| [YNAB](https://apps.apple.com/us/app/ynab/id1010865877) | iOS/web; budgeting | 2026-07-29 | Supports automatic import and manual entry, shared plans, goals, and Siri. | Its explicit automatic-or-manual parity supports keeping manual entry first-class even when richer import exists. |
| [Emma](https://apps.apple.com/us/app/emma-budget-planner-tracker/id1270062373) | iOS; linked-account finance | 2026-07-27 | Finds subscriptions, shows weekly reports, bill reminders, “true balance,” custom categories and offline accounts. | Reuse bill-aware balance only as a future insight; do not bury subscription management inside a broad finance super-app. |
| [Chronicle](https://apps.apple.com/us/app/chronicle-bill-organizer/id572561420) | iPhone/iPad/Mac; bill tracker | 2026-05-02 | Records payment history and confirmation numbers, provides 12-month forecast, and calculates an amount to save for non-monthly bills. | Strong support for payment history as a separate immutable surface and for long-horizon forecasting. |
| [Bills Monitor](https://apps.apple.com/us/app/bills-monitor-bill-reminder/id473477150) | iPhone/iPad/Watch; bill tracker | 2026-07-15 | Month calendar, recurrence with end date, partial/full payment state, history, search, categories, reminders and export. | Reuse calendar + state legend + history. Reject exposing all bill-account metadata in the primary subscription form. |

### Competitor pattern frequency and evidence strength

These counts refer only to features explicitly stated in the 15 official
listings.

| Pattern | Official listing count | Strength | Interpretation |
| --- | ---: | --- | --- |
| Renewal/bill reminders | 12/15 | strong | Reminders are expected, but reminder configuration should not crowd the minimum save path. |
| Upcoming overview, list, widget, or forecast | 12/15 | strong | The library row should expose next charge information without secondary navigation. |
| Catalog/template or automatic discovery | 10/15 | strong | Known services should not start as blank forms; manual entry must remain available. |
| Calendar or time-oriented forecast explicitly named | 4/15 | moderate | Calendar is valuable but not universal; it should complement the list/agenda. |
| Multiple currencies/conversion | 7/15 | moderate-strong | Currency belongs in ordinary editing; region defaults must derive from selected offers. |
| Price/payment history explicitly named | 4/15 | moderate | History is valuable but should not be mixed into editable current facts. |
| Archive/expiry/lifecycle explicitly named | 4/15 | moderate | Archive and finite-term status are common secondary state, not form requirements. |
| Local/on-device/no-account positioning | 6/15 | moderate | Privacy is a meaningful differentiator, especially against account-linked finance apps. |

No official listing provided reliable evidence for row swipe implementation,
whether tapping a row opens view versus edit, or exact date-picker commit
behavior. Those questions require source/runtime evidence and must not be
inferred from marketing copy.

## Open-source implementation cohort

The cohort favors active, inspectable subscription trackers and includes
native iOS, web, desktop, and data-driven implementations. “Reusable” below
means technically informative; license and platform fit still govern adoption.

| Repository | Commit / license | Source-backed implementation fact | Reuse assessment |
| --- | --- | --- | --- |
| [ellite/Wallos](https://github.com/ellite/Wallos/tree/3a7f965d0412b40ca29a678c90f0c830bc7e3faa) | `3a7f965d0412b40ca29a678c90f0c830bc7e3faa`; GPL-3.0 | The same subscription form carries Start Date, an explicit “calculate next payment” action, required Next Payment, category, inactive state, cancellation date, and delete; the endpoint handles insert and update. [Dates](https://github.com/ellite/Wallos/blob/3a7f965d0412b40ca29a678c90f0c830bc7e3faa/subscriptions.php#L411-L431), [lifecycle/actions](https://github.com/ellite/Wallos/blob/3a7f965d0412b40ca29a678c90f0c830bc7e3faa/subscriptions.php#L469-L554), [insert/update](https://github.com/ellite/Wallos/blob/3a7f965d0412b40ca29a678c90f0c830bc7e3faa/endpoints/subscription/add.php#L313-L342) | Useful counterexample: unified Add/Edit is good, but lifecycle and destructive actions overload the form. GPL code is not a direct fit. |
| [bscott/subtrackr](https://github.com/bscott/subtrackr/tree/cb5dcf048debccd19e398e2174be9e68b780b9c3) | `cb5dcf048debccd19e398e2174be9e68b780b9c3`; AGPL-3.0 | One modal template switches POST/PUT for Add/Edit, while category and currency are required; list rows expose edit and confirmed delete; calendar is a separate month projection. [Form](https://github.com/bscott/subtrackr/blob/cb5dcf048debccd19e398e2174be9e68b780b9c3/templates/subscription-form.html#L15-L63), [row actions](https://github.com/bscott/subtrackr/blob/cb5dcf048debccd19e398e2174be9e68b780b9c3/templates/subscription-list.html#L212-L232), [calendar](https://github.com/bscott/subtrackr/blob/cb5dcf048debccd19e398e2174be9e68b780b9c3/templates/calendar.html#L274-L335) | Reuse one form and direct row actions conceptually. Reject required category and default-USD assumptions. AGPL precludes casual code reuse. |
| [zhiyingzzhou/renewlet](https://github.com/zhiyingzzhou/renewlet/tree/fb5a7217d7cf2ff532f1b60ab8f7271cb6df5457) | `fb5a7217d7cf2ff532f1b60ab8f7271cb6df5457`; MIT | A shared recurrence module uses Temporal date-only arithmetic, stable month-end clamping, custom units, and a bounded search for the first cycle after a threshold. [Pinned source](https://github.com/zhiyingzzhou/renewlet/blob/fb5a7217d7cf2ff532f1b60ab8f7271cb6df5457/packages/shared/src/subscription-renewal.ts#L141-L189) | Strongest reusable domain pattern: one tested recurrence function feeds calendar and reminders. Port the behavior/tests, not necessarily the TypeScript dependency. |
| [wangwangit/SubsTracker](https://github.com/wangwangit/SubsTracker/tree/0115fadd0be1ecf9bb8bb025b025ef8afd29e6bf) | `0115fadd0be1ecf9bb8bb025b025ef8afd29e6bf`; MIT | Category is stored as empty when absent; renewal scheduling updates expiry/start/payment history. It globally defaults missing period to monthly and currency to CNY. [Pinned source](https://github.com/wangwangit/SubsTracker/blob/0115fadd0be1ecf9bb8bb025b025ef8afd29e6bf/src/data/subscriptions.js#L199-L233) | Optional category is good. Global monthly/CNY fallback is an anti-pattern: an unknown schedule must remain unknown and currency must come from a verified offer or explicit input. |
| [yassnemo/substream](https://github.com/yassnemo/substream/tree/308b3783a4b17f554988a2514135f225f087c0ea) | `308b3783a4b17f554988a2514135f225f087c0ea`; MIT | Selecting a popular-service suggestion fills name, URL, price and color and advances to cycle; a hard-coded name map guesses category and defaults unmatched names to `Other`. [Pinned source](https://github.com/yassnemo/substream/blob/308b3783a4b17f554988a2514135f225f087c0ea/src/components/AddSubscriptionModal.tsx#L70-L131) | The typeahead-to-confirm transition is useful. Embedded prices and guessed categories are not maintainable or trustworthy. |
| [filtauras/Obsidian-Subscription-Tracker](https://github.com/filtauras/Obsidian-Subscription-Tracker/tree/748ad9d13e4ae3d3defdf75bc8fedffd389934d3) | `748ad9d13e4ae3d3defdf75bc8fedffd389934d3`; no license found | One data object drives overview and recurrence; on load, active recurring records advance until `nextDate >= today`, while expired one-time records become dead. [Pinned source](https://github.com/filtauras/Obsidian-Subscription-Tracker/blob/748ad9d13e4ae3d3defdf75bc8fedffd389934d3/Subscription%20Tracker.md#L88-L95) | Demonstrates a compact derived-state model, but a monolithic custom script has poor testability/accessibility and no reusable license. |
| [fkonovalov/obsidian-subscription-tracker](https://github.com/fkonovalov/obsidian-subscription-tracker/tree/9387b8ad328b7471dbb430278ab7315cbda1acc4) | `9387b8ad328b7471dbb430278ab7315cbda1acc4`; MIT | A declarative table computes cycle counts, next duration/date and active state from note front matter, then projects those facts into table/calendar/filter views. [Pinned source](https://github.com/fkonovalov/obsidian-subscription-tracker/blob/9387b8ad328b7471dbb430278ab7315cbda1acc4/Subscriptions.base#L17-L54) | Strong evidence for a data-driven projection shared by list/calendar/statistics. Formula semantics still need domain tests and native accessibility. |
| [kallyas/SubTrackr](https://github.com/kallyas/SubTrackr/tree/13b930f10bdc84db1fdedd3d684e96f96f6ca7cf) | `13b930f10bdc84db1fdedd3d684e96f96f6ca7cf`; MIT | One SwiftUI `EditSubscriptionView` serves Add/Edit; a searchable template list opens it and injects template data; its calendar opens a selected-day sheet and can add from a chosen day. [Form](https://github.com/kallyas/SubTrackr/blob/13b930f10bdc84db1fdedd3d684e96f96f6ca7cf/SubTrackr/Views/EditSubscriptionView.swift#L95-L145), [templates](https://github.com/kallyas/SubTrackr/blob/13b930f10bdc84db1fdedd3d684e96f96f6ca7cf/SubTrackr/Views/TemplatePickerView.swift#L10-L59), [calendar](https://github.com/kallyas/SubTrackr/blob/13b930f10bdc84db1fdedd3d684e96f96f6ca7cf/SubTrackr/Views/CalendarView.swift#L88-L107) | Closest platform pattern. Reuse native Form/DatePicker/searchable/day sheet. Reject its delayed NotificationCenter template handoff as hidden duplicated state. |
| [jin-taiyu/SubTrack](https://github.com/jin-taiyu/SubTrack/tree/e6eb5acdd19bcbc381fa4cfefb83f39b77966a31) | `e6eb5acdd19bcbc381fa4cfefb83f39b77966a31`; no license found | One form serves Add/Edit, but navigation still routes calendar events into read-only details. FullCalendar exposes month/week, day click to Add, event click to Detail, and monthly estimate. Defaults are USD, monthly, and today; “platform” is required. [Form mode](https://github.com/jin-taiyu/SubTrack/blob/e6eb5acdd19bcbc381fa4cfefb83f39b77966a31/src/renderer/components/SubscriptionForm.vue#L11-L16), [defaults](https://github.com/jin-taiyu/SubTrack/blob/e6eb5acdd19bcbc381fa4cfefb83f39b77966a31/src/renderer/components/SubscriptionForm.vue#L189-L196), [calendar](https://github.com/jin-taiyu/SubTrack/blob/e6eb5acdd19bcbc381fa4cfefb83f39b77966a31/src/renderer/components/CalendarView.vue#L86-L103) | Useful direct comparison: calendar navigation is effective, while view-then-edit and invented defaults reproduce the reported product problems. No reusable license found. |
| [sachigoyal/calendar](https://github.com/sachigoyal/calendar/tree/a78abf0b95335e0b01a0f646eab601e4c6d52df6) | `a78abf0b95335e0b01a0f646eab601e4c6d52df6`; MIT | Month cells show up to two service logos then `+N`; populated cells reveal a tooltip with edit/delete. Recurrence matches by day-of-month or month/day. [Recurrence](https://github.com/sachigoyal/calendar/blob/a78abf0b95335e0b01a0f646eab601e4c6d52df6/src/components/subscription-calendar.tsx#L44-L59), [density/actions](https://github.com/sachigoyal/calendar/blob/a78abf0b95335e0b01a0f646eab601e4c6d52df6/src/components/subscription-calendar.tsx#L115-L160) | `+N` is a useful dense-day disclosure pattern. Tooltip-only actions and naive date matching are poor fits for touch, VoiceOver, and month-end correctness. |

### Source pattern frequency

| Source-backed pattern | Repository count | Strength / caveat |
| --- | ---: | --- |
| One model or form supports both Add and Edit | 5/10 | moderate-strong; reduces duplication, but only if unsaved state has one owner. |
| Month calendar is a projection of subscription data | 6/10 | strong; calendar-only navigation is not supported. |
| Catalog/template assistance | 2/10 | limited but consistent with stronger official-product evidence. |
| Explicit payment/price history | 2/10 | limited implementation sample; official listings strengthen the case for a separate history surface. |
| Row/cell-level edit or delete outside details | 3/10 | moderate; permanent deletion still needs confirmation. |
| Hard-coded default currency/category/period | 4/10 | repeated failure mode, not a recommendation. |
| Shared/tested recurrence logic | 3/10 | moderate; only Renewlet demonstrates robust month-end semantics in the inspected excerpt. |

## Community discussion sample

### Coding legend

- **T1:** forgotten, surprising, or hard-to-cancel renewal
- **T2:** advance or multi-window reminders
- **T3:** calendar, timeline, or upcoming visibility
- **T4:** manual/local/private operation; reluctance to link banks
- **T5:** cross-device sync or multiple notification channels
- **T6:** templates, import, or less retyping
- **T7:** annual, irregular, physical, or non-digital expiries
- **T8:** monthly/yearly totals or spending analysis
- **T9:** price, currency, region, or catalog maintenance

Every row is an anecdotal report. “Repeated” applies to the aggregate theme,
not to any one author's claim.

### Chinese community — V2EX (12)

| Discussion | Signal coding | Short supporting signal |
| --- | --- | --- |
| [续费鸭：订阅管理和扣费提醒](https://www.v2ex.com/t/1216281) | T1 T2 T6 T8 | The author frames the problem as too many memberships and offers a list, 1/3/7-day reminders, common templates, and monthly/category totals. |
| [SubsTracker](https://www.v2ex.com/t/1144366) | T2 T5 T7 | The post emphasizes configurable lead time, automatic renewal calculation, enabled/expired status and several messaging channels. |
| [如何管理各种会员/订阅到期时间](https://www.v2ex.com/t/664898) | T2 T5 | The requester wants one place for membership/service expiry; a reply reports a reminder mini-program failed to notify, showing delivery reliability matters. |
| [希望用 Google Drive/OneDrive/国内网盘同步](https://www.v2ex.com/t/1138623) | T5 | The request explicitly rejects iCloud-only lock-in for an iOS/Mac tracker. |
| [WhereMyMoney 订阅管理](https://www.v2ex.com/t/1171374) | T1 T2 T4 T8 | The author reports forgotten AI subscriptions/trials and emphasizes selectable reminder windows, analysis, and no bank password. |
| [订阅日期 App](https://www.v2ex.com/t/1084225) | T2 T3 T7 | The app/request domain spans card bills, subscriptions, rent and anniversaries, with calendar plus upcoming timeline. |
| [订阅通 2.0](https://www.v2ex.com/t/911840) | T2 T5 T7 T8 T9 | The discussion covers payment/expiry reminders, local-currency conversion, price history, trials, interruptions, and a requested timeline home. |
| [多渠道订阅到期提醒求推荐](https://www.v2ex.com/t/998085) | T2 T5 | The requester names email, SMS, WeChat, Bark and Telegram, supporting configurable delivery rather than one notification channel. |
| [订阅宝](https://www.v2ex.com/t/1212001) | T1 T2 T3 T4 T6 T7 T8 T9 | The author cites forgotten/unknown charges and describes local privacy, App Store CN/US search, multi-currency, trial/discount periods, calendar and widgets. |
| [Renewlet](https://www.v2ex.com/t/1213250) | T2 T3 T4 T5 T7 T8 | The author reports scattered AI/VPS/domain subscriptions and implements calendar, totals, notifications, multi-currency and self-hosting. |
| [轻量会员到期清单](https://www.v2ex.com/t/1022024) | T2 T7 | The request prefers a lightweight list and includes memberships, anniversaries, rent/mortgage and financial expiries. |
| [Notion Subscription Tracker](https://www.v2ex.com/t/966621) | T1 T2 T8 T9 | The author reports losing a VPS by missing renewal and complains that a stale exchange rate made CNY calculations inaccurate. |

### Overseas community — Reddit (12)

Reddit pages rejected anonymous Jina access, and OpenCLI could not connect to
its extension. The entries below come from the read-only search API result
corpus and are marked accordingly in the evidence manifest.

| Discussion | Signal coding | Short supporting signal |
| --- | --- | --- |
| [Universal expiry tracker discussion](https://www.reddit.com/r/personalfinance/comments/1skjprg/) | T1 T2 T4 T7 T8 | Author reports missing insurance renewal and says digital-only trackers omit taxes, licences, warranties and domains; prefers manual/CSV over bank credentials. |
| [Forgotten renewals and trials](https://www.reddit.com/r/personalfinance/comments/1ojsj91/) | T1 T2 T3 T8 | Author reports three renewals in one week, annual-plan surprise and an uncalendared free-trial conversion. |
| [Subscription audit spreadsheet](https://www.reddit.com/r/personalfinance/comments/1swcqbj/) | T1 T8 | Author reports finding unused spend after recording every subscription and renewal date in a sheet. |
| [Managing annual auto-renewals](https://www.reddit.com/r/personalfinance/comments/tzvihb/) | T1 T2 T3 T7 | A participant sets a calendar reminder when signing up and tracks annual renewal amount year over year. |
| [Automated subscription tracking in India](https://www.reddit.com/r/personalfinanceindia/comments/1sl3a01/) | T1 T2 T3 T4 T5 T7 | Discussion says bank filters miss wallets/UPI/annual charges and recommends manual entry plus 3-day/1-week reminders. |
| [Android renewal tracker](https://www.reddit.com/r/androidapps/comments/1o20sca/) | T1 T2 T3 | Post foregrounds calendar/list of upcoming renewals and reminders before auto-renew. |
| [How people track subscriptions](https://www.reddit.com/r/apps/comments/1u4z8nx/) | T1 T2 T3 T7 | Author says notes plus calendar became messy across SaaS, domains and yearly renewals; checks upcoming weekly. |
| [Looking for a better tracker](https://www.reddit.com/r/ProductivityApps/comments/1u77ddl/) | T2 T3 T8 | Requester wants price, renewal date, notes, reminders, calendar, and monthly/yearly totals together. |
| [Simple iOS renewal app](https://www.reddit.com/r/SideProject/comments/1us1584/) | T1 T2 T3 T4 | Post explicitly rejects a complex finance app in favor of subscription dates and pre-charge reminders. |
| [No-account iOS tracker](https://www.reddit.com/r/iosapps/comments/1r9w94m/) | T2 T3 T4 T8 | Post emphasizes no account, monthly/yearly totals, calendar, and reminders. |
| [Free Android tracker](https://www.reddit.com/r/Android/comments/1of1ylt/) | T1 T2 T3 T4 | Post describes local tracking and configurable 1/3/7-day renewal warnings; replies raise trust concerns, showing provenance matters. |
| [Apple Reminders-integrated tracker](https://www.reddit.com/r/iOSAppsMarketing/comments/1rzhss3/) | T2 T5 T8 T9 | Release feedback added sorting, currencies, billing-cycle controls, reminder detail and weekly/annual breakdown. |

### Chinese video community — B站 (8)

These public-search-API results primarily expose cancellation vocabulary and
discoverability pain. They do not prove the described refund/cancellation
advice is correct.

| Discussion | Signal coding | Short supporting signal |
| --- | --- | --- |
| [iPhone 如何取消偷偷扣费的订阅](https://www.bilibili.com/video/BV1tu4y1i7St) | T1 | Title vocabulary frames recurring charges as hidden and cancellation as something people repeatedly ask how to do. |
| [Billbot 管理追踪订阅](https://www.bilibili.com/video/BV12b2ZYwEEF) | T2 T3 T8 | A dedicated tracker tutorial indicates demand for a unified renewal/spend view. |
| [iPhone 查看 App 订阅和购买](https://www.bilibili.com/video/BV1MD421P7tR) | T1 T3 | Description teaches where to find active subscriptions and manage renewal status, supporting an external management link. |
| [手机自动扣费订阅服务如何关闭](https://www.bilibili.com/video/BV1Ry1iYmEGs) | T1 | Cancellation location is sufficiently non-obvious to generate a dedicated tutorial. |
| [自动续费忘关被扣钱](https://www.bilibili.com/video/BV1nKXYYYEjE) | T1 | Title directly reports surprise charge after forgotten auto-renewal. |
| [“自动续费”怎么取消](https://www.bilibili.com/video/BV1kwZuY1EHw) | T1 | Another independent cancellation tutorial contributes to a repeated discoverability pattern. |
| [记得关闭 Pokémon Home 自动续费](https://www.bilibili.com/video/BV15y4y1m7RL) | T1 T2 | Description says auto-renew defaults on and warns near annual expiry. |
| [如何查看大会员等服务自动续费](https://www.bilibili.com/video/BV1Sb6hBNEFq) | T1 T3 | The need to locate and inspect renewal state recurs across providers. |

### Community theme frequency

Frequency counts code the 32 rows above. They are sample frequencies, not
population prevalence.

| Theme | Discussions | Classification | Product implication |
| --- | ---: | --- | --- |
| T2 — advance reminders | 24/32 | repeated, strong within sample | Keep reminders available and support more than one useful lead window, but move advanced notification setup after core save. |
| T1 — forgotten/surprising/hard cancellation | 20/32 | repeated, strong | Surface renewal and cancellation-management context; never imply the app cancelled a provider subscription. |
| T3 — calendar/upcoming visibility | 15/32 | repeated, strong | Use month overview plus day agenda and preserve list navigation. |
| T8 — totals/analysis | 13/32 | repeated, moderate-strong | Show monthly equivalent and period total without opening analytics. |
| T7 — annual/irregular/non-digital | 10/32 | repeated, moderate | Preserve custom/manual records and recurrence/end-date semantics. |
| T4 — manual/local/private | 8/32 | repeated, moderate | Do not require bank access or an account; import is optional. |
| T5 — sync/channel choice | 8/32 | repeated, moderate | Keep notification and sync adapters replaceable; do not hard-wire one delivery service. |
| T9 — price/currency/catalog maintenance | 4/32 | repeated, lower-volume | Verification date and market/channel provenance are necessary catalog facts. |
| T6 — templates/less typing | 2/32 | anecdotal community signal | Community evidence alone is weak, but official competitors and source implementations strongly reinforce catalog assistance. |

## Findings against the 14 product questions

### 1. Add path and typeahead/catalog matching

**Finding:** Catalog-assisted entry is established, but the best interaction is
inline matching inside the service-name step, not a separate catalog gate.
Bobby, Subo, Subscriptions, and SubManager all describe preset/template
selection; Substream demonstrates suggestion-to-confirm in source.

**Reuse:** As the person types `88`, search localized name plus explicit
aliases and present verified market/plan candidates under the field. Selecting
one fills catalog-owned facts and keeps editable charge/schedule facts.

**Reject:** Hard-coded price/category maps, silent fuzzy identity attachment,
and a catalog-first screen that makes unknown services harder to add.

### 2. Direct editing versus view-first detail

**Finding:** Source provides stronger evidence than store listings. Wallos,
subtrackr, kallyas/SubTrackr, and jin-taiyu/SubTrack use one Add/Edit form, but
jin-taiyu still routes a calendar event through read-only Detail. That extra
surface adds no safety to ordinary field editing.

**Recommendation:** A library row opens an editable subscription workspace
with visible Save/Cancel and unsaved-change handling. History and lifecycle
events are read-only sections or linked surfaces, not another mode switch.

### 3. Which operations stay outside the editor

| Operation | Placement | Rationale |
| --- | --- | --- |
| Archive / restore | Library row swipe/context action | Changes library visibility; does not require viewing editable facts. Offer Undo where supported. |
| Pin / unpin | Library row swipe/context action | A list-order operation with immediate reversible feedback. |
| Permanent delete | Destructive library action with confirmation | Keeps deletion reachable without opening detail and preserves deliberate confirmation. |
| Confirm charge | History/charge surface and relevant upcoming agenda item | Creates an immutable historical fact; it is not ordinary form editing. |
| Price change | Edit current price, then append history at save boundary | One current-fact editor; historical record is derived from the accepted change. |
| Recorded cancellation / reactivation | Lifecycle section | A domain event with access-until and schedule consequences, not a generic overflow action. |
| Provider cancellation | External verified management URL / guidance | The local app must not imply provider-side cancellation succeeded. |

### 4. Date input and recurrence inference

Source demonstrates two viable patterns:

- native date controls in the unified editor, with schedule derivation in one
  domain owner;
- explicit Start Date plus “calculate next payment,” as in Wallos.

The first is lower-friction when the domain rules can derive a coherent pair;
the second is a useful recovery action when the person overrides or imports
ambiguous dates. Renewlet shows why derivation must be centralized and tested,
especially for month end.

**Reject:** defaulting missing dates to today, defaulting missing intervals to
monthly, advancing recurrence independently in multiple screens, or requiring
tap-outside to commit.

### 5. Calendar and information density

Monarch explicitly supports calendar **or list**. Chronicle provides a
long-horizon forecast. Native-source examples use:

- a month grid;
- small charge/category indicators;
- selected-day sheet/agenda;
- `+N` overflow on dense days;
- direct navigation to a subscription.

The recommended calendar is therefore an overview/agenda hybrid:

1. month navigation and Today;
2. a small accessible charge indicator and aggregate for occupied days;
3. selected-day agenda with service, price/currency, status and expected time;
4. row activation directly opens the editable subscription;
5. dense days disclose count rather than shrinking every logo/text;
6. the ordinary Subscription Library remains available and authoritative.

### 6. Region, currency, taxonomy and catalog maintenance

Open source repeatedly demonstrates the failure mode: USD, CNY, monthly, or
`Other` are inserted as universal fallbacks. Community discussion independently
reports stale exchange rates and region-specific App Store search needs.

**Recommendation:** The selected offer supplies market, channel, plan,
currency, interval, source and verification date. Manual entry asks for actual
currency and interval. Unknown category remains empty. AI can be a first-class
localized category, but category never blocks saving.

### 7. Visual hierarchy and segmented controls

No evidence supports nested pill containers. The competitor cohort's repeated
language is “one overview,” “at a glance,” and “clear.” The source examples
that perform best separate calendar, totals, and agenda by semantic region
rather than placing every control in a card.

Place Expected/Confirmed as one native segmented control directly in its
section hierarchy. A surrounding decorative pill/card adds no state or
interaction and should be removed.

## Interaction implications for shared scenarios

These are target interaction budgets derived from the reusable patterns, not
runtime measurements of the current app.

| Scenario | Proposed primary path | Activations / transitions | Visible before secondary navigation | Failure recovery |
| --- | --- | --- | --- | --- |
| S1 verified known service | Add → type → select offer → enter/confirm schedule → Save | 3–5 activations; one Add surface, no catalog detour | service/variant, price, currency, interval, dates | clear manual continuation; selected offer can be changed |
| S2 unknown service | Add → type → continue manually → minimum facts → Save | 2 primary activations plus field focus/entry | all five minimum facts; optional metadata collapsed or below | no-match state never blocks save |
| S3 edit | tap row → fields are editable → Save | 2 activations, one transition | service, price/currency, interval, dates, status/next charge | Cancel and unsaved-change confirmation |
| S4 archive | row swipe/context → Archive | 1 gesture/activation | row identity and next charge | immediate Undo; archive retains data/history |
| S5 delete | row destructive action → confirm | 2 activations | row identity; confirmation names service and permanence | cancel confirmation; no silent delete |
| S6 upcoming | open Calendar → choose day → choose agenda row | 2–3 activations | month distribution, day count, selected-day services/amounts | Today/month navigation; empty-day state; library remains available |
| S7 dates | choose Start/Next Renewal using native date control; derived counterpart updates visibly | 1 activation per edited date plus Save | active field, committed date, derived counterpart | explicit override/reset and validation |
| S8 partial name | Add → type `88` → select relevant 88VIP offer | 2 activations plus two characters | localized variant, market, recurring price/currency/interval | manual continuation and no silent match |

## Native APIs and mature implementations

### Prefer native or existing platform behavior

- SwiftUI `Form`, `DatePicker`, `searchable`, `swipeActions`,
  `confirmationDialog`, `toolbar`, `FocusState`, and native sheets/popovers.
- `UICalendarView` through a narrow SwiftUI wrapper when the required
  decoration/selection behavior exceeds current SwiftUI calendar presentation.
- `Calendar`/`DateComponents` for date-only scheduling behind one
  `SubscriptionWorkspace` command/query boundary.
- `UndoManager` or an app-owned reversible archive command for row archive.
- `OpenURLAction` for verified provider-management URLs.
- `Locale`, `Currency`, and `FormatStyle` for presentation only; they must not
  invent the subscription's actual market currency.

### Mature implementation evidence worth adapting

- Renewlet's bounded, tested recurrence advance and month-end semantics.
- kallyas/SubTrackr's unified native Add/Edit form, searchable templates, and
  selected-day sheet.
- sachigoyal/calendar's dense-day `+N` disclosure, adapted to native
  accessibility and touch rather than tooltip-only interaction.
- Chronicle/Monarch's list-calendar complement and forward-looking totals.

No inspected third-party calendar package is recommended for direct adoption
by this workstream. Native API comparison belongs to Workstream 4; the source
sample shows that custom calendars quickly accumulate date, density,
localization, and accessibility risk.

## Fewer-code and lighter-architecture opportunities

1. **One editable draft model:** Add, catalog confirmation, and Edit use the
   same draft and validation rules. A catalog match seeds the draft; it does
   not create a parallel form.
2. **One schedule projection:** Workspace/domain recurrence produces upcoming
   occurrences consumed by Library, Calendar, widgets and reminders. No view
   advances dates independently.
3. **One catalog representation:** localized names/aliases, product/variant,
   market/channel, verified offers, category and management URL serve
   typeahead, confirmation, defaults and future updates.
4. **Native actions:** swipe/context actions, confirmation, date controls and
   focus progression replace custom action menus, home-grown pickers and
   redundant state.
5. **History as append-only output:** price and confirmed-charge history are
   generated at the workspace boundary; the editor only owns current facts.

This is a feature-boundary replacement rather than a cosmetic incremental
patch: the experience becomes simpler by consolidating state ownership, not
by layering more controls onto current Detail/Edit/menu screens.

## Anti-patterns and failure modes

| Failure mode | Evidence | Why it fails here |
| --- | --- | --- |
| Hard-coded catalog prices and category maps | Substream source | Prices age; regional plans diverge; guessed category becomes false data. |
| Universal USD/CNY/monthly/today defaults | subtrackr, SubsTracker, jin-taiyu source | Creates a plausible but false schedule and contradicts minimum-fact rules. |
| Read-only detail before ordinary edit | jin-taiyu source | Adds a transition without improving safety or information. |
| Delete/lifecycle actions inside a dense form or catch-all menu | Wallos source | Mixes list visibility, destruction, history and editable facts. |
| Tooltip-only dense-day actions | sachigoyal/calendar source | Poor touch and VoiceOver affordance; actions are not persistently discoverable. |
| Calendar-only upcoming view | no strong official support; Monarch explicitly offers list or calendar | Dense and empty days need an agenda/list complement. |
| Independently advancing dates in the view | Obsidian monolith and simple calendar examples | Duplicates schedule state and produces month-end/time-zone inconsistencies. |
| Bank connection as the only discovery path | finance-app cohort vs manual/local community pattern | Excludes offline/privacy-first users and misses cash, wallets, domains and manually billed services. |

## Recommendation traceability

| Requirement | Workstream 3 contribution |
| --- | --- |
| R2-01 | Optional category is supported by manual/local patterns and SubsTracker source; required-category source is documented as an anti-pattern. |
| R2-02 | Unified Add/Edit source patterns and the read-only-detail counterexample support direct editable destination. |
| R2-03 | Row/cell actions and provider-management separation support external archive/delete/pin and lifecycle/history placement. |
| R2-04 | Official preset discovery plus Substream/kallyas source support inline catalog assistance with manual escape. |
| R2-05 | Native date fields plus centralized recurrence and explicit calculation/recovery support visible commit and derivation. |
| R2-06–R2-07 | Community/source evidence supports templates but not authoritative offers; Workstream 2 must establish product/price facts. |
| R2-08 | Repeated default-currency failures support offer-market currency, never a universal fallback. |
| R2-09 | AI appears as a distinct user vocabulary/category in Chinese community and source samples, but remains optional metadata. |
| R2-10–R2-11 | Region/channel maintenance evidence supports distinct product/offer identities; official pricing remains Workstream 2. |
| R2-12 | Official and community evidence supports month + list/agenda + dense-day disclosure. |
| R2-13 | This matrix supplies official, source-pinned and community evidence with explicit reuse/reject decisions. |
| R2-14 | At-a-glance hierarchy and native-control preference provide no support for redundant segmented-control containers. |

## Saturation

- **Competitors:** Products 13–15 added broader budgeting and bill-history
  evidence but no new primary Add/Edit/calendar interaction family. The cohort
  had stabilized into manual catalog trackers, linked-account finance apps,
  and bill/calendar trackers by product 12.
- **Open source:** Repositories 9–10 added a view-first counterexample and a
  dense-day `+N` treatment. They did not add a new state-ownership model. The
  main implementation families had saturated: unified form, separate detail,
  shared recurrence, month projection, and hard-coded-default failure.
- **Community:** The final B站 items repeated cancellation discoverability and
  renewal-state inspection; they did not add a new product alternative.
  Chinese and overseas samples converged on reminders, calendar/upcoming
  visibility, annual/irregular items, privacy, and spend totals.
- **Remaining gap:** Actual runtime behavior for proprietary competitors,
  小红书 search, X search, and Apple-platform accessibility cannot be settled
  by this workstream. Workstream 4 must decide native date/calendar details;
  product usability testing must validate the interaction budgets.

Further collection is unlikely to change the main architecture recommendation.
It could refine platform-specific vocabulary or identify another import
channel, but the major alternatives, risks, and anti-patterns are now stable.

## Evidence ID Index

| Evidence ID | Source / exact object |
| --- | --- |
| COM-001 | [Apple App Store — Rocket Money - Bills & Budgets](https://apps.apple.com/us/app/rocket-money-bills-budgets/id1130616675) |
| COM-002 | [Apple App Store — Bobby - Track subscriptions](https://apps.apple.com/us/app/bobby-track-subscriptions/id1059152023) |
| COM-003 | [Apple App Store — Subscription Manager: Orbit](https://apps.apple.com/us/app/subscription-manager-orbit/id6692620188) |
| COM-004 | [Apple App Store — Subscription Manager - Bills](https://apps.apple.com/us/app/subscription-manager-bills/id1259029889) |
| COM-005 | [Apple App Store — Subscriptions - Track Expenses](https://apps.apple.com/us/app/subscriptions-track-expenses/id1577082754) |
| COM-006 | [Apple App Store — SubManager: Subscriptions](https://apps.apple.com/us/app/submanager-subscriptions/id1632853914) |
| COM-007 | [Apple App Store — Subscription Manager: Subo](https://apps.apple.com/us/app/subscription-manager-subo/id6741823650) |
| COM-008 | [Apple App Store — Hiatus - Subscriptions & Bills](https://apps.apple.com/us/app/hiatus-subscriptions-bills/id977040079) |
| COM-009 | [Apple App Store — Copilot: Track & Budget Money](https://apps.apple.com/us/app/copilot-track-budget-money/id1447330651) |
| COM-010 | [Apple App Store — Monarch: Budget & Track Money](https://apps.apple.com/us/app/monarch-budget-track-money/id1459319842) |
| COM-011 | [Apple App Store — PocketGuard Budget Planner](https://apps.apple.com/us/app/pocketguard-budget-planner-app/id949414211) |
| COM-012 | [Apple App Store — YNAB](https://apps.apple.com/us/app/ynab/id1010865877) |
| COM-013 | [Apple App Store — Emma - Budget Planner Tracker](https://apps.apple.com/us/app/emma-budget-planner-tracker/id1270062373) |
| COM-014 | [Apple App Store — Chronicle - Bill Organizer](https://apps.apple.com/us/app/chronicle-bill-organizer/id572561420) |
| COM-015 | [Apple App Store — Bills Monitor - Bill Reminder](https://apps.apple.com/us/app/bills-monitor-bill-reminder/id473477150) |
| COM-016 | [GitHub — ellite/Wallos · `subscriptions.php#L411-L431`](https://github.com/ellite/Wallos/blob/3a7f965d0412b40ca29a678c90f0c830bc7e3faa/subscriptions.php#L411-L431) |
| COM-017 | [GitHub — bscott/subtrackr · `templates/subscription-form.html#L15-L63`](https://github.com/bscott/subtrackr/blob/cb5dcf048debccd19e398e2174be9e68b780b9c3/templates/subscription-form.html#L15-L63) |
| COM-018 | [GitHub — zhiyingzzhou/renewlet · `packages/shared/src/subscription-renewal.ts#L141-L189`](https://github.com/zhiyingzzhou/renewlet/blob/fb5a7217d7cf2ff532f1b60ab8f7271cb6df5457/packages/shared/src/subscription-renewal.ts#L141-L189) |
| COM-019 | [GitHub — wangwangit/SubsTracker · `src/data/subscriptions.js#L199-L233`](https://github.com/wangwangit/SubsTracker/blob/0115fadd0be1ecf9bb8bb025b025ef8afd29e6bf/src/data/subscriptions.js#L199-L233) |
| COM-020 | [GitHub — yassnemo/substream · `src/components/AddSubscriptionModal.tsx#L70-L131`](https://github.com/yassnemo/substream/blob/308b3783a4b17f554988a2514135f225f087c0ea/src/components/AddSubscriptionModal.tsx#L70-L131) |
| COM-021 | [GitHub — filtauras/Obsidian-Subscription-Tracker · `Subscription Tracker.md#L88-L95`](https://github.com/filtauras/Obsidian-Subscription-Tracker/blob/748ad9d13e4ae3d3defdf75bc8fedffd389934d3/Subscription%20Tracker.md#L88-L95) |
| COM-022 | [GitHub — fkonovalov/obsidian-subscription-tracker · `Subscriptions.base#L17-L54`](https://github.com/fkonovalov/obsidian-subscription-tracker/blob/9387b8ad328b7471dbb430278ab7315cbda1acc4/Subscriptions.base#L17-L54) |
| COM-023 | [GitHub — kallyas/SubTrackr · `SubTrackr/Views/EditSubscriptionView.swift#L95-L145`](https://github.com/kallyas/SubTrackr/blob/13b930f10bdc84db1fdedd3d684e96f96f6ca7cf/SubTrackr/Views/EditSubscriptionView.swift#L95-L145) |
| COM-024 | [GitHub — jin-taiyu/SubTrack · `src/renderer/components/CalendarView.vue#L86-L103`](https://github.com/jin-taiyu/SubTrack/blob/e6eb5acdd19bcbc381fa4cfefb83f39b77966a31/src/renderer/components/CalendarView.vue#L86-L103) |
| COM-025 | [GitHub — sachigoyal/calendar · `src/components/subscription-calendar.tsx#L44-L59`](https://github.com/sachigoyal/calendar/blob/a78abf0b95335e0b01a0f646eab601e4c6d52df6/src/components/subscription-calendar.tsx#L44-L59) |
| COM-026 | [V2EX topic `1216281`](https://www.v2ex.com/t/1216281) |
| COM-027 | [V2EX topic `1144366`](https://www.v2ex.com/t/1144366) |
| COM-028 | [V2EX topic `664898`](https://www.v2ex.com/t/664898) |
| COM-029 | [V2EX topic `1138623`](https://www.v2ex.com/t/1138623) |
| COM-030 | [V2EX topic `1171374`](https://www.v2ex.com/t/1171374) |
| COM-031 | [V2EX topic `1084225`](https://www.v2ex.com/t/1084225) |
| COM-032 | [V2EX topic `911840`](https://www.v2ex.com/t/911840) |
| COM-033 | [V2EX topic `998085`](https://www.v2ex.com/t/998085) |
| COM-034 | [V2EX topic `1212001`](https://www.v2ex.com/t/1212001) |
| COM-035 | [V2EX topic `1213250`](https://www.v2ex.com/t/1213250) |
| COM-036 | [V2EX topic `1022024`](https://www.v2ex.com/t/1022024) |
| COM-037 | [V2EX topic `966621`](https://www.v2ex.com/t/966621) |
| COM-038 | [Reddit — r/personalfinance post `1skjprg`](https://www.reddit.com/r/personalfinance/comments/1skjprg/) |
| COM-039 | [Reddit — r/personalfinance post `1ojsj91`](https://www.reddit.com/r/personalfinance/comments/1ojsj91/) |
| COM-040 | [Reddit — r/personalfinance post `1swcqbj`](https://www.reddit.com/r/personalfinance/comments/1swcqbj/) |
| COM-041 | [Reddit — r/personalfinance post `tzvihb`](https://www.reddit.com/r/personalfinance/comments/tzvihb/) |
| COM-042 | [Reddit — r/personalfinanceindia post `1sl3a01`](https://www.reddit.com/r/personalfinanceindia/comments/1sl3a01/) |
| COM-043 | [Reddit — r/androidapps post `1o20sca`](https://www.reddit.com/r/androidapps/comments/1o20sca/) |
| COM-044 | [Reddit — r/apps post `1u4z8nx`](https://www.reddit.com/r/apps/comments/1u4z8nx/) |
| COM-045 | [Reddit — r/ProductivityApps post `1u77ddl`](https://www.reddit.com/r/ProductivityApps/comments/1u77ddl/) |
| COM-046 | [Reddit — r/SideProject post `1us1584`](https://www.reddit.com/r/SideProject/comments/1us1584/) |
| COM-047 | [Reddit — r/iosapps post `1r9w94m`](https://www.reddit.com/r/iosapps/comments/1r9w94m/) |
| COM-048 | [Reddit — r/Android post `1of1ylt`](https://www.reddit.com/r/Android/comments/1of1ylt/) |
| COM-049 | [Reddit — r/iOSAppsMarketing post `1rzhss3`](https://www.reddit.com/r/iOSAppsMarketing/comments/1rzhss3/) |
| COM-050 | [Bilibili video `BV1tu4y1i7St`](https://www.bilibili.com/video/BV1tu4y1i7St) |
| COM-051 | [Bilibili video `BV12b2ZYwEEF`](https://www.bilibili.com/video/BV12b2ZYwEEF) |
| COM-052 | [Bilibili video `BV1MD421P7tR`](https://www.bilibili.com/video/BV1MD421P7tR) |
| COM-053 | [Bilibili video `BV1Ry1iYmEGs`](https://www.bilibili.com/video/BV1Ry1iYmEGs) |
| COM-054 | [Bilibili video `BV1nKXYYYEjE`](https://www.bilibili.com/video/BV1nKXYYYEjE) |
| COM-055 | [Bilibili video `BV1kwZuY1EHw`](https://www.bilibili.com/video/BV1kwZuY1EHw) |
| COM-056 | [Bilibili video `BV15y4y1m7RL`](https://www.bilibili.com/video/BV15y4y1m7RL) |
| COM-057 | [Bilibili video `BV1Sb6hBNEFq`](https://www.bilibili.com/video/BV1Sb6hBNEFq) |
| COM-058 | [X/Twitter search `subscription tracker` — access-gap record](https://x.com/search?q=subscription%20tracker) |
| COM-059 | [Xiaohongshu search `订阅管理` — access-gap record](https://www.xiaohongshu.com/search_result?keyword=%E8%AE%A2%E9%98%85%E7%AE%A1%E7%90%86) |
