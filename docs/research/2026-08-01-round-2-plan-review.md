# Round 2 Batch A Plan Review

**Date:** 2026-08-01
**Plan:** `docs/superpowers/plans/2026-08-01-direct-editor-atomic-edit.md`
**Verdict:** APPROVE for Batch A implementation
**Catalog evidence verdict:** REVISE-open; no provisional offer import

## Review Scope

The review cross-checked the Batch A plan against:

- `docs/research/2026-07-30-round-2-requirements.md`;
- `docs/research/2026-08-01-round-2-synthesis.md`;
- `docs/research/2026-08-01-round-2-manifest-validation.md`;
- the current SubscriptionCore, SwiftUI navigation/editor surfaces, Xcode
  project membership, shared scheme, unit tests, and UI test target.

## Independent Gates

| Gate | Result | Resolution evidence |
| --- | --- | --- |
| Editor/draft/session contract | APPROVE after revision | Draft now owns exact editable state and conversion APIs; the session owns one baseline and pending exit; Active/Trial/Cancelled date behavior and Save failure are explicit. |
| Xcode/test executability | APPROVE after revision | Every new Swift file has an explicit PBX target rule; simulator preflight replaces stale UUID assumptions; every focused UI method and artifact path is named. |
| Confirm Charge safety | APPROVE after revision | Batch A retains the Payment History fallback until Batch B proves the two-month-old month-range tracer, duplicate suppression, replacement, future hiding, and failure behavior. |
| Catalog shipping safety | APPROVE for non-importing Batch A | Bundled catalog hash is frozen; the 84 OFF/OGD and 52 second-community records remain provisional; selectable-price import still requires normalized facts and independent PASS. |
| Final whole-plan executability | APPROVE | Tasks 1–8 have finite call-site inventories, available domain seams, explicit ownership, regression commands, manual surface gates, and physical-device acceptance. |

## Baseline Evidence

- Normalized first-pass manifest: 187 records, 187 unique evidence IDs, zero
  excerpt-hash failures.
- `git diff --check`: PASS for the reviewed documents.
- SubscriptionCore baseline: 156 Swift Testing cases in 11 suites passed.
  The first restricted-shell attempt was invalid because the host blocked the
  Swift macro plugin process; the same baseline command passed outside that
  restriction with isolated writable caches. This was an environment failure,
  not a product failure.
- No product source file had been changed when this approval was recorded.

## Implementation Boundary

Implementation may proceed with Batch A only: effective amount, atomic ordinary
edit, shared draft/sections, explicit date completion, direct editor, semantic
action relocation, dirty navigation, accessibility parity, regression, local
commit, and device acceptance.

R2-04, R2-06–R2-11, and R2-12 retain their synthesis batch/evidence gates.
Research breadth does not authorize guessed prices. Requirements or evidence
must not be weakened to make an implementation pass.
