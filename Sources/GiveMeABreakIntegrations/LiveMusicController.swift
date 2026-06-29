import AppKit
import AVFoundation
import CoreGraphics
import GiveMeABreakEngine

/// 休息音效控制器（三轨，按优先级择一/叠加）：
/// 1. **自定义休息音频**（`restMusicPath` 指向的本地文件，`AVAudioPlayer` 循环）——设置即取代粉噪音；加载失败回退粉噪音；
/// 2. **内置粉噪音**（`AmbientSoundPlayer`）——可靠、零依赖，保证休息必有舒缓音效（无自定义音频时的默认）；
/// 3. **QQ 音乐媒体键联动**（CGEvent `NX_KEYTYPE PLAY`）——可选增强，需安装并授权，与上述任一音轨叠加。
///
/// 修复历史问题：原版仅靠媒体键控外部 QQ 音乐，未安装/未授权即**静默失败、无任何音效**。
/// 现内置粉噪音作为可靠底噪（无论 QQ 音乐是否可用都会响），QQ 音乐降级为可选联动。
/// 并补全诊断日志，让「为何不响」可观测。
final class LiveMusicController: MusicController {
    private let ambient = AmbientSoundPlayer()
    /// 自定义休息音频播放器（AVAudioPlayer，循环）。每次休息按当前 config 路径重新载入。
    private var filePlayer: AVAudioPlayer?
    private var config: DayPlanConfig = .defaultConfig

    // QQ 音乐联动（保留原 CGEvent 媒体键路径，降级为可选）
    private let qqMusicBundleId = "com.tencent.QQMusicMac"
    private let qqMusicAppURL = URL(fileURLWithPath: "/Applications/QQMusic.app")

    func updateConfig(_ config: DayPlanConfig) {
        self.config = config
    }

    func startPlayback() {
        // 优先：自定义休息音频（取代粉噪音）。加载失败则回退粉噪音，保证休息必有舒缓音效。
        let customPath = config.restMusicPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customPath.isEmpty {
            if startCustomFile(customPath) {
                // 自定义音频已起，跳过粉噪音
            } else if config.ambientSoundEnabled {
                ambient.start()
            }
        } else if config.ambientSoundEnabled {
            ambient.start()                  // 可靠音效：不依赖任何外部 app
        }
        if config.controlQQMusic {
            startQQMusic()                   // 可选联动：媒体键控 QQ 音乐
        }
    }

    func pausePlayback() {
        filePlayer?.stop()                   // 幂等：停止自定义音频并释放本次缓冲
        filePlayer = nil
        ambient.stop()                       // 幂等：未播放时 no-op
        if config.controlQQMusic {
            postMediaKey(16)                 // NX_KEYTYPE_PLAY toggle → 暂停（保留队列/进度）
            NSLog("[GiveMeABreak][music] 发送 pause 媒体键（toggle，保留队列）")
        }
    }

    // MARK: - 自定义休息音频（AVAudioPlayer，循环；文件由用户本地提供，不打包不分发）

    /// 载入并循环播放本地音频文件。成功返回 true；路径无效/格式不支持/解码失败时记日志并返回 false（由调用方回退粉噪音）。
    private func startCustomFile(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("[GiveMeABreak][music] 自定义休息音频不存在，回退粉噪音：\(path)")
            return false
        }
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.numberOfLoops = -1        // 无限循环，覆盖整段休息
            player.volume = 0.8              // 休息舒适响度（对齐粉噪音 0.4 的温和取向）
            guard player.prepareToPlay(), player.play() else {
                NSLog("[GiveMeABreak][music] 自定义休息音频 prepare/play 失败，回退粉噪音：\(path)")
                return false
            }
            filePlayer = player
            NSLog("[GiveMeABreak][music] 自定义休息音频已启动（循环）：\((path as NSString).lastPathComponent)")
            return true
        } catch {
            NSLog("[GiveMeABreak][music] 自定义休息音频载入失败（格式不支持或损坏），回退粉噪音：\(error.localizedDescription) · \(path)")
            return false
        }
    }

    // MARK: - QQ 音乐联动（含诊断日志）

    private func startQQMusic() {
        let isTrusted = AccessibilityChecker.isTrusted
        let installed = FileManager.default.fileExists(atPath: qqMusicAppURL.path)
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == qqMusicBundleId }
        // 诊断日志（解答「为何 QQ 音乐没反应」）：Console.app 可见
        NSLog("[GiveMeABreak][music] QQ 音乐：installed=\(installed) trusted=\(isTrusted) running=\(running)")

        guard isTrusted else {
            NSLog("[GiveMeABreak][music] Accessibility 未授权，CGEvent 媒体键将被系统丢弃；请在系统设置授权（粉噪音仍会播放）")
            launchQQMusicIfNeeded()
            return
        }
        launchQQMusicIfNeeded()
        // 启动后稍候再发媒体键，确保 QQ 音乐已注册为 Now Playing。
        // 已知限制：NX_KEYTYPE_PLAY 是 toggle——若 QQ 音乐此刻正在播放，此键反而会暂停。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.postMediaKey(16)
            NSLog("[GiveMeABreak][music] 发送 play 媒体键")
        }
    }

    private func launchQQMusicIfNeeded() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == qqMusicBundleId }
        guard !running else { return }
        guard FileManager.default.fileExists(atPath: qqMusicAppURL.path) else {
            NSLog("[GiveMeABreak][music] 未找到 /Applications/QQMusic.app，跳过启动")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: qqMusicAppURL, configuration: cfg) { _, error in
            if let error { NSLog("[GiveMeABreak][music] 启动 QQ 音乐失败：\(error.localizedDescription)") }
            else { NSLog("[GiveMeABreak][music] 已拉起 QQ 音乐") }
        }
    }

    // MARK: - CGEvent 媒体键合成（subtype=8 NX_SUBTYPE_AUX_CONTROL_BUTTONS，data1 编码 keyType + down/up）

    private func postMediaKey(_ keyCode: Int32) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            let mouseType: CGEventType = down ? .otherMouseDown : .otherMouseUp
            guard let event = CGEvent(mouseEventSource: source, mouseType: mouseType,
                                      mouseCursorPosition: .zero, mouseButton: .center) else { continue }
            event.setIntegerValueField(.mouseEventSubtype, value: 8)  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            let flags: Int64 = down ? (0x0A << 8) : (0x0B << 8)
            let data1 = (Int64(keyCode) << 16) | flags
            event.setIntegerValueField(.eventSourceUserData, value: data1)
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
}
