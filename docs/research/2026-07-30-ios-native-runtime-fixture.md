# iOS Native Calendar and Date Picker Runtime Fixture

**Experiment date:** 2026-07-31

**Status:** Completed local runtime QA; design evidence only

**Product changes:** None

**External evidence manifest:** None — this is a local experiment, not an external source

## Outcome

The fixture closes the three runtime questions left open by the Apple-platform
interaction research.

| Question | Runtime verdict | Design consequence |
| --- | --- | --- |
| Can a decorated, selected `UICalendarView` stand alone for VoiceOver? | **FAIL as a complete Upcoming surface.** Date cells are useful accessibility buttons and a custom decoration can contribute a count, but the decoration does not communicate the underlying subscriptions, the selected state was not present in the exported label/value, and the default dot is only described generically. | Keep the native month as a compact overview, but pair it with a selected-day agenda or equivalent stable summary. Do not encode essential meaning only in a decoration. |
| Does the native month tolerate accessibility Dynamic Type and narrow/split widths without an adaptive host? | **FAIL at the tested 280 pt width and with a fixed-height host at AX XXXL.** The native grid preserved its semantic date buttons, but the visual calendar exceeded the narrow frame. At AX XXXL, surrounding controls expanded and collided with the calendar header while later content moved below the fold. | Give the calendar an empirically tested minimum width, measure its native size, and use an agenda/list fallback below that width. At accessibility sizes, reflow surrounding controls and keep details out of day cells. |
| Does compact `DatePicker` provide the completion behavior the reported form needs? | **FAIL.** Selecting a day changed the binding immediately but left the popover open. Tapping outside dismissed it; there was no Done/Next control and outside dismissal was not a commit boundary. | Put the native picker inside a focused date task with explicit Next/Done and editor-local draft state. Form Save remains the persistence boundary. |

The runtime experiment therefore supports the proposed native
month-plus-agenda renderer and focused date editor, but it adds two hard
constraints: the agenda is required for meaning/accessibility, and the native
calendar needs an adaptive width/height host rather than a fixed narrow frame.

## Environment

| Item | Value |
| --- | --- |
| Repository revision during experiment | `28ebd05b0cf2` |
| Xcode | 27.0 (`27A5194q`) |
| Swift | Apple Swift 6.4 |
| Simulator | `SubscriptionManager-ReleaseGate-iOS27` |
| Runtime | iOS 27.0 |
| Explicit UDID | `899074E5-AB10-4AB3-AFD6-90571DB0C617` |
| Preview host bundle | `dev.swiftui-preview-browser.host` |
| Initial/final system content size | `large` |
| Accessibility content size tested | `accessibility-extra-extra-extra-large` |

`session_show_defaults` was called before the first simulator operation. The
subagent session initially had no simulator default, so it was then pinned to
the UDID above instead of inheriting or guessing another task's simulator.

## Disposable Fixture

The experiment lives outside the repository:

- Package: `/tmp/ios-native-runtime-fixture/Package.swift`
- Source:
  `/tmp/ios-native-runtime-fixture/Sources/IOSNativeRuntimeFixture/NativeRuntimeFixtureView.swift`
- Source length: 246 lines
- `Package.swift` SHA-256:
  `61450adc38322b3fa55969517eb64177ba6ef2568693fe1361ab2909728ee9f7`
- Fixture source SHA-256:
  `cf39e199e05975b8358e79fe575985e08102241edcf59513220abe395d369e7f`

The calendar fixture used:

- `UICalendarView` through `UIViewRepresentable`;
- Gregorian calendar, `zh_CN` locale, and `Asia/Shanghai` time zone;
- visible month August 2026;
- `UICalendarSelectionSingleDate`, initially selecting 2026-08-08;
- a custom 16 pt `UILabel` decoration on August 8 with visible text `2`,
  accessibility label `2 个续费`, and hint `ChatGPT 和 iCloud`;
- a native default orange circle decoration on August 15;
- an observable SwiftUI selection label;
- an optional, separately accessible selected-day agenda summary;
- 336 pt and synthetic 280 pt calendar containers.

The date fixture used:

- a SwiftUI compact `DatePicker`, initially 2026-08-08;
- an `onChange` counter;
- visible old/new bound values;
- a separate outside-tap target.

### Reproduction commands

```sh
node /Users/klaus/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/ios-simulator-browser/scripts/swiftui-preview-browser.mjs \
  /tmp/ios-native-runtime-fixture/Package.swift \
  --package-target IOSNativeRuntimeFixture \
  --device 899074E5-AB10-4AB3-AFD6-90571DB0C617
```

The preview launcher built and launched successfully and printed:

```text
launched package preview host for IOSNativeRuntimeFixture previews
swiftui-preview-browser ready on simulator 899074E5-AB10-4AB3-AFD6-90571DB0C617
```

Hot reload was also exercised successfully:

```text
hot reloaded package preview IOSNativeRuntimeFixture previews in pid 6437
hot reloaded package preview IOSNativeRuntimeFixture previews in pid 11802
```

The only build warning was the generated host's expected App Intents metadata
skip because the fixture has no `AppIntents.framework` dependency.

The scoped mirror was started with a UDID-specific cleanup trap and served
`http://localhost:3200`. It was stopped cleanly at the end, allowing the trap
to kill only this simulator's helper.

Dynamic Type was changed and restored with:

```sh
xcrun simctl ui 899074E5-AB10-4AB3-AFD6-90571DB0C617 \
  content_size accessibility-extra-extra-extra-large
xcrun simctl ui 899074E5-AB10-4AB3-AFD6-90571DB0C617 \
  content_size large
```

The final verification returned `large`.

## 1. Calendar Accessibility and Decorations

### Actual semantic tree

At 336 pt and default Dynamic Type, all 31 days were exported as actionable
buttons. Relevant rows from the XcodeBuildMCP runtime snapshot were:

```text
button | Saturday 8 August  | value: 2 个续费
text   | 8
text   | 2 个续费
button | Saturday 15 August | value: Small circle badge, filled
text   | 选择绑定值：2026年8月8日
```

After enabling the extra agenda summary, the tree additionally contained:

```text
text | 已选 2026年8月8日，ChatGPT 和 iCloud，共 2 项续费
```

### Observations

1. **PASS — native dates are independently reachable.** Every visible day was
   an accessibility button with a full weekday/day/month label, and selecting
   another day immediately updated the SwiftUI binding.
2. **PARTIAL — a custom decoration contributes a count.** The custom
   decoration's `2 个续费` label became the August 8 button value.
3. **FAIL — decoration semantics are not a complete event description.** The
   custom hint `ChatGPT 和 iCloud` did not appear in the exported runtime tree.
   The count also existed as a separate static-text node, so a custom
   decoration can create redundant semantics rather than one guaranteed
   sentence.
4. **FAIL — the native default dot is domain-free.** August 15 was described
   only as `Small circle badge, filled`; that says nothing about renewal count,
   services, price, or status.
5. **UNRESOLVED BY THIS EXPORT — selected trait speech.** The selected date was
   obvious visually and the binding label changed, but the rs/1 export did not
   put “selected” in the date button's label or value. It does not expose
   enough trait detail to claim the exact VoiceOver selected-state utterance.
6. **PASS — a selected-day agenda supplies the missing meaning.** One stable
   agenda label provided selected date, service identities, and count without
   trying to force all information into a seven-column cell.
7. **Localization caveat.** The generated preview host had no localized bundle
   resources. Although the visible month header was Chinese, UIKit's exported
   day labels were English. The product's zh-Hans build still needs a real
   localized VoiceOver pass before release.

### Design impact

- Keep decoration content to an indicator or count.
- Treat the selected-day agenda as required, not optional polish.
- The day/agenda reading order should be calendar selection followed by one
  summary heading and then charge rows.
- Agenda rows should carry service, plan where known, amount/currency, and
  expected/confirmed state.
- Add product UI tests for localized day label, count, selected state, and
  focus movement. A final manual VoiceOver speech/rotor pass remains required.

## 2. Dynamic Type and Narrow Width

### 336 pt, system `large`

**PASS.** The 336 pt fixture displayed a complete seven-column August grid,
all 31 dates, the selected state, both decorations, and the binding/agenda
controls. The semantic tree exposed all 31 date buttons.

Evidence:

- `/tmp/ios-native-runtime-fixture-evidence/calendar-standard-336.jpg`
- `/tmp/ios-native-runtime-fixture-evidence/calendar-agenda-summary.jpg`

### Synthetic 280 pt container, system `large`

**FAIL.** The calendar did not meaningfully compress to 280 pt. The rightmost
Saturday column rendered beyond the fixture's 280 pt border while the
accessibility tree still contained all dates. Clipping the host would therefore
hide usable dates visually; leaving it unclipped would collide with adjacent
content.

This experiment bounds, but does not determine, the practical minimum width:
280 pt failed and 336 pt passed. It would be incorrect to claim an exact
threshold without testing intermediate widths on the production host.

Evidence:

- `/tmp/ios-native-runtime-fixture-evidence/calendar-narrow-280.jpg`

### Accessibility XXXL

**FAIL for the fixed host; native grid semantics remained present.** At both
336 pt and 280 pt:

- surrounding SwiftUI labels and buttons grew substantially;
- the hard-coded calendar host allowed its month header to collide with the
  expanded controls above it;
- later dates and the agenda moved below the viewport and required scrolling;
- the seven-column grid itself retained dense date typography instead of
  putting enlarged event details in cells;
- the runtime tree continued to expose the visible dates as buttons.

The worst visual result came from combining 280 pt with AX XXXL. This is not
evidence that `UICalendarView` alone is broken: the disposable fixture
deliberately used a fixed 440 pt wrapper and large test controls. It is evidence
that a production wrapper must measure native size and reflow its surroundings
instead of imposing fixed geometry.

Evidence:

- `/tmp/ios-native-runtime-fixture-evidence/calendar-standard-a11y-xxxl.jpg`
- `/tmp/ios-native-runtime-fixture-evidence/calendar-narrow-a11y-xxxl.jpg`

### Design impact

- Do not place the month in a 280 pt fixed frame.
- Establish the production minimum from intermediate-width fixture tests; if
  the available width is below it, show the selected-day/upcoming agenda
  without a clipped seven-column month.
- Let the native wrapper report/measure its size. Avoid hard-coded heights
  around the month header.
- At accessibility sizes, stack month and agenda vertically, keep detailed
  amounts out of cells, and allow the page to scroll.
- Replace surrounding horizontal control groups with wrapped controls, a menu,
  or another adaptive presentation when their labels no longer fit.
- Test a real iPad split configuration in product QA; the 280 pt result here is
  a synthetic narrow-container stress test, not an iPad multitasking claim.

## 3. Compact Date Picker Timing and Dismissal

The clean run began at 2026-08-08 with update count zero.

1. Activating the compact field opened the August popover.
2. The accessibility tree contained date buttons and a
   `PopoverDismissRegion`; it contained no Done or Next action.
3. Activating August 9 changed the observable state immediately:

   ```text
   绑定值：2026年8月9日
   更新次数：1
   最近更新：2026年8月8日 → 2026年8月9日
   ```

4. The popover was still present after that update. A second date could be
   selected without reopening it.
5. Tapping a control above and outside the popover dismissed the popover. The
   underlying segmented control did not activate on that first outside tap.
6. After dismissal, the value and update count remained
   `2026年8月9日` and `1`.

Therefore:

- **FAIL — selecting a day does not auto-dismiss.**
- **PASS — the bound value updates immediately on day activation.**
- **PASS — an actual outside tap dismisses the popover.**
- **FAIL — outside dismissal is not an explicit completion or persistence
  boundary.** It performs no additional commit because the binding has already
  changed.

This supported-OS runtime result is more precise than inferring transaction
timing from API documentation. The form must not treat popover dismissal as
the moment data becomes real.

Evidence:

- `/tmp/ios-native-runtime-fixture-evidence/compact-picker-open.jpg`
- `/tmp/ios-native-runtime-fixture-evidence/compact-picker-immediate-binding-open.jpg`

### Design impact

- Use an editor-local date draft so live native binding changes do not
  directly persist the subscription.
- Present one focused date task with explicit Next/Done. Done applies to the
  parent form draft; the form's Save persists.
- Cancel restores the date-task snapshot.
- In Add, Next may move Start Date to Next Renewal when the latter still needs
  confirmation.
- In Edit, do not auto-advance after every date selection; the user may be
  correcting only one value.
- If a compact picker remains anywhere, never rely on “tap blank space” as the
  only visible way to finish.

## Runtime QA Matrix

| Case | Result | Evidence |
| --- | --- | --- |
| 336 pt, Large, selected/custom/default decorations | **PASS visually; PARTIAL semantically** | Complete month; custom count exported; default dot generic |
| Decoration alone communicates event details | **FAIL** | Hint/service names absent; count duplicated; no domain meaning for default dot |
| Agenda summary closes semantics gap | **PASS** | One complete selected-day summary node |
| 280 pt, Large | **FAIL** | Saturday column exceeded frame |
| 336 pt, AX XXXL with fixed wrapper | **FAIL host layout** | Expanded surrounding controls collided; content below fold |
| 280 pt, AX XXXL | **FAIL** | Narrow overflow plus accessibility-size host collision |
| Compact picker day selection auto-dismisses | **FAIL** | Popover remained open |
| Compact picker changes binding on selection | **PASS** | Count changed from 0 to 1 before dismissal |
| Outside tap dismisses picker | **PASS** | Popover disappeared and value remained |
| Outside tap is a commit boundary | **FAIL** | No new state transition occurred on dismissal |

## Limitations

1. XcodeBuildMCP supplied the runtime accessibility tree that VoiceOver
   consumes, real interactions, and real simulator frames. It did not capture
   VoiceOver audio, rotor order, or every trait. Exact spoken selected-state
   wording still requires a manual VoiceOver pass.
2. The Codex in-app browser backend was unavailable in this subagent session:
   browser discovery returned an empty list. The scoped `serve-sim` process
   successfully printed `http://localhost:3200`, but a browser-visible frame
   could not be verified or captured. XcodeBuildMCP screenshots verified the
   actual simulator frame instead.
3. The fixture's 280 pt case simulates a narrow container on the project's
   iPhone simulator. It does not replace an iPad split-view test.
4. The preview host had no zh-Hans localization bundle, so its built-in
   accessibility date labels were English.
5. `/tmp` fixture code and screenshots are intentionally disposable and may be
   removed by the operating system.

## Cleanup

- The system content size was restored to `large` and verified.
- The preview launcher was stopped.
- The scoped `serve-sim` terminal exited cleanly, running its
  UDID-specific cleanup trap.
- No product source, package manifest, Xcode project, test target, catalog, or
  evidence JSONL was changed.
