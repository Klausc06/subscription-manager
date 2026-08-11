# Expo Hybrid Rebuild — First Phase Tickets

## Date
2026-08-11

## Phase goal
在不砍功能的前提下，把 Expo 重建从“雾区”变成可验证的工程骨架：UI 能跑、领域接口对齐、存储/同步/系统能力以模块方式接回（保持现有原生仓库作为行为 oracle）。

## Ticket 1 — Expo app skeleton + bilingual UI shell
**Deliverable**
- 一个可运行的 Expo RN App（TypeScript、i18n：EN + zh-Hans、theme：system/light/dark），具备导航与主页面占位：
  - Library（我的订阅）列表与一条订阅摘要卡片布局
  - Add / Edit flow 入口占位（表单字段按领域最小可保存事实）
  - Upcoming 占位（month/day 视图容器）
  - Settings（包含 iCloud/sync 状态行占位）

**Acceptance criteria**
- `npm run` / `npx expo start` 能启动并在 iOS Simulator 正常渲染页面
- 基础 i18n 字段正确切换（至少覆盖 Library / Add / Upcoming / Settings / Edit）
- 不在 RN 层引入订阅事实的第二数据源（所有状态通过“领域 Workspace 接口”注入/占位）

## Ticket 2 — Domain Workspace port: Commands/Queries contract
**Deliverable**
- 在 Expo 项目内实现 `Workspace` 的接口层（TS 或最小等价形式），对齐 `SubscriptionCore` 的核心边界：
  - 最小可保存订阅事实：serviceName、amount、currency（CNY/USD/EUR）、Fixed Billing Schedule + Start Date + Confirmed Next Renewal
  - 生命周期动作：pin / archive / restore / record cancellation / reactivate / delete
  - 查询：library list + subscription summary + upcoming projection接口形状

**Acceptance criteria**
- 至少 3 个领域单元测试覆盖（add->summary、pin->ordering、schedule date projection 的接口一致性）
- 所有 UI 通过 Workspace 接口交互，UI 不直接操作持久化/CloudKit/EventKit

## Ticket 3 — Adapter contracts: Persistence + Catalog + FX (no-op / in-memory)
**Deliverable**
- 定义 adapter contract（interfaces/types）并提供：
  - Persistence：in-memory 实现（用于 UI 骨架验证）
  - Catalog：先用 bundled catalog JSON 直读的最小实现（或先接现有 bundle）
  - FX：先用固定值/缓存接口的 stub（只要接口存在，后续替换）

**Acceptance criteria**
- Ticket 1 的 UI 在“in-memory persistence + bundled catalog + fx stub”下能完成：
  - 添加一条订阅并在列表中显示
  - 进入编辑并保存，返回摘要卡片仍一致

## Ticket 4 — Private iCloud sync status module (monitor + status row)
**Deliverable**
- 实现同步状态监视的模块化接口（native later, but contract now）：
  - `LibrarySyncMonitor`：提供 account availability + sync progress 状态（localOnly/synchronizing/current/signedOut/requiresAttention）
  - Settings 里展示同步状态行（EN + zh-Hans，VoiceOver 对应可访问性元信息按原生风格）

**Acceptance criteria**
- 在 UI 里能切换 monitor 的模拟状态（deterministic fake）并立即刷新状态行
- 任一本地编辑都不等待 CloudKit 网络完成（“成功的本地编辑立即返回”语义在状态机上体现）

## Ticket 5 — Vertical slice parity gate (behavior oracle mapping)
**Deliverable**
- 写一份“对齐清单”，明确每个 UI/领域行为对应原生 oracle 的代码路径/测试：
  - SubscriptionCore workspace commands（对应行为）
  - Library summary rendering 的字段映射
  - Upcoming projection 的 date ordering / month/day 规则

**Acceptance criteria**
- 清单里列出至少 8 个 mapping 项，并每项给出：
  - 原生证据路径（repo 文件）
  - 预期行为（非实现细节）
  - 当前完成程度（UNVERIFIED / VERIFIED）

