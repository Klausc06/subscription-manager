# Catalog empty-price audit — C group

**Checked:** 2026-08-01 (Asia/Shanghai)  
**Method:** public first-party pages and public App Store China listings through
Jina Reader/search only. No account, checkout, browser interaction, conversion,
or campaign/first-term amount was used.  
**Decision rule:** `KEEP` means the row has a fixed recurring product with a
published list price. `REMOVE` is reserved for a product whose public offering
is course/package based rather than a standard recurring membership. Prices are
candidate catalog values and must be re-read immediately before a JSON import.

## Results

| id | Decision | Fixed offer(s): plan — price / currency / interval — market — channel | Public source |
| --- | --- | --- | --- |
| `tencent-docs` | **KEEP** | 腾讯文档会员 — 9 CNY / month — CN — iOS | [Tencent Docs, App Store CN](https://apps.apple.com/cn/app/%E8%85%BE%E8%AE%AF%E6%96%87%E6%A1%A3/id1370780836) |
| `shimo-docs` | **KEEP** | 石墨文档超级会员 — 9 CNY / month — CN — iOS | [石墨文档 App Store listing](https://apps.apple.com/sk/app/%E7%9F%B3%E5%A2%A8%E6%96%87%E6%A1%A3-%E5%9C%A8%E7%BA%BF%E6%96%87%E6%A1%A3%E5%8D%8F%E4%BD%9C%E7%BC%96%E8%BE%91%E5%92%8C%E8%A1%A8%E6%A0%BC%E5%88%B6%E4%BD%9C/id1013727678); [official personal pricing](https://shimo.im/pricing/personal) |
| `feishu` | **KEEP** | 飞书标准版 — 50 CNY / user / month — CN — web | [飞书定价版本介绍](https://www.feishu.cn/hc/zh-CN/articles/360049067600-%E9%A3%9E%E4%B9%A6%E5%AE%9A%E4%BB%B7%E7%89%88%E6%9C%AC%E4%BB%8B%E7%BB%8D); [version comparison](https://www.feishu.cn/service-internal) |
| `dingtalk` | **KEEP** | 钉钉 365 会员 — 365 CNY / year — CN — web | [钉钉官网](https://m.dingtalk.com/) |
| `youdao-cloud-note` | **KEEP** | 有道云笔记高级会员 — 18 CNY / month; 198 CNY / year — CN — iOS | [有道云笔记, App Store CN](https://apps.apple.com/cn/app/%E6%9C%89%E9%81%93%E4%BA%91%E7%AC%94%E8%AE%B0-%E7%AC%94%E8%AE%B0%E6%89%AB%E6%8F%8F%E6%95%88%E7%8E%87%E5%8A%9E%E5%85%AC/id450748070) |
| `xmind` | **KEEP** | Xmind Pro 全平台 — 68 CNY / month; 380 CNY / year — CN — iOS | [Xmind, App Store CN](https://apps.apple.com/cn/app/xmind-ai-%E6%80%9D%E7%BB%B4%E5%AF%BC%E5%9B%BE-%E5%A4%B4%E8%84%91%E9%A3%8E%E6%9A%B4/id1286983622) |
| `processon` | **KEEP** | ProcessOn 个人会员 — 99 CNY / year — CN — web | [ProcessOn product page](https://www.processon.com/); [App Store CN listing](https://apps.apple.com/cn/app/processon%E6%80%9D%E7%BB%B4%E5%AF%BC%E5%9B%BE-%E5%9C%A8%E7%BA%BF%E6%B5%81%E7%A8%8B%E5%9B%BE/id1564637971) |
| `lanhu` | **KEEP** | 蓝湖团队版 — 29 CNY / user / month — CN — web | [蓝湖官网](https://lanhuapp.com/) |
| `mubu` | **KEEP** | 幕布高级版 — 12 CNY / month; 108 CNY / year — CN — iOS | [幕布, App Store CN](https://apps.apple.com/cn/app/%E5%B9%95%E5%B8%83-%E5%A4%A7%E7%BA%B2%E7%AC%94%E8%AE%B0-%E6%80%9D%E7%BB%B4%E5%AF%BC%E5%9B%BE/id1214302139) |
| `tencent-meeting` | **KEEP** | 腾讯会议专业版高级账号 — 98 CNY / account / month; 988 CNY / account / year — CN — web | [腾讯会议 SaaS 定价](https://buy.cloud.tencent.com/price/tm/overview) |
| `xunlei` | **KEEP** | 迅雷超级会员连续包月 — 30 CNY / month; 328 CNY / year — CN — iOS | [迅雷, App Store CN](https://apps.apple.com/cn/app/%E8%BF%85%E9%9B%B7-%E9%9A%8F%E5%BF%83%E6%90%9C-%E6%94%BE%E5%BF%83%E5%AD%98-%E7%95%85%E5%BF%AB%E7%9C%8B/id1503466530?l=en-GB) |
| `baidu-wenku` | **KEEP** | 百度文库会员连续包月 — 19 CNY / month — CN — iOS | [百度文库, App Store CN](https://apps.apple.com/cn/app/%E7%99%BE%E5%BA%A6%E6%96%87%E5%BA%93-deepseek-r1%E8%81%94%E7%BD%91%E6%BB%A1%E8%A1%80%E7%89%88/id426340811) |
| `canva-china` | **KEEP** | Canva 可画专业版 — 39 CNY / month; 388 CNY / year — CN — web | [Canva 可画定价](https://www.canva.cn/pricing/) |
| `meitu-xiuxiu` | **KEEP** | 美图粉钻 VIP 连续包月 — 15 CNY / month; 128 CNY / year — CN — iOS | [美图秀秀, App Store CN](https://apps.apple.com/cn/app/%E7%BE%8E%E5%9B%BE%E7%A7%80%E7%A7%80-%E8%A7%86%E9%A2%91-%E5%9B%BE%E7%89%87-live%E4%BA%BA%E5%83%8F%E7%B2%BE%E4%BF%AE%E5%B7%A5%E5%85%B7/id416048305) |
| `jianying-pro` | **KEEP** | 剪映会员连续包月 — 25 CNY / month; 剪映 SVIP 连续包月 — 59 CNY / month — CN — iOS | [剪映, App Store CN](https://apps.apple.com/cn/app/%E5%89%AA%E6%98%A0-%E6%8A%96%E9%9F%B3%E5%AE%98%E6%96%B9ai%E5%88%9B%E4%BD%9C%E7%A5%9E%E5%99%A8/id1458072671?platform=ipad) |
| `foxit-pdf` | **KEEP** | 福昕会员连续包月 — 79 CNY / month; 福昕会员 — 279 CNY / year — CN — iOS | [福昕 PDF 编辑器, App Store CN](https://apps.apple.com/cn/app/%E7%A6%8F%E6%98%95pdf%E7%BC%96%E8%BE%91%E5%99%A8/id1583534770) |
| `iflytek-spark` | **KEEP** | 讯飞星火求职 AI 助手连续包月 — 15 CNY / month; 连续包季 — 36 CNY / quarter — CN — iOS | [讯飞星火, App Store CN](https://apps.apple.com/cn/app/%E8%AE%AF%E9%A3%9E%E6%98%9F%E7%81%AB-%E6%87%82%E4%BD%A0%E7%9A%84ai%E5%8A%A9%E6%89%8B/id6449919551) |
| `youdao-premium` | **KEEP** | 有道词典会员连续包月 — 25 CNY / month; 年卡 — 168 CNY / year — CN — iOS | [有道词典, App Store CN](https://apps.apple.com/cn/app/%E7%BD%91%E6%98%93%E6%9C%89%E9%81%93%E8%AF%8D%E5%85%B8-%E4%B8%93%E4%B8%9A%E6%9F%A5%E8%AF%8D%E7%BF%BB%E8%AF%91%E5%AD%A6%E4%B9%A0%E5%8A%A9%E6%89%8B/id353115739) |
| `baicizhan` | **KEEP** | 百词斩 Pro 连续包月 — 18 CNY / month — CN — iOS | [百词斩, App Store CN](https://apps.apple.com/cn/app/%E7%99%BE%E8%AF%8D%E6%96%A9-%E5%AD%A6%E8%8B%B1%E8%AF%AD-%E8%83%8C%E5%8D%95%E8%AF%8D%E5%BF%85%E5%A4%87/id557545298?l=en-GB) |
| `zuoyebang` | **KEEP** | 作业帮连续包月 VIP — 19 CNY / month — CN — iOS | [作业帮, App Store CN](https://apps.apple.com/cn/app/%E4%BD%9C%E4%B8%9A%E5%B8%AE-%E4%B8%AD%E5%B0%8F%E5%AD%A6%E5%AE%B6%E9%95%BF%E4%BD%9C%E4%B8%9A%E6%A3%80%E6%9F%A5%E5%92%8Cai%E4%BC%B4%E5%AD%A6%E8%BE%85%E5%AF%BC%E5%B7%A5%E5%85%B7/id803781859) |
| `yuanfudao` | **REMOVE** | — | [猿辅导官网](https://www.yuanfudao.com/) currently presents grade/course offerings; no single public, fixed recurring membership price was established for the preset itself. Do not substitute course bundles or a trial. |
| `xueersi` | **KEEP** | 小思 AI VIP 连续包月 — 19 CNY / month — CN — iOS | [小思 AI（学而思）, App Store CN](https://apps.apple.com/cn/app/%E5%B0%8F%E6%80%9Dai-%E5%AD%A6%E8%80%8C%E6%80%9Dai%E5%AD%A6%E4%B9%A0%E5%8A%A9%E6%89%8B/id6499319699) |
| `kaoyanbang` | **KEEP** | 考研帮 VIP 连续包月 — 18 CNY / month — CN — iOS | [考研帮, App Store CN](https://apps.apple.com/cn/app/%E8%80%83%E7%A0%94%E5%B8%AE-%E8%80%83%E7%A0%94%E7%94%A8%E6%88%B7%E9%83%BD%E5%9C%A8%E7%94%A8%E7%9A%84app/id1049596362) |
| `fan-deng-reading` | **KEEP** | 帆书（原樊登读书）非凡精读连续包月 VIP — 38 CNY / month — CN — iOS | [帆书, App Store CN](https://apps.apple.com/cn/app/%E5%B8%86%E4%B9%A6-%E5%8E%9F%E6%A8%8A%E7%99%BB%E8%AF%BB%E4%B9%A6-%E7%B2%BE%E9%80%89%E5%A5%BD%E4%B9%A6-%E8%BD%BB%E6%9D%BE%E9%98%85%E8%AF%BB/id963152777) |
| `meituan-membership` | **KEEP** | 美团会员连续包月 — 15 CNY / month — CN — iOS | [美团, App Store CN](https://apps.apple.com/cn/app/%E7%BE%8E%E5%9B%A2-%E5%A4%96%E5%8D%96%E5%9B%A2%E8%B4%AD%E7%BE%8E%E9%A3%9F%E7%94%9F%E6%B4%BB%E6%9C%8D%E5%8A%A1/id423084029) |
| `eleme-super-membership` | **KEEP** | 饿了么超级吃货卡连续包月 — 10 CNY / month — CN — iOS | [饿了么, App Store CN](https://apps.apple.com/cn/app/%E9%A5%BF%E4%BA%86%E4%B9%88-%E6%94%BE%E5%BF%83%E7%82%B9-%E5%87%86%E6%97%B6%E8%BE%BE/id507097717) |
| `costco-china` | **KEEP** | 开市客金星会员主卡 — 299 CNY / year — CN — web | [开市客中国会员页](https://www.costco.com.cn/membership); [official Costco China membership booklet](https://cdn.costco.com.cn/connection/Logo%20Book_%E6%9D%AD%E5%B7%9E%E5%BA%97_2023.5.8.pdf) |
| `qq-svip` | **KEEP** | QQ 超级会员连续包月 — 19 CNY / month; 238 CNY / year — CN — iOS | [QQ, App Store CN](https://apps.apple.com/cn/app/qq/id444934666) |
| `kuaishou-membership` | **KEEP** | 快手超粉团金粉团连续包月 — 29.9 CNY / month; 钻粉团 — 69.9 CNY / month — CN — iOS | [快手, App Store CN](https://apps.apple.com/cn/app/%E5%BF%AB%E6%89%8B/id440948110) |

## Counts and implementation notes

- **KEEP:** 28 presets
- **REMOVE:** 1 preset (`yuanfudao`)
- Each `KEEP` row has one or more named, non-promotional recurring prices,
  a currency, cadence, market, purchase channel, and public `sourceURL`.
- Use CNY yuan values above only as published; do not derive an annual price
  from a monthly price. For catalog storage, convert the displayed CNY amount
  directly to fen only at the import boundary (for example, `29.9 CNY` is
  `2990` fen), with no FX conversion.
- `feishu`, `dingtalk`, `processon`, `lanhu`, `tencent-meeting`,
  `canva-china`, `baidu-wenku`, `xueersi`, `kaoyanbang`, `meituan-membership`,
  and `eleme-super-membership` are web/client-rendered or channel-sensitive
  plans. Re-read the linked public page immediately before a product-data
  change; do not replace these with a campaign, first-month, student, or
  account-specific checkout price.
- `yuanfudao` is deliberately the only removal: the preset name does not map
  to a publicly priced, standard recurring membership in this verification.
  Its public product surface is paid course/package oriented, so adding a
  guessed plan would violate the fixed-subscription rule.
