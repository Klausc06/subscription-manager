# Privacy-safe widgets design

**Status:** Approved implementation direction from the accepted product
specification and the user's standing instruction to complete non-interactive
work autonomously.

## Goal

Provide glanceable subscription-renewal widgets without network work or
financial disclosure on protected surfaces.

## Design

The app writes a compact, versioned widget snapshot to its App Group only after
the existing workspace has loaded local subscriptions. The snapshot contains a
stable subscription UUID, localized service name, renewal date, an optional
already-computed display amount, source freshness state, and no CloudKit,
Calendar, or account identifier. WidgetKit reads that immutable local snapshot;
it never invokes the exchange-rate source, CloudKit, or the subscription
repository directly.

`WidgetTimelineProvider` maps the snapshot to populated, empty, and stale
entries. Timelines refresh at the next local midnight and have a bounded
fallback refresh. A privacy-aware presentation model removes amount text when
`redacted` or in the accessory families. Widget URLs use stable app deep links:
`subscription-manager://subscription/<UUID>` for a represented renewal and
`subscription-manager://insights` for forecast summary.

The WidgetKit extension supports accessory rectangular, system small, and
system medium. Small shows the next service and date; rectangular emphasizes
the imminent renewal; medium adds a concise forecast only when privacy permits
it. Empty and stale states are textual, localized, and accessible. The app
exposes each view's accessibility label from the same presentation model.

## Verification

- Unit tests cover snapshot decoding, empty/stale/populated timelines, all
  supported families, redaction, URLs, and next-refresh calculation.
- Widget previews cover populated, empty, and stale entries for each family.
- Simulator smoke tests render the extension and confirm the app writes a
  snapshot after normal workspace loading.
