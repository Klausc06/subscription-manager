# R2-06 China membership offers: renewal-price verification

**Verified:** 2026-08-01 (Asia/Shanghai)  
**Scope:** 88VIP, JD PLUS, and Sam's Club China only.  
**Decision:** **zero offers are eligible for import.** This report deliberately
does not infer a price from a promotion, an app-download price, a historical
price, or an account-specific checkout.

## Import standard used

An offer must have all of the following in a first-party, currently readable
source before it may be written to a catalog:

1. a named membership/plan;
2. its normal renewal price and currency;
3. its renewal cadence; and
4. a China-market purchase channel to which that price applies.

Amounts are recorded in CNY and fen (minor units) only after all four facts are
proven together. A price contingent on status, a first-term promotion, a
campaign, or a checkout-only entitlement is not a normal renewal price.

## Results by provider

| Service (CN) | English display rendering* | First-party evidence verified today | Price / cadence result | Import status |
| --- | --- | --- | --- | --- |
| 88VIP | 88VIP | [88VIP Membership Service Agreement](https://terms.alicdn.com/legal-agreement/terms/suit_bu1_tmall/suit_bu1_tmall201903151049_99115.html); [Alibaba Group loyalty announcement](https://www.alibabagroup.com/en-US/document-1889827556354424832) | Agreement makes the live opening flow authoritative for both eligibility and fee, and states a 365-day term. Alibaba's `RMB 88` statement is explicitly for Platinum-or-above users, so it is eligibility-bound rather than a generally applicable renewal price. No public first-party source found today states a normal renewal price or a complete plan/price set. | **Not importable** |
| 京东PLUS会员 | JD PLUS Membership | [JD PLUS User Agreement](https://help.jd.com/user/issue/894-4216.html) | Terms confirm formal annual and seasonal products and describe auto-renewal, but state fees may change and do not publish amounts. The public `plus.m.jd.com` entry resolves to sign-in/registration rather than a price page in this verification context. | **Not importable** |
| 山姆会员商店 | Sam's Club China Membership | [Sam's official site](https://www.samsclub.cn/); [App Store China listing](https://apps.apple.com/cn/app/id818237113); [Apple Lookup JSON](https://itunes.apple.com/lookup?id=818237113&country=cn) | Official sources establish the service and the "卓越会员" benefit context, but publish neither a membership fee nor a standard renewal cadence. The Lookup field `formattedPrice: 免费` is the app download price, not a membership price, and is excluded. Public `/h5/*-rules` routes are client-rendered shells with no embedded price evidence. | **Not importable** |

\* English values are controlled display renderings for this research report,
not claims that each provider publishes an official English plan name.

## Source-by-source findings

### 88VIP

- The agreement identifies the service as **88VIP会员服务**, requires the
  applicable qualification, sets a **365-day** membership period, and directs
  users to pay the price shown in the actual opening flow. It also says a
  renewal is charged at the price effective at that time. That proves a
  variable, eligibility-sensitive checkout model, not a fixed public renewal
  rate.
- Alibaba Group's public announcement says only that **Platinum-tier-or-above**
  users can become 88VIP for **RMB 88**. This is useful negative evidence: the
  stated price has an explicit eligibility condition. It must not be normalized
  into `8800` fen as a standard offer.
- Direct public probes of `88vip.com` did not resolve, and
  `88vip.taobao.com` exposed a generic Taobao storefront page without an offer
  or fee. The next legitimate verification path is the current Taobao 88VIP
  opening flow with a documented account tier; that result would still need to
  distinguish standard renewal from a tier benefit or campaign.

### 京东PLUS会员

- The official agreement calls the paid service **京东PLUS会员正式期** and
  distinguishes annual and seasonal auto-renewal products. It states that fees
  can be adjusted, which prevents an old or third-party price from being
  treated as current.
- No numeric fee is displayed in the public agreement. `https://plus.m.jd.com/`
  returned a sign-in/registration surface in this run, so an anonymous public
  request cannot establish either the current price or the plan selected after
  renewal.
- The required next evidence is a first-party JD purchase/renewal response that
  visibly ties the product label, CNY amount, cadence, account state, and
  verification date together. Do not substitute a trial, coupon, or
  auto-renewal discount.

### 山姆会员商店

- Sam's official web and App Store sources identify the China service; the App
  Store description refers to benefits for a **卓越会员主卡注册人**. Neither
  source attaches a money amount or renewal interval to that membership.
- Apple's public Lookup response identifies the same app (`id=818237113`) and
  reports `formattedPrice: 免费`. That field describes the free app download;
  it is not evidence of a free membership and is excluded from catalog data.
- The official site's JavaScript route list includes `/h5/vip-rules`,
  `/h5/retail-vip-rules`, `/h5/upgrade-rules`, and `/h5/use-rules`; each route
  returned the same client-rendered application shell and no embedded price
  text in this public read. A first-party membership purchase/renewal page or
  response is still required.

## Standard renewal versus excluded prices

| Candidate | Why it is excluded | What would be required instead |
| --- | --- | --- |
| 88VIP `RMB 88` | Official statement limits it to Platinum-or-above users; it is not a universal, ordinary renewal price. | A live first-party opening/renewal display explicitly labelled as normal renewal for the same plan. |
| JD PLUS annual / seasonal references | The agreement proves product cadences, but has no monetary amount. | The corresponding current first-party checkout/renewal price. |
| Sam's App Store `免费` | App acquisition price, not membership price. | Membership product price and normal renewal cadence in the same official source. |

## Direct import table

No row passes the four-fact import standard above. **Do not edit
`catalog-v1.json` from this report.**

| Service | Plan | Amount (CNY) | Minor units | Cadence | Market | Purchase channel | Result |
| --- | --- | ---: | ---: | --- | --- | --- | --- |
| — | — | — | — | — | — | — | **0 eligible rows** |

## Reproducibility notes

- Public pages were read through the configured reader route (Jina Reader) and
  direct public `curl` checks on 2026-08-01; no authenticated checkout,
  browser interaction, or third-party price listing was used as evidence.
- A first-party source remains the gating requirement. Search snippets and
  historical/secondary reports may discover URLs, but cannot supply an import
  value.
- Related existing evidence records are `OFF-011` through `OFF-014` in
  `docs/research/evidence/official-catalog.jsonl`; this document rechecks their
  conclusion and records the current public-route limitations without altering
  that evidence architecture.
