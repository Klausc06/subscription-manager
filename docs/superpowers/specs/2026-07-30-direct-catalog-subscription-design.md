# Direct Catalog Subscription Targets

Date: 2026-07-30
Status: Approved direction; implementation pending

## Purpose

Make adding a known subscription a selection task instead of a data-entry
task. A person should open the catalog, choose a service, choose one of that
service's verified official offers, confirm the dates, and save.

This document is the target and acceptance baseline. The implementation plan
must reference the identifiers in this document, and verification must report
against the same identifiers.

## Scope

This delivery changes the normal add flow, introduces service-level official
offers in the catalog, and ships a first verified batch for:

1. ChatGPT
2. Claude
3. Google AI
4. Microsoft 365
5. YouTube Premium
6. Spotify
7. Netflix
8. Disney+
9. Notion
10. Canva

The bundled catalog remains offline-first. Official prices are reference
presets, not a promise that every account, tax jurisdiction, promotion, App
Store storefront, or legacy plan will be billed identically.

## User-Experience Targets

### UX-01 — The add button opens the catalog

Tapping the library `+` presents `Browse Catalog` as the root of the add
sheet. The current intermediate `Add Subscription` form is not shown first.

Acceptance:

- One tap on `+` reveals catalog search, categories, service rows, and the
  alphabet index.
- The catalog root has one `Cancel` action that dismisses the add sheet.
- A secondary `Add Manually` action remains available from the catalog for a
  service that has not been collected yet.

### UX-02 — A service opens confirmation directly

Tapping a catalog service pushes `Confirm Subscription` directly. The current
`Catalog Details` page, its suggested-details section, management link, and
`Use This Preset` action are removed from this flow.

Acceptance:

- A catalog row requires one tap to reach confirmation.
- `CatalogPresetDetailView` is no longer reachable from normal add or
  first-run setup flows.
- Existing catalog search, category filtering, alphabet navigation, and
  diagnostics continue to work.

### UX-03 — Period and plan are selectable presets

The first section of catalog-backed confirmation is `Official Offer`.

- When a service has more than one supported billing period, the period
  control appears first.
- The plan control is filtered to offers available for the selected period.
- When only one period is available, it is shown as information rather than
  as a redundant picker.
- Selecting an offer immediately fills the plan name, amount, currency, and
  Fixed Billing Schedule interval.
- Monthly is the initial period when verified monthly offers exist; otherwise
  the first deterministic period and offer are selected.
- The selected market and purchase channel are visible in secondary text.

Acceptance:

- Choosing a verified offer requires no keyboard input.
- Switching period or plan updates all dependent values atomically.
- An unsupported period is never invented. For example, ChatGPT Go, Plus,
  and Pro do not show an annual option.

### UX-04 — Confirmation asks only for personal facts

In catalog-backed confirmation:

- Service name and category are read-only.
- Plan, price, currency, and interval come from the selected offer.
- Start date, renewal anchor, next renewal, status, notes, and management URL
  retain their existing behavior because the official catalog cannot know the
  person's actual dates or account state.
- A disclosed `Adjust Actual Charge` action permits correction when tax,
  region, a legacy price, or an App Store storefront differs. It is not part
  of the primary path.

Acceptance:

- A standard verified offer can be saved without typing.
- The default next-renewal date is derived from the selected interval and can
  be corrected with the date picker.
- Changing an offer recomputes untouched default dates but never overwrites a
  date after the person has changed it.
- Saving still uses `SubscriptionWorkspace.createCatalogSubscription`.

### UX-05 — Navigation has one way back

The catalog is the presented sheet root and confirmation is pushed within its
navigation stack.

Acceptance:

- The catalog root has `Cancel`.
- Catalog-backed confirmation has the system back button and `Save`; it does
  not also show `Cancel`.
- Manual confirmation pushed from the catalog follows the same rule.
- A successful save dismisses the entire add sheet and refreshes the library.

### UX-06 — First-run setup uses the same confirmation

The first-run catalog may retain its multi-selection behavior, but confirming
each selected service pushes the same offer-driven confirmation view directly.

Acceptance:

- First-run setup does not show `Catalog Details` or `Use This Preset`.
- Confirmed preset identity and setup-resume behavior remain intact.

## Catalog-Data Targets

### DATA-01 — Services and offers are separate concepts

`CatalogPreset` represents a service such as `ChatGPT`, not a particular paid
plan such as `ChatGPT Plus`.

Each service contains zero or more `CatalogOffer` values. An offer contains
the information required to prefill a subscription:

- stable offer identifier;
- localized plan name;
- price in minor units and ISO currency;
- Fixed Billing Schedule interval;
- market, such as `US`;
- purchase channel, such as `web` or `iOS`;
- official source URL;
- verification date;
- review status.

The first delivery uses two review states: `verified`, which is selectable,
and `reviewRequired`, which is retained as research metadata but is not
offered as an automatic price.

The first implementation supports fixed-price consumer offers. Quote-only,
seat-count-dependent, non-renewing prepaid, legacy, promotional, and free
plans may be documented but are not selectable until their billing semantics
can be represented without asking the person to repair the preset.

Acceptance:

- Decoding old catalog records without `offers` remains supported.
- Duplicate service and offer identifiers are rejected.
- Selectable offers require a positive price, supported currency and interval,
  HTTPS source, non-empty market/channel, and verification date.
- A service with no verified offers still opens a prefilled manual
  confirmation rather than failing.
- `suggestedInterval` remains decodable as the fallback for old and
  offer-less records; new confirmation prefers the selected offer.

### DATA-02 — ChatGPT is one service with four personal offers

Replace the `chatgpt-plus` service preset with service identifier `chatgpt`
and localized service name `ChatGPT`.

Verified United States Web offers:

| Offer | Billing | Price |
| --- | --- | ---: |
| Go | Monthly | USD 8 |
| Plus | Monthly | USD 20 |
| Pro (5x) | Monthly | USD 100 |
| Pro (20x) | Monthly | USD 200 |

Acceptance:

- All four offers are selectable under one ChatGPT service.
- No personal annual ChatGPT offer is displayed.
- Existing subscriptions created from the old `catalog:chatgpt-plus`
  identity remain readable; only newly created subscriptions use
  `catalog:chatgpt`.

### DATA-03 — First-batch offers are traceable

For the ten services in scope, include only fixed prices that the official
provider or its official App Store listing exposed on 2026-07-30.

Acceptance:

- Every selectable offer records source URL, market, channel, and
  `verifiedAt = 2026-07-30`.
- Web and iOS prices are separate offers when both are included.
- Confirmation cannot save a service that has verified offers until one
  deterministic offer is selected.
- Unknown annual prices, enterprise quotes, promotions, and remembered prices
  are not guessed.
- High-volatility providers may ship fewer offers; omission is preferable to
  an unverified default.

### DATA-04 — Price provenance is visible

The confirmation UI displays the selected offer's market and purchase channel
and provides its official source as an external link in the existing optional
details area.

Acceptance:

- A person can distinguish, for example, Claude Web pricing from Claude iOS
  App Store pricing.
- The UI explains that taxes, storefront, account eligibility, and regional
  pricing can change the actual charge.

### DATA-05 — Catalog updates stay backward compatible

The new fields are additive within the current catalog transport. A newer
bundled catalog version is required, while old cached catalogs remain
decodable.

Acceptance:

- A cached service without offers still loads and remains usable.
- Catalog validation covers the new offer fields.
- The existing offline fallback remains unchanged.

## Verified First-Batch Baseline

The implementation plan must select only entries supported by the sources
below. It may omit a volatile or ambiguous offer, but it may not substitute a
non-official source or infer an unknown price.

| Service | Verified baseline | Static-data risk |
| --- | --- | --- |
| ChatGPT | Go USD 8/mo; Plus 20/mo; Pro 5x 100/mo; Pro 20x 200/mo | Medium |
| Claude | Pro 20/mo or 200/yr; Max 5x 100/mo; Max 20x 200/mo on US Web | Medium-high |
| Google AI | US Web AI Plus 9.99/mo; AI Pro 19.99/mo | High |
| Microsoft 365 | Personal 9.99/mo or 99.99/yr; Family 12.99/mo or 129.99/yr; Premium 19.99/mo or 199.99/yr | Low-medium |
| YouTube Premium | US Premium Lite 7.99/mo; other exact Web prices omitted unless reverified | Very high |
| Spotify | US Web Individual 12.99/mo; Student 6.99/mo; Duo 18.99/mo; Family 21.99/mo | Medium-high |
| Netflix | US Web Ads 8.99/mo; Standard 19.99/mo; Premium 26.99/mo | High |
| Disney+ | US Web Ads 11.99/mo; Premium 18.99/mo or 189.99/yr | Medium-high |
| Notion | US Web Plus 12/member/mo or 120/member/yr | High |
| Canva | US Web Pro 180/yr; Business 250/person/yr | Very high |

Per-seat entries in this baseline are research evidence only and are not
selectable in this delivery unless the implementation also supplies an
explicit seat-count control and tests the computed total.

## Official Sources

Sources were read on 2026-07-30:

- ChatGPT: <https://openai.com/chatgpt/pricing/> and
  <https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro>
- Claude: <https://www.anthropic.com/pricing>
- Google AI: <https://one.google.com/about/google-ai-plans/>
- Microsoft 365:
  <https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365>
- YouTube Premium:
  <https://support.google.com/youtube/answer/16475192>
- Spotify: <https://www.spotify.com/us/premium/>
- Netflix: <https://help.netflix.com/en/node/22>
- Disney+: <https://help.disneyplus.com/article/disneyplus-price>
- Notion: <https://www.notion.com/pricing>
- Canva: <https://www.canva.com/pricing/>

## Verification Targets

### TEST-01 — Core model and validation

Unit tests cover offer decoding, legacy records without offers, invalid offer
rejection, offer grouping by period, and ChatGPT's exact four-offer baseline.

### TEST-02 — Direct add path

A focused UI test proves:

1. `+` opens `Browse Catalog`.
2. Selecting ChatGPT opens `Confirm Subscription` directly.
3. `Catalog Details` and `Use This Preset` never appear.
4. Selecting Pro (5x) fills USD 100 and monthly billing.
5. Confirmation has back and save actions without a duplicate cancel action.

### TEST-03 — Save and navigation

A focused UI test saves a catalog offer without keyboard entry, returns to the
library, and verifies service name, plan, amount, and catalog identity.

### TEST-04 — Regression

Existing catalog search, category filter, alphabet index, diagnostics,
first-run setup resume, manual entry, catalog refresh fallback, App Intents
metadata generation, and SubscriptionCore tests continue to pass.

### TEST-05 — Device smoke

After tests and a local commit, install the new build on the already registered
physical iPhone, launch it, and confirm both the main application and widget
processes. Do not push this new delivery unless the user explicitly requests
another push.

## Release Target

### REL-01 — Mark the completed state as milestone 0.1

The project already declares `MARKETING_VERSION = 0.1.0`. Keep that version
for this delivery.

After every implementation and verification target in this document passes,
create a GitHub milestone named `0.1` for the repository. Its description
summarizes the offline subscription library, catalog, direct official-offer
flow, forecasts, backup/restore, widgets, App Intents, and supported Apple
platform surfaces that form the current 0.1 state.

Acceptance:

- The built app reports marketing version `0.1.0`.
- GitHub has one open milestone named `0.1`.
- The milestone is created only after the implementation, regression, local
  commit, and device smoke are complete.
- This target does not authorize creating a GitHub Release, Git tag, or remote
  push of the new implementation.

## Out of Scope

- Automatically detecting which provider plan the person already has.
- Scraping provider accounts or purchase receipts.
- Converting official prices into another currency.
- Treating promotion, tax, legacy, or App Store pricing as identical to Web
  pricing.
- Selecting enterprise quote-only offers.
- Completing verified offers for all 100 existing catalog services in this
  single delivery. The new model is the foundation for subsequent researched
  batches.
