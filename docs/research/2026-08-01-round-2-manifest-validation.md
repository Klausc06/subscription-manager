# Round 2 Evidence Manifest Validation

**Date:** 2026-08-01
**Manifest:** `docs/research/2026-07-30-round-2-evidence-manifest.jsonl`
**Structural verdict:** PASS for the four durable first-pass fragments
**Source/claim verdict:** REVISE — official catalog and selected community
records remain open

## Deterministic Merge

The manifest is a sorted, field-normalized merge of:

- `docs/research/evidence/current-product.jsonl` — 32 records;
- `docs/research/evidence/official-catalog.jsonl` — 78 records;
- `docs/research/evidence/competitive-community.jsonl` — 59 records;
- `docs/research/evidence/ios-interaction.jsonl` — 18 records.

Normalized fields are:

```text
evidence_id
workstream
source_type
url
accessed_at
verification_date
market
locale
account_context
purchase_channel
command
excerpt
excerpt_sha256
claim_ids
repository_commit_sha
commit_permalink
disposition
```

`access_timestamp` was normalized to `accessed_at`, `verified_on` to
`verification_date`, `sha256` to `excerpt_sha256`, and
`commit_pinned_permalink` to `commit_permalink`. Source excerpts and hashes
were not rewritten.

## Structural Results

| Check | Result |
| --- | --- |
| JSON Lines parse | PASS — 187/187 |
| Unique `evidence_id` | PASS — 187 unique, 0 duplicates |
| Required normalized field types | PASS — 0 invalid records |
| SHA-256 of exact UTF-8 excerpt | PASS — 187/187 |
| CUR count | 32 |
| OFF count | 78 |
| COM count | 59 |
| IOS count | 18 |

Source types are limited to the approved vocabulary:

- `official`: 56;
- `store`: 52;
- `source-code`: 45;
- `community`: 34.

Disposition counts are:

- `supports`: 150;
- `contradicts`: 8;
- `lead-only`: 15;
- `not-verifiable`: 14.

## Independent Sampling

Independent reviewers exceeded the 10% sampling floor for every durable
fragment:

- current product: all 32 command-backed records were replayed against the
  pinned commit;
- official catalog: all high-volatility/selectability rows and the named gaps
  were re-opened, with targeted full review of the volatile second-pass set;
- competitor/community: 10 of 59 first-pass records were rechecked;
- iOS interaction: 6 of 18 records were rechecked, plus the current-run native
  calendar/date fixture.

The final external re-read was partially constrained by the prior platform
quota. That limitation is recorded rather than treated as a pass.

## Open Claim Corrections

Structural normalization closes the first-pass schema mismatch only. It does
not approve price-bearing facts.

1. `OFF-015` says 豆包 did not expose a stable public recurring offer, while
   second-pass OGD extraction found six exact monthly/yearly offers. The
   official response must be preserved, sanitized, hashed, normalized, and
   independently re-opened before those offers become selectable.
2. Kimi and 秘塔 observations without explicit continuous-renewal semantics
   remain `lead-only` or Price Required.
3. Apple Music Individual, Canva 可画, and 智谱清言 require a documented
   authority/recency rule and explicit conflict status.
4. Second-pass OGD records need content-addressed sanitized raw responses;
   mutable reader output plus excerpt hash alone is not a shipping gate.
5. Community commands that only download archives must print the cited commit,
   file, and lines. Reddit and Bilibili excerpts need deterministic snapshots
   or must remain design supplements.
6. iOS open-source commands must explicitly check out the recorded SHA rather
   than relying on a future depth-one HEAD.
7. The 84-record OGD pass and 52-record second community pass are not merged
   into this manifest. They remain provisional until their own durable
   fragments satisfy this schema and hash policy.

## Re-audit Gate

Catalog import remains blocked until:

1. OFF and OGD are reconciled into one normalized allowlist;
2. every selectable row has exact charged amount, ISO currency, charged
   cadence, market, purchase channel, standard-renewal semantics, source, and
   verification date;
3. raw responses are sanitized and content-addressed;
4. conflict/lead-only rules are machine-validated;
5. every high-volatility price is independently re-opened;
6. the re-audit returns PASS for the exact shipping allowlist.

UX and architecture work that does not import catalog prices may proceed while
this gate remains open.

## Reproducible Validation Commands

```bash
jq -s 'length' \
  docs/research/2026-07-30-round-2-evidence-manifest.jsonl

jq -r '.evidence_id' \
  docs/research/2026-07-30-round-2-evidence-manifest.jsonl |
  sort | uniq -d

node -e '
const fs = require("fs");
const crypto = require("crypto");
const records = fs.readFileSync(
  "docs/research/2026-07-30-round-2-evidence-manifest.jsonl",
  "utf8"
).trim().split(/\n/).map(JSON.parse);
const failures = records.filter(record =>
  crypto.createHash("sha256")
    .update(record.excerpt, "utf8")
    .digest("hex") !== record.excerpt_sha256
);
if (failures.length > 0) process.exit(1);
console.log(`${records.length} excerpt hashes passed`);
'
```
