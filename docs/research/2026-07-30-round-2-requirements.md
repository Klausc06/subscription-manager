# Round 2 UX and Catalog Requirements

**Date:** 2026-07-30
**Status:** Approved for research — independent subagent review: `OKAY`
**Scope:** Requirements and research questions only; no implementation is
authorized by this document.

**Paired decision and execution documents:**

- `docs/research/2026-08-01-round-2-synthesis.md` resolves researched design
  choices and records which catalog claims remain open.
- `docs/superpowers/plans/2026-08-01-direct-editor-atomic-edit.md` implements
  Batch A and maps its tasks back to the requirement IDs in this document.
- `docs/research/2026-08-01-round-2-manifest-validation.md` is the evidence
  gate; it may block catalog breadth without blocking approved UX work.

## Product Rule

Each item in this document separates four things:

1. **Confirmed problem:** the current experience is not acceptable and must
   change.
2. **Suggested direction:** a possible solution proposed during product
   review.
3. **Research question:** alternatives that must be compared before choosing
   an implementation.
4. **Outcome acceptance:** the result the final design must achieve regardless
   of which control or layout is selected.

The confirmed problem and outcome are requirements. A suggested direction is
not automatically the final design.

## Product Priority

The product is optimized in this order:

1. **Fast, obvious task completion:** use the fewest meaningful taps, typing
   steps, screens, and decisions needed to finish the person's task.
2. **High useful information yield:** show the information needed to
   understand and act without forcing navigation into secondary pages.
3. **Low cognitive load:** more information must not become clutter,
   ambiguity, or a wall of equally weighted controls.
4. **Visual quality:** hierarchy, spacing, typography, motion, and native
   platform behavior must remain calm, coherent, and polished.
5. **Implementation convenience:** existing architecture is not protected when
   a different boundary would materially improve the first four priorities.

Large architectural changes are allowed. Existing views, workspace commands,
catalog models, persistence fields, navigation structure, and tests may be
replaced or reorganized when research shows that doing so produces a simpler
and more coherent product. Architecture must still preserve correctness,
privacy, offline behavior, accessibility, and testability.

Research depth is itself a product requirement. The design must not stop at
the first plausible competitor pattern, calendar component, or catalog
source. Research continues until additional credible examples stop changing
the main alternatives, risks, or recommendation.

When two approaches produce comparable experiences, prefer the one that uses
native platform behavior, data-driven configuration, fewer custom abstractions,
less duplicated state, and a smaller maintainable code surface. Fewer lines of
code are valuable only when they preserve clarity, correctness, accessibility,
and test coverage.

“Fewest operations” does not mean hiding necessary information or making an
irreversible action easier to trigger. Destructive actions, ambiguous catalog
matches, and unsaved changes retain appropriate confirmation.

## Minimum Savable Subscription

A person may save a subscription when these facts are present:

- service name;
- price;
- currency;
- billing interval;
- billing dates required to produce a real schedule.

These fields are optional metadata and must never block saving:

- plan;
- category;
- management URL;
- notes.

Initial status may have a useful default and does not require extra interaction
when the default is correct.

Unknown values remain unknown. The application must not invent a plan,
category, zero price, monthly interval, or arbitrary date merely to satisfy
storage.

## Requirement Traceability

| ID | Original point | Confirmed problem | Outcome acceptance |
| --- | ---: | --- | --- |
| R2-01 | 1 | Plan and category are currently required even when the person does not know or need them. | A record with the five minimum facts saves successfully with empty plan and category. |
| R2-02 | 2 | Opening a tracked subscription first shows a read-only page, adding an unnecessary step before ordinary editing. | Tapping a subscription immediately exposes editable service, price, currency, interval, and billing-date facts. |
| R2-03 | 3 | A chevron/overflow menu and several secondary screens hide ordinary actions and make the detail hierarchy too deep. | Ordinary editing and library management do not require opening a catch-all secondary menu. Archive and permanent delete are reachable from the library without entering the subscription screen; permanent delete retains confirmation. |
| R2-04 | 4 | Manual entry does not help the person reuse an existing catalog service while typing. | Typing a partial name or alias such as `88` presents relevant catalog matches; selecting one adopts verified data without preventing manual entry. |
| R2-05 | 5 | Month/date selection has unclear completion, focus progression, and commit state. The person must tap blank space or Save without knowing what has been accepted. | Date entry is one continuous, predictable flow with visible committed values and no reliance on tapping an arbitrary blank area. |
| R2-06 | 6 | Important Chinese memberships have incomplete or inaccurate plan and price coverage. | 88VIP, JD PLUS, Sam's Club, and a broader researched membership set contain verified regional plan variants instead of one guessed generic offer. |
| R2-07 | 7 | The catalog omits many current AI, creation, ByteDance, Tencent, and Chinese consumer subscriptions. | A researched expansion covers every named example and a justified broader inventory, with traceable official offers. |
| R2-08 | 8 | Offer currency defaults ignore the service market, forcing Chinese users to change USD to CNY manually. | Selecting a verified offer immediately uses that offer's market currency; the person may still override the actual charge. |
| R2-09 | 9 | The current taxonomy puts AI services such as ChatGPT under Productivity. | AI services use a dedicated, localized AI category or another researched taxonomy that remains understandable and stable. |
| R2-10 | 10 | Regional products such as Canva International and 可画中国版 are conflated despite different plans and prices. | Region-specific products and offers are distinguishable without duplicating or misleading the person. |
| R2-11 | 11 | YouTube Premium is represented by Lite only even though multiple official variants exist. | Verified personal, family, student, Lite, and other supported regional variants are represented when their recurring prices can be proved. |
| R2-12 | 12 | Today/30-day/90-day filters do not provide a comfortable visual understanding of upcoming charges. | Upcoming charges are glanceable by month and day, navigable over time, and connected to the affected subscriptions. |
| R2-13 | 13 | The product has not yet systematically learned from established subscription trackers, open-source implementations, or community experience. | Design choices cite a competitor/community/open-source research matrix and state what is reused, adapted, or rejected. |
| R2-14 | 14 | Segmented controls are visually wrapped in redundant containers, producing nested pills/bars and unnecessary hierarchy. | Segmented controls such as Expected/Confirmed appear with one clear visual boundary and no decorative outer container. |

## Detailed Product Boundaries

### A. Add and Confirm

**Confirmed problems**

- Manual add behaves as an isolated blank form instead of a catalog-assisted
  flow.
- Catalog-backed confirmation still exposes avoidable form friction.
- Optional descriptive metadata blocks creation.
- Date controls do not communicate when a selection is complete.
- Currency defaults do not follow a verified offer's market.

**Suggested directions to evaluate**

- Inline typeahead suggestions below the service-name field.
- Selecting a suggestion converts the form into a catalog-backed confirmation
  while preserving an explicit “continue manually” path.
- A focused date editor with Done/Next, automatic focus progression, or
  immediate commit.
- Market-aware currency defaults sourced from the selected offer.

**Outcome acceptance**

- A known service can be selected without retyping official data.
- A missing service can still be saved manually.
- Empty plan and category never block saving.
- Minimum schedule facts remain required and produce no fake forecasts.
- The person can tell which date is active, which value was committed, and
  what the next action will do.

### B. Subscription Editing and Actions

**Confirmed problems**

- Read-only detail followed by Edit duplicates navigation.
- Original price is not part of ordinary editing.
- The overflow menu exposes Edit, Confirm Charge, Record Price Change, Record
  Cancellation, Archive, and Delete as a second-level command collection.
- Archive and delete already have more discoverable list gestures.

**Suggested directions to evaluate**

- Make the destination reached from a library row an editable subscription
  screen by default.
- Keep archive and permanent delete exclusively in native library swipe
  actions.
- Remove the chevron/overflow menu, or replace it only if research proves that
  a different primary interaction solves the same hierarchy problem better.
- Decide through research whether payment-history and lifecycle facts belong
  in the editable screen, a history surface, or outside the primary 0.2 flow.

**Outcome acceptance**

- Price, currency, billing interval, Start Date, and Next Renewal can be
  changed without navigating through a read-only page and then a modal.
- Saving, cancelling, validation, and unsaved-change behavior are explicit.
- Destructive actions remain deliberate and recoverable where possible.
- The primary screen is not burdened by a catch-all action menu.

### C. Catalog Data, Regions, and Taxonomy

**Confirmed problems**

- The current catalog has 106 services but its selectable official offers are
  concentrated in USD.
- AI is not a first-class category.
- A service record does not yet express every distinction needed for Chinese
  and international variants.
- Static price data can become misleading when region, channel, promotion,
  renewal price, or verification date is missing.

**Required research coverage**

- Alibaba ecosystem, including the actual current 88VIP variants.
- JD PLUS and related JD memberships.
- Sam's Club China membership tiers.
- ByteDance ecosystem, including 豆包、剪映、即梦 and other paid AI/creation
  services discovered during research.
- Tencent ecosystem, including AI products and multi-tier consumer
  subscriptions such as QQ Music.
- Canva International and 可画中国版.
- YouTube Premium variants.
- A broader priority inventory across AI, music, video, productivity,
  creation, cloud, learning, reading, retail, and delivery memberships.

**Outcome acceptance**

- Every selectable offer records service/variant, market, channel, plan,
  recurring price, currency, interval, official source, verification date,
  and confidence/review state.
- Introductory promotions, continuous-subscription discounts, standard
  renewal prices, and one-time prepaid products are not conflated.
- A price without first-party evidence is not selectable as verified.
- Region-specific variants are understandable in search and confirmation.
- Selecting a Chinese offer defaults to CNY; selecting a US ChatGPT offer
  defaults to USD.

### D. Upcoming Calendar and Visual Simplification

**Confirmed problems**

- Range presets expose a list but not the distribution of upcoming charges.
- Nested containers make segmented controls look heavier than their content.

**Suggested directions to evaluate**

- An embedded month calendar with charge indicators and a selected-day agenda.
- A calendar/agenda hybrid rather than a calendar-only replacement.
- Native `UICalendarView`, a SwiftUI wrapper, or a mature accessible
  open-source component.
- Segmented controls placed directly in the page's content hierarchy.

**Outcome acceptance**

- A person can move between months, see which days contain charges, select a
  day, and open the related subscription.
- Empty, dense, and multi-charge days remain legible.
- Dynamic Type, VoiceOver, localization, iPhone, iPad, and macOS behavior are
  addressed.
- Expected/Confirmed and any remaining segmented controls have no redundant
  outer pill or card.

## Cross-Cutting Constraints

- The Subscription Library remains the source of truth; Calendar remains a
  projection.
- Offline catalog use remains supported.
- Official sources establish prices; community sources establish pain points,
  vocabulary, and preference signals.
- Search must support localized names and explicit aliases but must not use
  unsafe fuzzy matching to silently attach the wrong identity.
- Every recommendation must distinguish fact, community evidence, and design
  inference.
- Every proposed primary flow must report its interaction count, information
  available without secondary navigation, and failure-recovery behavior.
- Engineering cost and migration scope must be stated, but neither may veto a
  clearly superior core experience merely because the current architecture
  makes it expensive.
- Research must identify native or reusable mechanisms that can replace
  product-specific code and must explain when a shared data-driven model can
  serve multiple surfaces.
- No feature implementation starts until the research synthesis and product
  design are reviewed.
