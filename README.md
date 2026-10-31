# CodexBar Cockpit

A native macOS menu-bar home for AI usage, daily planning, and session receipts.

CodexBar Cockpit combines [CodexBar](https://github.com/steipete/CodexBar)'s native menu bar and
provider support with local planning and task workflows inspired by
[Codex Cockpit](https://github.com/HouSiyuan2001/codex-cockpit). It is an independent community project.

**Development status:** pre-release integration under active validation. No signed public binary is available yet.

## 设计目标

- 保留 CodexBar 的全部提供商及菜单栏呈现。
- 点击菜单栏图标，在同一面板切换用量、统计、日历和组员与设备；每日建议直接出现在用量页。
- 宽屏用量页采用双栏：左侧保留完整提供商卡片和操作，右侧显示每日建议与个人上限；小屏自动切回单栏。
- 复用现有统计账本，提供用量图表、模型和项目统计；日历支持日／周／月／季度／年浏览与 Token／费用切换，缺失历史保持未知。
- 日历同步 [Codex Resets](https://codex-resets.com/zh-CN) 的常规与备用重置公告；区分已公告的待执行重置、网站预测和本机历史估算，发现新预告时尽早提醒。
- 以本地自然日保存预算和体感记录；额度、Token 和估算金额各有明确口径。
- 根据合格的历史观测提供带独立验证的星期用量参考，体感趋势更重视近期记录；均不改变个人上限。每日建议依据最新观测余额及有效重置窗口动态更新，并标注公告或估算来源。
- 在用量统计的历史会话中选定一个会话，点击“用量小票”预览、复制或保存 PNG；小票沿用当前统计范围和隐私设置。
- 组员可关联多台设备，通过自托管 Cloudflare 服务同步归属与每日预算；额度分配是协作计划。默认不上传本机用量，明确确认后仅共享合格汇总，见[团队同步设置](docs/cockpit/TEAM_SYNC.md)。
- 开发版使用独立设置与缓存，在“设置 → 通用”主动导入原 CodexBar 的主要显示设置。
- 沿用现有 23 种语言；每日建议、日历、重置提醒和小票均有对应翻译。在“设置 → 通用 → 语言”选择，或跟随系统；阿拉伯语、波斯语支持从右向左排版。
- 可在“设置 → 菜单栏”开启“菜单栏文字使用英文”，单独将屏幕顶部文字设为英文，展开面板继续使用当前语言。

- 菜单栏编辑器的显示项、预设、排版参数和条件规则均提供本地化鼠标悬浮说明。

当前实现与未完成验收见 [开发清单](docs/cockpit/ROADMAP.md)，已完成检查见 [验证记录](docs/cockpit/VALIDATION.md)，原版功能差异见 [对照表](docs/cockpit/PARITY.md)。

## Preview

Native SwiftUI/AppKit rendering with synthetic data; these are not personal usage records.
Screenshots show earlier layouts; receipt creation now opens from the selected historical session.

![Unified menu-bar usage panel with daily advice](docs/cockpit/images/unified-usage-zh.png)

[Compact single-column fallback](docs/cockpit/images/unified-usage-compact-zh.png)

![Calendar and personal state in the same menu-bar panel](docs/cockpit/images/unified-calendar-zh.png)

![Task receipt with partial costs and separate currencies](docs/cockpit/images/receipt-zh.png)

## Build

Requires macOS, full Xcode with Swift 6.2 or later, and the dependencies pinned in `Package.resolved`.
The initial baseline was compiled with Xcode 27 / Swift 6.4 on Apple Silicon.

```sh
swift build --product CodexBar
make test-fast FILTER='Cockpit'
make check
./Scripts/package_cockpit.sh debug
```

The bundle is `CodexBar Cockpit.app`. Click the status icon and switch pages in the same panel.
An independent application identity and data directory
allow testing alongside the original app. The full upstream test suite can be run with
`./Scripts/test.sh --direct-workers 8`.

## Data and privacy

App-owned files live in `~/.config/codexbar-cockpit` and
`~/Library/Application Support/CodexBar Cockpit`. Provider logs and login sessions remain local inputs.
Missing values stay unknown; prices are estimates and quota observations can have incomplete coverage.
Budget plans apply to supported fixed weekly quota windows and never infer official quota from dollar costs.

The reset calendar reads the public, key-free [Codex Resets API](https://codex-resets.com/api/docs).
Only public announcements are downloaded; no account, usage, or personal-state data is sent.
Status is checked once per minute while the app runs, with complete history refreshed every 15 minutes
or when a new reset appears. Cached history remains available offline. Forecast notifications can be
disabled in Settings → Notifications without hiding calendar history. Website forecasts and local
historical estimates are not OpenAI commitments or confirmation of your account’s quota.

Cloud sharing from Cockpit is outside the initial scope. Existing CodexBar capabilities are preserved;
using them requires their own configuration. Public repositories contain source and synthetic fixtures,
not personal logs, tokens, settings, or usage exports.

## Contributing and provenance

Read [architecture](docs/cockpit/ARCHITECTURE.md), [contribution notes](CONTRIBUTING.md),
and [upstream pins](UPSTREAM.md). The original CodexBar documentation remains available as
[README.upstream.md](README.upstream.md); its release links describe upstream, not this fork.

MIT licensed. Copyright notices for Peter Steinberger, Quota Float contributors, and this project's
contributors are retained in [LICENSE](LICENSE) and [licenses](licenses).
