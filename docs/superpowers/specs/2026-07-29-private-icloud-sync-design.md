# TB-16 Private iCloud Sync Design

- Date: 2026-07-29
- Issue: #17 — Synchronize the private library with visible iCloud status
- Status: Approved for autonomous implementation

## Decision

Use SwiftData's managed CloudKit synchronization with one explicitly named
private container, `iCloud.com.klausc06.SubscriptionManager`. The production
`ModelConfiguration` opts into `.private(containerID)`; in-memory and named
UI-test stores explicitly remain `.none`. Add the iCloud and remote-notification
entitlements required by SwiftData, but introduce neither a public database nor
any custom account or backend.

The application keeps `SubscriptionWorkspace` as its only data command/query
seam. A narrow injected `LibrarySyncMonitor` reports iCloud account availability
and local synchronization progress to the workspace. The production monitor
uses `CKContainer.accountStatus()` and refreshes on `CKAccountChanged`; tests
use a deterministic fake. It never queries subscription records from CloudKit
or changes the local store, so a device stays fully usable offline or signed
out.

## Sync state and merge semantics

`LibrarySyncStatus` has five user-visible states:

- `localOnly`: account unavailable or sync intentionally disabled; local edits
  still save and will be eligible when iCloud returns.
- `synchronizing`: local data is saved and the private iCloud account is
  available, but the app has pending local changes or observed remote activity.
- `current`: account is available and no local pending activity remains. This
  is an availability/progress signal, not a false promise of instantaneous
  server acknowledgement.
- `signedOut`: no usable iCloud account is present; no login prompt is shown.
- `requiresAttention`: the account-status probe failed; the local library and
  all edits remain available, with a retry action.

Every workspace mutation marks a currently available account as synchronizing
only after its local repository operation succeeds. Signed-out, local-only,
and attention states remain visible after a local edit. A monitor refresh turns
an available account current; a remote model observation also refreshes
workspace views without duplicating records. No operation waits for CloudKit
before returning a successful local edit.

Records retain application-generated `UUID` identifiers. Scalar subscription
and preferences fields use CloudKit's normal last-writer-wins behavior. The
existing encoded confirmed-payment and price-change arrays remain append-only
at the workspace boundary and deduplicate by their stable occurrence/effective
identity before persistence; a concurrent scalar edit never synthesizes a new
subscription. Permanent deletion is represented by deleting the same stable
record and is included in the two-device convergence matrix.

## Presentation, privacy, and delivery prerequisite

A compact status row is shown in Settings and in the library toolbar context,
with localized English and Simplified Chinese labels, an icon plus text, and a
VoiceOver value. It has no Calendar permission behavior and does not reveal
account identity, CloudKit record IDs, or financial data.

Apple requires an active Developer Program account with admin access to create
and enable the CloudKit container and remote-notifications capability. The
repository can encode the required entitlement/configuration and run local
tests without that account, but real two-device convergence must be performed
after those capabilities are provisioned. The matrix documents offline create,
concurrent scalar edit, append history, deletion, reconnect, signed-out, and
account-change cases on two physical devices or simulators signed into the
same Apple ID.

## Verification

- Workspace tests drive an injected monitor through every status and prove that
  mutations remain local-first.
- Persistence tests confirm the production configuration requests the named
  private container while UI-test stores request none.
- App tests assert status copy/accessibility routing without CloudKit network
  access.
- Build iPhone, iPad, and macOS targets; run the core suite and publish the
  two-device matrix with its exact account/container prerequisites.
