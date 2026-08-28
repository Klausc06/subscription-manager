# S2：Upcoming 月份导航与 UI 测试 — 设计

**日期：** 2026-08-29
**固定起点：** `d4fd91b`（S0 合并后的 `main` HEAD）
**子项目：** S2，八子项目程序中的下一项。S6 依赖本子项目（均触及 `UpcomingView`）。

---

## 1. 目标

修复 `UpcomingView` 在宽屏/iPhone 上使用 `UICalendarView` 时，自定义月份 header 与系统日历导航重复、且自定义控件在 `List` 滚动后从 accessibility 树消失，导致 UI 验收测试失败的问题。

修复后，`testOnlyDueExpectedOccurrenceOffersConfirmCharge` 及受影响的 Upcoming 月份导航断言必须通过，且不引入第二套并行的月份状态源。

## 2. 背景与根因

### 2.1 症状

```text
SubscriptionManagerUITests.swift:1424
Failed to tap "upcoming.month.previous" Button: No matches found
```

单测 `testOnlyDueExpectedOccurrenceOffersConfirmCharge` 在 `main` @ `d4fd91b` 上本地复现（约 15 秒）。步骤：`upcoming.month.next` 成功 → `upcoming.month.previous` 失败。

### 2.2 已确认根因

`UpcomingView` 在 `canUseNativeMonthCalendar == true` 时同时渲染：

1. **List 第一节**：自定义 `HStack`（`upcoming.month.previous` / `upcoming.month.title` / `upcoming.month.next`）
2. **List 第二节**：`UpcomingMonthCalendar`（`UICalendarView`，自带 `DatePicker.PreviousMonth` / `DatePicker.NextMonth`）

点「下月」后 `List` 重排/滚动，第一节滚出可见区域，自定义 identifier 从 XCUI 树消失；`UICalendarView` 的系统导航仍在树中。这不是 identifier 拼写错误——初始加载时 `testTopLevelSegmentedControlsUseOneVisualBoundary` 能查到自定义按钮。

`UpcomingMonthCalendar.Coordinator` 已实现 `calendarView(_:didChangeVisibleDateComponentsFrom:)` 并调用 `onDisplayedMonthChange` → `selectMonth`，系统导航与 `displayedMonth` 的同步路径**已存在**。问题在于 UI 层重复导航 + 自定义控件不可达。

### 2.3 与 Apple 平台惯例的对齐

`docs/product-goal.md` 要求优先使用原生控件。`UICalendarView` / 系统日历 App 的惯例是：**月份导航内嵌于日历 chrome**，不在可滚动的 `List` 节中再叠一套 chevron。宽屏路径应遵循此模式；仅在无法展示网格日历时（无障碍 Dynamic Type）保留自定义月份控件。

### 2.4 范围外（已证明）

- S0 改动与此失败无关（基线 stash 隔离后同样失败）。
- `_UICalendarDateViewCell` 的 Automation type mismatch 警告存在，但不是本次 tap 失败的直接原因；不纳入本子项目 unless 修复后仍阻塞。

## 3. 设计方案（用户已批准 2026-08-29）

### 3.0 唯一导航面不变量

月份导航面由一个纯判定决定，两处渲染分支共用它，不各写一份条件：

```swift
UpcomingView.showsNativeMonthCalendar(
    canUseNativeMonthCalendar:hasUpcomingFailure:
) == canUseNativeMonthCalendar && !hasUpcomingFailure

UpcomingView.showsPinnedMonthNavigation(...) == !showsNativeMonthCalendar(...)
```

因此在 (布局宽度 × 加载状态) 的每种组合下，`UICalendarView` chrome 与 pinned 自定义 header
恰好挂载一个，永不同时出现、也永不同时缺席 —— 这由「后者定义为前者取反」保证，而非靠两处条件
各自写对。`displayedMonth` 的**月份导航写者**在任一时刻只有一个（`loadTimeline` 的
`selectsFirstChargeAfterMonthChange` 路径也会经 `selectMonth` 写入，但那不是导航控件）。

### 3.1 宽屏路径（`canUseNativeMonthCalendar == true`）

**加载成功（`hasUpcomingFailure == false`）：**

- **删除** List 中的自定义月份 header `Section`（chevron + `Text` 标题）。
- **唯一**月份导航：`UICalendarView` 自带的 `DatePicker.PreviousMonth` / `DatePicker.NextMonth`（及系统月份标题 chrome）。
- **状态**：继续通过现有 `Coordinator.calendarView(_:didChangeVisibleDateComponentsFrom:)` → `selectMonth` 同步 `displayedMonth` / `selectedDay`；**不得**再经 `moveMonth(by:)` 平行写入。
- **程序化换月**（若 UI 内仍有需要）：通过 `UpcomingMonthCalendar` 暴露的 `setVisibleDateComponents` 路径驱动 `UICalendarView`，而不是自定义 Button。
- **accessibility**：保留 `upcoming.calendar` 于 `UICalendarView`；此状态下不声明 `upcoming.month.previous` / `next` / `title`。

**加载失败（`hasUpcomingFailure == true`）：**

- 无 projection 可渲染，`UICalendarView` 不挂载，因此系统月份 chrome 不存在。
- pinned 自定义 header **恢复**：它是此状态下唯一能改变 `displayedMonth`、从而触发
  `.task(id: displayedMonth)` 重新加载的控件。声明 `upcoming.month.previous` / `next` / `title`。
- 此状态下 `moveMonth(by:)` 是唯一的月份导航写者，与 §3.1 禁止的"平行写入"不冲突：
  两个写者从不同时挂载。失败恢复后 `UpcomingMonthCalendar` 是重新挂载，因此由
  `makeUIView` 依据 `displayedMonth` 播种 `visibleDateComponents`（后续换月才走
  `updateUIView`）。

### 3.2 无障碍 / 紧凑路径（`canUseNativeMonthCalendar == false`）

- 加载成功时使用 `groupedDayList`，加载失败时改为 `upcoming.month.failed`；两种情况都无 `UICalendarView`。
- 自定义月份 header **移出 `List`**，置于 `safeAreaInset(edge: .top)`（或等价的非滚动容器），保证滚动日列表时月份控件始终在 accessibility 树中。
- 保留 `upcoming.month.previous` / `upcoming.month.next` / `upcoming.month.title` identifier。
- `moveMonth(by:)` 用于所有未挂载 `UICalendarView` 的状态：紧凑 / 无障碍路径，以及宽屏加载失败态（§3.1）。

### 3.3 布局结构（宽屏，加载成功）

```text
NavigationStack
  └─ List
       ├─ (无月份 header Section)
       ├─ Section: UpcomingMonthCalendar  [upcoming.calendar]
       └─ Section: 当日 agenda / ContentUnavailable
```

### 3.3.1 布局结构（宽屏，加载失败）

```text
NavigationStack
  └─ safeAreaInset(top): 月份 header  [upcoming.month.*]
  └─ List
       ├─ Section: ContentUnavailableView  [upcoming.month.failed]
       └─ Section: ContentUnavailableView  [upcoming.agenda.failed]
```

### 3.4 布局结构（无障碍尺寸）

```text
NavigationStack
  └─ safeAreaInset(top): 月份 header  [upcoming.month.*]
  └─ List
       └─ Section "Days": groupedDayList
```

## 4. UI 测试变更

### 4.1 共享 helper（推荐）

在 `SubscriptionManagerUITests.swift` 增加月份导航 helper，按当前树选择控件，避免测试再次绑定错误 surface：

| 条件 | 上一月 | 下一月 | 月份上下文断言 |
|---|---|---|---|
| 存在 `upcoming.month.previous` | 点该 Button | 点 `upcoming.month.next` | `staticTexts["upcoming.month.title"]` |
| 否则（原生日历） | 点 `DatePicker.PreviousMonth` | 点 `DatePicker.NextMonth` | `buttons` 含 `label == "Month"` 且 `value` 含目标年月，或 `DatePicker.Show` |

Helper 名称建议：`tapUpcomingPreviousMonth(in:)` / `tapUpcomingNextMonth(in:)` / `assertUpcomingMonthContextVisible(in:minimumWidth:)`。

### 4.2 受影响的测试

| 测试 | 变更 |
|---|---|
| `testOnlyDueExpectedOccurrenceOffersConfirmCharge` | 1412、1424 行改用 helper |
| `testTopLevelSegmentedControlsUseOneVisualBoundary` | 90–97 行改用 `assertUpcomingMonthContextVisible`；宽屏下断言系统 Month chrome 宽度，而非已删除的 `upcoming.month.title` |

不得仅把失败断言改为 `XCTSkip`；必须覆盖「换月后仍能返回原月并点到 Confirm Charge」的行为。

## 5. 验收标准

| # | 标准 | 验证方式 |
|---|---|---|
| AC1 | `UICalendarView` chrome 与 pinned 自定义 header 在 (宽度 × 加载状态) 每种组合下恰好挂载一个：宽屏+成功仅原生、宽屏+失败仅自定义、紧凑 / 无障碍仅自定义 | 判定层：`UpcomingMonthNavigationTests` 以字面值钉住全部四种组合的真值表。渲染层：`assertUpcomingMonthContextVisible` 在两个分支各断言另一套控件不存在（覆盖宽屏+成功、紧凑+成功），`testUpcomingAccessibilitySizeUsesPinnedMonthNavigation` 覆盖无障碍档位。**宽屏+失败的渲染层未覆盖**，原因同 AC7 |
| AC2 | `testOnlyDueExpectedOccurrenceOffersConfirmCharge` 通过 | `-only-testing:…/testOnlyDueExpectedOccurrenceOffersConfirmCharge` |
| AC3 | `testTopLevelSegmentedControlsUseOneVisualBoundary` 通过 | 同上 `-only-testing` |
| AC4 | 无障碍 Dynamic Type 路径仍可通过自定义 header 换月，且滚动日列表后 header 仍在 accessibility 树中 | 已自动化：`testUpcomingAccessibilitySizeUsesPinnedMonthNavigation`。经由 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` 启动参数驱动真实 Dynamic Type 档位（UIKit 从 user defaults 的 argument domain 读取，故不能用 `launchEnvironment`），不使用任何生产开关。测试断言月份标题在 next / previous 后变化并回到起点，并以 `seedsTask6OccurrenceFixture` 保证日列表可滚动 |
| AC5 | `SubscriptionCore` 与 app 单元测试不退步 | 现有命令集通过；本子项目不修改 Core |
| AC6 | SwiftLint 0；`verify_repository.py` 通过 | 标准仓库验证 |
| AC7 | 宽屏加载失败态仍存在可改变 `displayedMonth` 的控件（否则无法离开失败月份或重试） | `showsPinnedMonthNavigation(canUseNativeMonthCalendar: true, hasUpcomingFailure: true) == true`。**仅在纯判定层验证**：`upcomingTimelineState == .failed` 目前没有可注入的启动参数（仅有 `--ui-testing-fail-lifecycle-mutations`），新增失败注入 hook 超出本子项目变更面，UI 级覆盖延后 |

## 6. 变更面

**允许修改：**

- `SubscriptionManager/Library/UpcomingView.swift`
- `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- `SubscriptionManagerTests/ConfirmChargeEligibilityTests.swift`（纯判定的单元覆盖）
- 本设计文档与对应 plan（记录失败态行为与 AC4 自动化方式）

**不得修改：**

- `Packages/SubscriptionCore/**`（S6 范围）
- `Localizable.xcstrings`（无新用户可见文案）
- CI 配置（S7）
- 其他子项目的文件

## 7. 排除项

- 不重构 `UpcomingView` 其余 agenda / confirm 逻辑（S6）。
- 不修改 `UICalendarView` decoration / badge 行为。
- 不解决 macOS Upcoming（当前 macOS 无 `UICalendarView` 节）。
- 不 filing / 修复 `_UICalendarDateViewCell` type mismatch 除非 AC2 仍失败且证据指向该警告。

## 8. 验证命令

```sh
# Core（iCloud 仓库必须 scratch-path）
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors

swiftlint lint

python3 Scripts/verify_repository.py

# 判别性 UI 测试（约 1–2 分钟 each）
xcodebuild test \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testOnlyDueExpectedOccurrenceOffersConfirmCharge \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild test \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testTopLevelSegmentedControlsUseOneVisualBoundary \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testUpcomingAccessibilitySizeUsesPinnedMonthNavigation \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

完整 UI 套件（约 40 分钟）在 `artifact_verified` 阶段按需运行；本子项目至少跑上述两项判别测试。

## 9. GitHub issue

**#121** — https://github.com/Klausc06/subscription-manager/issues/121

实现前 root-cause issue 已创建；Agent Brief 指向本文档。

## 10. 批准记录

- **2026-08-29**：维护者批准方案 B（宽屏用 `UICalendarView` 单一导航）+ 无障碍路径 pinned 自定义 header。
