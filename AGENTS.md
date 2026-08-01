# Repository Agent Guide

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

## Product execution guardrails

- Before every plan or change, state in one sentence which user step it removes or what direct value it adds.
- Over-design is the first gate: when the existing structure can deliver it, do not add pages, state, abstractions, caches, or explanation layers.
- Every catalog preset must have at least one real, public, fixed-price offer. Do not ship shells, guessed prices, or placeholders; delete services with no real fixed subscription.
- Do not model discount eligibility or promotional conditions. Presets are one-click selections that remain editable.
- Mark each item complete only after checking all 14 points in `docs/research/2026-07-30-round-2-requirements.md` and providing code, test, and UI evidence.
- Work on one requirement at a time. Do not expand scope opportunistically.
- Do not push without the user's explicit authorization in the current turn.
