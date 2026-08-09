# Repository Agent Guide

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the two category labels and five default triage-state labels. See
`docs/agents/triage-labels.md`.

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

## Production workflow

Follow `docs/agents/production-flow.md`. It is binding immediately, including
for the recovery of PR #50.

- One confirmed root cause is one GitHub issue. Link duplicate bot comments to
  that issue instead of creating another work item.
- The GitHub issue is the only mutable task record. Do not create a parallel
  `progress.md` or ledger. Automated-review remediation does not use an
  umbrella issue.
- One Codex context owns a root-cause issue continuously through diagnosis,
  implementation, review findings, `remote_verified`, and issue closure.
  Different root causes may use different Codex contexts.
- Route incoming findings through `/triage`; use `/diagnosing-bugs` when the
  cause is not established; use `/implement` for an approved agent brief.
  `/implement` uses `/tdd` where a suitable seam exists and ends with the
  Standards and Spec axes from `/code-review` against a pinned fixed point.
- The two `/code-review` axes (Standards and Spec) are bounded, read-only review
  contexts. They do not replace the owning implementation context or modify
  code.
- Do not add adjacent features, unrelated tests, UI tests, broad audits, or new
  verification lanes. Resolve only the current issue's acceptance criteria.
- Codex may manage root-cause issues and make a scoped local commit after
  `artifact_verified`. A push, PR creation or update, merge, or comment that
  summons an external bot requires the user's explicit authorization in the
  current turn.
- Ask the user only about product/UX choices or missing authority. Resolve
  technical choices from the product goals, domain docs, ADRs, and current
  source, and record the evidence.
