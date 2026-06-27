# CHANGELOG

本文件记录 Give me a break 的版本变更事件。

## Unreleased

## v0.1.0 — 2026-06-27（GA · MVP 正式发布）

首个正式发布（GA）：一款功能完备的 macOS 菜单栏强制作息应用，整合作息节律、全屏遮罩、休息音效、Google 日历门控、工作日志与图形化设置。本版聚合了此前迭代的全部能力，作为 MVP 的正式基线。

### 核心能力

- **强制排版作息**：自定义工作时段（每日重复、可跨午夜）内累计工作 N 分钟（默认 50）即触发强制休息 M 分钟（默认 10）；AFK 阈值（默认 3 分钟）在离座时暂停累计，避免人不在时误触发。
- **全屏遮罩**：休息时遮罩所有显示器（`CGShieldingWindowLevel`，压过菜单栏 / Dock / 全屏），Esc 二次确认方可提前结束（软强制，留逃生阀）；多屏热插拔自适应。
- **休息音效（取代 / 回退链路）**：设置「休息音乐」后循环播放本地音频（mp3/m4a/aac/wav/flac 等）取代内置粉噪音，文件缺失或格式不支持时自动回退；音频仅以本地路径引用、不打包不分发。粉噪音由 AVAudioEngine 实时合成，零音频文件、可靠且不依赖外部播放器。可叠加联动 QQ 音乐（经系统媒体键控制，需辅助功能权限，不可用则静默跳过）。
- **Google 日历门控**：会议计为工作时间，休息推迟至会议结束（EventKit 复用 OS 登录态，无 OAuth 代码）。
- **工作日志（认知闭合）**：自然休息前花 30 秒写下「刚完成什么 + 下一步」，永不阻塞休息（回车提交 / Esc 或关窗跳过 / 到点自动放行，默认 3 分钟可调，或开启「永久等待」）；可整体关闭，「立即休息」不弹。记录落盘，菜单「工作日志…」生成今日 / 本周 / 本月报告（Markdown，可复制 / 导出）；并支持「补录工作日志」回填漏记时段。循证设计（Leroy 注意力残留 / Stubblebine 插值日记 / Fogg 行为模型 / JITAI）。
- **图形化设置（四页签）**：通用（开机自启 + 关于）/ 作息（工作时段 + 节律）/ 休息音效 / 工作日志；草稿—应用一次性提交、恢复默认二次确认、窗口按当前页签内容自适应（免滚动 / 留白）。即时保存 + 引擎热更新。
- **健壮性**：AFK / 睡眠暂停累加（不回灌）、崩溃恢复 fast-forward、状态持久化；配置 schema v5（含 `restMusicPath` / `workLogPromptTimeoutSeconds`），旧配置容错解码平滑迁移。

### 工程

- 三模块正交分解：`GiveMeABreakEngine`（纯 FSM + evaluate 纯函数）/ `GiveMeABreakIntegrations`（AppKit / EventKit / CGEvent）/ `GiveMeABreak`（@main 壳）；54 单测全绿（<1s，CLT 自建运行器）。
- 跨平台 SSOT：`shared/` 黄金 fixture + config / work-log schema；Windows 端 C#/.NET 8 WPF 平行移植，CI 多平台一次发布 macOS + Windows 双 asset。

### 说明

- 本 GA 标志 MVP 功能完备；macOS 与 Windows 产物**均未做代码签名 / 公证**，首次启动需手动放行（详见 [README](./README.md)）。代码签名 / 公证与 Windows 真机验收将在后续版本补齐。
