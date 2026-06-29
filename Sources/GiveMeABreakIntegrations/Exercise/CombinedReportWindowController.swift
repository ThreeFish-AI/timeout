import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 综合报告窗口控制器：NSWindow + NSHostingController（同 WorkLogReportWindowController 范式）。
/// 单例复用；每次 show 重新读取两个 store 并按当前 scope 渲染。
final class CombinedReportWindowController {
    private var window: NSWindow?
    private let workStore: WorkLogStore
    private let exerciseStore: ExerciseStore

    init(workStore: WorkLogStore, exerciseStore: ExerciseStore) {
        self.workStore = workStore
        self.exerciseStore = exerciseStore
    }

    func show() {
        // 调试：GIVEMEABREAK_COMBINED_SCOPE=week|month|quarter|year 指定初始周期（默认本周）
        let initialScope = ProcessInfo.processInfo.environment["GIVEMEABREAK_COMBINED_SCOPE"]
            .flatMap { CombinedReportScope(rawValue: $0) } ?? .week
        let view = CombinedReportView(workStore: workStore, exerciseStore: exerciseStore, initialScope: initialScope) { [weak self] in
            self?.window?.close()
        }

        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "综合报告"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.contentMinSize = NSSize(width: 620, height: 480)
            w.setContentSize(NSSize(width: 740, height: 580))
            w.isReleasedWhenClosed = false
            window = w
        } else {
            (window?.contentViewController as? NSHostingController<CombinedReportView>)?.rootView = view
        }

        // 显式居中到主屏可见区（弃 center()，issue #7）
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 740, height: 580)
            window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                           y: visible.midY - frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
