# Repository Agent Guide

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the two category labels and five default triage-state labels. See
`docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### Product and evidence

- `docs/product-goal.md` is the current product boundary.
- `CONTEXT.md` defines canonical domain terms and invariants.
- `docs/adr/` records durable technical decisions.
- `docs/evidence-index.md` identifies current source authority and retained
  historical evidence.

## Product execution guardrails

- Before every plan or change, state in one sentence which user step it removes or what direct value it adds.
- Over-design is the first gate: when the existing structure can deliver it, do not add pages, state, abstractions, caches, or explanation layers.
- Follow `docs/product-goal.md`; historical research and completion claims do
  not authorize new product behavior.
- Never turn an unknown catalog fact into a verified fact. Volatile price,
  market, channel, or eligibility claims require current primary-source
  evidence as defined in `docs/evidence-index.md`.
- Keep catalog selections editable and never attach an alias to the wrong
  service identity merely to produce a match.
- Work on one requirement at a time. Do not expand scope opportunistically.
- Do not push without the user's explicit authorization in the current turn.

## Production workflow

`docs/agents/production-flow.md` is binding and owns intake, issue routing,
implementation, review, commit, and remote-verification procedure.
`docs/agents/issue-tracker.md` owns GitHub task authority and authorization
boundaries.
