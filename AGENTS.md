# Subscription Manager

Tracks personal subscriptions. The subscription library is authoritative; Calendar is a projection of that library.

## Reads

- Product requirements → `docs/superpowers/specs/2026-08-11-authoritative-product-requirements.md`
- Product boundary (supporting) → `docs/product-goal.md`
- Domain terms → `CONTEXT.md` when editing domain behavior
- Architecture → matching file in `docs/adr/` when changing structure
- Evidence → `docs/evidence-index.md` for catalog, price, market, channel, or eligibility claims
- Ship flow → `docs/agents/production-flow.md` (Superpowers: brainstorm → plan → TDD → verify)

## Commands

- Core behavior: `swift test --package-path Packages/SubscriptionCore`
- App / UI / adapters:
  ```sh
  xcodebuild \
    -project SubscriptionManager.xcodeproj \
    -scheme SubscriptionManager \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
    test
  ```

## Work

- Workflow is Superpowers end to end. Do not use Matt as the primary router.
- Choose the simplest complete solution that best achieves the approved product outcome (Expo UI + native modules allowed when it serves the requirements).
- One requirement at a time. Do not cut required capabilities to simplify the stack.
- Treat catalog facts as verified only with current primary-source evidence.
- Keep catalog selections editable; route UI to persistence and EventKit through `SubscriptionWorkspace`.
- Ask before push.

## Verification (before done)

Report each item with evidence, or mark it open:

1. Requirement / issue under change identified
2. Matching tests run (`SubscriptionCore` and/or app suite as appropriate) with output cited
3. Catalog or schedule claims tied to current evidence rules when touched
4. Touched paths listed; push only after explicit approval

## Agent skills

- Issue tracker → `docs/agents/issue-tracker.md`
- Triage labels → `docs/agents/triage-labels.md`
- Domain docs → `docs/agents/domain.md`
