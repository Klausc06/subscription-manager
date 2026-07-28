# TB-15 Native Mac Window Design

- Date: 2026-07-29
- Issue: #16 — Work productively in the native Mac window
- Status: Approved for autonomous implementation

## Decision

Keep `SubscriptionWorkspace` as the only command/query seam. On macOS, replace
the phone-oriented root with a three-region `NavigationSplitView`: library
scope/filter sidebar, sortable/searchable subscription table, and detail
inspector. iPhone and iPad retain their existing root view.

`MacLibraryView` owns only selection, column sort descriptors, search text,
and sheet presentation. It derives visible records from workspace-loaded
library content, then routes Add, Edit, Archive, Settings, and window actions
to existing views or workspace commands. The App scene supplies matching
`Commands` menus and customary keyboard shortcuts; no menu bypasses the
workspace.

## Behavior and accessibility

- The table has service, plan, category, next renewal, and amount columns;
  its empty, single-selection, and multi-selection states remain explicit.
- Search and scope filters apply before sorting and preserve stable IDs.
- Toolbar actions have an equivalent app/menu location. Disabled actions stay
  discoverable when selection is absent or multiple rows are selected.
- VoiceOver labels name sort state and selection count. Standard SwiftUI
  `Table`, `NavigationSplitView`, commands, and focus behavior provide
  keyboard operation and Dynamic Type adaptation.
- Closing a window performs no lifecycle or persistence mutation; ordinary
  process termination remains the platform default.

## Verification

- Workspace-facing tests prove table query filtering/sorting and command
  routing without view hierarchy assertions.
- macOS build plus keyboard/VoiceOver smoke tests cover English and
  Simplified Chinese; iPhone/iPad regressions remain green.
