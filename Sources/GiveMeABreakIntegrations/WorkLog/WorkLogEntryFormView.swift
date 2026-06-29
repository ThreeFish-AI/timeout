import SwiftUI
import GiveMeABreakEngine

/// 工作日志「条目表单」：补录（新增）与编辑（改已有）共用同一视觉与交互。
///
/// 与 `WorkLogPromptView` 同源视觉语言（leaf/pencil 标题 · summary TextEditor + 软字符计数 · 可选下一步），
/// 但语义为「用户自选时段、无超时、保存/取消、不触发休息」。两模式差异：
/// - `.create`：标题「补录工作日志」、字段空、保存生成新 `id`；时长默认 `end−start` 且未手动调整时随时段联动。
/// - `.edit`：标题「编辑工作日志」、字段预填、保存**保留原 `id` 与 `modelVersion`**；时长默认该条原 `durationSeconds`
///   且**不随时段自动覆盖**（自动记录因 AFK 冻结，专注时长可能 < 时段跨度，避免静默篡改）。
enum WorkLogEntryFormMode {
    case create(defaultStart: Date, defaultEnd: Date)
    case edit(WorkLogEntry)
}

struct WorkLogEntryFormView: View {
    private let mode: WorkLogEntryFormMode
    private let onSubmit: (WorkLogEntry) -> Void
    private let onCancel: () -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var summary: String
    @State private var nextAction: String
    @State private var nextExpanded: Bool
    @State private var durationMinutes: Int
    /// 时长是否已被用户手动锁定：锁定后不再随时段联动（编辑模式默认锁定，保护原专注时长）。
    @State private var durationPinned: Bool

    private let softLimit = 120

    init(mode: WorkLogEntryFormMode,
         onSubmit: @escaping (WorkLogEntry) -> Void,
         onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        switch mode {
        case .create(let defaultStart, let defaultEnd):
            // 防御：起始不得晚于结束，否则回退到结束前 1 分钟。
            let safeStart = defaultStart < defaultEnd ? defaultStart : defaultEnd.addingTimeInterval(-60)
            _start = State(initialValue: safeStart)
            _end = State(initialValue: defaultEnd)
            _summary = State(initialValue: "")
            _nextAction = State(initialValue: "")
            _nextExpanded = State(initialValue: false)
            _durationMinutes = State(initialValue: Self.minutes(from: safeStart, to: defaultEnd))
            _durationPinned = State(initialValue: false)
        case .edit(let entry):
            let safeStart = entry.startedAt < entry.endedAt ? entry.startedAt : entry.endedAt.addingTimeInterval(-60)
            _start = State(initialValue: safeStart)
            _end = State(initialValue: entry.endedAt)
            _summary = State(initialValue: entry.summary)
            _nextAction = State(initialValue: entry.nextAction ?? "")
            _nextExpanded = State(initialValue: entry.nextAction?.isEmpty == false)
            _durationMinutes = State(initialValue: max(0, Int((entry.durationSeconds / 60).rounded())))
            _durationPinned = State(initialValue: true)
        }
    }

    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }
    private var titleText: String { isEdit ? "编辑工作日志" : "补录工作日志" }
    private var iconName: String { isEdit ? "pencil" : "square.and.pencil" }
    private var descText: String {
        isEdit
            ? "调整这条记录的时段、时长、小结或下一步，保存后报告自动重算。"
            : "为漏掉的某段时间补一段工作小结。选择时段、写下完成了什么，保存后并入工作日志报告。"
    }

    private var trimmedSummary: String { summary.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedSummary.isEmpty && end > start }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: iconName).foregroundStyle(.teal).font(.system(size: 20))
                Text(titleText).font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            Text(descText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 时段选择（DatePicker 互相约束：start ≤ end）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("开始").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    DatePicker("", selection: $start, in: ...end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityLabel("时段的开始时间")
                    Spacer()
                }
                HStack(spacing: 10) {
                    Text("结束").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    DatePicker("", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityLabel("时段的结束时间")
                    Spacer()
                }
                // 专注时长（可手动微调；新增时未调整则随时段联动）
                HStack(spacing: 10) {
                    Text("时长").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    Text(humanizedDuration(TimeInterval(durationMinutes * 60)))
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minWidth: 56, alignment: .leading)
                    Stepper("", value: Binding(get: { durationMinutes },
                                               set: { durationMinutes = max(0, $0); durationPinned = true }),
                            in: 0...600, step: 5)
                        .labelsHidden()
                        .accessibilityLabel("专注时长（分钟）")
                    Spacer()
                }
            }

            // summary（同 WorkLogPromptView 风格：TextEditor + 软字符计数 + 占位）
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $summary)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(minHeight: 64, idealHeight: 72)
                    .overlay(alignment: .topLeading) {
                        if summary.isEmpty {
                            Text("例：调试登录 bug，定位到 token 过期")
                                .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                .font(.system(size: 14))
                                .padding(.horizontal, 5).padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                HStack {
                    Spacer()
                    Text("\(summary.count)/\(softLimit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(summary.count > softLimit ? .orange : .secondary)
                }
            }

            // 可选「下一步」（默认折叠；编辑时若原有 nextAction 则展开）
            if nextExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一步的第一个动作（可选）")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("例：打开 LoginViewModel 补单测", text: $nextAction)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { nextExpanded = true }
                } label: {
                    Label("加一条「下一步」", systemImage: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            HStack {
                Text(isEdit ? "改这一条" : "新增一条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440, height: 470)
        .onChange(of: start) { _, _ in syncDurationIfNeeded() }
        .onChange(of: end) { _, _ in syncDurationIfNeeded() }
    }

    /// 未锁定时（新增且用户未手动改时长）让时长随时段联动。
    private func syncDurationIfNeeded() {
        guard !durationPinned else { return }
        durationMinutes = Self.minutes(from: start, to: end)
    }

    private static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    private func save() {
        let na = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = TimeInterval(durationMinutes * 60)
        let entry: WorkLogEntry
        switch mode {
        case .create:
            entry = WorkLogEntry(
                startedAt: start, endedAt: end,
                summary: trimmedSummary,
                nextAction: na.isEmpty ? nil : na,
                durationSeconds: duration
            )
        case .edit(let original):
            entry = WorkLogEntry(
                id: original.id,
                startedAt: start, endedAt: end,
                summary: trimmedSummary,
                nextAction: na.isEmpty ? nil : na,
                durationSeconds: duration,
                modelVersion: original.modelVersion
            )
        }
        onSubmit(entry)
    }
}
