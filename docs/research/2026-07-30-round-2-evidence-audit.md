# Round 2 Research Evidence Audit

**Audit date:** 2026-07-31
**Auditor:** independent reverse-review subagent
**Scope:** official-catalog and current-product workstreams only
**Verdict:** **FAIL — blocking corrections are required before synthesis or manifest merge**

## Audit Coverage

This audit reviewed:

- `docs/research/2026-07-30-official-subscription-catalog-expansion.md`;
- `docs/research/evidence/official-catalog.jsonl`;
- `docs/research/2026-07-30-round-2-current-product-gap-audit.md`;
- `docs/research/evidence/current-product.jsonl`.

Coverage exceeded the required 10% sample:

- all 65 `OFF-*` source commands were independently rerun through the
  Agent Reach Jina Reader route;
- all 49 `OFF-*` records currently labeled `supports` or `contradicts` were
  reopened, including every price-bearing/high-volatility AI, streaming, and
  Chinese App Store record;
- all 16 `not-verifiable` records were reopened;
- all 14 `CUR-*` commands were rerun;
- all 14 GitHub commit-pinned permalinks were requested and returned HTTP 200.

Raw retrieval output is in
`/tmp/subscription-evidence-audit-20260731/` and is intentionally not committed.

## Gate Summary

| Gate | Result | Evidence |
| --- | --- | --- |
| JSONL parses one object per line | PASS | 65/65 `OFF-*`, 14/14 `CUR-*` |
| Evidence IDs are unique | PASS | 79 unique IDs, no duplicates |
| Required values are present | PASS within each fragment | No empty required scalar/array fields |
| Excerpt SHA-256 | PASS | 79/79 hashes equal the exact UTF-8 excerpt |
| Report-to-evidence references | PASS | Official report 65/65; current-product report 14/14 |
| GitHub commit exists remotely | PASS | `9b0adccd79c5edc90cbe8db54b64abdffc46b0aa` resolves |
| Commit-pinned links | PASS | 14/14 returned HTTP 200 |
| Exact current-product commands | PASS with reproducibility warning | 14/14 exited 0 |
| Cross-fragment schema consistency | FAIL | Two incompatible key vocabularies |
| Official source supports recorded facts | FAIL | Several facts are missing, ambiguous, promotional, or contradicted |
| Selectable-offer safety | FAIL | Review-only facts are mixed into the “Verified offer matrix” |
| Mandatory ChatGPT tier coverage | FAIL | `$200` Pro is not an independently evidenced matrix row |

## Blocking Findings

### AUD-01 — OFF-001 is not reproducible and does not cover all required ChatGPT tiers

**Priority:** blocker

Rerunning the recorded command:

```sh
curl -sL --max-time 45 \
  'https://r.jina.ai/https://chatgpt.com/pricing'
```

returned the Free, Go, Plus, and Pro headings and `/ month` labels, but all
numeric consumer prices were blank. It therefore does not reproduce the
recorded `$8`, `$20`, or `from $100` fields.

The report also says its second session retained ChatGPT's key values, which
the independent rerun did not reproduce. More importantly, the mandatory
coverage says “complete tiers,” but its verified matrix has only one
`Pro from USD 100` row and no independent `Pro 20x USD 200/month` row.

This can be repaired without guessing by splitting the evidence:

```sh
curl -sL --max-time 45 \
  'https://r.jina.ai/https://openai.com/index/introducing-chatgpt-go/'
curl -sL --max-time 45 \
  'https://r.jina.ai/https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus'
curl -sL --max-time 45 \
  'https://r.jina.ai/https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro'
```

The first source states US Go at `$8/month`; the second states Plus at
`$20/month`; the third explicitly distinguishes Pro `$100` (5x) and `$200`
(20x). `OFF-001` must be replaced or downgraded, not retained as-is.

### AUD-02 — “Verified offer matrix” conflates evidence with selectability

**Priority:** blocker

The report correctly states that `from`, annual-equivalent, promotional, and
unknown-renewal values must not silently populate an exact charge. Its matrix
then includes those same values among recommendations for a reviewed preset
batch.

Affected records include:

- `OFF-003`: Claude Max is `from $100`, not one exact offer;
- `OFF-028`: Perplexity exposes `$17` and `$167` monthly equivalents when
  billed annually, but the captured source does not state the annual totals;
- `OFF-037`: GitHub Team `$4` is explicitly “for the first 12 months”;
- `OFF-038`: Grammarly shows `$12`, but the captured output does not bind it
  to a complete charge cadence or annual total;
- `OFF-047`: Medium `$50/year` is a discounted annual value whose standard
  renewal is not captured.

Required correction:

1. separate `source supports this displayed fact` from
   `verifiedSelectable`;
2. add an explicit decision column to the offer matrix;
3. require an exact charged amount and charged interval before selectability;
4. store annual totals separately from monthly display equivalents;
5. keep `from`, promotional-only, eligibility-dependent, and unresolved
   renewal values `review-required`.

### AUD-03 — Several App Store records contain unresolved internal conflicts

**Priority:** blocker for the affected offers

The exact source reruns exposed additional conflicts:

- `OFF-020`: QQ Music lists Super Member monthly at both CNY 19 and CNY 30.
  CNY 19 is not safe as a selectable default until the segment/current SKU is
  identified. Green Diamond CNY 15 can be split into a separate record.
- `OFF-025`: WeChat Reading prose says the annual card is CNY 228, while the
  current IAP list shows CNY 168. The recurring CNY 19 monthly record can be
  split and retained; quarter/year values require review.
- `OFF-044`: the same Apple Music page shows Individual at USD 11.99 in its
  current plan/footnote section and USD 10.99 in a stale FAQ paragraph. The
  record must be `contradicts` until the authoritative section and recency
  rule are documented.
- `OFF-055`: Calm prose says USD 14.99/month and USD 69.99/year, while its IAP
  list also exposes USD 16.99 and USD 79.99 for the same generic plan label.
  Treat as `contradicts`, not selectable.
- `OFF-049`: Disney+ Basic is explicitly labeled monthly, but Premium
  USD 18.99 and USD 189.99 do not carry cadence in the captured IAP labels.
- `OFF-052`: Paramount+ Essential has an explicit monthly label; Premium
  USD 13.99 does not.
- `OFF-054`: the Duolingo IAP list has several “Super Duolingo” values with no
  unambiguous plan/cadence mapping.
- `OFF-057`: Strava exposes USD 11.99 and USD 79.99 under generic
  “Subscription” labels without binding each value to month/year.
- `OFF-022`: the App Store proves YouTube Individual/Family prices, while
  `OFF-021` proves membership families and the individual monthly family.
  The record pair is sufficient for plan discovery, but Family cadence still
  needs an explicit channel-specific source before preset adoption.

`OFF-010` and `OFF-032` are already correctly labeled `contradicts`; their
offer rows must also remain non-selectable until resolved.

### AUD-04 — Four “not-verifiable” sources now expose complete prices

**Priority:** blocker for research completeness

Rerunning the exact stored commands produced facts that the report says were
unavailable:

- `OFF-063`: iCloud+ shows 50 GB USD 0.99/month, 200 GB USD 2.99/month,
  2 TB USD 9.99/month, 6 TB USD 29.99/month, and 12 TB USD 59.99/month.
- `OFF-064`: Microsoft 365 Personal, Family, and Premium expose monthly and
  annual prices plus auto-renewal semantics.
- `OFF-067`: Xbox Game Pass exposes Essential USD 9.99/month, Premium
  USD 14.99/month, Ultimate USD 22.99/month, and PC USD 13.99/month after
  any stated introductory period.
- `OFF-068`: PlayStation Plus Premium, Extra, and Essential expose explicit
  1-, 3-, and 12-month prices.

These records must be recollected with new excerpts/hashes and upgraded from
`not-verifiable`. The report's saturation conclusion should be revised:
targeted rereading still produced substantial new catalog coverage.

### AUD-05 — Six CUR records combine claims that their single link cannot prove

**Priority:** should fix before final manifest

- `CUR-002` links the Actions toolbar but not the read-only detail form or the
  library navigation that precedes it.
- `CUR-003` links row swipe actions but not the duplicated detail Actions menu.
- `CUR-004` links the exact matcher but not the manual form's lack of
  typeahead.
- `CUR-008` links Add defaults but its claim also depends on the offer-adoption
  lines and the catalog currency inventory.
- `CUR-009` links ChatGPT's catalog JSON but not the `CatalogIcon` enum.
- `CUR-010` links Canva's catalog JSON but not the catalog row presentation.

The report conclusions are consistent with the inspected code, but each
evidence object should support one atomic claim. Split the records or allow a
`source_refs` array containing every pinned permalink and exact command.

`CUR-013` is also weak negative evidence: a zero-result keyword search does
not by itself prove that no equivalent research matrix exists under different
vocabulary. Keep the report's broader code/history audit as the basis, or
reduce the excerpt to the literal search result.

### AUD-06 — Fragment schemas are incompatible

**Priority:** must fix during deterministic merge

Official records use:

- `access_timestamp`;
- `verification_date`;
- `sha256`;
- `commit_pinned_permalink`.

Current-product records use:

- `accessed_at`;
- `verified_on`;
- `excerpt_sha256`;
- `commit_permalink`.

Both fragments are internally consistent, but concatenating them does not
produce one manifest schema. Normalize to one key set before the final merge
and validate every output record against it.

### AUD-07 — Five CUR commands read the mutable working tree

**Priority:** should fix

`CUR-006`, `CUR-007`, `CUR-010`, `CUR-011`, and `CUR-013` have pinned URLs but
their recorded commands read current files. They happened to pass because
`9b0adcc..HEAD` has no product-code/test diff, but the commands are not
self-pinning.

Use forms such as:

```sh
git show 9b0adccd79c5edc90cbe8db54b64abdffc46b0aa:SubscriptionManager/Resources/catalog-v1.json |
  jq '...'
git grep -n -E 'competitor|community|open-source|open source' \
  9b0adccd79c5edc90cbe8db54b64abdffc46b0aa -- \
  SubscriptionManager Packages SubscriptionManagerTests SubscriptionManagerUITests
```

## OFF-001–OFF-070 Disposition

“Selectable” below means the captured record contains a complete exact charge
for at least the named offer. Mixed records must still be split before import.

| ID | Audit disposition | Required action |
| --- | --- | --- |
| OFF-001 | FAIL | Replace with separate official Go/Plus/Pro records; add both Pro tiers |
| OFF-002 | Selectable | Retain Business fixed seat prices and minimum-seat caveat |
| OFF-003 | Mixed | Split Pro/Team selectable facts from Max `from` review-required fact |
| OFF-004 | Selectable | Retain International Canva offers with tax/channel context |
| OFF-010 | Contradicts | Keep Canva 可画 monthly/annual non-selectable pending reconciliation |
| OFF-011 | Not verifiable | Retain service identity; no price |
| OFF-012 | Review-required | Eligibility-dependent RMB 88 lead only; not the complete two-tier set |
| OFF-013 | Not verifiable | Retain JD PLUS identity/cadences; no price |
| OFF-014 | Not verifiable | Retain Sam's tier names; no price |
| OFF-015 | Not verifiable | Do not infer a 豆包 subscription from “App 内购买” |
| OFF-016 | Selectable | Retain the two explicit monthly membership offers |
| OFF-017 | Selectable | Retain explicit monthly/yearly auto-renew offers |
| OFF-018 | Not verifiable | No 腾讯元宝 recurring plan |
| OFF-019 | Selectable | Retain explicit Tencent Video/Sports recurring offers |
| OFF-020 | Contradicts/mixed | Split Green Diamond; Super Member remains review-required |
| OFF-021 | Plan-only support | Retain YouTube plan-family evidence; no prices |
| OFF-022 | Review-required | Preserve iOS prices; obtain explicit Family cadence |
| OFF-023 | Selectable | Retain explicit iQIYI recurring offers |
| OFF-024 | Selectable | Retain explicit Youku offers |
| OFF-025 | Contradicts/mixed | Keep CNY 19 monthly; quarter/year require reconciliation |
| OFF-026 | Selectable | Retain explicit Bilibili monthly offer |
| OFF-027 | Selectable | Retain explicit NetEase monthly offers |
| OFF-028 | Review-required | Capture annual totals before adoption |
| OFF-029 | Selectable | Retain Cursor Pro/Teams monthly offers |
| OFF-030 | Selectable | Retain explicit Kugou monthly offers |
| OFF-031 | Selectable | Retain named WPS offers; preserve variant labels |
| OFF-032 | Contradicts | No selectable Baidu Netdisk price until CNY 25/30 is resolved |
| OFF-033 | Selectable | Retain explicit Mango TV cadences/prices |
| OFF-034 | Selectable | Retain named CapCut monthly/yearly offers |
| OFF-035 | Selectable | Retain exact Figma plan/seat facts |
| OFF-036 | Selectable with semantics | Separate standard renewal from introductory promotion |
| OFF-037 | Review-required | First-12-month price is not a stable renewal preset |
| OFF-038 | Review-required | Capture charged cadence and total |
| OFF-039 | Selectable | Retain exact Dropbox offer |
| OFF-040 | Selectable | Retain annual total and cadence; equivalent is display-only |
| OFF-041 | Mixed | Monthly USD 16.99 selectable; annual equivalent needs charged total |
| OFF-042 | Mixed | Monthly standard prices selectable; annual equivalents need totals |
| OFF-043 | Selectable | Retain post-intro Spotify renewal prices |
| OFF-044 | Contradicts | Resolve USD 11.99/10.99 internal page conflict |
| OFF-045 | Selectable | Retain exact Google One/AI monthly offers |
| OFF-046 | Selectable | Retain explicit Coursera monthly/annual offers |
| OFF-047 | Review-required | Discounted annual price lacks standard renewal |
| OFF-048 | Selectable | Netflix plan prices plus month-to-month semantics are present |
| OFF-049 | Mixed | Basic monthly selectable; Premium cadence requires explicit evidence |
| OFF-050 | Selectable | IAP labels bind Max plans to monthly/yearly cadences |
| OFF-051 | Selectable | Hulu prices plus current-subscription-month semantics are present |
| OFF-052 | Mixed | Essential monthly selectable; Premium cadence requires evidence |
| OFF-053 | Selectable | Audible IAP labels explicitly state monthly |
| OFF-054 | Review-required | Ambiguous Duolingo price/cadence mapping |
| OFF-055 | Contradicts | Resolve prose/IAP Calm prices |
| OFF-056 | Selectable | Headspace prose explicitly binds both cadences/prices |
| OFF-057 | Review-required | Generic Strava IAP labels do not bind cadence |
| OFF-058 | Selectable | Discord IAP labels explicitly bind monthly/yearly |
| OFF-059 | Selectable | Annual membership terms plus named IAP prices support rows |
| OFF-060 | Not verifiable | Core Notion plan prices remain absent in captured output |
| OFF-061 | Not verifiable | Poe page still exposes no stable price |
| OFF-062 | Not verifiable | 1Password reader output still omits numeric prices |
| OFF-063 | Newly selectable | Replace excerpt/hash with current iCloud+ plan-price matrix |
| OFF-064 | Newly selectable | Replace excerpt/hash with Microsoft 365 monthly/annual matrix |
| OFF-065 | Not verifiable | IAP is only the Prime Video ad-free add-on |
| OFF-066 | Not verifiable | Kindle Unlimited price remains absent |
| OFF-067 | Newly selectable | Replace excerpt/hash with current Game Pass plan matrix |
| OFF-068 | Newly selectable | Replace excerpt/hash with current PS Plus plan/cadence matrix |
| OFF-069 | Not verifiable | Nintendo page still exposes no numeric price |
| OFF-070 | Not verifiable | Midjourney pricing remains login-gated |

## CUR-001–CUR-014 Checklist

| ID | Command | Link | Claim support |
| --- | --- | --- | --- |
| CUR-001 | PASS | 200 | PASS |
| CUR-002 | PASS | 200 | PARTIAL — missing read-only/navigation source |
| CUR-003 | PASS | 200 | PARTIAL — missing detail-menu source |
| CUR-004 | PASS | 200 | PARTIAL — missing manual-form source |
| CUR-005 | PASS | 200 | PASS |
| CUR-006 | PASS | 200 | PASS; command should be commit-pinned |
| CUR-007 | PASS | 200 | PASS; command should be commit-pinned |
| CUR-008 | PASS | 200 | PARTIAL — compound claim and permalink range mismatch |
| CUR-009 | PASS | 200 | PARTIAL — missing icon-enum source |
| CUR-010 | PASS | 200 | PARTIAL — missing row-presentation source |
| CUR-011 | PASS | 200 | PASS; command should be commit-pinned |
| CUR-012 | PASS | 200 | PASS |
| CUR-013 | PASS/zero result | 200 | WEAK negative evidence; command should be commit-pinned |
| CUR-014 | PASS | 200 | PASS |

## Reproducible Audit Commands

Environment and routing:

```sh
agent-reach doctor --json
```

JSONL, uniqueness, and report references:

```sh
jq -c . docs/research/evidence/official-catalog.jsonl
jq -c . docs/research/evidence/current-product.jsonl
jq -r '.evidence_id' docs/research/evidence/official-catalog.jsonl |
  sort | uniq -d
jq -r '.evidence_id' docs/research/evidence/current-product.jsonl |
  sort | uniq -d
rg -o 'OFF-[0-9]+' \
  docs/research/2026-07-30-official-subscription-catalog-expansion.md |
  sort -u
rg -o 'CUR-[0-9]+' \
  docs/research/2026-07-30-round-2-current-product-gap-audit.md |
  sort -u
```

Hash recomputation used Node's UTF-8 SHA-256 over each exact `excerpt` and
compared it with `sha256` or `excerpt_sha256`.

Official rerun pattern:

```sh
curl -sL --max-time 45 'https://r.jina.ai/https://…'
```

Pinned commit verification:

```sh
gh api \
  repos/Klausc06/subscription-manager/commits/9b0adccd79c5edc90cbe8db54b64abdffc46b0aa \
  --jq '.sha'
git diff --quiet \
  9b0adccd79c5edc90cbe8db54b64abdffc46b0aa..HEAD -- \
  Packages SubscriptionManager SubscriptionManagerTests SubscriptionManagerUITests
```

Each `CUR-*` command was executed verbatim. Each `commit_permalink` was then
requested with:

```sh
curl -sL --max-time 30 -o /dev/null -w '%{http_code}' 'PINNED_URL'
```

## Acceptance Conditions for Re-review

The two workstreams can pass after:

1. ChatGPT evidence is split into Go, Plus, Pro 5x, and Pro 20x with
   reproducible first-party sources;
2. every row in the selectable matrix has exact charged amount, currency,
   charged interval, market, channel, and standard-renewal semantics;
3. the affected conflict/ambiguity IDs are downgraded or split;
4. `OFF-063`, `OFF-064`, `OFF-067`, and `OFF-068` are recollected from the
   now-visible official facts;
5. compound `CUR-*` claims receive all necessary pinned references;
6. mutable current-tree commands are pinned;
7. all fragments are normalized to one manifest schema;
8. JSON parsing, uniqueness, hashes, report references, and an independent
   source rerun pass again.
