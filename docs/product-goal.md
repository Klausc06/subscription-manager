# Product Goal

Subscription Manager helps a person understand what they pay for, when the
next charge is expected, and safely maintain that record across iPhone, iPad,
and Mac. The Subscription Library is authoritative; external services and
system surfaces are supporting interfaces or projections, not competing
sources of truth.

## Near-term outcome

- Keep add, review, and edit flows direct. A person can start from a catalog
  match or manual entry; service name, positive amount, CNY/USD/EUR currency,
  and a valid Fixed Billing Schedule with its Start Date and Confirmed Next
  Renewal are the minimum facts. Plan and category are optional.
- Keep the main library entry to its current settings, title, and add structure.
  The add action owns the choice between catalog-assisted and manual entry;
  current source owns exact placement and labels.
- Present one concise subscription summary and edit it in the same presentation
  instead of creating a second read-only detail layer. Ordinary editing does
  not ask the person to choose an “Active” state.
- Make renewal dates predictable with the app's Gregorian billing calendar and
  readable month/day upcoming views. There is no alternate or user-selectable
  calendar system.
- Preserve deliberate lifecycle actions: pin, archive, restore, record a
  cancellation, reactivate, and confirm destructive deletion. Unsaved or
  destructive changes must never happen implicitly.
- Keep the catalog trustworthy. A market-specific offer keeps its own currency
  and remains editable; unknown prices or eligibility stay unknown. AI remains
  a stable localized category, and regional variants remain distinguishable.
  Aliases must never silently attach a selection to the wrong service identity.
- Keep confirmations concise and provider/evidence URLs internal to catalog
  provenance rather than adding them to ordinary user-facing forms.
- Prefer native controls, stable system shapes, and system/light/dark
  appearance. Do not introduce redundant containers, custom card systems, or
  fixed visual measurements that are not required by current source or an
  approved issue.

## Current engineering priority

Stabilize the implemented product and resolve approved, reproducible defects.
New capability work requires its own product decision and issue; historical
research, a candidate list, or a previous completion claim is not authorization
to implement it.

## Frozen and out of scope

- Future iCloud behavior is frozen. Preserve the current private CloudKit
  implementation, but do not expand synchronization features under a
  stabilization or review-remediation issue.
- Alternate calendar systems and a user-facing calendar-system selector are
  out of scope.
- Guessed prices, inferred promotions, and unverified “standard” offers are out
  of scope. Dynamic facts follow [Evidence Index](evidence-index.md).
- Provider-side cancellation automation is out of scope. A Recorded
  Cancellation remains a local fact, as defined in [`CONTEXT.md`](../CONTEXT.md).
