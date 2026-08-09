# SubscriptionManager Round 3 优化实施计划

> **Workflow status (2026-08-09):** This file is retained as historical product
> and acceptance context. Its Luna routing, reviewer topology, batch execution,
> and `.superpowers/sdd/progress.md` instructions are superseded by `AGENTS.md`
> and `docs/agents/production-flow.md` and must not be executed. A current
> root-cause issue must explicitly cite and revalidate any product requirement
> reused from this plan.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for implementation tasks after this plan passes independent review. Each task is bounded, must preserve the global constraints, and must not be widened during execution.

**Goal:** 让用户在一个清楚、轻量、符合系统行为的订阅主流程中看到服务、花费和下一次续费，并能在同一张卡片内完成编辑；同时让目录分类、套餐变体、价格和周期具备可核验的事实基础。

**Architecture:** 保留 `SubscriptionWorkspace` 作为行为边界，保留现有本地 SwiftData、`Subscription Library → Upcoming` 投影关系和本地 JSON 目录。UI 只重组已有 Library、Detail、Editor、Catalog 和 Upcoming 表面；目录审计只增加能表达变体、标准续费语义和证据关联的最小字段，不把原始研究材料塞进运行时 UI。

**Tech Stack:** Swift 6、SwiftUI、UIKit `UICalendarView`、SwiftData、Swift Testing、XCTest/UI tests、现有本地 `catalog-v1.json` 和 `docs/research/evidence/*.jsonl`。

## Global Constraints

- 先解决用户主流程：看懂订阅、花费和续费日期；每个任务必须写明它删除的用户步骤。
- 一次只处理一个需求组；完成一个任务后先跑对应 focused test，再进入下一个任务。
- 不增加页面、仓库、全局状态框架、第三方日历或第三方搜索；已有结构能完成时不抽象出新层。
- 订阅最小保存事实仍是服务名称、价格、实际扣款货币、固定账单周期和账单日期；类别、套餐、管理网址、备注不阻塞保存。所有用户可见网址均删除，内部来源字段只用于证据和兼容。
- 编辑页面不展示“使用中”状态行；域层生命周期事实仍用于存档、续费和日历投影。
- 订阅实际货币的用户选择只允许 CNY、USD、EUR；不得把显示货币设置静默写入实际扣款货币。
- 目录可选 offer 必须有服务/变体、市场、币种、周期、渠道、标准续费语义、来源和核验日期；促销、资格价、首月价和渠道差异必须分开。
- Apple 资料只证明当前 SwiftUI/HIG 的 API 和设计原则，不证明固定的 iOS 27 圆角、间距、sheet 高度或日历布局数值。
- 保留 R2 的 14 条验收基线；本轮不宣称 Round 2 或 Round 3 已完成，直到代码、测试和设备 UI 证据齐全。
- 原 Round 3 产品功能不新增 iCloud/CloudKit 或云端架构；方案 A Batch 2 已批准的 SwiftData/CloudKit remediation 仅限其列明的数据完整性修复，不扩展产品功能。本轮不自动 commit、不 push。

### Implementation isolation rule

- 以下 Task 按相关文件归组，但实际写入单位仍是单个 R3 requirement；同一时刻只允许一个写入 agent 处理一个 requirement。
- 每个 requirement 的顺序固定为：读取当前 diff → 写入最小修改 → 主 agent 检查 diff → 运行该 requirement 的 focused test → 通过后才进入下一个 requirement。
- 不同 requirement 若共享文件，后一个 requirement 必须读取前一个 requirement 的已落盘结果；subagent 不得覆盖或回滚其他已审阅改动。
- subagent 只负责被分配的文件边界；目录研究 agent 只交付证据和状态，不能直接把候选标为 verified；主 agent 负责最终落盘和验收。

## 当前代码和证据边界

| 区域 | 当前入口 | 计划中的最小职责 |
| --- | --- | --- |
| 订阅库/Upcoming | `SubscriptionManager/Library/LibraryView.swift` | 顶部工具栏、列表行入口、Upcoming 月历和议程的 UI 组合 |
| 摘要/编辑 | `SubscriptionManager/Library/SubscriptionDetailView.swift`、`EditSubscriptionView.swift`、`SubscriptionEditorSections.swift` | 同一 sheet 内摘要 → 编辑，删减状态/网址/来源 UI |
| 新增/目录 | `SubscriptionManager/Catalog/CatalogBrowserView.swift`、`AddSubscriptionView.swift` | 加号入口、目录顶部、类别文案和手动添加路径 |
| 领域/偏好 | `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`、`UserPreferences.swift` | 实际货币、外观模式、稳定类别和生命周期边界 |
| 目录数据 | `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`、`SubscriptionManager/Resources/catalog-v1.json` | 变体、标准续费语义、证据关联和分类迁移 |
| 目录测试 | `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift`、`SubscriptionManagerTests/CatalogOfferSelectionTests.swift`、`SubscriptionManagerTests/BundledCatalogRepositoryTests.swift` | 结构、可选性、证据和兼容性门 |
| UI 测试 | `SubscriptionManagerUITests/SubscriptionManagerUITests.swift` | 主流程、可见文案、sheet、swipe 和日历可达性 |

## 执行顺序

```text
Task 0 调研基线与执行门
    ├── Task 1 库顶部、加号、目录入口、存档 swipe
    ├── Task 2 同一 sheet 的摘要卡片与编辑状态
    ├── Task 3 编辑字段与来源/网址 UI 清理
    └── Task 4 货币入口与三态外观
Task 5 Upcoming 月历边界与圆角呈现诊断
Task 6 类别稳定化与分类迁移
Task 7 目录证据审计与分批数据修正
Task 8 集成验收：focused → full regression → 设备 UI → 目标反查
```

## GitHub review remediation execution（方案 A，已批准）

本节是已批准的 remediation plan，不是从仓库旧 brief 推断出的新产品范围；产品目标、页面边界、货币边界和依赖边界保持不变。Batch 1 已在 `dd6de2cbcfb11e69314e088408113a0d923e8fa3` 完成，下面的 Batch 2–5 仍需用户授权后才能开始。

### 公共流程

1. 主任务按批次先使用 `superpowers:receiving-code-review` 在当前 HEAD 核对 finding 是否仍成立；scope 已锁定时不额外 brainstorming。
2. 实现 Luna 使用 `tdd` 或 `superpowers:test-driven-development`，先取得故障路径的真实 RED，再做最小 GREEN。实现提示必须写明目标/用户价值、起始 SHA、允许文件、禁止项、failure invariants、技能、RED → GREEN 顺序、focused + batch regression、完成证据和 remote side effects。
3. 数据、并发或外部系统批次增加 `debug-like-expert`；数据模型迁移增加 `domain-modeling`；SwiftUI 批次增加 `build-ios-apps:swiftui-ui-patterns`。只有 brief 明确要求真实运行时 UI 证据时才使用 `ios-simulator-browser`。
4. 每批默认一个实现 Luna 加一个独立 Luna Medium 只读 review；验收者只能输出 `APPROVE` 或 `FINDINGS`。finding 必须包含复现、影响、最小修复和永久回归测试。真实 finding 才返回原实现者修复，修复后由同一 Medium reviewer 复核，不增加第三 reviewer。
5. 每批运行 focused tests，再运行一次批次级 regression；后续批次不得把历史测试结果冒充本轮重跑。fake/mock 必须模拟物理副作用、事务失败、retry/idempotency 和适用的系统语义，不得复制生产算法自证。
6. 每批结论后立即更新唯一 canonical `.superpowers/sdd/progress.md`。不因置信度自动增加 UI tests、全量审计、Max 或 reviewer；不增加未请求工作流、页面、依赖、币种或功能。GitHub reply/resolve/mark read 只有全部批次验证后且用户当轮授权才可做；push 始终需要用户当轮明确授权。

### Batch 2 — SwiftData/CloudKit 数据完整性

**允许/预期文件：**

- `SubscriptionManager/Persistence/SubscriptionRecord.swift`
- `SubscriptionManager/Persistence/SwiftDataSubscriptionRepository.swift`
- `SubscriptionManager/App/AppDependencies.swift`
- `SubscriptionManager/Sync/CloudKitLibrarySyncMonitor.swift`
- 对应 repository/dependency/sync tests

**目标与 failure invariants：**

- `ConfirmedCharge`/`PriceChange` 从整块 `Data` 迁移为稳定 ID 的独立 SwiftData records。
- 旧 `Data` 只作为一次性迁移源；成功保存后不再写旧格式。
- `CalendarProjectionMappingRecord` 使用 `cloudKitDatabase .none` 的本地 configuration。
- `UserPreferencesRecord` 使用稳定身份和确定性重复合并；禁止无排序 `fetchLimit=1`。
- 单条损坏记录保留、不自动删除且不隐藏整个 library；仍返回有效订阅。
- iCloud account available 不等于 sync current；远端导入后必须触发 workspace reload。

**验收：** 旧库升级后的数量、ID、金额和日期不变；独立追加不覆盖；mapping 不进入 CloudKit；坏记录不拖垮库；没有同步完成证据时不显示 current。

**分工/技能：** Luna XHigh 实现，使用 `superpowers:receiving-code-review`、`domain-modeling`、`debug-like-expert` 和 `tdd`；独立 Luna Medium 使用 `review` 与 `debug-like-expert` 只读验收。只有迁移/CloudKit 语义不能在现有 seam 表达，或一次真实修复后仍有跨层 finding，才允许升级 Max。

**Remote side effects：** 无；不得在本批执行 push、GitHub reply/resolve/mark read 或其他远端操作。

### Batch 3 — 洞察、汇率、续费日期

**预期文件：** `SubscriptionCore.swift`、`ExchangeRates.swift`、`LibraryView.swift`、`SubscriptionWorkspaceTests`。

**目标与验收：** `required quote currencies` 覆盖原价、price changes、confirmed charges 和 display currency；当天 cache 必须含全部币种；`CancellationError` 不写失败时间；磁盘缓存失败使用进程内 attempt state；首尾日计入；expected 覆盖未来 30 天、confirmed 覆盖过去 30 天；月末使用完整时段；Upcoming 使用 billing timezone 且 accessibility 有日期；读取失败与空列表区分。必须覆盖月末中午不漏、1–30 日按 30 天、新币种补请求、失败不伪装空。

**分工/技能：** Luna High 实现，使用 `superpowers:receiving-code-review`、`debug-like-expert` 和 `tdd`；独立 Luna Medium 只读 review。不得添加页面、汇率供应商、依赖、币种或额外审计层。

**Remote side effects：** 无；不得在本批执行 push、GitHub reply/resolve/mark read 或其他远端操作。

### Batch 4 — 首次设置与 macOS 窗口

**预期文件：** `UserPreferences.swift`、`LibraryView.swift`、`SubscriptionManagerApp.swift`、对应 UserPreferences/Mac tests。

**目标与验收：** 非空或仅 archived library 无 preferences 时持久化 completed；setup load failure 在现有界面内重试；preset confirmed 后取消再选不重复；每个 macOS window 拥有独立 scope/snapshot/search/sort；Command-N 单一；修复 locale compare、search focus、sort、accessibility 和 localization。老用户不重进 setup，两个窗口不串状态。

**分工/技能：** Luna High 实现，使用 `superpowers:receiving-code-review`、`tdd` 和 `build-ios-apps:swiftui-ui-patterns`；独立 Luna Medium 只读 review。只有 brief 明确要求真实 UI 行为证据时才使用 `ios-simulator-browser`；不得新增页面、窗口管理框架或 UI test 层。

**Remote side effects：** 无；不得在本批执行 push、GitHub reply/resolve/mark read 或其他远端操作。

### Batch 5 — 便携导出与 GitHub 收尾

**预期文件：** `PortableBackup.swift`、`PortableExportView.swift`、`PortableExportTests`。

**代码目标与验收：** UI 只通过 `SubscriptionWorkspace` 请求 JSON/CSV `Data`；CSV 增加 `record_type`/`renewal_anchor`；空库输出 preferences row；公开 JSON decode 统一校验 schema/version。实现完成后由独立 Luna Medium 只读 review；若现场确认只是单一 encoder seam，可将实现降为 Medium。技能为 `superpowers:receiving-code-review` + `tdd`。

GitHub 收尾与代码实现分离：只有全部批次验证后且用户当轮授权，才可 reply/resolve/mark read；push 始终需要用户当轮明确授权。未获授权前不得执行任何 GitHub 或 remote side effect。

## Task 0：调研基线、当前实现映射和执行门

**用户步骤价值：** 用已完成的官方调研直接解决网址和 Claude 价格的歧义，不再把研究任务退回给用户；同时固定本轮的最小实现边界。

**Files:**

- Read: `docs/research/2026-08-02-round-3-product-goal.md`
- Read: `CONTEXT.md`
- Read: `docs/adr/0001-subscription-workspace-boundaries.md`
- Read: `docs/research/2026-08-01-round-2-synthesis.md`
- Read: `docs/research/2026-08-01-round-2-manifest-validation.md`

**Steps:**

- [x] 已确定 R3-04/R3-12：所有用户可见网址、`Link`、管理网址输入和账单/续订/取消跳转说明全部删除；内部来源证据不删除。
- [x] 已从真实 `SubscriptionManager/Resources/catalog-v1.json` 定位 `claude`：当前有 Pro 月付/年付、Max 5x 月付、Max 20x 月付；Max 20x 当前标准价为 200 USD/月，不加入 240 USD/月。
- [x] 已记录百度网盘当前运行时目录只提供一个 CN/iOS SVIP 月付 offer；VIP、SVIP10/等级、空间扩容和套餐虽有官方产品结构证据，但金额未形成稳定固定价格证据，不能直接伪造可选 offer。
- [x] 固定本轮不变的域边界：实际扣款货币、生命周期、存档数据、日历投影和 `SubscriptionWorkspace` 不因 UI 简化被删除。
- [x] 将调研结果写回目标文档与本计划；以上不再构成需要用户回答的决策门。

**验收：** 研究结论、当前目录事实和不变的域边界均有记录；没有因为计划文档而修改源码或目录。

**Focused verification：**

```sh
jq -e '.schemaVersion == 1 and (.presets | length > 0)' \
  SubscriptionManager/Resources/catalog-v1.json
swift run --package-path Packages/SubscriptionCore --scratch-path \
  /private/tmp/subscription-manager-task7-review-fix CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json \
  docs/research/evidence/2026-08-02-round-3-catalog-audit.jsonl
jq -e '.presets[] | select(.id == "claude") | .offers[] | select(.id == "max-20x-monthly-us-web") | .price.minorUnits == 20000' \
  SubscriptionManager/Resources/catalog-v1.json
```

Expected: JSON and validator pass, and the Claude Max 20x assertion is true; no source or catalog write occurs in Task 0.

### 已确认的执行决策

- **网址：** 摘要、编辑、新增确认和确认订阅流程均不显示任何用户可见 URL，不保留摘要链接例外；目录 `sourceURL`、preset `managementURL` 和 evidence URL 仅保留在内部数据层。
- **Claude：** Pro 20 USD/月、Pro 年付 200 USD/年、Max 5x 100 USD/月、Max 20x 200 USD/月；240 USD/月不是标准 Max 20x 目录价。用户实际账单若为 240，应由用户实际订阅记录承载，不能覆盖标准目录 offer。
- **百度网盘：** 先审计 VIP、SVIP、SVIP10/等级、空间扩容和套餐；只有取得服务、变体、市场、渠道、币种、固定金额、周期和证据后才进入可选目录。

## Task 1：重排订阅库顶部和新增入口

**用户步骤价值：** 删除顶部存档按钮和目录列表里的手动添加行，让用户只需点击右上角加号即可开始新增。

**Files:**

- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionRow.swift`（仅在需要接入 trailing-edge swipe 时）
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`（仅保持 macOS 现有存档入口和键盘命令不被破坏）
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Implementation contract:**

- Library toolbar 使用系统导航栏：leading 设置、inline/center 标题“我的订阅”、trailing `+`。
- 删除顶部 archive toolbar item；保留 archived query、restore 和数据语义。
- 在列表行上使用 trailing-edge `swipeActions` 提供用户左滑存档；破坏性 Delete 不得借 full swipe 误触发，Archive 与 Delete 的角色分开。
- `+` 继续先进入 `CatalogBrowserView`；目录页面顶部中央标题为“浏览目录”。
- 删除独立“手动添加”行；在加号流程内保留“手动添加”按钮/分支。
- 将过滤器对外文案从“所有类别”改为“类别”，不改成新的类别体系。

**Focused tests:**

- [x] UI test：订阅库显示“我的订阅”、设置和加号；不显示顶部存档按钮。
- [x] UI test：在 `zh-Hans` 下断言导航标题为“我的订阅”，不依赖英文显示字符串。
- [x] UI test：点击加号进入“浏览目录”，目录结果前没有独立手动添加大行，但手动路径可达。
- [x] UI test：列表行左滑后可看到存档动作；存档后从当前库消失，恢复语义仍存在。
- [x] Run the focused `SubscriptionManagerUITests` cases before changing any editor code.

**验收：** 主库顶部只剩用户要求的三个位置；新增和存档仍可完成，没有删除存档数据。

## Task 2：同一张 sheet 的摘要卡片与编辑模式

**用户步骤价值：** 删除“先看只读详情、再进入第二页编辑”的额外导航步骤。

**Files:**

- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify: `SubscriptionManager/Library/EditSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionEditorSections.swift`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Implementation contract:**

- 列表行使用 `sheet(item:)` 打开一个当前订阅的 presentation；不要再从行点击直接 push 到单独编辑页。
- `SubscriptionDetailView` 在同一个 presentation 内持有 `.summary`/`.edit` 两个 UI 模式，不新增持久化实体或第二个 modal。
- `.summary` 使用轻量 key-value 行：左标签、右值；至少显示服务名称、价格/货币、周期、下一次续费，存在时显示类别/套餐/备注。
- 右上角使用系统 toolbar 的“编辑订阅”动作，把模式切换为 `.edit`；不再 push 第二页。
- `.edit` 复用现有 `SubscriptionDraft`、编辑器 sections、Save/Cancel 和 Workspace command；保存仍是原子的。
- 下滑关闭在有未保存修改时遵守 `interactiveDismissDisabled`/现有 dirty-state 语义；不要额外引入导航状态机。

**Focused tests:**

- [x] UI test：点击库行后只出现一个摘要 sheet，能看到服务、金额、货币和下一次续费。
- [x] UI test：点击“编辑订阅”后仍在同一 presentation 内看到编辑字段，系统返回/关闭层级不增加。
- [x] UI test：编辑保存后摘要显示新值；取消不写入变更。
- [x] Keep existing Workspace/editor domain tests green; do not replace them with screenshot-only checks.

**验收：** 用户从“我的订阅”到“看懂一条订阅”与“修改一条订阅”不再被第二页打断。

## Task 3：删除无意义编辑字段并解决网址/来源呈现

**用户步骤价值：** 让编辑卡片只保留能改变订阅事实的字段，避免状态、来源和账单说明占据主流程。

**Files:**

- Modify: `SubscriptionManager/Library/SubscriptionEditorSections.swift`
- Modify: `SubscriptionManager/Library/EditSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Test: relevant editor/domain tests under `SubscriptionManagerTests/` and `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/`

**Implementation contract:**

- 删除编辑页“使用中/Active”可见行；保留内部生命周期派生逻辑和存档状态处理。
- 删除确认订阅界面的“官方定价来源”字段。
- 删除“打开服务商的账单、续订或取消页面”说明；本轮不保留任何用户可见 URL、`Link` 或跳转入口。
- 删除编辑“其他详情”中的订阅管理 URL，并从摘要、新增确认和确认订阅 UI 中移除所有 URL 文本和链接控件。
- 删除 `AddSubscriptionView` 中“官方价格可能因地区、税费和 storefront 而异”的主体说明；不把它挪成新的信息块或额外页面。
- 保留类别、备注等可选元数据，并确保它们不阻塞保存。
- 内部 catalog `sourceURL`、`verifiedOn` 和 evidence manifest 不删除；这些是审计数据，不是用户确认字段。

**Focused tests:**

- [x] UI test：编辑页不存在“使用中”“官方定价来源”“打开服务商账单”等旧文案。
- [x] UI test：摘要、编辑、新增确认和确认订阅 UI 均不存在 URL 文本、`Link` 或服务商跳转入口。
- [x] UI test：新增确认 UI 不显示“官方定价来源”或地区/税费/storefront 说明。
- [x] UI test：类别、备注仍可编辑且为空时仍可保存。

**验收：** 摘要、编辑和确认卡片只展示用户能理解、能修改、能影响订阅管理的内容；所有用户可见网址消失，内部来源仍可审计。

## Task 4：货币入口与三态外观模式

**用户步骤价值：** 删除重复货币入口，让用户可以明确选择实际扣款货币；同时让外观偏好可预测。

**Files:**

- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/UserPreferences.swift`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`（仅在实际模型需要兼容性调整时）
- Modify: `SubscriptionManager/Persistence/SubscriptionRecord.swift`
- Modify: `SubscriptionManager/Persistence/SwiftDataSubscriptionRepository.swift`
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/UserPreferencesTests.swift`
- Test: `SubscriptionManagerTests/AppDependenciesTests.swift`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Implementation contract:**

- 先确认当前 `Currency.allCases` 已是 CNY/USD/EUR；若仍是这三个，只做 UI 清理，不扩大 Currency 枚举。
- 删除目标新增/编辑流中重复的“选择货币”层或 `Primary Currency` 展示行；实际订阅编辑只保留三个货币选项。
- 增加可持久化 `AppearanceMode` 三态：`.system`、`.light`、`.dark`；默认 `.system`，旧数据迁移到默认值。
- 在 app 根 presentation 应用 `preferredColorScheme(nil/.light/.dark)`；system 不强制覆盖系统。
- 日历、摘要 sheet、编辑 sheet、洞察和导航栏共享同一外观设置；不分别设置一套颜色。

**Focused tests:**

- [x] Domain test：三态外观偏好可编码、读取、迁移，默认跟随系统。
- [x] Persistence test：保存 `.dark`、`.light`、`.system` 后重建 repository 仍读取同值；旧记录缺字段回落 `.system`。
- [x] Domain/UI test：实际扣款货币仍单独保存，只有 CNY/USD/EUR 可选。
- [x] UI test：切换日间/夜间/跟随系统后重启仍保持选择；未出现固定色导致的低对比文本。

**Focused commands:**

```sh
swift test --package-path Packages/SubscriptionCore --filter UserPreferencesTests
xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -derivedDataPath /private/tmp/subscription-manager-r3-derived \
  -only-testing:SubscriptionManagerTests/AppDependenciesTests
xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -derivedDataPath /private/tmp/subscription-manager-r3-derived \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testAppearanceModePersistsAndFollowsSystem
```

Expected: preference encoding/decoding, repository migration and the three UI choices pass; if the documented simulator is unavailable, record the environment limitation rather than substituting a different product test.

**验收：** 货币和外观都是一次明确选择，不产生第二层无意义设置。

## Task 5：Upcoming 月历边界与圆角呈现诊断

**用户步骤价值：** 让用户能稳定读日期和扣费，不再被贴边数字、异步直角闪现和过重卡片干扰。

**Files:**

- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Library/CalendarProjectionView.swift`（仅当预览/导入表面共享同一问题）
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/UpcomingCalendarProjectionTests.swift`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Research gate:**

- [x] 已使用 Apple [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[HIG Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[Presentation modifiers](https://developer.apple.com/documentation/SwiftUI/View-Presentation) 和 `UICalendarView`/`DatePicker` 官方资料确认系统能力。
- [x] 已记录“Apple 没有规定固定 iOS 27 inset、圆角、sheet 高度”的结论；实际数字只能定义为项目实现值，不写成官方标准。

**Implementation contract:**

- 先用 `rg` 审计 `.cornerRadius`、`RoundedRectangle`、`.clipShape`、`.background`、`.presentationBackground` 和加载/错误状态分支，定位直角闪现的具体链路。
- 保持当前月历+选中日议程投影，不把 EventKit 变成源数据，不新建日历仓库。
- 让 `UICalendarView` 的外层内容、系统安全区、月历宽度和选中日议程拥有稳定 padding；不让日期数字越界。
- 使用少量连续圆角容器；优先接受 `Form`/`List`/系统 sheet 的原生形状，不给每一行叠自定义卡片。

**Focused tests/inspection:**

- [x] Domain tests 保持月历投影、选中日和多月边界通过。
- [x] UI test 确认月历、选中日期、议程和扣费标记可达且有稳定 accessibility identifiers。
- [x] 在目标 iPhone 与 iPad、Dynamic Type、浅色/深色下做一次人工视觉检查；记录一个明确问题到一个明确修复，不增加截图回归框架。

**验收：** 日历数字不贴边、不裁切，状态条和 sheet 不先直角后圆角，视觉修复没有扩大成全局设计系统。

## Task 6：稳定类别并完成重新分类

**用户步骤价值：** 用户按“类别”浏览目录时看到的是可理解的分类，ChatGPT 等 AI 服务不会再出现在错误的效率分类。

**Files:**

- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`
- Modify: `SubscriptionManager/Resources/catalog-v1.json`
- Modify: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift`
- Test: `SubscriptionManagerTests/CatalogOfferSelectionTests.swift`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Implementation contract:**

- 让类别拥有稳定 ID 和本地化标题；不要再只从英文显示文字动态推导身份。
- 保留向旧 catalog JSON 解码的兼容路径，迁移缺少 ID 的旧 preset 时使用现有规范化值作为一次性 fallback。
- 将 ChatGPT 及经审计的 AI 服务迁移到 `ai`；重新检查所有现有 preset 的类别，输出迁移前/后数量和未决列表。
- 将用户可见筛选文案统一为“类别/Categories”；不新增无法解释的类别。
- 类别迁移只改分类事实，不改价格、周期、服务身份或用户已有订阅的实际扣款事实。

**Focused tests:**

- [x] Catalog test：旧 JSON 可解码，显式 stable category ID 能 round-trip。
- [x] Catalog test：中文/英文类别过滤仍按稳定 ID 工作，ChatGPT 命中 AI 不命中 Productivity。
- [x] UI test：分类文案为“类别”，目录筛选结果与当前 locale 一致。

**验收：** 类别身份稳定、翻译一致、迁移可追溯，用户不会因改标签而丢失订阅。

## Task 7：目录变体、证据和价格分批审计

**用户步骤价值：** 用户选择的套餐、价格和续费周期是真实可解释的，而不是一个把多个商品混在一起的猜测值。

**Files:**

- Modify: `SubscriptionManager/Resources/catalog-v1.json`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`（只添加审计证明需要的最小字段）
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift`
- Modify: `SubscriptionManagerTests/CatalogOfferSelectionTests.swift`
- Modify: `Packages/SubscriptionCore/Sources/CatalogValidator/main.swift`
- Read/Update evidence: `docs/research/evidence/official-catalog.jsonl`、`docs/research/evidence/competitive-community.jsonl`、`docs/research/2026-08-01-round-2-manifest-validation.md`
- Create/Update audit manifest: `docs/research/evidence/2026-08-02-round-3-catalog-audit.jsonl`

**Delegation boundary:**

- Agent A：只读本地 inventory，按 preset → offer → market → channel → interval 列出重复/缺字段项。
- Agent B：只审百度网盘 VIP/SVIP/SVIP10/扩容；输出 verified/conflict/unresolved/not checked，不改 catalog。
- Agent C：只审 Claude/ChatGPT/Google AI/Perplexity/Cursor/Copilot 等第一批 AI；不把候选直接标 verified。
- Agent E：只审 Midjourney/Canva/Runway/HeyGen/Suno；分别输出 verified/conflict/unresolved/not checked，不把候选直接标 verified。
- Agent D：只检查标准续费与年/月周期冲突；不把月价乘 12。
- 主 agent 负责整合、拒绝越界结果、写入 catalog 和测试；subagent 的 `changed:true` 或口头结论不是持久化证明。

**Audit manifest contract:**

- 每一行 JSON 代表一个本轮审计对象，至少包含 `batch`、`service`、`plan`/`variant`、`market`、`purchaseChannel`、`status` 和 `evidenceIDs`；`status` 只能是 `verified`、`conflict`、`unresolved` 或 `not_checked`。
- `verified` 必须同时有固定金额、币种、周期、标准续费语义、市场/渠道和至少一个 evidence ID；动态价格、登录态价格、促销或资格价不能进入 `verified`。
- `unresolved`/`not_checked` 可以记录候选和缺口，但不写入运行时 selectable catalog；该 manifest 是审计事实，不是用户 UI 数据。
- 主 agent 只在复核证据后写入 manifest；subagent 的外部搜索结果不能直接成为 catalog 或 manifest 的 verified 记录。

**Implementation contract:**

- 先从当前 93 presets/192 offers 导出去重清单，分批处理，不声称一次完成 192 条。
- 当前目录事实必须先写入审计结果：`chatgpt` 仍标为 Productivity，需要迁移到 AI；`baidu-netdisk` 目前只有一个 CN/iOS、CNY 25/月的 SVIP offer；`claude` 已有 Pro 月付/年付、Max 5x 月付、Max 20x 月付四个主要 offer。
- 百度至少审计 VIP、SVIP、SVIP10/等级或直升商品、空间扩容和套餐；没有稳定固定金额的条目保持 `unresolved`/审计待核验，不创建无价格的可选 shell，也不把第三方卡密或促销价当标准续费。
- Claude 的标准基线固定为 Pro 20 USD/月、Pro 年付 200 USD/年、Max 5x 100 USD/月、Max 20x 200 USD/月；不加入 Max 20x 240 USD/月。若用户实际订单是 240 USD，只作为实际订阅记录金额，不改标准目录 offer。
- 月付、年付、自动续费、年卡/激活码、首月促销和资格价使用独立语义；不把促销写进标准续费字段。
- 先复用现有 `planName`、`market`、`purchaseChannel`、`billingInterval`、`price`、`reviewStatus`、`sourceURL` 和 `verifiedOn`；只有 validator/选择器无法表达本轮真实冲突时，才增加一个最小字段，并同步旧 JSON 兼容测试。
- validator 需要报告证据缺失、冲突、动态价格、变体重复和标准续费语义缺失；不得为填数量而把待核验条目标成 verified。
- 官方来源是首选；社区/搜索来源可作为候选和冲突证据，但不足以单独把高波动价格标为 verified，除非现有证据政策明确允许且记录市场/渠道/日期。

**Focused tests:**

- [x] Catalog test：现有 `CatalogOffer`/旧 JSON 兼容路径保持通过；本轮不增加未证明的运行时审计字段。
- [x] Catalog test：review-required offer 不进入 selectable verified offers；SubscriptionCore 回归覆盖该边界。
- [x] Selection test：`CatalogOfferSelectionTests` 8/8，通过 review status 过滤和周期排序。
- [x] Validator test/command：输出目录 offer 统计和每批 verified/conflict/unresolved/not checked 计数；verified 行强制证据、金额、币种、周期和续费语义。

**Focused commands:**

```sh
jq -e . SubscriptionManager/Resources/catalog-v1.json
swift run --package-path Packages/SubscriptionCore --scratch-path \
  /private/tmp/subscription-manager-task7-review-fix CatalogValidator \
  SubscriptionManager/Resources/catalog-v1.json \
  docs/research/evidence/2026-08-02-round-3-catalog-audit.jsonl
jq -s -e 'all(.[]; (.batch | type == "string") and (.status | IN("verified", "conflict", "unresolved", "not_checked")) and (.evidenceIDs | type == "array"))' \
  docs/research/evidence/2026-08-02-round-3-catalog-audit.jsonl
jq -s 'group_by(.batch)[] | {batch: .[0].batch, verified: (map(select(.status == "verified")) | length), conflict: (map(select(.status == "conflict")) | length), unresolved: (map(select(.status == "unresolved")) | length), not_checked: (map(select(.status == "not_checked")) | length)}' \
  docs/research/evidence/2026-08-02-round-3-catalog-audit.jsonl
swift test --package-path Packages/SubscriptionCore --filter CatalogTests
xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -derivedDataPath /private/tmp/subscription-manager-r3-derived \
  -only-testing:SubscriptionManagerTests/CatalogOfferSelectionTests
```

Expected: JSON, validator, model tests and offer-selection tests pass; each audit batch has explicit four-state counts, and no batch with missing fixed price becomes selectable.

**验收：** 已通过 JSON/manifest/validator/focused tests；目录审计明确区分已核验、冲突、未解决和未检查项，不用猜测补齐空白。详见 `.superpowers/sdd/task-7-report.md`。

## Task 8：整体验收与目标反查

**用户步骤价值：** 确保最终版本同时满足目标文档和实际手机操作，而不是只通过单元测试。

**当前状态：** complete。Phase 2 full UI gate 已有效通过；真实 exchange-rate cache timestamp 仍是未观察到的 fixture/evidence boundary，不伪造时间戳，也不作为未完成的产品功能。

**Files:**

- Read: `docs/research/2026-08-02-round-3-product-goal.md`
- Read/Update: this plan's task checkboxes and coverage matrix
- Test: all focused tests above, then relevant full test suites
- Build/install: existing documented local Personal Team signing path only when a code change requires a new device build

**Verification order:**

- [x] 每个任务先运行对应 focused test，确认通过后再进入下一任务。
- [x] 对每个 requirement 记录对应 focused command 的结果；不得用一个全量命令替代所有 requirement 证据。
- [x] 运行完整 `SubscriptionCore`/应用测试；Phase 2 UI target 已产生可解析的全量 xcresult：`SubscriptionManagerUITests` 71 tests / 70 passed / 0 failed / 1 expected iPad-only skipped，聚合 207 / 206 / 0 / 1。
- [x] 重新构建 simulator；本轮最终生产修正后的 XcodeBuildMCP build/run 已通过。个人设备签名安装不在本轮授权范围内。
- [x] 人工走一条最小主流程：我的订阅 → 摘要卡片 → 编辑 → 保存 → 返回摘要；再走加号 → 浏览目录/手动添加和列表左滑存档。
- [x] 人工检查 Upcoming 月历/议程、洞察的圆角不可用状态、日间/夜间/跟随系统入口、Dynamic Type 和 iPad 宽度；交换率更新时间条因该 UI 测试存储没有汇率缓存，当前显示系统不可用态，未伪造更新时间证据。
- [x] 用下面的 R3 覆盖矩阵逐条标记 code/test/UI evidence；真实 exchange-rate cache timestamp 作为明确的 fixture/evidence boundary 记录，不伪造且不阻塞已完成的 Task 8。
- [x] 未执行 commit/push；只有用户明确授权后才允许执行，本计划本身不提交。

**当前执行记录：**

- [x] Task 7 审查修复：Google AI Plus/Pro、QQ 绿钻、微信读书连续包月/月卡的证据映射已校正；微信年卡、百度和 Canva 两项仍为 `reviewRequired`。
- [x] Task 7 当前目录统计：`catalogVersion=11`、93 presets、192 offers、188 selectable、4 `reviewRequired`；manifest 35 行，五批次状态计数已写入报告。
- [x] 完整 `SubscriptionCore` 回归：185/185。
- [x] 应用单元测试：136/136；目录 focused selection 测试 8/8。
- [x] JSON、manifest、validator 和 `git diff --check` 已通过。
- [x] 已确认安装包存在且可直接启动：`xcrun simctl listapps` 找到 `com.klausc06.SubscriptionManager`，`simctl launch` 返回进程；本地截图 `/private/tmp/subscription-manager-task8-library.png` 显示的是首次设置页，只证明启动和 CNY/USD/EUR 入口存在，不作为主流程视觉验收证据。
- [x] Task 8 追加修复：实机截图发现 `accessibility-extra-extra-extra-large` 下订阅行横向挤压；仅在 `SubscriptionRow.swift` 增加原生动态字体垂直重排，正常字号分支保持不变。两次独立 code review 均 APPROVED，最终构建成功。
- [x] 最终 iPhone focused 摘要测试：1/1，xcresult `/private/tmp/subscription-manager-20260803-final-ui-focused.xcresult`；iPad Air 11-inch 自适应侧栏测试：1/1，xcresult `/private/tmp/subscription-manager-20260803-ipad-ui.xcresult`。
- [x] 本地设备视觉检查：标准字号主库 `/private/tmp/subscription-manager-20260803-library-final.png`、超大动态字体 `/private/tmp/subscription-manager-20260803-library-accessibility-final.png`、iPad 宽屏 `/private/tmp/subscription-manager-20260803-ipad-library.png`；深色标准字号检查 `/private/tmp/subscription-manager-20260803-library-dark.png`。动态字号下服务名/金额保持主色且不再横向断裂，套餐/日期保持次级色。
- [x] XcodeBuildMCP iPhone 17 Pro / iOS 27.0 主流程人工验收：同一 sheet 内完成列表行 → 摘要卡片 → 编辑 → 保存 → 摘要；右上角加号 → 浏览目录 → 目录内手动添加；在日期校验提示后选择有效的 2026-09-03 续费日并保存新订阅；再次编辑该新订阅并将金额从 `$12.30` 改为 `$13.30`，保存后列表立即显示新值；Upcoming 显示 2026 年 8 月月历、议程和确认扣费行；列表左滑显示 `Archive`，归档后该行从当前库消失。目录货币弹出层现场只显示 `CNY`、`USD`、`EUR`，设置现场显示 `System`、`Light`、`Dark` 三态。
- [x] 主流程验收中的数据边界记录：seeded `Direct Editor Fixture` 的 `2026-07-02` 起始日、月付周期和 `2026-10-02` 下一续费日彼此不一致，编辑保存正确显示“Choose a billing date.”并保留编辑态；这属于测试 fixture 的日期事实不一致，不作为产品保存路径失败。新建且日期有效的手动订阅已完成真实创建/编辑保存验证。
- [x] UI 全量回归：历史 pre-Phase-2 记录包括此前全量 runner 在启动阶段 signal kill、shell 重试在 211 秒停在 `IDELaunchiPhoneSimulatorLauncher`/`waiting for workers to materialize`，以及后续 partial xcresult 缺少 `Info.plist` 的情况。历史记录中的 `testArchivesAndRestoresSubscription` 与 `testCatalogRenameClearsStaleIdentityWhilePriceOverrideRetainsIt` 失败已按当时证据保留，并未自动归因于产品或测试；归档返回导航、目录重命名后续编辑和目录编辑 helper 的 focused 修正也已保留。针对修正后的 focused 用例，旧 runner 曾在 bootstrapping 前以 `signal kill` 退出，shell 也报告 CoreSimulatorService/simdiskimaged connection invalid，未产生可解析结果。该历史状态已由下方 Phase 2 有效 full run supersede，不再作为当前 blocker。
- [x] Phase 2 最终 full UI gate：仅一轮 ReleaseGate XcodeBuildMCP、无 `only-testing` selector、`-parallel-testing-enabled NO`、`-maximum-parallel-testing-workers 1`；`SubscriptionManagerUITests` 71 tests / 70 passed / 0 failed / 1 expected iPad-only skipped，聚合 207 / 206 / 0 / 1，`TEST EXECUTE SUCCEEDED`。log：`/Users/klaus/Library/Developer/XcodeBuildMCP/workspaces/subscription-manager-task8-luna-recovery-2c24e1642bb2/logs/test_sim_2026-08-02T21-45-59-389Z_pid53016_d060fef2.log`；xcresult：`/Users/klaus/Library/Developer/XcodeBuildMCP/workspaces/subscription-manager-task8-luna-recovery-2c24e1642bb2/result-bundles/test_sim_2026-08-02T21-45-59-390Z_pid53016_40dcd1c1.xcresult`，含 `Info.plist` 且可由 `xcresulttool` 解析。

### 最新 Task 8 复核（2026-08-03）

- [x] 生产修正：`SubscriptionManager/Library/LibraryView.swift` 的订阅列表行补齐了整行点击区域。现场点击目录保存后的订阅行中间空白区域现在能打开 summary 卡片；这直接修复了用户主入口，不增加额外产品功能。
- [x] 修正后的 focused UI：`testCatalogRenameClearsStaleIdentityWhilePriceOverrideRetainsIt` 1/1；`testArchivesAndRestoresSubscription` 1/1。两项均在 XcodeBuildMCP 的 ReleaseGate iOS 27 模拟器上真实执行并生成结果包。
- [x] 同一修正后的 simulator build 通过；`git diff --check` 通过。
- [x] 历史 pre-Phase-2 记录：单并发 XcodeBuildMCP runner 曾在前 5 个 UI 用例通过后达到工具 300 秒上限，结果包缺少 `Info.plist`；`testPermanentDeleteRequiresConfirmation` 的独立运行曾在 XCTest bootstrap 前被 `signal kill`，没有产品级测试结论。该历史记录不再代表当前 full UI 状态。
- [x] 历史 pre-Phase-2 记录：shell 全量调用曾遭遇 CoreSimulatorService/simdiskimaged 断连及宿主缓存诊断权限错误，6 个主流程 UI 用例批次也曾在 XCTest bootstrap 前被 `signal kill`；这些无效重试已停止，不构成当前产品结论。
- [x] 汇率“更新于”真实缓存态未在当前 UI 测试存储中出现；已按证据边界保留无缓存时的圆角不可用态，不伪造更新时间；该边界不阻塞已完成的 Task 8。

**最新交叉核对结论：** 12 个目标均有计划任务和实现/专项证据；本轮新增的整行点击修正已由手动运行与两个 focused UI 用例覆盖。Phase 2 full UI gate 已形成可解析的有效 xcresult 并通过：`SubscriptionManagerUITests` 71 / 70 / 0 / 1，聚合 207 / 206 / 0 / 1。唯一保留的边界是当前 UI fixture 没有真实 exchange-rate cache timestamp；不得伪造该证据，也不新增产品功能来绕过它；未授权 commit/push 仍不执行。

### 最终目标—计划—证据交叉核对（2026-08-02）

| 目标 | 计划任务 | 当前证据判断 |
| --- | --- | --- |
| R3-01～R3-06 | Task 1～4、Task 6 | 实现与对应 focused UI/domain 测试已通过；专项报告分别记录了顶部、加号、同 sheet 编辑、字段清理、三种货币和类别迁移。Phase 2 full UI gate 已通过。 |
| R3-07～R3-08 | Task 5 + Task 8 follow-up | `UpcomingCalendarProjectionTests` 1/1、专项 UI 1/1、iPhone Upcoming 月历/议程人工操作和代码定位/修复已通过；标准/深色/超大动态字体及 iPad 主库截图已检查。Insights 无缓存时的圆角不可用态已现场检查；交换率更新时间条仍缺少真实缓存态证据。 |
| R3-09 | Task 4 | `AppearanceMode` 三态持久化、迁移、根级继承和重启 UI probe 已通过；本轮没有额外声称人工视觉全覆盖。 |
| R3-10 | Task 6 | 稳定类别 ID、ChatGPT → AI、93 presets/192 offers 保持、目录过滤专项测试已通过。 |
| R3-11 | Task 7 | 目录 validator 和审计 manifest 已通过：version 11、93 presets、192 offers、188 selectable、4 `reviewRequired`；未核验或有冲突的价格没有被伪装成可选项。 |
| R3-12 | Task 3、Task 7 | 用户可见来源/网址/账单说明清理和目录证据边界均有专项 UI、单元测试及 manifest 证据；Phase 2 full UI gate 已形成有效结果并通过。 |

**交叉核对结论（历史记录）：** 目标文档中的 12 个需求均已在计划矩阵中有对应任务；当时已有实现、域行为、专项 UI、设备截图和 XcodeBuildMCP 主流程证据覆盖了摘要/编辑/保存/加号/左滑/Upcoming。该时点的 focused/full UI 受模拟器服务阻断，故未标记完成；后续最新复核见上方“最新 Task 8 复核”，不再把旧 runner 失败当作当前状态。真实汇率更新时间条仍需保留无缓存边界。后续只应补齐已有验收缺口，不应新增产品功能。

**Concrete integration commands:**

```sh
swift test --package-path Packages/SubscriptionCore
jq -e . SubscriptionManager/Resources/catalog-v1.json
jq -e . SubscriptionManager/Resources/Localizable.xcstrings
xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -derivedDataPath /private/tmp/subscription-manager-r3-derived
git diff --check
```

Expected: focused checks, full core tests, application unit tests, JSON checks and diff hygiene pass; the UI target is only complete when a valid full xcresult is produced with no unexplained failures. Any simulator, runner or signing limitation is reported separately from code failures.

## R3 目标—计划覆盖矩阵

| 目标 | 计划任务 | 必须证明的结果 |
| --- | --- | --- |
| R3-01 货币极简 | Task 4 | 只有 CNY/USD/EUR；重复“选择货币”入口消失 |
| R3-02 删除使用中 | Task 3 | 编辑 UI 无状态行；生命周期/存档仍正确 |
| R3-03 同卡片查看/编辑 | Task 2 | 一个 sheet 内摘要与编辑切换，无第二页/第二 modal |
| R3-04 删除网址 | Task 0 + Task 3 | 摘要、编辑、新增确认和确认订阅 UI 均无 URL、`Link`、管理/账单跳转；内部证据保留 |
| R3-05 顶部导航/存档 | Task 1 | 齿轮—我的订阅—加号；顶部无存档；左滑存档可用 |
| R3-06 新增入口/类别文案 | Task 1 + Task 6 | 加号承载手动添加；目录顶部；文案为“类别” |
| R3-07 日历边界 | Task 5 | 日期数字、月历、议程不贴边/裁切 |
| R3-08 圆角逻辑 | Task 5 | 不再出现直角闪现；没有全局卡片泛滥 |
| R3-09 外观三态 | Task 4 | 日间/夜间/跟随系统持久化并统一生效 |
| R3-10 类别审计 | Task 6 | 稳定 ID；ChatGPT 在 AI；所有 preset 有迁移结论 |
| R3-11 套餐/价格审计 | Task 7 | 变体、周期、市场和证据可区分；未核验项不进入 verified |
| R3-12 确认 UI 清理 | Task 3 + Task 7 | 用户 UI 精简；内部证据保留；价格仍可审计 |

## 计划自检

- 覆盖检查：R3-01 至 R3-12 全部在目标文档和本计划中出现，并在矩阵中有任务和证据要求。
- 范围检查：没有加入云同步、通知、账务、推荐、第三方组件或新的产品目标。
- 证据检查：Apple 来源只支持 API/HIG 原则；固定间距/圆角需要运行时验证；价格仍按市场/渠道/周期核验。
- 冲突检查：网址要求已按用户明确指令统一为全部用户可见网址删除；Claude 240 美元已按官方标准价与实际扣款语义分离，不再是决策门。
- 研究检查：Apple API/HIG、Claude 标准价格、百度网盘变体边界和当前目录中的 ChatGPT/Baidu/Claude 状态均已写入计划；动态或缺证据价格留在待核验队列。
- 完成检查（已履行）：文档调整阶段不改代码、不改 catalog、不跑实现构建、不 commit、不 push；计划审核、分阶段实现和最终逐条验收均已完成。

## 执行前置条件（历史，已履行）

1. [已完成] 独立 plan reviewer 已审核 `docs/research/2026-08-02-round-3-product-goal.md` 与本计划，确认没有遗漏、范围膨胀或不可执行任务。
2. [已完成] 计划审核通过后，已按本计划的独立边界执行；任何 subagent 输出均由主 agent review 后落盘。
3. [已完成] 每个实现任务均先运行对应 focused test，再进入下一个任务；全部完成后已逐条对照 goal 验收。
