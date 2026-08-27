# S0：落地在途改动 — 设计

**日期：** 2026-08-27
**固定起点：** `cc7818d`（`origin/main` 与 `main` 当前 HEAD）。§5 步骤 0 落地文档提交后，代码审核的固定起点重新钉到该提交。
**子项目：** S0，八子项目程序的前置项。后续 S1–S8 各有独立的规格→计划→实现循环。

---

## 1. 目标

把已完成并已验证的在途改动，按"一个 root cause 一个 scoped commit"落地为三个提交，并在提交前通过仓库绑定的两轴审核。本子项目不引入任何新的行为变更。

## 2. 背景与现状

工作树当前有 17 个已跟踪文件被修改（+105 / −197）以及 3 个未跟踪新文件。这些改动已经完成并通过验证，但从未提交，因此挡在其余七个子项目前面：在未提交改动之上叠加新工作会让后续每一次 diff 与审核都混入无关内容，直接违反 `docs/agents/production-flow.md` §4 中 `artifact_verified` 的"diff 不含无关工作"条款。

已跟踪文件（按关注点归组见 §4）：

```
.swiftlint.yml
CONTEXT.md
Packages/SubscriptionCore/Sources/SubscriptionCore/BillingDateResolver.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/DomainModels.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/FixedBillingSchedule.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/HistorySupport.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/LibraryQueries.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/RepositoryProtocols.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/Subscription.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionInputs.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionSummary.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/UpcomingProjection.swift
SubscriptionManager/App/SubscriptionManagerApp.swift
SubscriptionManager/Library/RenewalProgressView.swift
SubscriptionManager/Resources/Localizable.xcstrings
SubscriptionManagerTests/AppDependenciesTests.swift
```

未跟踪新文件：

```
Packages/SubscriptionCore/Sources/SubscriptionCore/RenewalPeriodProgress.swift
Packages/SubscriptionCore/Tests/SubscriptionCoreTests/RenewalPeriodProgressTests.swift
Packages/SubscriptionCore/Tests/SubscriptionCoreTests/LibraryQueriesTests.swift
```

`git status --short --untracked-files=all` 当前共 27 条。除上述 20 条在范围内的条目外，其余条目的处置必须显式声明，因为 §5 步骤 2 把该输出定为完整候选清单，而 `production-flow.md` §4 步骤 4 规定两个审核者会在审阅内容之前驳回任何未归类的清单条目：

- 三个 iCloud 冲突副本（`docs/research/evidence/screenshots/round-2-current-ui/*" 2.jpg"`，已用 `cmp` 确认与已跟踪原件逐字节相同）、两份既有研究文档（`docs/research/2026-08-25-*.md`）、一份 `semantic-review/` 报告：**均不在本子项目范围内，不得进入任何提交。**
- `docs/superpowers/specs/2026-08-27-s0-land-in-flight-work-design.md`（本文档）：**在范围内**，作为 commit 0 单独提交，见 §5 步骤 0。它不属于任何 root cause，因此不得混入 RC1–RC3 的任何提交。把它长期留在未跟踪状态会对 S1–S8 重演本节开头所述的污染问题——这正是本子项目要消除的东西。

## 3. 已验证状态

以下结果在本设计撰写前已取得，构成三个 commit 的基线证据：

| 检查项 | 结果 |
|---|---|
| `SubscriptionCore` | 267 tests / 15 suites 通过（`-warnings-as-errors`）。`cc7818d` 基线为 253 tests / 12 suites，新增 14 个测试与 3 个套件 |
| App 单元测试 iOS Simulator（iPhone 17 Pro Max） | 187 tests / 17 suites，`TEST SUCCEEDED` |
| App 单元测试 macOS | 188 tests / 17 suites，`TEST SUCCEEDED` |
| Release 构建 macOS 与 iOS | 均 `BUILD SUCCEEDED` |
| `Scripts/verify_repository.py` | 通过，`files=168 structured=14`。该计数随仓库文件数变动：撰写本设计之前为 `files=167`，本文档写出后为 `168`。复现时以当前树的实际值为准，不要把某个历史数字当作固定期望 |
| `Scripts/verify_release_logs_tests.sh` | 全部 PASS |
| `CatalogValidator` | 有效，`schema=1 version=12 presets=93 offers=190` |
| SwiftLint | 0 violations |
| xcodegen 漂移 | 无 |
| iOS UI 验收套件 | 71 tests，1 项跳过（`testWideIPadUsesSidebarToSwitchDestinations`，仅 iPad），1 项失败：`testOnlyDueExpectedOccurrenceOffersConfirmCharge` |

该 UI 失败已证明为既有缺陷，与本子项目无关：stash 全部已跟踪改动并把三个未跟踪新文件移出目录后，基线可干净编译且该测试以完全相同原因失败（`SubscriptionManagerUITests.swift:1424`，`Failed to tap "upcoming.month.previous" Button: No matches found`）。修复它属于子项目 S2。

本地测试循环需要 `--scratch-path` 绕开 iCloud 对构建产物打 `com.apple.FinderInfo` 导致的 codesign 失败：

```sh
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors
```

`xcodebuild` 使用默认 DerivedData（`~/Library/Developer/Xcode/DerivedData`，在 iCloud 之外），不得传 `-derivedDataPath .build/*`。

## 4. 设计：三个 root cause

关注点归属已机械核实，三组文件零重叠。判定方式为对每个文件运行 `git diff --ignore-all-space --ignore-blank-lines`，结果为空者即纯空白变更。

### Root cause 1：SwiftLint 排除项漏掉嵌套构建目录

**当前行为：** `.swiftlint.yml` 的 `excluded` 相对配置文件所在目录解析，因此裸写的 `.build` 只排除仓库根目录那一个，`Packages/SubscriptionCore/.build` 下的生成文件持续被检查。生成物告警把 10 处真实违规淹没。

**期望行为：** 只检查仓库自有源码，真实违规可见且为零。

**变更：** `excluded` 增加 `"**/.build"` 与 `"**/DerivedData"` 两个 glob 并附注释说明相对解析这一原因；随后修掉被掩盖的 10 处违规——7 个 Core 源文件末尾多余换行（`DomainModels`、`HistorySupport`、`RepositoryProtocols`、`Subscription`、`SubscriptionInputs`、`SubscriptionSummary`、`UpcomingProjection`，均以 `0a0a` 结尾，各删一个字节）、`Catalog.swift:385` `guard` 中 `||` 分组的冗余括号（`,` 结合度低于 `||`，删括号语义等价）、`AppDependenciesTests.swift` 一处双空行与一处纯空白行。

**文件：** `.swiftlint.yml`、`Catalog.swift`、上述 7 个 Core 源文件、`AppDependenciesTests.swift`。

**验收标准：** `swiftlint lint` 报告 0 violations 且输出不含任何 `/.build/` 路径；`SubscriptionCore` 套件仍全绿。

### Root cause 2：续订进度按设备时区推导，且 VoiceOver 标签未本地化

**当前行为：** `RenewalProgressView` 用 `Calendar(identifier: .gregorian)`，跟随设备时区，忽略 `subscription.billingSchedule.timeZoneIdentifier`，因此跨时区订阅的剩余天数与进度可能偏一天。同一视图把插值后的 Swift `String` 交给 `.accessibilityLabel`，绑定到 SwiftUI 逐字返回的 `StringProtocol` 重载，导致中文设备上 VoiceOver 朗读英文。该视图还第四次重复了计费间隔到日历步长的映射表。

**期望行为：** 进度与剩余天数在账单时区推导，与投影出的到期扣款一致；VoiceOver 朗读用户语言；间隔映射只有一处权威定义。

**变更：**
1. 在 `BillingInterval` 上新增 `public var calendarStep: (component: Calendar.Component, value: Int)`，作为权威的间隔到日历步长映射，置于 `isValid` 之后。
2. `BillingDateResolver` 的私有 `calendarStep(for:)` 改为委托 `interval.calendarStep`，保留可选返回类型以便三处既有 `guard let`（`:17`、`:68`、`:119`）继续编译。
3. 新增 Core 值类型 `RenewalPeriodProgress(schedule:confirmedNextRenewal:asOf:)`，暴露 `fraction`、`daysRemaining`、`percentElapsed`。它经 `BillingCalendar.calendar(timeZoneIdentifier:)` 取账单时区日历；标识符不可用时回落 `BillingCalendar.calendar(timeZone: .autoupdatingCurrent)`。注意该回落并非设备日历——`BillingCalendar` 始终把 `identifier` 钉在 `.gregorian`、`locale` 钉在 `en_US_POSIX`，只有时区取自参数，所以回落只影响时区一项。选择建立此类型的原因是：留在视图的 `private` 计算属性里该推导无法验证。
4. `RenewalProgressView` 删除本地推导，只渲染 `RenewalPeriodProgress`；无障碍标签改为单个 `Text("...")` 字面量，使其成为 `LocalizedStringKey`。注意不能用 `+` 拼接字符串，那会重新绑定逐字重载。
5. 字符串目录新增键 `%lld days until renewal, %lld percent elapsed`，含 `en` 与 `zh-Hans` 两个语言。插入位置紧随既有 `Next Renewal` 条目，沿用该文件既有紧凑写法。该文件按功能区域分组、并非排序，且使用 Xcode 的 `"key" : {` 风格，必须逐条插入，不可整体重新序列化。
6. `CONTEXT.md` 术语表新增 **Renewal Period Progress**，置于 `Confirmed Next Renewal` 之后、`Confirmed Charge` 之前。

**文件：** 新增 `RenewalPeriodProgress.swift` 与 `RenewalPeriodProgressTests.swift`；修改 `FixedBillingSchedule.swift`、`BillingDateResolver.swift`、`RenewalProgressView.swift`、`Localizable.xcstrings`、`CONTEXT.md`。

**验收标准：** 同一时刻下，账单时区为 `Asia/Tokyo` 的订阅报告 `daysRemaining == 0`，而 `UTC` 订阅报告 `1`，证明推导跟随账单时区而非进程时区；`swiftlint` 与 `verify_repository.py` 通过（后者强制字符串目录每个叶子非空且已翻译）；iOS 与 macOS 构建在 `-warnings-as-errors` 下成功。

### Root cause 3：Mac 库视图重复实现筛选排序且排序规则与 iOS 分叉

**当前行为：** `MacLibraryView` 私有实现 `applyTableQuery(to:)` 与 `localizedComparison(of:and:)`，与 Core 的 `SubscriptionTableQuery.apply(to:locale:)` 职责重复。两者排序不一致：Core 用 `localizedCompare`，Mac 用 `compare(options: [.caseInsensitive, .diacriticInsensitive], locale:)`，因此仅大小写或音标不同的服务名在 macOS 与 iOS 上顺序不同。连带缺陷：Core 的 `comparison(of:and:locale:)` 接收 `locale:` 参数却调用 `localizedCompare`，把该参数静默丢弃——筛选用了 locale，排序没用。

Core 的 `makeLibraryState` 只以默认参数调用 `SubscriptionTableQuery()`，而 iOS 的 `ScopedLibraryView` 没有排序或搜索界面，因此 `MacLibraryView` 是用户驱动排序搜索的唯一消费者，却使用了自己那份分叉实现。

**期望行为：** 各界面共享同一筛选排序行为，符合 ADR-0001；Core 兑现它自己声明的 `locale:` 参数。

**变更：**
1. Core 的 `comparison` 中四处 `localizedCompare` 改为调用新增私有辅助 `order(_:_:locale:)`，其实现为 `lhs.compare(rhs, options: [], range: nil, locale: locale)`。`localizedCompare` 的定义即"无选项、当前 locale 的比较"，因此传默认 `.current` 的既有调用点行为完全不变。
2. 删除 `MacLibraryView` 的 `applyTableQuery(to:)` 与 `localizedComparison(of:and:)`，`visibleSummaries` 改为构造 `SubscriptionTableQuery(searchText:sort:ascending:)` 并调用 `.apply(to:locale:)`。该视图既有的三个 `@State`（`searchText`、`sort`、`ascending`）与该类型的初始化参数一一对应。
3. 新增 `LibraryQueriesTests.swift`，覆盖 locale 敏感排序、三字段搜索、空白与音标归一、置顶行优先、升降序。

**文件：** 修改 `LibraryQueries.swift`、`SubscriptionManagerApp.swift`；新增 `LibraryQueriesTests.swift`。

**验收标准：** `en_US` 下 `Äpple` 排在 `Zebra` 之前，`sv_SE` 下相反，证明排序已跟随传入 locale（改动前 `localizedCompare` 忽略该参数，两者结果必然相同）；macOS 构建在 `-warnings-as-errors` 下成功；Core 套件全绿。

**已知行为变更：** macOS 排序规则收敛到 iOS，即由"忽略大小写与音标"改为 locale 敏感的默认排序。筛选行为不变，因为 Core 与 Mac 原本使用相同的 `[.caseInsensitive, .diacriticInsensitive]` 选项加 locale。依据为 ADR-0001"SwiftUI、widgets、App Intents 与菜单栏共享同一行为"。

**授权状态：已批准。** 它是本子项目唯一的用户可见行为变更，按 `production-flow.md` §3"仅产品/UX 选择、实质范围变更或授权缺失才上报用户"的规定属于必须上报的一类，已于 2026-08-27 规格审查关卡上报并获用户明确接受。曾评估的替代方案是反向收敛——改动 Core 的 `comparison` 让两端统一采用"忽略大小写与音标"的排序——因其会改变 iOS 现有行为且缺少产品依据而未采纳。

需要说明的是，两个平台收敛到同一个**排序算法**，但不必然是同一个 locale：macOS 的 locale 取自 `@Environment(\.locale)`，而 iOS 经 `WorkspaceLibrary.swift:91` 走 `apply(to:)` 的默认值 `Locale.current`。这是刻意的——`apply(to:locale:)` 的契约就是"按调用方给出的 locale 排序"，谁提供 locale 由调用方决定。

## 5. 流程与错误处理

0. **Commit 0（文档）**：本设计文档经用户在规格审查关卡批准后，与随后由 `writing-plans` 产出的实现计划一起，作为一个 `docs(superpowers):` 提交落地。此提交只含 `docs/superpowers/` 下的内容，不含任何代码。完成后**把固定起点重新钉到该提交**，使 RC1–RC3 的候选 diff 恰好等于三个 root cause，不夹带文档。这样两轴审核看到的就是纯代码变更。
1. 按 `docs/agents/issue-tracker.md` 建三个 root-cause issue，每条正文首行为 `> *This was generated by AI during triage.*`，各含当前行为、期望行为、验收标准与排除项。
2. 按 `production-flow.md` §4 的提交前适配协议供出完整候选 diff，其中 `<fixed-point>` 为步骤 0 产生的文档提交：记录 `git log <fixed-point>..HEAD --oneline`；以 `git status --short --untracked-files=all` 作为完整候选文件清单，并对其中每一条给出归类（RC1/RC2/RC3 或"范围外"，依据见 §2）；已跟踪文件用 `git diff --binary <fixed-point> -- <in-scope-paths>`；三个未跟踪新文件各用 `git diff --no-index /dev/null <path>`。清单漏项会被两个审核者在看内容之前直接驳回。
3. 派两个只读审核上下文，分别执行 Standards 轴与 Spec 轴。中文风格叠加 `chinese-code-review`。
4. 汇总两轴报告，逐条对证据裁决，在当前上下文完成修正，并重跑受影响的那一轴。
5. 三个 root cause 全部满足 `artifact_verified` 后，按 §4 归组拆出三个 scoped commit，顺序为 1 → 2 → 3。每个 commit 之后运行该 commit 影响面的最小验证，确认其可独立编译并通过。
6. 不执行 push、不建 PR、不召唤外部审核 bot。这些需要用户在当回合显式授权。

**错误处理：** 若任一 commit 单独无法编译，说明关注点切分有误；回退到"四个独立循环"方案，把 `calendarStep` 提取拆为自己的 commit 并置于 root cause 2 之前。若两轴审核提出实质发现，在当前上下文修正而非新开上下文，然后重跑该轴。若 `verify_repository.py` 因字符串目录报错，检查新键的 `en` 与 `zh-Hans` 两个叶子是否均非空且状态为 `translated`。

## 6. 明确排除

- 修复既有 UI 失败 `testOnlyDueExpectedOccurrenceOffersConfirmCharge`，属 S2。
- 删除 `docs/research/evidence/screenshots/round-2-current-ui/` 下三个 iCloud 冲突副本。
- 为 iCloud 的 `--scratch-path` 变通做持久化（包装脚本或迁出同步目录），属 S7。
- 修正 CI 中 `macos_tests` 的 `continue-on-error` 与 `release_gate` 断言的矛盾，以及 `AGENTS.md` 与 CI 目标机型不一致，属 S7。
- 任何触及 `MacLibraryView` 之外的 `SubscriptionManagerApp.swift` 结构拆分，属 S4。
- 任何新的用户可见能力。
- push、PR、合并、召唤 bot。
