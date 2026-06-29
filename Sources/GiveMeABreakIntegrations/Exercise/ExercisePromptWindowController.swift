import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 退出休息后运动记录提示窗口控制器（NSWindow + NSHostingController，同 WorkLogPromptWindowController 范式）。
///
/// 与工作日志小结窗的关键差异：运动记录在休息**已结束**后弹出，无倒计时可保护，故**不冻结引擎心跳、不耦合
/// 引擎状态**——形态接近补录窗，仅自动弹出并预填休息时段。为避免窗口长期悬空，提供固定自动放行兜底
/// （`autoDismissSeconds`，到点等同跳过/关窗）。`isPresenting` 防重入，`finish` 多路合一幂等收尾。
final class ExercisePromptWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var timeoutTimer: DispatchSourceTimer?
    private var presenting = false
    var isPresenting: Bool { presenting }
    private var onSubmit: (([ExerciseSet], String?) -> Void)?
    private var onSkip: (() -> Void)?

    /// 固定自动放行兜底（秒）：到点未操作即等同跳过，防窗口悬空。
    private let autoDismissSeconds: TimeInterval = 180

    override init() { super.init() }

    /// 弹出提示。`onSubmit`/`onSkip` 由 AppRoot 提供：前者落库运动记录，后者计跳过。
    func present(restStartedAt: Date,
                 restEndedAt: Date,
                 onSubmit: @escaping ([ExerciseSet], String?) -> Void,
                 onSkip: @escaping () -> Void) {
        guard !presenting else { return }
        presenting = true
        self.onSubmit = onSubmit
        self.onSkip = onSkip

        let view = ExercisePromptView(
            restStartedAt: restStartedAt,
            restEndedAt: restEndedAt,
            onSubmit: { [weak self] sets, note in self?.submit(sets: sets, note: note) },
            onSkip: { [weak self] in self?.skip() }
        )

        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "记录运动"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.delegate = self  // 红色关闭按钮经 windowWillClose 等同「跳过」
            w.setContentSize(NSSize(width: 460, height: 360))
            window = w
        } else {
            (window?.contentViewController as? NSHostingController<ExercisePromptView>)?.rootView = view
        }

        centerOnMainScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        startTimeout(after: autoDismissSeconds)
    }

    // MARK: - 提交 / 跳过 / 超时 / 关窗（多路合一，guard presenting 幂等防二次回调）

    private func submit(sets: [ExerciseSet], note: String?) {
        guard presenting else { return }
        finish { self.onSubmit?(sets, note) }
    }

    private func skip() {
        guard presenting else { return }
        finish { self.onSkip?() }
    }

    func windowWillClose(_ notification: Notification) {
        skip()
    }

    private func startTimeout(after seconds: TimeInterval) {
        cancelTimeout()
        guard seconds > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in self?.skip() }  // 到点自动跳过，防悬空窗
        timer.resume()
        timeoutTimer = timer
    }

    private func cancelTimeout() {
        if let timeoutTimer { timeoutTimer.cancel(); self.timeoutTimer = nil }
    }

    /// 统一收尾：取消超时、隐藏窗口、清重入标志，再触发回调（确保回调只跑一次）。
    private func finish(_ action: () -> Void) {
        cancelTimeout()
        window?.orderOut(nil)
        presenting = false
        action()
        onSubmit = nil
        onSkip = nil
    }

    // MARK: - 显式居中（弃 center()，issue #7：accessory app 多屏下 center() 落离屏负坐标）

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 460, height: 360)
        window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                       y: visible.midY - frame.height / 2))
    }
}
