# Round 2 UX and Catalog Research Plan

**Date:** 2026-07-30
**Status:** Approved for research — independent subagent review: `OKAY`
**Input:** `2026-07-30-round-2-requirements.md`

## Goal

Produce enough verified evidence to choose the next UX and catalog design
without treating the user's proposed controls as predetermined solutions.
Research must cover all 14 reported problems and every named service, then
expand beyond the examples using a bounded priority framework.

The winning design is the one that gives the person the most useful
information with the fewest understandable operations while remaining
visually polished. Existing architecture may be changed substantially when it
blocks that result.

## Evaluation Rubric

Every UX alternative must be compared in this order:

1. number of taps, screens, focus changes, and required text entries for the
   primary task;
2. amount of decision-relevant information visible before secondary
   navigation;
3. clarity of state, completion, validation, undo, and destructive-action
   recovery;
4. visual hierarchy, density, native feel, accessibility, and adaptation
   across Apple platforms;
5. implementation, migration, testing, and maintenance cost.

The report must include the current-flow baseline and the proposed-flow
interaction count for Add, manual matching, editing, date entry, archive,
delete, and upcoming-renewal inspection. Raw tap reduction is not sufficient
when it makes state ambiguous or destructive behavior unsafe.

Architecture is an evaluated variable, not a fixed constraint. The synthesis
must explicitly say whether each recommended experience is best delivered by
incremental refactoring, replacement of a feature boundary, or a larger
domain/navigation redesign.

## Shared Comparison Protocol

Every interaction alternative is measured against the same fixtures.

| Scenario | Fixed start state | Required end state |
| --- | --- | --- |
| S1 — Add verified known service | Current library and the unchanged catalog's verified ChatGPT offers | Correct verified offer and schedule are saved |
| S2 — Add unknown service | Manual add with no catalog match | Service, price, currency, interval, and dates save; plan/category stay empty |
| S3 — Edit subscription | Existing active ChatGPT subscription is selected | Price, currency, interval, and linked dates are changed and visible |
| S4 — Archive | Current-library row is visible | Subscription is archived and absent from current forecasts |
| S5 — Delete | Current-library row is visible | Confirmation is completed and the subscription is permanently absent |
| S6 — Inspect upcoming | A month contains empty, single-charge, and dense multi-charge days | Person identifies a charge date and opens its subscription |
| S7 — Enter dates | Add/Edit has valid price and interval | Start Date and Next Renewal are visibly committed without ambiguous dismissal |
| S8 — Match manual partial name | Manual add is open and the person enters `88` | Relevant 88VIP catalog variants appear and one can be adopted without retyping official facts |

Primary comparison uses the supported iPhone in portrait with Simplified
Chinese and Dynamic Type at the default size. Each viable recommendation is
then checked on iPad split view, macOS, English, one accessibility text size,
and VoiceOver navigation. The fixture data and device/OS versions are recorded
in the synthesis.

The unchanged-build baseline may record a scenario as **unavailable** when the
reported capability does not exist; this is evidence, not a failed research
run. Proposed S8 alternatives use a non-shipping fixture in `/tmp` whose
aliases and offers come from the verified research manifest. The fixture is
never written to `catalog-v1.json` during research.

Counting units:

- **activation:** one tap, click, keyboard activation, swipe completion, or
  VoiceOver activation;
- **text entry:** each required field focus plus entered value, with character
  count reported separately rather than treating typing as one tap;
- **transition:** a push, sheet, popover, mode change, or focus context that
  replaces the current task surface;
- **visible information:** whether service, plan when known, price, currency,
  interval, dates, status, and next charge are available before secondary
  navigation;
- **ambiguity/cognitive flags:** hidden action, unlabeled icon, unclear commit,
  competing primary actions, duplicated controls, or state that is visible
  only after dismissal;
- **visual/accessibility checks:** hierarchy, redundant containers, Dynamic
  Type clipping, contrast, VoiceOver order/labels, localization expansion, and
  platform adaptation;
- **implementation surface:** estimated changed files, state owners, custom
  views, duplicated logic, external dependencies, and source-line range.

Decision rule:

1. Reject an alternative that fails correctness, destructive-action safety,
   clear commit state, accessibility, or required information.
2. Prefer a Pareto-dominant alternative that uses no more operations while
   exposing at least as much useful information.
3. When no alternative dominates, apply the ordered Evaluation Rubric and
   document the explicit trade-off.
4. Never select a lower tap count that increases ambiguity, error risk, or
   hidden state.

## Breadth and Saturation

The listed sample sizes are minimums, not ceilings:

- official catalog research covers every named product plus at least 30
  additional high-priority recurring services across the target ecosystems;
- competitor research compares at least 12 maintained subscription, finance,
  or renewal-tracking products;
- open-source research inspects at least 10 relevant repositories and reads
  source for the strongest implementations rather than relying on README
  screenshots;
- community research samples all available target platforms and records at
  least 30 relevant discussions in total, with Chinese and overseas evidence;
- Apple interaction research compares official native APIs plus at least
  three credible implementation families for date entry, calendar, and
  autocomplete.

Research does not end merely because these minimums were reached. Each
workstream records saturation: what the last sources added, whether any major
alternative remains unexplored, and why further collection is unlikely to
change the recommendation.

The synthesis must identify opportunities to reduce implementation surface:

- native APIs that replace custom controls;
- one data-driven flow that can serve Add and Edit;
- one catalog representation that can serve search, confirmation, defaults,
  widgets, and future updates;
- shared schedule and presentation state instead of per-screen state;
- maintained open-source components whose license, accessibility, and
  maintenance risk justify adoption.

## Research Scope Approach

### Approach A — Named examples only

Research only the products explicitly named in the review.

- Advantage: fastest.
- Risk: repeats the current problem of adding isolated offers without a
  coherent taxonomy or expansion strategy.
- Decision: reject.

### Approach B — Verified ecosystem batches

Research every named example, then expand by product ecosystem and category.
Only first-party-verifiable recurring offers become verified presets.

- Advantage: thorough enough to improve the product while remaining
  reviewable and maintainable.
- Risk: requires explicit prioritization and ongoing verification.
- Decision: recommended.

### Approach C — Attempt an exhaustive global catalog

Collect every discoverable subscription and price before implementation.

- Advantage: broad nominal coverage.
- Risk: unbounded scope, rapidly stale data, inconsistent sources, and weak
  quality control.
- Decision: reject as a release gate; retain a backlog for later batches.

## Evidence Rules

### Catalog facts

Use sources in this order:

1. official provider pricing or membership page;
2. official provider help/billing documentation;
3. official Apple App Store or regional first-party store listing;
4. provider terms that explicitly state recurring price and interval.

Third-party articles, search snippets, affiliate pages, remembered prices, and
community posts may identify a lead but cannot verify an offer.

Every candidate offer must capture:

- provider and product variant;
- localized service and plan names;
- market/region;
- purchase channel;
- recurring price and currency;
- billing interval;
- promotion versus standard renewal semantics;
- source URL;
- verification date;
- selectable/review-required decision and reason.

### UX and community evidence

- Official product documentation and store listings establish features.
- GitHub source code establishes implementation facts.
- Reddit, X/Twitter, V2EX, 小红书, and B站 establish reported preferences and
  pain points, not universal truth.
- Community claims must include the thread/post URL and be labeled as
  anecdotal, repeated pattern, or isolated report.
- Browser sessions may be used for login only. Retrieval uses CLI/API readers
  so the evidence is reproducible.

## Reproducible Evidence Manifest

Every source used in a finding receives one JSON Lines record in:

`docs/research/2026-07-30-round-2-evidence-manifest.jsonl`

Parallel workstream owners first write isolated fragments under
`docs/research/evidence/`. The primary researcher then performs a deterministic
merge into the manifest above, validates the schema, and rejects duplicate
`evidence_id` values. This avoids concurrent edits to one shared file without
weakening the final audit trail.

Required fields:

- `evidence_id`;
- `workstream`;
- `source_type` (`official`, `store`, `source-code`, or `community`);
- canonical `url`;
- access timestamp and verification date;
- market, locale, account/login context, and purchase channel when relevant;
- exact CLI/API/reader command with secrets removed;
- a short supporting excerpt or structured fields, plus SHA-256 of the
  captured normalized text;
- claim IDs supported;
- repository commit SHA and commit-pinned permalink for source-code evidence;
- researcher disposition (`supports`, `contradicts`, `lead-only`, or
  `not-verifiable`).

Raw page/CLI output stays in `/tmp` during collection and is not committed.
The manifest stores only the minimum excerpt and hash needed for audit, within
source quotation limits. A second researcher reopens a sample of at least 10%
of manifest records, including every high-volatility price, and records
pass/fail in the synthesis.

## Workstreams

### Workstream 1 — Current-product gap audit

**Questions**

- Which fields are currently required by the domain and UI?
- Which screens, menus, gestures, and navigation transitions implement the
  reported friction?
- Which catalog fields cannot represent region/product variants cleanly?
- Which current tests encode superseded behavior?

**Output**

- A code-backed gap appendix in the final synthesis.
- Traceability from R2-01 through R2-14 to current files and behaviors.

**Procedure and QA**

1. Use `rg`, `git log`, `git blame`, the shipped catalog validator, and current
   tests to identify every relevant state owner and UI path.
2. Execute S1–S8 against the unchanged build and record baseline counting
   units using the Shared Comparison Protocol.
3. Map each R2 requirement to at least one concrete file/line and test or mark
   the missing test explicitly.

Expected result: 14/14 requirements mapped, 8/8 baseline scenarios recorded
(including explicit unavailable results),
and zero unmapped current behaviors.

### Workstream 2 — Official catalog and price research

**Mandatory named coverage**

- 88VIP variants;
- JD PLUS;
- Sam's Club China membership tiers;
- 豆包、剪映、即梦;
- additional ByteDance paid AI/creation products found through official
  sources;
- Tencent AI and consumer subscriptions;
- QQ Music plan variants;
- Canva International and 可画中国版;
- YouTube Premium variants;
- the existing first-batch international AI services.

**Expansion framework**

Rank additional candidates using:

1. likelihood that a Chinese or international user tracks it;
2. recurring fixed-price suitability;
3. availability of first-party price evidence;
4. category/ecosystem coverage;
5. volatility and maintenance cost.

The research report proposes verified batches; it does not directly edit
`catalog-v1.json`.

**Output**

- `docs/research/2026-07-30-official-subscription-catalog-expansion.md`
- A source-linked offer matrix.
- Data-model gaps and catalog migration recommendations.

**Procedure and QA**

1. Discover candidates through official indexes and Jina Reader searches, then
   open the canonical first-party page with
   `curl -s https://r.jina.ai/https://…`.
2. Use official store/API readers only when the provider page does not expose
   a channel-specific recurring price.
3. Record every accepted, conflicting, and not-verifiable result in the
   evidence manifest.
4. Recheck all high-volatility offers and a 10% random sample from another
   access session.

Expected result: every mandatory named product has a verified or explicit
not-verifiable result; at least 30 additional services are assessed; 100% of
selectable offers have complete market/channel/price/currency/interval/source
fields; zero third-party-only prices are marked verified.

### Workstream 3 — Competitor, open-source, and community research

**Product questions**

- Do successful trackers open in view mode, edit mode, or a hybrid?
- How do they handle unknown plan/category while preserving useful forecasts?
- Where do archive, delete, payment history, price changes, and cancellation
  facts live?
- How do they visualize upcoming renewals?
- How do they surface catalog-assisted manual entry?

**Sources**

- official sites and store listings for established subscription trackers;
- active and relevant GitHub repositories, cited with commit-pinned links;
- Reddit, X/Twitter, V2EX, 小红书, and B站 discussions.

**Output**

- `docs/research/2026-07-30-subscription-tracker-competitive-community.md`
- Competitor matrix, repeated pain points, successful patterns, and
  anti-patterns.

**Procedure and QA**

1. Read official product/store pages through Jina Reader.
2. Search GitHub using `gh search repos` and inspect relevant code at a fixed
   commit using `gh api` or a read-only checkout.
3. Use `opencli reddit`, `opencli xiaohongshu`, `opencli bilibili`,
   `twitter`, and the V2EX public API for community evidence; save the exact
   read/search command in the manifest.
4. Code each community item by requirement, sentiment, and whether it is an
   isolated report or repeated pattern.

Expected result: at least 12 maintained products, 10 repositories with
commit-pinned evidence, and 30 relevant community discussions across every
available target platform; each claimed repeated pattern is supported by at
least three independent sources or is labeled anecdotal.

### Workstream 4 — Apple-platform interaction and calendar research

**Questions**

- What is the clearest native editing model for a data-heavy subscription?
- Which date-entry designs provide explicit completion without adding
  unnecessary taps?
- Should focus advance automatically, use Next/Done controls, or commit
  immediately?
- Which calendar architecture best supports month overview plus day agenda?
- How do native and open-source options compare for VoiceOver, Dynamic Type,
  localization, iPhone/iPad/macOS support, testability, and maintenance?
- How should inline search suggestions behave with keyboard navigation and
  accessibility?
- What hierarchy does Apple recommend for segmented controls without
  decorative nesting?

**Candidate families to compare**

- SwiftUI `DatePicker` styles and focused form navigation.
- UIKit `UICalendarView` wrapped for SwiftUI.
- Calendar/agenda hybrid built from native date calculations.
- Mature open-source calendar components with acceptable licensing and active
  maintenance.

**Output**

- `docs/research/2026-07-30-ios-editing-date-calendar-patterns.md`
- Two or three viable approaches for each major interaction, with a
  recommendation and risks.

**Procedure and QA**

1. Read Apple HIG, SwiftUI/UIKit documentation, and WWDC material through
   official URLs using Jina Reader or Apple documentation data endpoints.
2. Inspect native API behavior with a minimal throwaway fixture in `/tmp` when
   documentation does not settle an interaction question.
3. Search implementations with `gh search code`, inspect the source at a fixed
   commit, and record license, maintenance, accessibility, and platform
   support.
4. Score each alternative using S1–S8 and the Shared Comparison Protocol.

Expected result: at least two viable alternatives for direct editing, date
flow, autocomplete, calendar/agenda, and segmented-control hierarchy; at least
three implementation families for calendar/date/autocomplete; every rejected
alternative has a documented reason.

### Workstream 5 — Synthesis and design decision preparation

**Output**

- `docs/research/2026-07-30-round-2-research-synthesis.md`
- One evidence table mapping every R2 requirement to findings.
- Two or three product/technical approaches with trade-offs.
- A recommended staged delivery with explicit acceptance tests.
- Proposed changes to domain vocabulary and ADRs, if required.

The synthesis is not an implementation plan. Product review selects the design
direction first.

**Procedure and QA**

1. Validate manifest schema, unique evidence IDs, reachable URLs, required
   context, and claim references.
2. Reconcile conflicting findings and preserve dissent rather than silently
   choosing one source.
3. Map the recommendation back to R2-01–R2-14 and S1–S8.
4. Compare incremental, boundary-replacement, and larger-redesign
   architectures using the same experience and implementation-surface rubric.

Expected result: 14/14 requirements and 8/8 scenarios have supported findings,
every recommendation has at least one manifest-backed source and an explicit
inference label, all breadth floors are met, and the independent 10% evidence
recheck passes.

## Execution Order After Approval

1. Freeze the requirements draft after requested corrections.
2. Run Workstreams 2, 3, and 4 in parallel.
3. Complete Workstream 1 against the unchanged codebase.
4. Cross-check conflicting prices, regional names, and community claims.
5. Write Workstream 5 and present alternatives for product approval.

## Research Completion Gates

Research is complete only when:

- all 14 reported problems appear in the synthesis;
- every named service has an official-source result or an explicit
  “not verifiable” result;
- no third-party price is labeled verified;
- Chinese and international variants are not silently merged;
- catalog recommendations include currency defaults and AI taxonomy;
- editing, date flow, upcoming calendar, autocomplete, and segmented-control
  choices each compare at least two viable approaches;
- community evidence is separated from official and technical facts;
- proposed implementation batches are independently testable;
- the recommended experience includes interaction-count and
  information-density comparisons against the current product;
- architectural changes are sized honestly and are not rejected solely
  because they are large;
- every workstream meets its breadth floor and documents research saturation;
- the synthesis compares estimated custom code and architectural surface, not
  only feature coverage;
- no product code or bundled catalog data was changed during research.

## Approval Gate

The product owner delegated draft review to an independent planning subagent.
After two correction rounds, its terminal verdict was `OKAY`:

> Fixture contradiction resolved, S1–S8 consistent, unavailable baseline
> explicit. Plan executable, auditable, correctly blocked pending approval.

Research may begin. Functional implementation remains blocked until the later
research synthesis and design are separately approved.
