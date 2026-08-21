# Production Flow

This is the binding engineering workflow for repository work. The smallest
unit is one confirmed root cause. Product guardrails in `AGENTS.md`, the domain
language in `CONTEXT.md`, and applicable ADRs remain authoritative.

## 1. Intake and triage

Use `/triage` for an incoming bug report or automated-review finding.

1. Read the complete finding, its thread, the current source, and relevant
   domain documentation.
2. Decide whether it is reproducible and current before proposing a change.
3. Group comments that describe the same root cause. Create one GitHub issue
   and link every duplicate source comment to it.
4. Give the issue exactly one triage category and one triage state using
   `docs/agents/triage-labels.md`.
5. When it is ready, publish a durable Agent Brief with current behavior,
   desired behavior, key interfaces, testable acceptance criteria, and explicit
   out-of-scope items.

If the root cause is uncertain, use `/diagnosing-bugs` before implementation.
Do not turn a hypothesis into an implementation ticket.

The issue is the sole mutable task record. Repository documentation holds
stable policy; it does not duplicate issue-by-issue progress.

For a purely technical finding already inside a user-approved task boundary,
the standing delegation in `docs/agents/issue-tracker.md` satisfies the
maintainer-direction pause after the triage recommendation. Product/UX choices,
scope changes, conflicting labels, and unusual overrides still stop for the
user.

## 2. Route the work

- A confirmed, bounded bug or small change goes to `/implement` using its Agent
  Brief as the spec.
- A multi-session feature that the user has explicitly placed in scope uses
  `/grill-with-docs` -> `/to-spec` -> `/to-tickets`, then one `/implement` run
  per approved vertical-slice ticket.
- Use `/domain-modeling` only when the work introduces or changes durable domain
  vocabulary or boundaries.

Automated-review remediation does not authorize feature work, a broad audit, or
historical re-review. The current root-cause issue is the complete work boundary.

For an explicitly approved multi-session feature, the `/to-spec` parent issue
is the stable specification and each `/to-tickets` child is its own mutable
implementation record. That hierarchy is not an automated-remediation umbrella
or a parallel progress ledger.

## 3. Ownership and implementation

One Codex context owns one root-cause issue from diagnosis through
`remote_verified` and issue closure, including any corrections required by
review. Do not hand continuous work on that root cause to a replacement
context. A different root cause may start in a fresh context.

Before changing code, the owner records:

- the issue and user value;
- the pinned starting commit;
- the acceptance criteria and exclusions;
- the allowed change surface;
- the existing public testing seam, when one is suitable;
- the required verification and authorized side effects.

Use `/tdd` where the behavior has a suitable public seam:

1. demonstrate a genuine failing behavior at that seam;
2. make the smallest production change that passes it;
3. repeat only for another acceptance criterion.

Tests describe observable behavior and use independent expected values. Mock
only system boundaries. Do not add unrelated coverage, UI tests, speculative
abstractions, or a new test harness merely to increase confidence. If no
reliable automated seam exists, record why and use the narrowest existing
verification that proves the acceptance criterion.

Technical implementation and seam choices come from the product goals, current
source, `CONTEXT.md`, and ADRs. Escalate only a product/UX choice, a material
scope change, or missing authority to the user.

## 4. Local verification and review

Run the focused test or check during each implementation slice. Run the
repository's existing complete test suite once at the end when it is available
and relevant; do not create an additional suite or audit lane.

The repository release verifier also enforces mechanically reviewable source
policy: structured inputs and entitlements must parse, every English and
Simplified Chinese string-catalog leaf must be translated and non-empty, Swift
production and test code must not use `try!`, and repository UTF-8 input must
not be accepted through lossy `String(decoding:)` conversion. The verifier
conservatively rejects executable calls carrying the `decoding:as:` argument
signature, including qualified, explicit-initializer, contextual, and aliased
spellings, as well as compound references to `init(decoding:as:)`. Use explicit
error propagation and failable UTF-8 decoding instead. The verifier also uses
the compiler's syntax tree to require the macOS command set to be installed on
the app scene and to replace, rather than append after, the default New Window
command. This structural policy belongs in the release verifier instead of an
XCTest that opens repository source files at runtime.

Before committing, run the two axes defined by `/code-review` against the
complete candidate diff from the pinned starting commit. The repository's
commit-after-verification policy requires this pre-commit adapter instead of
the skill's `git diff <fixed-point>...HEAD` command:

1. Resolve the fixed point and record `git log <fixed-point>..HEAD --oneline`.
2. Use `git status --short` as the complete candidate-file manifest.
3. Supply `git diff --binary <fixed-point> -- <in-scope-paths>` for tracked
   files and `git diff --no-index /dev/null <path>` for every in-scope untracked
   file.
4. Both read-only reviewers reject an omitted in-scope manifest entry before
   reviewing content.

Then apply the two review axes:

- **Standards** checks documented repository standards and the skill's smell
  baseline.
- **Spec** checks the diff against the root-cause issue's Agent Brief, including
  missing behavior and scope creep.

These are exactly two bounded, read-only review contexts. The owner aggregates
their reports, decides each finding against evidence, and makes any required
correction in the original context.

Mark `artifact_verified` only when:

- every acceptance criterion is satisfied;
- focused verification passes;
- the applicable existing complete suite passes, or any unavailable check is
  reported precisely;
- both review axes have no unresolved actionable finding;
- the diff contains no unrelated work.

After `artifact_verified`, the owner may create one scoped local commit. Do not
include pre-existing or unrelated working-tree changes.

## 5. Remote verification

A push, PR creation or update, merge, or bot-summoning comment requires the
user's explicit authorization in the current turn.

After an authorized push, review only the current remote HEAD. Let every
available configured bot report, then classify every individual finding that
is applicable to that HEAD, including a finding from an older comment that is
still confirmed current, as:

- the same root cause;
- a distinct new root cause;
- a duplicate;
- invalid, stale, or already fixed.

The same-root-cause finding returns to the original owner. A distinct valid
root cause receives a separate issue and does not expand the current issue.
Unavailable bots or exhausted quota are reported as unavailable and are never
represented as a pass.

Mark `remote_verified` and close the root-cause issue only when the authorized
remote HEAD is known, all available bot reports for that HEAD have completed,
and every finding applicable to that HEAD has been classified. Record the
commit, checks, bot availability, classification links, and any remaining
external limitation in the closing comment.

## 6. PR #50 transition

Apply this workflow immediately to PR #50. Use only findings confirmed against
its current HEAD. Collapse duplicate bot comments onto their root-cause issues.
Do not re-audit the full development history, revive stale comments, or create
an umbrella tracking issue; PR #50 is the shared index.

## 7. Superseded execution instructions

Earlier plans may remain as historical product or acceptance records. Any
earlier instruction that mandates Luna routing, a different reviewer topology,
or `.superpowers/sdd/progress.md` is superseded by `AGENTS.md` and this flow and
must not be executed.
