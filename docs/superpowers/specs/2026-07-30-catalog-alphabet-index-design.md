# Catalog Alphabet Index Design

Date: 2026-07-30

## Goal

Add a compact, Contacts-style alphabet index to the trailing edge of the
catalog so people can move quickly through the expanded bundled catalog.

## Scope

The index appears only when the catalog contains presets and the search query
is empty. It reflects the current category filter, so it never offers a letter
that has no visible destination. Existing catalog loading, search, category
selection, preset detail, confirmation, and diagnostics behavior remain
unchanged.

The index supports both tapping a letter and dragging vertically across
letters. Selecting a letter scrolls the first matching catalog section into
view and briefly highlights the active index letter.

## Ordering and Localization

Visible presets are grouped and sorted by the localized service name.

- Latin names use their first letter.
- Simplified Chinese names use the first letter of their Mandarin
  transliteration, so `百度网盘` appears under `B`.
- Names beginning with a digit, symbol, or unsupported character appear under
  `#`.
- Comparisons use the current locale and are case-insensitive.

Only letters represented by visible presets are shown. The index follows the
conventional `A–Z` order with `#` last.

## SwiftUI Structure

`CatalogBrowserView` keeps the existing `List` and places it in a `ZStack`
with a trailing `CatalogAlphabetIndex`. A `ScrollViewReader` provides stable
section anchors without introducing a UIKit bridge.

A small, independently testable catalog-index projection converts visible
presets into ordered sections:

- section identifier;
- localized display title;
- ordered presets.

The `List` renders one section per projected letter and assigns the letter as
the section anchor. The category control remains above these sections and the
diagnostics section remains below them.

`CatalogAlphabetIndex` receives only the represented letters and a selection
callback. Its drag gesture maps the vertical pointer position to a clamped
letter index, avoids repeatedly scrolling to the same letter, and provides
light selection feedback. Taps use the same callback.

## Accessibility and Input

Each letter is exposed as a button with a localized label such as
`Jump to B`. The index remains usable with VoiceOver and pointer input; the
drag gesture is an enhancement rather than the only interaction.

The touch target spans the full index width even though the visible letters
remain compact. Dynamic Type does not enlarge the index enough to cover the
catalog rows; accessibility text sizes retain the tappable buttons and allow
the list itself to remain the primary reading surface.

The index is hidden while search is active because search results are already
narrowed and alphabetical jumps would compete with the search task.

## Error and Edge Behavior

- Empty catalog results show the existing empty state and no index.
- A category with only one represented letter still shows that letter.
- Changing locale, category, search text, or catalog snapshot rebuilds the
  projection from the current visible presets.
- If a previously selected letter disappears, the highlight clears.
- Gesture positions above or below the index clamp to the first or last letter.

## Verification

Unit tests cover Latin initials, Simplified Chinese transliteration, numeric
and symbol fallback, locale-aware sorting, and represented-letter filtering.

Focused UI tests cover:

- the index appearing for the normal catalog;
- tapping a letter to reveal the matching section and preset;
- dragging across the index to another represented letter;
- hiding the index during search;
- rebuilding the available letters after category filtering.

The focused catalog tests, focused UI scenarios, full SubscriptionCore suite,
catalog validator, JSON validation, and iPhone simulator build must pass.
After the local commit, the build is installed on the already registered
physical iPhone and launched for a smoke check. No remote push occurs.
