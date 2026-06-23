# Issues 摘要

> 用于跨上下文留存问题处理经验，避免重复踩坑。新条目追加在末尾，同 Issue 只维护一处。
>
> 每条摘要包含：**表因 / 根因 / 处理方式 / 后续防范 / 同类问题影响**。

---

## #1 CLT 无 XCTest / Swift Testing，无法 `swift test`

- **表因**：`import XCTest` 报 `no such module 'XCTest'`；`import Testing`（Swift Testing）报宏插件 `TestingMacros` not found。
- **根因**：Command Line Tools（非完整 Xcode）不含 XCTest 框架与 Swift Testing 宏插件，二者均随 Xcode 附带。
- **处理方式**：自建极简测试运行器——`tests/` 下可执行目标 `TimeoutTests`，提供 `test(name){}` / `expect(...)` / `expectEqual(...)` + 计数 + 退出码，`make test` → `swift run TimeoutTests` 驱动。语义对齐 XCTest，30 用例 <1s。
- **后续防范**：若未来安装完整 Xcode，可平滑迁移回 XCTest（断言 API 一一对应）；AGENTS.md 已注明此适配。
- **同类影响**：任何纯 CLT 环境的 Swift 项目均适用此方案，勿再尝试 `swift test` + XCTest。

## #2 CGEvent.subtype / CGEventSubtype 在 CLT SDK 不可写

- **表因**：合成媒体键事件设 `event.subtype = CGEventSubtype(rawValue: 8)` 报 `cannot find 'CGEventSubtype' in scope`；`.init(rawValue:)` 亦不可推断。
- **根因**：CLT 的 Swift overlay 未暴露 `CGEventSubtype` 类型，且 `event.subtype` 属性不可赋值。
- **处理方式**：改用 `event.setIntegerValueField(.mouseEventSubtype, value: 8)` 字段写法（探测确认 `.mouseEventSubtype` CGEventField 可用）；CGEvent 构造用完整 `init(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`。
- **后续防范**：CLT 下涉及 CGEvent 复杂属性时优先用 `setIntegerValueField` 字段路径，勿依赖具名属性。
- **同类影响**：所有合成系统事件（媒体键/特殊鼠标）的代码。

## #3 CGEvent 媒体键需 Accessibility + Now Playing 竞争（待真机核实）

- **表因**：无头环境无法验证 QQ 音乐实际播放/暂停效果。
- **根因**：CGEvent 媒体键路由依赖 (a) Accessibility 权限、(b) QQ 音乐注册为当前 Now Playing 应用。二者均需真机 + 用户授权，无头不可复现。
- **处理方式**：实现 `LiveMusicController`（CGEvent `NX_KEYTYPE_PLAY`=16，经二进制验证 QQ 音乐注册 Now Playing），未授权时优雅降级（日志提示 + 不崩溃）；降级兜底为终止 QQ 音乐保静音。
- **后续防范**：实机回归时先授 Accessibility，确认 QQ 音乐前台/Now Playing 激活后再测；若其他 app 抢占 Now Playing，媒体键可能路由错误。
- **同类影响**：任何控制第三方媒体播放器的方案。

## #4 macOS 26 `canBecomeKey=true` 实机回归——已验证无崩溃

- **表因**：遮罩 NSPanel 需 `canBecomeKey=true` 以接收 Esc；2024-2025 报告称 macOS 26 beta 下窗口出现数秒后可能崩溃。
- **根因**：OS beta 期回归（release 已修复）。
- **处理方式**：保留 `canBecomeKey=true`（Esc 双保险：本地事件监听 + key）。
- **验证结果（macOS 26.5.1 实机）**：遮罩触发期间进程持续存活（无崩溃）；`CGWindowListCopyWindowInfo` 查询证实面板位于 `layer=2147483628`（CGShieldingWindowLevel）、bounds 匹配全屏、多显示器各一面板。**结论：beta 崩溃问题在 release 已消失。**
- **附带发现**：`screencapture` 无法捕获 CGShieldingWindowLevel 窗口（macOS 安全限制）——验证遮罩可见性须用 `CGWindowListCopyWindowInfo` 查询窗口服务器，而非截图。
- **同类影响**：全屏置顶 borderless 面板场景的 macOS 版本回归。

## #5 无 Xcode → SPM + Makefile 手工 .app 装配

- **表因**：本机未装 Xcode，无法 `xcodebuild` 生成 `.xcodeproj`。
- **根因**：方案原定 `.xcodeproj`，但环境约束不允许。
- **处理方式**：改用 Swift Package Manager（`Package.swift` 三目标）+ `Makefile` 手工装配 `.app`（`Contents/MacOS` + `Info.plist` + `PkgInfo` + `codesign` ad-hoc + Hardened Runtime + entitlements + `xattr` 清 quarantine）。比 `.xcodeproj` 更简约，且 `codesign`/`notarytool` 随 CLT 可用。
- **后续防范**：公开分发时用 Developer ID + `notarytool` + `stapler`（Makefile 已预留注释）；个人用 ad-hoc 即可。
- **同类影响**：任何无 Xcode 的 macOS 应用构建。

## #6 休息模式 Esc 退出失效（对话框被遮罩遮挡 + forcedRest 残留死循环）

- **表因**：(a) 休息遮罩下按 Esc，确认对话框不可见，Esc 退出永远无反应；(b)（经菜单「立即休息」进入休息后）即便能触发「直接退出」，遮罩消失后约 1 秒重新出现并重置 10 分钟倒计时，永远无法退出。
- **根因**：
  - (a) `LiveOverlayController` 遮罩面板 `level=CGShieldingWindowLevel()`（≈2147483628，窗口层级最高）；确认用 `NSAlert.runModal()`，其模态窗默认 `level=NSModalPanelWindowLevel`（=8）≪ 遮罩，对话框渲染在遮罩之下不可见；且 `runModal` 阻塞主线程但按钮不可达。`OverlayPanel.canBecomeMain=false` 进一步使 NSAlert 模态 session 不稳。
  - (b) `LiveTimeoutEngine.requestEarlyRestExit()` 设 `phase=.working` 但**未清除 `forcedRest`**；该标志唯一清除点是 `tick()` 内（`oldPhase==.resting && s.phase!=.resting`），而 `requestEarlyRestExit` 绕过了 tick 路径。下个 tick 的 `transition` 纯函数见非休息态且 `forcedRest==true`，无视一切重进 `.resting` 并设新 `restStartedAt=now`（新倒计时）→ 死循环。仅「立即休息」入口触发（自然触发的休息 `forcedRest=false`，Esc 退出正常）。
- **处理方式**：
  - (a) 弃用 NSAlert，确认 UI 改为**内嵌遮罩 SwiftUI 视图**（新增 `OverlayViewModel: ObservableObject`，`@Published isConfirming` 驱动倒计时态/确认态切换），与遮罩同层级，从根上消除遮挡；非阻塞、不依赖 main window、多屏一致；Esc 双语义（倒计时态→进入确认，确认态→取消返回倒计时）；主屏 panel `makeKeyAndOrderFront` 使 Button 可接收点击/回车。
  - (b) `requestEarlyRestExit()` 加 `forcedRest = false`，与 tick 共享「离开 .resting 即清 forcedRest」不变量。配回归测试（`forceRestNow`→`requestEarlyRestExit`→再 tick，断言 `overlay.showCount` 修复前=2/后=1，phase 保持 working）。
- **后续防范**：
  - CGShieldingWindowLevel 遮罩下任何需用户交互的 UI，必须**内嵌于遮罩面板内部**（同层级），禁用 NSAlert / 独立普通窗口（会被遮挡）。
  - 任何**绕过 tick 直接修改 state 的路径**（`requestEarlyRestExit`/`handleSleep`/`handleWake`/`fastForward`/`forceRestNow`/`updateConfig`）必须与 tick 的状态不变量逐一对齐（本次即 forcedRest 清除）；新增此类路径时审查是否复现「标志残留被下个周期 tick 拉回」模式。
  - 回归测试须覆盖「用户主动操作 + 后续 tick」组合，而非只断言操作瞬间的状态（原盲点：`requestEarlyRestExit` 后不再 tick）。
- **同类影响**：任何「全屏置顶遮罩 + 弹窗交互」「一次性意图标志 + 周期 FSM 决策」混合架构的应用；(b) 的 forcedRest 残留模式可推广到所有「一次性意图标志 + 周期 tick」组合。
