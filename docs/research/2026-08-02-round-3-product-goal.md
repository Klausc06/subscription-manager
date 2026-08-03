# SubscriptionManager Round 3 产品目标

**日期：** 2026-08-02
**状态：** 调研与计划审核已完成；Tasks 0–8 已完成。动态字体修复、设备视觉检查、XcodeBuildMCP 主流程人工验收和最终 focused UI 均已完成；Phase 2 full UI gate 有效通过：`SubscriptionManagerUITests` 71 tests / 70 passed / 0 failed / 1 expected iPad-only skipped，聚合 207 / 206 / 0 / 1，`TEST EXECUTE SUCCEEDED`。真实汇率缓存时间戳仍未在当前 UI 测试存储中出现，继续作为诚实的 fixture/evidence boundary，不伪造；本文件本身不授权提交或推送
**基线：** `3a221bb feat: complete subscription catalog and upcoming calendar`
**适用范围：** iOS 27.0 主流程；macOS 只保持现有架构和行为不被无意破坏

## 一句话目标

用户点进一条订阅后，应当马上、清楚、漂亮地看到：订阅了什么、实际花了多少钱、使用什么货币、下一次大概什么时候续费；编辑这些事实时只需要在当前卡片中完成，不被多余页面、无意义字段或错误目录数据打断。

## 产品判断顺序

1. 先让“看懂一条订阅”和“修改一条订阅”变得直接。
2. 再让新增订阅、目录分类、价格和续费日期可信。
3. 最后做视觉统一；视觉修正不能牺牲可读性、系统行为或数据正确性。

本轮不追求更多功能数量，不增加与订阅管理无关的页面、服务或复杂状态。

## 硬约束

- Subscription Library 是订阅事实的来源；Upcoming 日历只是投影，不反过来成为数据源。
- 保留 `SubscriptionWorkspace`、现有本地 SwiftData 和现有目录/证据边界；不引入第二个仓库、第三方日历、第三方搜索或新的全局状态框架。
- 订阅最小可保存事实仍是：服务名称、价格、实际扣款货币、固定账单周期、产生真实计划所需的账单日期。
- 套餐、类别、管理网址和备注是可选元数据；本轮所有用户可见网址都删除，但不为了满足 UI 而删除域层兼容字段、目录证据或生命周期事实。
- 目录价格必须区分市场、币种、渠道、周期、标准续费和促销/资格条件；没有证据的价格不能成为可选套餐。
- 不猜价格、不把促销价当标准续费价、不把月价乘 12 当年价、不把不同地区/渠道合并成一个套餐。
- 使用官方 API/HIG 或可复现的公开方案；“看起来像 iOS 27”不能写成 Apple 的版本标准。
- 本轮只写目标和计划；实现前需要用户审阅这两份文档。实现期间按一个需求一个需求推进。

## 目标需求

### R3-01：货币选择保持极简

**用户目标：** 在订阅编辑的“货币”字段中只看到 `CNY`、`USD`、`EUR`；删除上方没有意义的“选择货币”入口/标题。

**完成标准：**

- 订阅实际扣款货币的可选项只有 CNY、USD、EUR。
- 订阅编辑页不再出现重复的“选择货币”入口或一层没有行为价值的货币页面。
- 不把实际扣款货币和洞察/显示货币混为一谈；如果现有全局主货币设置不再面向用户展示，内部数据仍不能被静默改写。

### R3-02：编辑订阅中删除“使用中”状态字段

**用户目标：** 编辑订阅时不再看到没有帮助的“使用中”状态行。

**完成标准：**

- 编辑表单不显示“使用中”/Active 这类普通状态选择或只读行。
- 生命周期计算、存档可见性和续费投影所需的内部事实继续正确工作。
- 不把“删除一个 UI 字段”扩大成删除生命周期模型或重做状态系统。

### R3-03：一张订阅卡片完成查看与编辑

**用户目标：** 点击“我的订阅”中的一条订阅后，弹出一张简洁的卡片；左侧是项目名称，右侧是对应值；右上角有“编辑订阅”。点击后，卡片在原地变成当前编辑样式，而不是再进入一个第二页。

**完成标准：**

- 列表行点击后只打开一个当前订阅的卡片/底部 sheet。
- 摘要优先展示服务名称、实际价格与货币、账单周期、下一次续费；有值的类别、套餐和备注可按同一套 key-value 结构展示。
- 标签左对齐、值右对齐，层级少，信息密度高但不堆叠成多页。
- 卡片右上角的编辑动作在同一个 presentation 内切换到编辑表单；不再 push 一个新的编辑页面，也不再叠加第二个 modal。
- 编辑保存后数据回到同一订阅摘要；取消和下滑关闭遵守未保存变更规则。

### R3-04：删除所有用户可见网址

**用户目标：** 网址对订阅管理主流程没有价值；摘要卡片、编辑卡片、新增/确认流程和账单说明中全部不显示网址。

**完成标准：**

- 摘要、编辑、目录新增确认和订阅确认 UI 中不出现 URL 文本、`Link`、订阅管理网址输入或打开服务商账单/续订/取消页面的入口。
- 不创建任何“访问服务商网站”的替代入口；用户可见信息只聚焦服务、套餐、金额、货币、周期、类别、备注和下一次续费。
- 目录 `sourceURL`、preset `managementURL`、核验日期和 evidence manifest 继续作为内部研究/兼容数据保留，但不进入任何用户主流程。

### R3-05：顶部导航只保留真正的主操作

**用户目标：** “我的订阅”在顶部中间；左边是齿轮，右边只保留加号；顶部不再放存档图标。

**完成标准：**

- 订阅库标题使用系统导航栏的居中/inline 位置，文案为“我的订阅”。
- 左侧保留设置入口，右侧只保留新增入口。
- 顶部存档按钮/图标移除。
- 存档数据、恢复能力和查询范围不删除；当前库中的存档动作通过列表行从 trailing edge 左滑完成，并保留必要的确认/撤销语义。

### R3-06：新增入口不再单独占一行

**用户目标：** 删除“手动添加”这一行；手动添加逻辑放进右上角加号。目录浏览放在新增流程顶部中央；“所有类别”改成“类别”。

**完成标准：**

- 目录浏览页面顶部中央显示“浏览目录”。
- 类别过滤器显示“类别”，不显示“所有类别”。
- 目录列表中不再有独立的“手动添加”大行。
- 点击右上角加号后仍能选择目录服务或进入手动添加；手动录入能力不被删除，只改变入口层级。

### R3-07：Upcoming 日历重新做视觉边界

**用户目标：** 日历不再贴边，数字不顶到边缘，整体符合系统日历的留白和层级。

**完成标准：**

- 先定位当前 `UICalendarView` 包装、外层容器、安全区和 padding 的真实原因，再改代码。
- 月历、选中态、扣费标记、选中日期议程之间有稳定的内容边界；日期数字不被裁切或贴边。
- 优先使用系统 `UICalendarView`/SwiftUI 原生日期控件和系统环境，不替换成第三方日历。
- 在 iPhone、iPad、动态字体、浅色/深色和不同月份长度下都保持可读。
- 不把某个固定 inset、圆角或高度写成“iOS 27 官方标准”；这些是本项目的设计 token，必须经过运行时检查。

### R3-08：统一圆角与呈现时序

**用户目标：** “汇率更新于……”和其他相关区域不要先显示直角、再突然渲染成圆角；圆角逻辑要稳定。

**完成标准：**

- 先审计 `.background`、`.clipShape`、`RoundedRectangle`、`presentationBackground`、列表/表单系统容器和异步状态切换，找出直角闪现的具体来源。
- 只修复被证实的表面和呈现时序，不建立覆盖全 App 的自定义卡片系统。
- 相关摘要、洞察、sheet 和状态条在初始、加载、成功、错误、浅色、深色状态下保持一致的形状。
- 形状使用系统语义和少量分组容器；不把每一行都变成独立卡片。

### R3-09：提供日间、夜间、跟随系统

**用户目标：** 设置中可以选择“日间模式”“夜间模式”或“跟随系统”。

**完成标准：**

- 设置提供三态且文案清楚：日间模式、夜间模式、跟随系统。
- 跟随系统时不强制覆盖 `ColorScheme`；日间/夜间才在根 presentation 施加偏好。
- 选择在本地持久化，重启后保持；摘要卡片、编辑 sheet、日历、洞察和导航栏使用同一外观策略。
- 颜色使用语义色/材料，保证动态字体和浅色/深色可读性。

### R3-10：重做类别分类

**用户目标：** 所有类别重新审计；ChatGPT 等 AI 服务不再被错误归到“效率工具”，分类要符合用户直觉。

**完成标准：**

- 目录类别使用稳定 ID 和本地化标题，不再只靠英文显示字符串推导身份。
- AI 工具使用独立的 AI 类别；ChatGPT 归入 AI，而不是 Productivity/效率。
- 对现有全部目录 preset 做一次类别审计，记录迁移前后数量和未决条目。
- 类别过滤、搜索、添加确认、用户已有订阅的展示保持一致。
- 不为满足一个例子而无理由新增大量类别；类别集合以可解释、可维护为准。

### R3-11：重新审计订阅服务、套餐、价格和周期

**用户目标：** 目录不能只给一个看似正确的套餐；要覆盖常见 AI 工具和中国区常见服务的实际变体，价格与周期要可核验。

**必须先处理的点：**

- 百度网盘至少单独审计 VIP、SVIP、SVIP10/等级或直升商品、空间扩容；它们不能合并成一个模糊的“百度会员”。
- 扩充常见 AI 候选，包括 ChatGPT、Claude、Google AI、Perplexity、Cursor、GitHub Copilot、Midjourney、Canva、Runway、HeyGen、Suno 等；候选不等于立即可选，必须逐条核验。
- 对所有进入可选目录的 offer 分开核验月付、年付、标准续费、促销、首月、资格价、应用商店价和网页价。
- Claude 的官方基线已经核实：Pro 为 20 USD/月，Pro 年付为 200 USD/年，Max 5x 为 100 USD/月，Max 20x 为 200 USD/月；这些是标准网页订阅价，仍需保留市场/渠道语义。
- 不把 Claude Max 20x 的 240 USD/月写入标准目录；240 只能在有具体订单/发票证据时作为用户实际扣款处理，不能覆盖标准 200 USD/月。

**完成标准：**

- 每一批审计都有 `verified`、`conflict`、`unresolved`、`not checked` 数量。
- 只有具备服务/变体、市场、币种、周期、渠道、标准续费语义、来源和核验日期的 offer 才能进入 verified/可选集合。
- 社区和搜索结果可以帮助发现候选或冲突，但不能把促销或未经确认的数字直接写成标准价格。
- 如果找不到稳定价格，明确告诉用户缺什么证据，不填猜测值。

### R3-12：确认页面只保留用户真正需要的信息

**用户目标：** 确认订阅时不要展示“官方定价来源”和“官方价格可能因地区、税费和购买渠道而异”这类占据主要空间的解释；其他详情只保留类别、备注等必要信息。

**完成标准：**

- 确认订阅 UI 删除“官方定价来源”字段。
- 地区/税费/渠道提示如果仍有必要，移到页面最底部且不打断确认主流程；默认不占据主体信息层级。
- 编辑的“其他详情”只保留类别、备注等必要元数据；管理网址、摘要链接和“打开服务商账单”说明全部删除。
- 目录内部证据、来源 URL、核验日期继续保留在研究/数据层，用于防止错误价格；它们不需要成为用户确认时的主字段。

## 终极验收

对一条已存在的订阅，用户可以在一次清楚的主流程里完成：

1. 看见服务名称、实际花费、货币和下次续费时间。
2. 需要时从同一张卡片进入编辑，不进入无意义的第二页。
3. 修改价格、货币、周期和账单日期，并知道保存结果。
4. 从顶部加号新增目录或手动订阅，从列表左滑存档。
5. 在日历中看懂即将发生的扣费，而不是被贴边和错乱的容器干扰。

## 明确不做

- 不做 iCloud/CloudKit 同步、云端架构或新的跨设备数据层。
- 不增加订阅之外的财务、任务、通知、社交或推荐功能。
- 不引入第三方日历、第三方搜索、TCA/Redux 或新的全局路由/仓库。
- 不把“官方来源”从内部审计证据中删除；只删除不必要的用户可见来源字段。
- 不把所有 192 个 offer 假装一次性审计完；按有界批次输出未检查清单。
- 不用截图、旧记忆或单个社区价格替代可复现的当前证据。
- 不在目标/计划审阅前改代码，不在本轮自动 commit 或 push。

## 本轮研究结论与执行前置

1. **网址决策已确定：** R3-04/R3-12 统一为“删除所有用户可见网址”。没有摘要链接例外，也不保留任何用户可点击的服务商网址；内部 `sourceURL`、`managementURL` 和证据字段只用于审计、兼容和价格核验。
2. **Claude 决策已确定：** 当前官方标准价是 Pro 20 USD/月、Pro 年付 200 USD/年、Max 5x 100 USD/月、Max 20x 200 USD/月；没有证据证明 240 USD/月是标准 Max 20x 目录价，因此目录不得加入 240 USD/月。
3. **百度网盘研究结论：** 官方产品结构至少区分 VIP、SVIP、SVIP10/等级、空间扩容和套餐，但本轮没有为每个变体取得稳定的公开固定金额。没有金额证据的变体只能进入审计待核验清单，不能伪装成可选目录 offer。
4. **AI 审计范围：** Claude、ChatGPT、Google AI/Gemini、Perplexity、Cursor、GitHub Copilot、Midjourney、Canva、Runway、HeyGen、Suno 按服务/套餐/市场/渠道/周期分批核验；动态、登录态或地区价格保持待核验，不用旧价格填充。
5. **执行前置（历史，已履行）：** 以上是调研已解决的事实，不再构成需要用户回答的决策门；独立审核计划已审核通过，且已按计划完成 Tasks 0–8。审核后实现的执行前置已结束，不额外扩大产品范围。

## 研究基础

- 本地基线：`docs/research/2026-08-01-round-2-synthesis.md`、`docs/research/2026-08-01-round-2-manifest-validation.md`、`docs/adr/0001-subscription-workspace-boundaries.md`。
- Apple： [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[HIG Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[sheet(item:)](https://developer.apple.com/documentation/swiftui/view/sheet%28item%3Aondismiss%3Acontent%3A%29)、[presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents%28_%3A%29)、[swipeActions](https://developer.apple.com/documentation/swiftui/view/swipeactions%28edge%3Aallowsfullswipe%3Acontent%3A%29)、[preferredColorScheme](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme%28_%3A%29)、[UICalendarView](https://developer.apple.com/documentation/uikit/uicalendarview)、[RoundedRectangle](https://developer.apple.com/documentation/swiftui/roundedrectangle)。这些资料支持公开 API/HIG 原则，不支持固定的“iOS 27 标准”圆角、间距或日历数值。
- Claude 价格核验： [Anthropic 选择 Claude 计划](https://support.anthropic.com/en/articles/11049762-choosing-a-claude-ai-plan)、[Anthropic 定价](https://www.anthropic.com/pricing?subjects=claude&type=product)、[Pro 月付/年付说明](https://support.claude.com/en/articles/10185996-how-to-change-your-pro-plan-from-monthly-to-annual-billing)。这些官方资料共同支持 Pro 20 USD/月、Pro 年付 200 USD/年、Max 5x 100 USD/月、Max 20x 200 USD/月；不支持把 240 USD/月写成标准 Max 20x 价格。
- 百度网盘结构核验： [百度网盘会员中心](https://yun.baidu.com/buy/center)、[百度网盘会员服务协议](https://yun.baidu.com/disk/vipduty)。产品变体可以确认，但动态/登录态金额必须单独核验。

## Task 8 执行后核对（2026-08-03）

- 订阅列表行已补齐完整可点击区域；现场点击行中间空白处也能打开同一张 summary 卡片。该修正直接覆盖“点进我的订阅项目”的主入口，不增加新功能。
- 修正后的目录价格覆盖/改名路径 focused UI 通过 1/1，归档后恢复路径 focused UI 通过 1/1；结果包由 XcodeBuildMCP 生成在其本地工作区。
- Phase 2 之前的历史证据：单并发 UI 全量 runner 曾成功启动；日志显示前 5 个 UI 用例全部通过，随后在 `testCatalogAICategoryUsesLocalizedStableFilter` 开始时达到工具 300 秒时限，结果包缺少 `Info.plist`，所以当时不计为全量通过。删除 focused 测试的另一轮运行在 XCTest bootstrap 前被 `signal kill`，单独记录为运行环境限制；该历史状态已由下方有效 Phase 2 full run supersede。
- Phase 2 之前的历史证据：后续 shell 全量调用在测试启动前曾遇到 CoreSimulatorService/simdiskimaged 断连和宿主缓存诊断权限错误；随后 6 个主流程 UI 用例的 XcodeBuildMCP 批次也曾在 XCTest bootstrap 前被 `signal kill`。这些历史调用没有产生可用于产品结论的测试结果，不与当前有效 full PASS 混算。
- Phase 2 最终 full UI gate 已完成：xcresult `/Users/klaus/Library/Developer/XcodeBuildMCP/workspaces/subscription-manager-task8-luna-recovery-2c24e1642bb2/result-bundles/test_sim_2026-08-02T21-45-59-390Z_pid53016_40dcd1c1.xcresult` 含 `Info.plist` 且可由 `xcresulttool` 解析；log `/Users/klaus/Library/Developer/XcodeBuildMCP/workspaces/subscription-manager-task8-luna-recovery-2c24e1642bb2/logs/test_sim_2026-08-02T21-45-59-389Z_pid53016_d060fef2.log` 记录 `TEST EXECUTE SUCCEEDED`。汇率缓存时间戳仍是未观察到的证据边界，不伪造也不作为未完成产品工作。
