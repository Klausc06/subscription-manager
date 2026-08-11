# Production Flow

Binding engineering workflow for this repository. Product requirements live in
`docs/superpowers/specs/2026-08-11-authoritative-product-requirements.md`.
Domain language in `CONTEXT.md` and applicable ADRs remain authoritative for
domain vocabulary and structural boundaries.

This repository uses **Superpowers** end to end. Do not run Matt as the
primary workflow router.

## 1. Spec and plan

For new product or multi-step work:

1. `brainstorming` — refine intent, present design, get approval, write the
   design under `docs/superpowers/specs/`.
2. `writing-plans` — produce a bite-sized plan under
   `docs/superpowers/plans/`.
3. Implement only from an approved plan (or from a bounded bug brief when the
   change is already inside approved requirements).

For an incoming bug or review finding:

1. Reproduce against current source before proposing a change.
2. Group findings that share one root cause.
3. Record one issue (or one plan task) with current behavior, desired
   behavior, acceptance criteria, and out-of-scope items.
4. Use systematic debugging when the root cause is uncertain. Do not turn a
   hypothesis into implementation work.

## 2. Implementation

Use `test-driven-development` (or the local TDD equivalent) where a public
seam exists:

1. demonstrate a genuine failing behavior at that seam;
2. make the smallest production change that passes it;
3. repeat only for another acceptance criterion.

Rules:

- One requirement or root cause at a time.
- Prefer the simplest complete solution that meets the approved product
  outcome.
- Route UI through the workspace seam; do not connect UI directly to
  persistence or EventKit.
- Treat catalog facts as verified only with current primary-source evidence.
- Mock only system boundaries. Do not add unrelated coverage or speculative
  abstractions.
- Do not cut required capabilities from
  `2026-08-11-authoritative-product-requirements.md` to simplify a stack
  choice.

## 3. Verification before completion

Use `verification-before-completion` before claiming done:

1. Requirement or issue under change identified.
2. Matching focused tests run; cite output.
3. Applicable existing suite run when relevant; unavailable checks reported
   precisely.
4. Catalog or schedule claims tied to evidence rules when touched.
5. Touched paths listed.

Also enforce repository mechanical policy via the existing release verifier
(structured inputs, string catalogs, no `try!`, no lossy UTF-8 decoding, macOS
command-set policy). Prefer existing seams over inventing a new audit lane.

## 4. Review

Before commit, run two read-only review axes against the complete candidate
diff from the pinned starting commit:

1. Resolve the fixed point and record
   `git log <fixed-point>..HEAD --oneline`.
2. Use `git status --short` as the complete candidate-file manifest.
3. Supply binary diffs for tracked in-scope paths and `/dev/null` diffs for
   in-scope untracked files.
4. **Standards** — documented repository standards and smell baseline.
5. **Spec** — diff against the approved requirements / plan / bug brief;
   reject missing behavior and scope creep.

Mark local work ready to commit only when acceptance criteria pass, focused
verification passes, both review axes have no unresolved actionable finding,
and the diff contains no unrelated work.

## 5. Remote actions

A push, PR create/update, merge, or bot-summoning comment requires the user's
explicit authorization in the current turn (`AGENTS.md`: ask before push).

After an authorized push, classify every applicable bot finding on the current
remote HEAD as same root cause, distinct new root cause, duplicate, or
invalid/stale/fixed. Same-root-cause returns to the original owner. Distinct
valid findings get separate work items and do not expand the current one.

## 6. Superseded instructions

Earlier Matt-primary handoffs, ask-matt-only routing, and any instruction that
treats private CloudKit sync as permanently out of product scope are
superseded by:

- `docs/superpowers/specs/2026-08-11-authoritative-product-requirements.md`
- this Superpowers production flow
- `AGENTS.md`

Historical Superpowers plans and specs remain useful product/acceptance
records. Do not revive Luna routing or a parallel progress ledger as a second
source of truth.
