# TB-08 China Catalog Batch A Design

- Date: 2026-07-29
- Issue: #9 — Add China catalog batch A: media, music, reading, and games
- Status: Approved for autonomous implementation

## Decision

Add 47 China-focused presets to the versioned bundled catalog: 10 video,
10 music, 9 reading, 9 news, and 9 gaming. Existing presets remain intact;
the bundled snapshot advances from catalog version 1 to 2 so the snapshot
identity correctly reflects the new reviewed data.

Each entry has a stable ASCII identifier, English and Simplified Chinese
labels, one of the existing localized categories, a monthly cycle suggestion,
and an official provider account, membership, or support URL. A suggested
interval is only a form convenience; the catalog makes no price or current
offer claim.

## Artwork and provenance

The batch deliberately does not redistribute provider logos or other official
artwork. Every entry uses an existing, neutral app symbol (`video`, `music`,
`reading`, `news`, or `game`), records `originalSymbol` / `CC0-1.0`, and
names its own stable identifier as the provenance source. This preserves the
strict TB-07 catalog validation invariant and keeps the data safe to ship.

The accompanying provenance report records the source URL and neutral-asset
decision for every row. The URL is a navigational management/help endpoint,
not an assertion that a particular plan, price, or payment method is current.

## Verification

- Core catalog tests assert the 47 reviewed stable IDs, all five localized
  categories, and representative English and Simplified Chinese search.
- The validator must accept the final resource document.
- App repository tests continue to load the bundle, and the existing browse
  and confirmation UI path remains usable for representative entries.
- The report is reviewed alongside the JSON; every row has a provenance
  record and no row references external artwork.
