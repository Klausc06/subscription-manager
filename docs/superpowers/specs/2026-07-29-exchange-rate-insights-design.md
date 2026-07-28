# TB-14 Exchange-Rate Insights Design

- Date: 2026-07-29
- Issue: #15 — Convert daily exchange rates and present spending insights
- Status: Approved for autonomous implementation

## Decision

Introduce a domain-owned `ExchangeRateSnapshot` and injected adapters for a
rate source and a local cache. A snapshot is anchored on EUR, carries the
provider date, fetch timestamp, source identifier, and a decimal rate per
supported currency. Conversion goes through EUR and never treats a missing
rate as one-to-one.

The production source requests Frankfurter v2 with only `base=EUR` and the
needed `quotes` symbols. A request contains no subscription ID, name, amount,
category, dates, or device/account identifier. The cache is reused for the
current calendar day; a failed refresh keeps the last successful snapshot and
marks it stale with its timestamp. No snapshot produces an unavailable state,
not a fabricated total.

## Insights projection

`SubscriptionWorkspace` owns report generation. It derives expected charges
from the existing schedule projection and confirmed payments from payment
history, then calculates monthly, annualized, selected-range, and category
totals in `UserPreferences.primaryCurrency`. Every converted total retains its
source amount/currency and snapshot metadata for presentation.

The Insights destination replaces its placeholder with mode controls for
expected versus confirmed data, a native Swift Charts category chart, and a
complete textual category summary with accessible labels. Original values stay
visible in subscription and upcoming rows; changing the primary currency
recomputes only presentation values from the existing snapshot.

## Failure and privacy boundaries

- The workspace reads the rate cache before deciding whether to fetch; at most
  one successful or failed refresh attempt occurs per calendar day.
- Currency conversion uses `Decimal` and explicit target-currency rounding.
- A stale cache remains usable but its rate date and timestamp are visible.
- Missing, incomplete, or unsupported rate data yields an unavailable report
  state with original values untouched.
- Views never invoke networking or cache APIs directly; Calendar/EventKit,
  accounts, analytics, and custom backend behavior remain absent.

## Verification

- Core fake-clock/source/cache tests cover daily reuse, refresh, stale cache,
  unavailable data, privacy-minimal request currencies, CNY/USD/EUR decimal
  fixtures, and each report mode.
- Adapter tests decode Frankfurter v2 rates and persist/reload snapshots.
- UI tests cover display-currency change, fresh/stale/unavailable copy,
  textual chart summary, VoiceOver labels, English and Simplified Chinese.
