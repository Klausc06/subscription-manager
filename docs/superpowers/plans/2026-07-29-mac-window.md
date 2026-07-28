# TB-15 Native Mac Window Implementation Plan

**Goal:** Provide a productive, native macOS subscription window while sharing the existing workspace behavior with iPhone and iPad.

**Architecture:** Add a macOS-only root and command set at the application boundary. Keep filtering/sorting as a pure projection of `SubscriptionWorkspace.libraryState`; route all mutations through existing workspace APIs and sheets.

## Tasks

### Task 1: Define the query projection

- [ ] Write a failing workspace-facing test for scope, text search, and stable table sorting.
- [ ] Add a small `MacLibraryQuery` projection with `service`, `plan`, `category`, `next renewal`, and `amount` sort keys.
- [ ] Verify `swift test --package-path Packages/SubscriptionCore` and commit `feat(core): query subscriptions for Mac table`.

### Task 2: Build the Mac window

- [ ] Write a failing macOS UI/command test for table selection and Add routing.
- [ ] Add `MacLibraryView` with sidebar, `Table`, inspector, empty/multi-selection state, search, and toolbar.
- [ ] Use `#if os(macOS)` in `SubscriptionManagerApp` so mobile roots remain unchanged.
- [ ] Build and test the macOS destination, then commit `feat(mac): add native subscription window`.

### Task 3: Add commands and accessibility

- [ ] Write failing command-routing and keyboard shortcut tests.
- [ ] Add application menus for Add, Edit, Search, Archive, Export placeholder, Settings, and standard window actions; localize new copy.
- [ ] Run keyboard and VoiceOver smoke scenarios in English and Simplified Chinese, then commit `feat(mac): add workspace command menus`.

### Task 4: Verify and deliver

- [ ] Run core, iPhone, iPad, and macOS focused regressions; record exact results.
- [ ] Push `feat/tb-15-mac-window` and create a PR based on `feat/tb-14-insights`; do not merge without explicit authorization.
