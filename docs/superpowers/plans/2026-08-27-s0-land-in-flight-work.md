# S0 落地在途改动 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 `subagent-driven-development`（推荐）或 `executing-plans` 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把已完成并已验证的在途改动，按"一个 root cause 一个 scoped commit"落地为三个提交，提交前通过仓库绑定的两轴审核。

**架构：** 代码本身已写完并通过全量验证，本计划不写新产品代码。工作内容是：先用一个文档提交把规格与计划落地并重钉固定起点，再按 `docs/agents/issue-tracker.md` 建三个 root-cause issue，再按 `docs/agents/production-flow.md` §4 对纯代码候选 diff 跑 Standards 与 Spec 两轴只读审核，最后按文件分组拆出三个互不重叠的 scoped commit，每个提交用 pathspec 限定的 stash 隔离后独立验证。

**技术栈：** Swift 6.4 / Xcode 27.0、swift-testing、SwiftLint 0.65.1、xcodegen 2.46.0、`gh` CLI、git 2.54.0。

**规格：** `docs/superpowers/specs/2026-08-27-s0-land-in-flight-work-design.md`

---

## 前置事实

这些值在计划撰写时实测取得，执行时应复现：

- 固定起点 `cc7818d`，`cc7818d..HEAD` 提交数为 0。
- `git status --short --untracked-files=all` 共 **28** 条：17 条已跟踪修改（+105 / −197）、11 条未跟踪。全篇统一使用 `--untracked-files=all`，不使用普通模式——普通模式会把整体未跟踪的 `docs/superpowers/` 与 `semantic-review/` 各折叠成一行（得数 27），而折叠会隐藏目录内容，与 `production-flow.md` §4 步骤 4"审核者驳回未归类清单条目"的要求相冲突。
- `cc7818d` 基线 `SubscriptionCore` 为 **253 tests / 12 suites**。
- 本地测试必须用 `--scratch-path` 绕开 iCloud 对构建产物打 `com.apple.FinderInfo` 导致的 codesign 失败。`xcodebuild` 用默认 DerivedData，不得传 `-derivedDataPath .build/*`。

**Shell 约束（必读）。** 本机 shell 为 zsh，**zsh 不对未加引号的变量做词拆分**。因此本计划不把多词命令或多路径列表放进变量再展开——那会让 `git stash push -- $PATHS` 把整串当成单个路径，输出 `No local changes to save` 却**退出码 0**，隔离静默不发生。所有多路径与多词命令一律写成字面量。若必须引入路径变量，使用 zsh 数组并以 `"${arr[@]}"` 展开。

Core 测试命令，后续步骤逐字复制：

```sh
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors
```

## 文件结构

三组文件互不重叠，合计 20 条（17 已跟踪 + 3 新增）。分组已用 `git diff --ignore-all-space --ignore-blank-lines` 机械核实。

**RC1 组（10 条，全部已跟踪）** — 职责：lint 配置与被它掩盖的违规

```
.swiftlint.yml
Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/DomainModels.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/HistorySupport.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/RepositoryProtocols.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/Subscription.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionInputs.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionSummary.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/UpcomingProjection.swift
SubscriptionManagerTests/AppDependenciesTests.swift
```

**RC2 组（7 条：5 已跟踪 + 2 新增）** — 职责：账单时区推导与本地化的无障碍标签

```
Packages/SubscriptionCore/Sources/SubscriptionCore/FixedBillingSchedule.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/BillingDateResolver.swift
Packages/SubscriptionCore/Sources/SubscriptionCore/RenewalPeriodProgress.swift          ← 新增
Packages/SubscriptionCore/Tests/SubscriptionCoreTests/RenewalPeriodProgressTests.swift  ← 新增
SubscriptionManager/Library/RenewalProgressView.swift
SubscriptionManager/Resources/Localizable.xcstrings
CONTEXT.md
```

**RC3 组（3 条：2 已跟踪 + 1 新增）** — 职责：库表查询收拢到 Core 单一实现

```
Packages/SubscriptionCore/Sources/SubscriptionCore/LibraryQueries.swift
SubscriptionManager/App/SubscriptionManagerApp.swift
Packages/SubscriptionCore/Tests/SubscriptionCoreTests/LibraryQueriesTests.swift         ← 新增
```

**文档组（2 条，任务 1 提交）**

```
docs/superpowers/specs/2026-08-27-s0-land-in-flight-work-design.md
docs/superpowers/plans/2026-08-27-s0-land-in-flight-work.md
```

**范围外（6 条，不得进入任何提交）**

```
docs/research/2026-08-25-implementation-plan.md
docs/research/2026-08-25-round-3-opportunities.md
docs/research/evidence/screenshots/round-2-current-ui/03-manual-required-plan-category 2.jpg
docs/research/evidence/screenshots/round-2-current-ui/06-edit-date-picker-no-done 2.jpg
docs/research/evidence/screenshots/round-2-current-ui/09-swipe-archive-delete 2.jpg
semantic-review/2026-08-25-053501-pr-review.md
```

**stash pathspec 陷阱。** 任务 4、5 的 stash 命令必须把路径写成字面量参数（已在对应步骤中展开）。另需注意：若 pathspec 中任一条目拼错而匹配不到文件，git 会**先建好 stash 条目，再报 `fatal: pathspec ... did not match any files` 并退出 1，且不回滚工作树**；随后 `git stash pop` 会以 "local changes would be overwritten" 拒绝，stash 条目保留。工作不会丢失，但恢复路径不直观。因此每条 stash 命令之后都要检查退出码，而不是只看输出。

---

## 任务 1：文档提交并重钉固定起点

**文件：**
- 提交：`docs/superpowers/specs/2026-08-27-s0-land-in-flight-work-design.md`、`docs/superpowers/plans/2026-08-27-s0-land-in-flight-work.md`

- [ ] **步骤 1：确认工作树处于预期起点**

```sh
git log --oneline -1
git status --short --untracked-files=all | wc -l
git diff --shortstat
```

预期：HEAD 为 `cc7818d`；**28** 条；`17 files changed, 105 insertions(+), 197 deletions(-)`。任何偏差都停下核对，不要继续。

- [ ] **步骤 2：只暂存文档，确认索引不含代码**

```sh
git add docs/superpowers
git diff --cached --name-only
```

预期：恰好两条，均在 `docs/superpowers/` 下。若出现任何 `.swift`、`.yml`、`.xcstrings` 或 `CONTEXT.md`，执行 `git reset` 后重做。

- [ ] **步骤 3：提交**

```sh
git commit -m "docs(superpowers): add S0 spec and plan for landing in-flight work"
```

- [ ] **步骤 4：记录新的固定起点**

```sh
git rev-parse --short HEAD
git status --short --untracked-files=all | wc -l
```

预期：条目数变为 **26**（28 减去两条已提交文档）。

把 `git rev-parse --short HEAD` 的输出**直接写回本计划文件**，替换任务 3 与任务 7 中的 `<FIXED_POINT>` 占位记号。不要依赖 shell 变量跨步骤传递：若每个步骤在新 shell 里执行，空变量会让 `git log <FIXED_POINT>..HEAD` 退化成合法但为空的 `git log ..HEAD`，任务 7 会显示 0 个提交而看起来像失败。同理，任务 2 取得的三个 issue 号也写回正文。

---

## 任务 2：建三个 root-cause issue

**文件：** 无仓库文件变更。产出为三个 GitHub issue 号。

按 `docs/agents/issue-tracker.md`，每条正文首行必须是 `> *This was generated by AI during triage.*`。仓库 issue 与 commit 正文使用英文，与既有历史一致。

- [ ] **步骤 1：建 RC1 issue**

```sh
gh issue create \
  --title "SwiftLint excluded paths miss nested SwiftPM build directories" \
  --body '> *This was generated by AI during triage.*

## Current behavior

`excluded` entries in `.swiftlint.yml` resolve relative to the configuration file, so the bare `.build` entry only excludes the repository-root directory. Generated sources under `Packages/SubscriptionCore/.build` are linted on every run. Their warnings bury 10 real violations in repository-owned source.

## Desired behavior

SwiftLint inspects only repository-owned source. Real violations are visible, and the count is zero.

## Change surface

- `.swiftlint.yml`: add `"**/.build"` and `"**/DerivedData"` globs with a comment recording the relative-resolution cause.
- Seven Core sources ending `0a0a` (duplicated trailing newline): `DomainModels.swift`, `HistorySupport.swift`, `RepositoryProtocols.swift`, `Subscription.swift`, `SubscriptionInputs.swift`, `SubscriptionSummary.swift`, `UpcomingProjection.swift`.
- `Catalog.swift:385`: redundant parentheses around the `||` group in a `guard`. Removing them is semantics-preserving because `,` binds looser than `||` in a condition list.
- `AppDependenciesTests.swift`: one double blank line and one whitespace-only line.

## Acceptance criteria

- `swiftlint lint` reports 0 violations.
- No reported path contains `/.build/`.
- `SubscriptionCore` suite stays green at 253 tests / 12 suites.

## Out of scope

Enabling new lint rules, reformatting untouched files, and any behavior change.'
```

- [ ] **步骤 2：建 RC2 issue**

```sh
gh issue create \
  --title "Renewal progress is derived in the device time zone, and its VoiceOver label is unlocalized" \
  --body '> *This was generated by AI during triage.*

## Current behavior

`RenewalProgressView` builds `Calendar(identifier: .gregorian)`, which follows the device time zone and ignores `subscription.billingSchedule.timeZoneIdentifier`. For a subscription billed in another zone the remaining-day count and the progress fraction can be off by one day. The same view passes an interpolated Swift `String` to `.accessibilityLabel`, which binds SwiftUI verbatim `StringProtocol` overload, so VoiceOver reads English on a Chinese device. The view also restates the billing-interval-to-calendar-step table a fourth time.

## Desired behavior

Progress and remaining days are derived in the billing time zone so they agree with the projected charge. VoiceOver reads the user language. The interval mapping has one authoritative definition.

## Change surface

- Add `public var calendarStep` on `BillingInterval` as the authoritative mapping.
- `BillingDateResolver.calendarStep(for:)` delegates to it, keeping its optional return so the existing `guard let` sites at `:17`, `:68`, `:119` still compile.
- Add Core value type `RenewalPeriodProgress(schedule:confirmedNextRenewal:asOf:)` exposing `fraction`, `daysRemaining`, `percentElapsed`. It resolves the billing calendar through `BillingCalendar.calendar(timeZoneIdentifier:)`. The derivation moves to Core because it is unverifiable inside the view private computed properties.
- `RenewalProgressView` renders that type and builds the label as a single `Text` literal.
- String catalog gains `%lld days until renewal, %lld percent elapsed` with `en` and `zh-Hans`.
- `CONTEXT.md` gains the **Renewal Period Progress** term.

## Acceptance criteria

- At one instant, a subscription billed in `Asia/Tokyo` reports `daysRemaining == 0` while a `UTC` one reports `1`, proving the derivation follows the billing zone rather than the process zone.
- `SubscriptionCore` reaches 261 tests / 14 suites.
- `swiftlint` and `Scripts/verify_repository.py` pass; the latter enforces that every string-catalog leaf is translated and non-empty.
- iOS build succeeds under `-warnings-as-errors`.

## Out of scope

Changing the ring visual design, touching any other view, and the `UpcomingView` re-derivation tracked separately as S6.'
```

- [ ] **步骤 3：建 RC3 issue**

```sh
gh issue create \
  --title "Mac library view duplicates the Core table query and sorts with different collation" \
  --body '> *This was generated by AI during triage.*

## Current behavior

`MacLibraryView` privately implements `applyTableQuery(to:)` and `localizedComparison(of:and:)`, duplicating `SubscriptionTableQuery.apply(to:locale:)`. Collation diverges: Core uses `localizedCompare` while the Mac copy uses `compare(options: [.caseInsensitive, .diacriticInsensitive], locale:)`, so service names differing only by case or diacritics order differently on macOS than on iOS. Separately, Core `comparison(of:and:locale:)` accepts a `locale:` argument and then calls `localizedCompare`, discarding it: the locale is honored for filtering but not for sorting.

`makeLibraryState` only ever calls `SubscriptionTableQuery()` with defaults, and the iOS `ScopedLibraryView` has no sort or search affordance, so `MacLibraryView` is the sole consumer of user-driven sort and search and uses the divergent copy.

## Desired behavior

Every surface shares one filter and sort behavior per ADR-0001. Core honors the `locale:` argument it declares.

## Change surface

- Core `comparison` routes its four comparisons through a new private `order(_:_:locale:)` implemented as `lhs.compare(rhs, options: [], range: nil, locale: locale)`. Because `localizedCompare` is defined as an option-free comparison in the current locale, existing call sites that pass the default are unchanged.
- Delete both private members from `MacLibraryView`; `visibleSummaries` constructs `SubscriptionTableQuery(searchText:sort:ascending:)` and calls `.apply(to:locale:)`.
- Add `LibraryQueriesTests.swift`.

## Acceptance criteria

- Under `en_US`, `Äpple` sorts before `Zebra`; under `sv_SE` the order reverses. This is discriminating because `localizedCompare` ignored the argument, so both would previously match.
- `SubscriptionCore` reaches 267 tests / 15 suites.
- macOS build succeeds under `-warnings-as-errors`.

## Approved behavior change

macOS sort collation converges to iOS: from case- and diacritic-insensitive to locale-sensitive default collation. Filtering is unchanged because Core and the Mac copy already used the same options plus locale. Approved by the maintainer on 2026-08-27 under ADR-0001.

## Out of scope

Splitting `MacLibraryView` out of `SubscriptionManagerApp.swift`, which is S4. Adding sort or search affordances to iOS.'
```

- [ ] **步骤 4：记录三个 issue 号**

```sh
gh issue list --state open --limit 5 --json number,title
```

把三个号记为 `ISSUE_RC1`、`ISSUE_RC2`、`ISSUE_RC3`，任务 4–7 的提交尾注引用它们。

---

## 任务 3：两轴只读代码审核

**文件：** 无仓库文件变更。产出为两份审核报告。

按 `production-flow.md` §4，审核对象是从 `FIXED_POINT` 起的完整候选 diff，且必须先给出完整清单。两个审核者会在审阅内容之前驳回任何未归类的清单条目。

- [ ] **步骤 1：生成清单与 diff 材料**

把下面的 `<FIXED_POINT>` 替换为任务 1 步骤 4 记录的实际 SHA。

```sh
git log <FIXED_POINT>..HEAD --oneline
git status --short --untracked-files=all
git diff --binary <FIXED_POINT> -- \
  .swiftlint.yml CONTEXT.md \
  Packages/SubscriptionCore/Sources/SubscriptionCore/ \
  SubscriptionManager/ SubscriptionManagerTests/ > /tmp/s0-tracked.diff
: > /tmp/s0-untracked.diff
for p in \
  Packages/SubscriptionCore/Sources/SubscriptionCore/RenewalPeriodProgress.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/RenewalPeriodProgressTests.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/LibraryQueriesTests.swift ; do
  git diff --no-index /dev/null "$p" >> /tmp/s0-untracked.diff || true
done
git diff --name-only <FIXED_POINT> -- \
  .swiftlint.yml CONTEXT.md \
  Packages/SubscriptionCore/Sources/SubscriptionCore/ \
  SubscriptionManager/ SubscriptionManagerTests/ | wc -l
wc -l /tmp/s0-tracked.diff /tmp/s0-untracked.diff
```

预期：`git log` 为空（文档提交就是 `<FIXED_POINT>` 本身，不在其后）；清单 **26** 条；已跟踪 diff 恰好覆盖 **17** 个文件；两个 diff 文件均非空。

两处已核实的细节：`: >` 先清空追加目标，否则重跑会让内容翻倍；`git diff --no-index` 在有差异时退出 1，`|| true` 防止在 `set -e` 下中断循环。目录级 pathspec 已验证与不加限定的全量 diff 逐行相同（均 17 个文件），`Packages/SubscriptionCore/Tests/` 缺席无害——该目录下只有未跟踪新文件，`git diff <commit>` 本就不输出它们，由上面的 `--no-index` 循环覆盖。

- [ ] **步骤 2：派 Standards 轴审核者**

只读子代理，提示要点：审核对象为上述 diff 与清单；检查仓库既有标准与代码异味基线；每条清单条目必须已归类为 RC1/RC2/RC3 或范围外，缺一条先驳回；叠加 `chinese-code-review` 的中文表达风格；禁止修改文件、禁止运行构建去"修好"问题；输出格式为状态、问题、建议。

- [ ] **步骤 3：派 Spec 轴审核者**

只读子代理，提示要点：审核对象同上；对照 `docs/superpowers/specs/2026-08-27-s0-land-in-flight-work-design.md` 以及三个 issue 的 Agent Brief，检查缺失行为与范围蔓延；特别核查 diff 是否含任何不属于三个 root cause 的内容；同样禁止修改文件；输出格式同上。

- [ ] **步骤 4：裁决两轴发现**

逐条对证据裁决。实质发现在当前上下文修正，然后重跑受影响的那一轴。措辞偏好与风格建议记录但不阻塞。若某条发现指出分组错误，按规格 §5 错误处理回退到四提交方案。

---

## 任务 4：Commit 1 — RC1 lint 配置与被掩盖的违规

**文件：** RC1 组 10 条，见文件结构。

- [ ] **步骤 1：只暂存 RC1 组**

```sh
git add .swiftlint.yml \
  Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/DomainModels.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/HistorySupport.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/RepositoryProtocols.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/Subscription.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionInputs.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionSummary.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/UpcomingProjection.swift \
  SubscriptionManagerTests/AppDependenciesTests.swift
git diff --cached --name-only | wc -l
```

预期：10。

- [ ] **步骤 2：提交**

```sh
git commit -m "fix(lint): exclude nested build directories and clear masked violations

Refs #<ISSUE_RC1>"
```

- [ ] **步骤 3：隔离出该提交的独立状态**

路径必须写成字面量参数，不得用变量展开（见前置事实的 Shell 约束）。

```sh
git stash push -u -m "s0-remaining-after-c1" -- \
  Packages/SubscriptionCore/Sources/SubscriptionCore/FixedBillingSchedule.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/BillingDateResolver.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/RenewalPeriodProgress.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/RenewalPeriodProgressTests.swift \
  SubscriptionManager/Library/RenewalProgressView.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  CONTEXT.md \
  Packages/SubscriptionCore/Sources/SubscriptionCore/LibraryQueries.swift \
  SubscriptionManager/App/SubscriptionManagerApp.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/LibraryQueriesTests.swift
echo "stash 退出码: $?"
git stash list | head -1
git diff --quiet HEAD && echo "工作树已等于 HEAD" || echo "错误：仍有已跟踪修改残留"
git status --short --untracked-files=all | wc -l
```

预期：stash 退出码 0；`git stash list` 出现 `s0-remaining-after-c1`；输出"工作树已等于 HEAD"；条目数 6（仅范围外未跟踪条目）。

若 stash 输出 `No local changes to save` 或条目数不是 6，**停下**：说明路径未被正确拆分为多个参数，隔离没有发生，继续往下会得到误导性的测试数。

- [ ] **步骤 4：验证该提交可独立编译并通过**

```sh
swiftlint lint --quiet --reporter csv | tail -n +2 | grep -c . || true
swiftlint lint --quiet --reporter csv | grep -c '/\.build/' || true
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors 2>&1 | grep -E "Test run with|✘"
```

预期：两个计数均输出 `0`；`Test run with 253 tests in 12 suites passed`。若测试数不是 253/12，说明步骤 3 的隔离未生效，回到步骤 3 排查。

- [ ] **步骤 5：恢复剩余改动**

```sh
git stash pop
git status --short --untracked-files=all | wc -l
```

预期：恢复后共 16 条（10 条 RC2/RC3 相关 + 6 条范围外）。

---

## 任务 5：Commit 2 — RC2 账单时区与本地化标签

**文件：** RC2 组 7 条，见文件结构。

- [ ] **步骤 1：只暂存 RC2 组**

```sh
git add Packages/SubscriptionCore/Sources/SubscriptionCore/FixedBillingSchedule.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/BillingDateResolver.swift \
  Packages/SubscriptionCore/Sources/SubscriptionCore/RenewalPeriodProgress.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/RenewalPeriodProgressTests.swift \
  SubscriptionManager/Library/RenewalProgressView.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  CONTEXT.md
git diff --cached --name-only | wc -l
```

预期：7。

- [ ] **步骤 2：提交**

```sh
git commit -m "fix(ui): derive renewal progress in the billing time zone

Move the billing-period derivation into a testable SubscriptionCore value
type, add the authoritative BillingInterval calendar step, and build the
VoiceOver label as a localized key.

Refs #<ISSUE_RC2>"
```

- [ ] **步骤 3：隔离出该提交的独立状态**

```sh
git stash push -u -m "s0-remaining-after-c2" -- \
  Packages/SubscriptionCore/Sources/SubscriptionCore/LibraryQueries.swift \
  SubscriptionManager/App/SubscriptionManagerApp.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/LibraryQueriesTests.swift
echo "stash 退出码: $?"
git stash list | head -1
git diff --quiet HEAD && echo "工作树已等于 HEAD" || echo "错误：仍有已跟踪修改残留"
git status --short --untracked-files=all | wc -l
```

预期：stash 退出码 0；输出"工作树已等于 HEAD"；条目数 6。同任务 4 步骤 3，若出现 `No local changes to save` 就停下。

- [ ] **步骤 4：验证该提交可独立编译并通过**

规格 §4 的 RC2 验收标准要求 iOS 与 macOS 两个平台都构建成功，所以此处两个都要跑——否则 RC2 的 macOS 条目要等到任务 6 才首次验证，那时 RC3 已落地，就不再是隔离验证。

```sh
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors 2>&1 | grep -E "Test run with|✘"
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/verify_repository.py | tail -1
swiftlint lint --quiet --reporter csv | tail -n +2 | grep -c . || true
xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`Test run with 261 tests in 14 suites passed`；verifier 通过；violations 输出 `0`；两个构建均 `** BUILD SUCCEEDED **` 且无 `error:`/`warning:`。

- [ ] **步骤 5：恢复剩余改动**

```sh
git stash pop
git status --short --untracked-files=all | wc -l
```

预期：9 条（3 条 RC3 + 6 条范围外）。

---

## 任务 6：Commit 3 — RC3 库表查询收拢到 Core

**文件：** RC3 组 3 条，见文件结构。

- [ ] **步骤 1：只暂存 RC3 组**

```sh
git add Packages/SubscriptionCore/Sources/SubscriptionCore/LibraryQueries.swift \
  SubscriptionManager/App/SubscriptionManagerApp.swift \
  Packages/SubscriptionCore/Tests/SubscriptionCoreTests/LibraryQueriesTests.swift
git diff --cached --name-only | wc -l
```

预期：3。

- [ ] **步骤 2：提交**

```sh
git commit -m "refactor(mac): route library table query through SubscriptionCore

Delete the divergent private filter and sort from MacLibraryView, and make
the Core comparison honor the locale argument it already declared.

Refs #<ISSUE_RC3>"
```

- [ ] **步骤 3：确认工作树只剩范围外条目**

```sh
git status --short --untracked-files=all
git diff --shortstat
```

预期：恰好 6 条未跟踪范围外条目；无已跟踪修改。此时 HEAD 等于规格 §3 已全量验证过的那个状态，无需 stash 隔离。

- [ ] **步骤 4：跑完整验证集**

```sh
swift test --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors 2>&1 | grep -E "Test run with|✘"
swiftlint lint --quiet --reporter csv | tail -n +2 | grep -c . || true
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest Scripts.verify_repository_tests 2>&1 | tail -3
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/verify_repository.py | tail -1
Scripts/verify_release_logs_tests.sh 2>&1 | tail -4
swift run --package-path Packages/SubscriptionCore \
  --scratch-path "$HOME/.cache/subscriptionmanager-spm" \
  -Xswiftc -warnings-as-errors CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json 2>&1 | tail -1
xcodegen generate --spec project.yml >/dev/null && \
  git status --short -- SubscriptionManager.xcodeproj SubscriptionManager/Info.plist
```

预期：`Test run with 267 tests in 15 suites passed`；violations 0；verifier 单测 20 通过；verifier 通过；release-log 校验全 PASS；catalog 有效 `presets=93 offers=190`；xcodegen 无漂移输出。

- [ ] **步骤 5：跑应用测试与 Release 构建**

```sh
for D in 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' 'platform=macOS' ; do
  xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
    -destination "$D" -only-testing:SubscriptionManagerTests \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED"
done
for D in 'generic/platform=macOS' 'generic/platform=iOS' ; do
  xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
    -configuration Release -destination "$D" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
done
```

预期：iOS 187 tests / 17 suites、macOS 188 tests / 17 suites，均 `TEST SUCCEEDED`；两个 Release 构建均 `BUILD SUCCEEDED`。

UI 验收套件不在本任务重跑：规格 §3 已记录它有一项既有失败 `testOnlyDueExpectedOccurrenceOffersConfirmCharge`，且已通过基线复现证明与本子项目无关，修复属 S2。

---

## 任务 7：记录 artifact_verified 并收尾

**文件：** 无仓库文件变更。产出为三条 issue 评论。

- [ ] **步骤 1：确认三个提交的形状**

把 `<FIXED_POINT>` 替换为任务 1 步骤 4 记录的实际 SHA。

```sh
git log <FIXED_POINT>..HEAD --stat --oneline
git log <FIXED_POINT>..HEAD --oneline | wc -l
```

预期：恰好三个提交，文件数依次为 10、7、3，无任何文件出现在两个提交里。

- [ ] **步骤 2：在每个 issue 上记录证据**

对任务 2 步骤 4 记录的三个 issue 号各执行一次 `gh issue comment <n> --body "..."`，正文首行为 `> *This was generated by AI during triage.*`，并记录：该提交 SHA、验收标准逐条结果、任务 4–6 引用的实测命令输出、两轴审核结论与裁决。按 `issue-tracker.md`，issue 在 `artifact_verified` 保持开启，只有 `remote_verified` 之后才关闭。

- [ ] **步骤 3：报告未推送状态并请求授权**

明确告知：三个提交在本地 `main`，未推送、未建 PR、未召唤 bot。按 `production-flow.md` §5，这些动作需要用户在当回合显式授权。不要自行推送。

---

## 自检

**1. 规格覆盖度。** 规格 §4 三个 root cause 分别由任务 4、5、6 实现；§5 步骤 0 由任务 1 实现；§5 步骤 1 由任务 2 实现；§5 步骤 2–4 由任务 3 实现；§5 步骤 5 由任务 4–6 的验证步骤实现；§5 步骤 6 由任务 7 步骤 3 实现。§3 的验证矩阵由任务 6 步骤 4–5 复现。§6 的排除项在文件结构"范围外"一节固定为 6 条，并由任务 6 步骤 3 断言。无遗漏。

**2. 占位符扫描。** 无"待定"、"TODO"、"类似任务 N"。每个代码步骤都给出可直接执行的命令与预期输出。文中仅有四个待替换记号 `<FIXED_POINT>`、`<ISSUE_RC1>`、`<ISSUE_RC2>`、`<ISSUE_RC3>`，它们由任务 1 步骤 4 与任务 2 步骤 4 取得后**写回本文件正文**，而不是靠 shell 变量跨步骤传递——原因见任务 1 步骤 4 的说明。所有多词命令与多路径列表均为字面量，不经变量展开，理由见前置事实的 Shell 约束。

**3. 类型一致性。** 全篇引用同一批标识符：`BillingInterval.calendarStep`、`RenewalPeriodProgress(schedule:confirmedNextRenewal:asOf:)` 及其 `fraction` / `daysRemaining` / `percentElapsed`、`BillingCalendar.calendar(timeZoneIdentifier:)`、`SubscriptionTableQuery(searchText:sort:ascending:)` 与 `.apply(to:locale:)`、Core 私有 `order(_:_:locale:)`。与规格 §4 逐一吻合，无改名漂移。

**4. 测试数递进自洽。** 253/12（基线与 commit 1）→ 261/14（commit 2，+8 测试 +2 套件）→ 267/15（commit 3，+6 测试 +1 套件）。两个新测试文件实测含 3 个 `@Suite` 与 14 个 `@Test`，与递进吻合。
