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

## Bug-fix execution protocol

- The main task owns the boundary, Luna level, status, and final conclusion; implementation and acceptance are separate jobs.
- Default to the smallest two-task loop: one implementation Luna plus one independent read-only Luna Medium reviewer. Return to the original implementer only for a real reproducible finding; the same Medium reviewer rechecks that finding after the fix. Do not add a third reviewer.
- Use only `gpt-5.6-luna`: narrow logic or documentation uses Medium or High; cross-Workspace/adapter/persistence uses High or XHigh; SwiftData/CloudKit/schema uses XHigh; Max is only for high-risk architecture review or one XHigh fix that still has a real cross-layer finding.
- Every implementation prompt must state: goal/user value, starting SHA, allowed files, prohibitions, failure invariants, skills, RED → GREEN order, focused plus batch regression, completion evidence, and remote side effects.
- Hard implementation gate: obtain a real RED on the failure path first. A test added afterward must be labeled regression, not called RED. Fakes/mocks must model physical side effects, transaction failures, retry/idempotency, and applicable system semantics; they must not copy the production algorithm to prove itself.
- Acceptance output is only `APPROVE` or `FINDINGS`. A finding must include reproduction, impact, minimal fix, and a permanent regression test.
- Do not add UI tests, a full audit, Max, or another reviewer merely because of confidence; verify only the current batch brief.
- Update the single canonical `progress.md` immediately after each batch conclusion.
