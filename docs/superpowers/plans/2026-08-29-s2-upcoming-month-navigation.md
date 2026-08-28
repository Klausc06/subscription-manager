# S2 Upcoming 月份导航 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `subagent-driven-development`（推荐）或 `executing-plans` 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 消除宽屏 `UpcomingView` 上重复的月份导航，修复 UI 测试在换月后找不到 `upcoming.month.previous` 的失败；无障碍 Dynamic Type 路径保留 pinned 自定义 header。

**架构：** 宽屏路径删除 List 内自定义 chevron header，仅依赖 `UICalendarView` 的 `DatePicker.PreviousMonth` / `NextMonth` 与既有 `Coordinator.calendarView(_:didChangeVisibleDateComponentsFrom:)` 同步 `displayedMonth`。紧凑/无障碍路径将同一 header 提取为 `monthNavigationHeader`，经 `safeAreaInset(edge: .top)` 固定在 List 外。UI 测试新增 helper，按 accessibility 树在自定义 identifier 与系统 identifier 之间选择。

**技术栈：** SwiftUI、`UICalendarView` / `UIViewRepresentable`、XCUITest、SwiftLint、`verify_repository.py`、`gh` CLI。

**规格：** `docs/superpowers/specs/2026-08-29-s2-upcoming-month-navigation-design.md`

**Issue：** [#121](https://github.com/Klausc06/subscription-manager/issues/121)

---

## 前置事实

执行前在 `fix/s2-upcoming-month-navigation` 上复现：

- 固定起点（spec 已提交）：`8604207`；合并基线 `d4fd91b`。
- 判别性 UI 失败已确认（约 15s）：

```sh
xcodebuild test \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testOnlyDueExpectedOccurrenceOffersConfirmCharge \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

预期：`TEST FAILED` @ `SubscriptionManagerUITests.swift:1424`，`No matches found` for `upcoming.month.previous`。

- Core 当前 **268 tests / 15 suites**（`-warnings-as-errors`，`--scratch-path` 见 S0 handoff）。
- **Shell：** zsh 不对未引号变量做词拆分；多路径命令写为字面量（同 S0 计划）。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `SubscriptionManager/Library/UpcomingView.swift` | 宽屏去掉 List 内 header；无障碍路径 `safeAreaInset` + 提取 `monthNavigationHeader` |
| `SubscriptionManagerUITests/SubscriptionManagerUITests.swift` | 月份导航 helper；更新 2 个受影响的 UI 测试 |
| `docs/superpowers/plans/2026-08-29-s2-upcoming-month-navigation.md` | 本计划（任务 1 提交） |

**不得修改：** `Packages/SubscriptionCore/**`、`Localizable.xcstrings`、CI 配置、其他子项目文件。

---

## 任务 1：提交实现计划

**文件：**
- 提交：`docs/superpowers/plans/2026-08-29-s2-upcoming-month-navigation.md`

- [ ] **步骤 1：确认分支与起点**

```sh
git branch --show-current
git log --oneline -3
git status --short --untracked-files=all
```

预期：分支 `fix/s2-upcoming-month-navigation`；HEAD 含 `8604207` spec 提交；工作树除 6 条范围外 untracked 外干净。

- [ ] **步骤 2：暂存并提交计划**

```sh
git add docs/superpowers/plans/2026-08-29-s2-upcoming-month-navigation.md
git commit -m "$(cat <<'EOF'
docs(superpowers): add S2 plan for Upcoming month navigation

EOF
)"
```

- [ ] **步骤 3：记录新固定起点**

```sh
git rev-parse HEAD
```

将输出 SHA 记入 `.superpowers/sdd/2026-08-29-s2-upcoming-month-navigation/progress.md`（gitignored ledger），作为后续 §4 审核的 `<fixed-point>`。**不要**把 FIXED_POINT 写回已提交的计划文件正文（CodeRabbit S0 教训）。

---

## 任务 2：`UpcomingView` 布局修复

**文件：**
- 修改：`SubscriptionManager/Library/UpcomingView.swift`

- [ ] **步骤 1：提取 `monthNavigationHeader`**

将 `body` 内 List 第一节（约 27–60 行：chevron + 月份 `Text` + chevron）提取为私有计算属性：

```swift
@ViewBuilder
private var monthNavigationHeader: some View {
    HStack {
        Button { moveMonth(by: -1) } label: {
            Label("Previous Month", systemImage: "chevron.left")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Previous Month")
        .accessibilityIdentifier("upcoming.month.previous")
        .buttonStyle(.borderless)

        Spacer()
        Text(displayedMonth, format: .dateTime.year().month(.wide))
            .font(.headline)
            .accessibilityIdentifier("upcoming.month.title")
        Spacer()

        Button { moveMonth(by: 1) } label: {
            Label("Next Month", systemImage: "chevron.right")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Next Month")
        .accessibilityIdentifier("upcoming.month.next")
        .buttonStyle(.borderless)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}
```

- [ ] **步骤 2：宽屏路径删除 List 内 header**

在 `List { ... }` 内**删除**原 header `Section` 整块。`monthOverview` 成为 List 的第一节（宽屏下直接是 `UpcomingMonthCalendar`）。

- [ ] **步骤 3：无障碍路径 pinned header**

在 `List` 上添加（仍在 `GeometryReader` 内，以便读取 `geometry.size.width`）：

```swift
.safeAreaInset(edge: .top, spacing: 0) {
    if !canUseNativeMonthCalendar(availableWidth: geometry.size.width) {
        monthNavigationHeader
            .background(.background)
    }
}
```

宽屏（`canUseNativeMonthCalendar == true`）时 inset 为空，不渲染自定义 header。

- [ ] **步骤 4：确认 `moveMonth` 仅服务紧凑路径**

不删除 `moveMonth(by:)` / `selectMonth`——紧凑路径仍需要。宽屏换月仅经 `UpcomingMonthCalendar.Coordinator` 的 `didChangeVisibleDateComponentsFrom`（已存在，勿重复接线）。

- [ ] **步骤 5：构建冒烟**

```sh
xcodebuild build \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

预期：`BUILD SUCCEEDED`。此步骤**不**期望 UI 测试通过——测试仍引用旧 identifier。

---

## 任务 3：UI 测试 helper 与受影响的测试

**文件：**
- 修改：`SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

在 `private func moveCalendarMonth` 附近（约 3860 行）添加：

- [ ] **步骤 1：编写 `tapUpcomingPreviousMonth(in:)`**

```swift
private func tapUpcomingPreviousMonth(in app: XCUIApplication) {
    let custom = app.buttons["upcoming.month.previous"]
    if custom.waitForExistence(timeout: 2) {
        custom.tap()
        return
    }
    let native = app.buttons["DatePicker.PreviousMonth"]
    XCTAssertTrue(
        native.waitForExistence(timeout: 5),
        "Expected custom or native previous-month control."
    )
    native.tap()
}
```

- [ ] **步骤 2：编写 `tapUpcomingNextMonth(in:)`**

```swift
private func tapUpcomingNextMonth(in app: XCUIApplication) {
    let custom = app.buttons["upcoming.month.next"]
    if custom.waitForExistence(timeout: 2) {
        custom.tap()
        return
    }
    let native = app.buttons["DatePicker.NextMonth"]
    XCTAssertTrue(
        native.waitForExistence(timeout: 5),
        "Expected custom or native next-month control."
    )
    native.tap()
}
```

- [ ] **步骤 3：编写 `assertUpcomingMonthContextVisible(in:minimumWidth:)`**

```swift
private func assertUpcomingMonthContextVisible(
    in app: XCUIApplication,
    minimumWidth: CGFloat
) {
    let customTitle = app.staticTexts["upcoming.month.title"]
    if customTitle.waitForExistence(timeout: 2) {
        XCTAssertTrue(app.buttons["upcoming.month.previous"].exists)
        XCTAssertTrue(app.buttons["upcoming.month.next"].exists)
        XCTAssertGreaterThan(
            customTitle.frame.width,
            minimumWidth * 0.2,
            "Upcoming must expose its month context directly."
        )
        return
    }
    let monthChrome = app.buttons["DatePicker.Show"]
    XCTAssertTrue(
        monthChrome.waitForExistence(timeout: 5),
        "Expected native month chrome when custom header is absent."
    )
    XCTAssertTrue(app.buttons["DatePicker.PreviousMonth"].exists)
    XCTAssertTrue(app.buttons["DatePicker.NextMonth"].exists)
    XCTAssertGreaterThan(
        monthChrome.frame.width,
        minimumWidth * 0.2,
        "Upcoming must expose its month context directly."
    )
}
```

- [ ] **步骤 4：更新 `testOnlyDueExpectedOccurrenceOffersConfirmCharge`**

将 1412、1424 行：

```swift
app.buttons["upcoming.month.next"].tap()
// ...
app.buttons["upcoming.month.previous"].tap()
```

替换为：

```swift
tapUpcomingNextMonth(in: app)
// ...
tapUpcomingPreviousMonth(in: app)
```

- [ ] **步骤 5：更新 `testTopLevelSegmentedControlsUseOneVisualBoundary`**

将 90–97 行替换为：

```swift
assertUpcomingMonthContextVisible(
    in: app,
    minimumWidth: minimumDirectControlWidth
)
```

- [ ] **步骤 6：运行判别性 UI 测试（两者必须通过）**

```sh
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
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

预期：两次均 `TEST SUCCEEDED`。

---

## 任务 4：仓库验证、§4 两轴审核、提交与 `artifact_verified`

**文件：**
- 修改：`SubscriptionManager/Library/UpcomingView.swift`、`SubscriptionManagerUITests/SubscriptionManagerUITests.swift`（任务 2–3 已完成）

- [ ] **步骤 1：完整仓库验证**

```sh
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors

swiftlint lint

python3 Scripts/verify_repository.py

xcodebuild test \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -only-testing:SubscriptionManagerTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

预期：Core **268/15**；SwiftLint **0**；verifier 通过；app unit **190/18** `TEST SUCCEEDED`
（较基线 187/17 增加 `UpcomingMonthNavigationTests` 一个 suite / 三个 test，以字面值钉住 AC1 真值表与 AC7 失败态）。

- [ ] **步骤 2：AC4 无障碍路径（已自动化）**

```sh
xcodebuild \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testUpcomingAccessibilitySizeUsesPinnedMonthNavigation \
  test
```

该测试以 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
启动参数驱动真实无障碍档位（UIKit 从 user defaults 的 argument domain 读取，`launchEnvironment`
不生效），覆盖：pinned header 三个 identifier 存在、`upcoming.calendar` 不存在、
next / previous 使月份标题变化并回到起点、滚动日列表后 header 仍在 accessibility 树中。
不需要生产代码开关，也不需要手动调 Settings。

变异验证（确认该测试不是空跑）：去掉 `preferredContentSizeCategory` 实参后重跑，应得 6 条
断言失败，含 `Accessibility sizes must not show the native calendar chrome`。

- [ ] **步骤 3：§4 两轴审核**

按 `docs/agents/production-flow.md` §4：

1. `git log <fixed-point>..HEAD --oneline`（fixed-point = 任务 1 步骤 3 SHA）
2. `git status --short` 为完整 manifest
3. 对 manifest 内路径跑 Standards + Spec 两轴只读审核（非 skill 默认 `git diff main` 命令）

Spec 轴对照 #121 Agent Brief 与 `docs/superpowers/specs/2026-08-29-s2-upcoming-month-navigation-design.md` §5。

- [ ] **步骤 4：一个 scoped commit**

```sh
git add SubscriptionManager/Library/UpcomingView.swift \
  SubscriptionManagerUITests/SubscriptionManagerUITests.swift
git commit -m "$(cat <<'EOF'
fix(ui): unify Upcoming month navigation with UICalendarView

Route wide-phone month paging through UICalendarView chrome and pin the
custom header only for accessibility Dynamic Type layouts. Update UI tests
to tap native or custom controls as appropriate.

Fixes #121
EOF
)"
```

不得混入 plan/spec 以外的无关改动。

- [ ] **步骤 5：`artifact_verified` 评论**

```sh
gh issue comment 121 --body "$(cat <<'EOF'
> *This was generated by AI during triage.*

## artifact_verified

**Commit:** `<SHA>` on `fix/s2-upcoming-month-navigation`

### Acceptance criteria

| Criterion | Result |
|---|---|
| AC2 `testOnlyDueExpectedOccurrenceOffersConfirmCharge` | TEST SUCCEEDED (paste log tail) |
| AC3 `testTopLevelSegmentedControlsUseOneVisualBoundary` | TEST SUCCEEDED |
| AC5 Core unchanged + app unit no regression | 268/15 + 190/18（基线 187/17 + `UpcomingMonthNavigationTests`） |
| AC6 SwiftLint + verify_repository | 0 violations; verifier OK |
| AC4 accessibility pinned header | `testUpcomingAccessibilitySizeUsesPinnedMonthNavigation` TEST SUCCEEDED（AccessibilityXXXL，含变异验证） |

### Review

Both §4 axes: <summary>. No unresolved Critical/Important findings.

Issue stays open until `remote_verified`.
EOF
)"
```

- [ ] **步骤 6：告知维护者**

报告：commit SHA、判别测试结果、§4 结论、**未 push / 未 PR / 未召唤 bot**（§5 需当回合授权）。Release Gate 全量 UI 套件（~40min）留到 push 前或 `remote_verified` 阶段按需运行。

---

## 规格自检（计划撰写时已完成）

| 规格章节 | 对应任务 |
|---|---|
| §3.1 宽屏删除重复 header | 任务 2 步骤 2 |
| §3.2 无障碍 safeAreaInset | 任务 2 步骤 3 |
| §4 UI test helpers | 任务 3 步骤 1–3 |
| §4.2 两个受影响测试 | 任务 3 步骤 4–5 |
| §5 AC1–AC6 | 任务 3 步骤 6 + 任务 4 |
| §6 变更面 / §7 排除项 | 文件结构 + 各任务范围 |

无占位符；类型与 helper 名称与 spec §4.1 一致。

---

## 执行方式

计划已保存。两种执行方式：

1. **子代理驱动（推荐）** — 每任务一个新子代理 + 任务审查；用 `subagent-driven-development`，ledger 目录 `.superpowers/sdd/2026-08-29-s2-upcoming-month-navigation/`
2. **内联执行** — 当前会话用 `executing-plans`，批量执行并在任务 4 前设检查点

维护者要求：**代码改动同步更新相关文档**；**严格 §4 双轴审查**。本子项目无新用户文案，无需改 `Localizable.xcstrings`。
