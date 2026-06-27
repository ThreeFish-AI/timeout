import SwiftUI
import AppKit
import GiveMeABreakEngine

/// 工作日志报告视图：周期切换（今日/本周/本月/全部）+ **原生层级化阅读器** + 逐条编辑/删除 + 复制/导出/清空。
///
/// 阅读器消费 `buildWorkLogReportModel(...)`（结构化模型，单一事实源），用原生 SwiftUI 渲染标题/元数据/
/// Top 3/明细/月度汇总/待续——比等宽原貌更具层级与可读性，且零第三方依赖。明细行携带原始 `WorkLogEntry`（含 id），
/// 悬停显隐「编辑/删除」、右键菜单常驻（不依赖 hover-only），编辑/新增经 `.sheet` 复用 `WorkLogEntryFormView`。
/// 复制/导出仍输出 `renderWorkLogReport(...)` 的 Markdown（与模型同源，行为零回归）；清空走 NSAlert 二次确认。
struct WorkLogReportView: View {
    private let store: WorkLogStore
    private let onClose: () -> Void

    @State private var scope: WorkLogReportScope
    @State private var model: WorkLogReportModel?
    @State private var reportMarkdown: String = ""
    @State private var entryCount: Int = 0
    @State private var showClearConfirm: Bool = false
    @State private var clearAlertMessage: String = ""
    @State private var activeSheet: ActiveSheet?
    @State private var pendingDelete: WorkLogEntry?

    init(store: WorkLogStore, initialScope: WorkLogReportScope = .today, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _scope = State(initialValue: initialScope)
    }

    /// 编辑/新增弹窗的两种来源（`.sheet(item:)` 需 Identifiable）。
    private enum ActiveSheet: Identifiable {
        case create
        case edit(WorkLogEntry)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let e): return "edit-\(e.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 720, minHeight: 460, idealHeight: 560)
        .onAppear { regenerate() }
        .sheet(item: $activeSheet) { sheet in sheetForm(sheet) }
    }

    // MARK: - 工具栏（周期 + 条数）

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("周期", selection: $scope) {
                Text("今日").tag(WorkLogReportScope.today)
                Text("本周").tag(WorkLogReportScope.week)
                Text("本月").tag(WorkLogReportScope.month)
                Text("全部").tag(WorkLogReportScope.all)
            }
            .pickerStyle(.segmented)
            .onChange(of: scope) { _, _ in regenerate() }
            Spacer()
            Text("\(entryCount) 条")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - 内容（原生阅读器 / 空态）

    @ViewBuilder private var content: some View {
        if let model, !model.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header(model)
                    topThreeSection(model)
                    detailSection(model.detail)
                    nextActionsSection(model.nextActions)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 删除二次确认（挂在内容区，避免与「清空」alert 冲突）
            .alert("删除这条记录？",
                   isPresented: Binding(get: { pendingDelete != nil },
                                        set: { if !$0 { pendingDelete = nil } }),
                   presenting: pendingDelete) { entry in
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    store.delete(id: entry.id)
                    pendingDelete = nil
                    regenerate()
                }
            } message: { entry in
                Text("将删除「\(entry.summary)」（\(humanizedDuration(entry.durationSeconds))），且不可恢复。")
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("（暂无记录）")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("点击「补录…」记录一段已完成的工作。")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button("补录…") { activeSheet = .create }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 章节

    private func header(_ model: WorkLogReportModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.meta)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func topThreeSection(_ model: WorkLogReportModel) -> some View {
        section(model.topThreeTitle) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.topThree.enumerated()), id: \.element.id) { idx, entry in
                    HStack(spacing: 10) {
                        rankBadge(idx + 1)
                        Text(entry.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(humanizedDuration(entry.durationSeconds))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.teal)
                    }
                }
            }
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        let opacity = [1: 0.9, 2: 0.65, 3: 0.45][rank] ?? 0.35
        return Text("\(rank)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.teal.opacity(opacity)))
    }

    @ViewBuilder private func detailSection(_ detail: WorkLogReportDetail) -> some View {
        switch detail {
        case .completion(let entries):
            section("完成清单") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries, id: \.id) { entryRow($0) }
                }
            }
        case .byDay(let groups):
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("按日拆解")
                ForEach(groups, id: \.dayKey) { g in
                    groupBlock(title: "\(g.dayKey) \(g.weekday) · \(humanizedDuration(g.totalSeconds))", entries: g.entries)
                }
            }
        case .byWeek(let groups):
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("按周拆解")
                ForEach(groups, id: \.weekKey) { g in
                    groupBlock(title: "\(g.weekKey) · \(g.count) 条 · \(humanizedDuration(g.totalSeconds))", entries: g.entries)
                }
            }
        case .byMonth(let rows):
            section("按月汇总") { monthGrid(rows) }
        }
    }

    private func groupBlock(title: String, entries: [WorkLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.bottom, 2)
            ForEach(entries, id: \.id) { entryRow($0) }
        }
    }

    private func monthGrid(_ rows: [WorkLogMonthSummary]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("月份").gridColumnAlignment(.leading)
                Text("条数").gridColumnAlignment(.trailing)
                Text("专注").gridColumnAlignment(.trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            Divider().gridCellColumns(3)
            ForEach(rows, id: \.monthKey) { r in
                GridRow {
                    Text(r.monthKey).font(.system(size: 13, design: .monospaced))
                    Text("\(r.count)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    Text(humanizedDuration(r.totalSeconds)).font(.system(size: 13, design: .monospaced)).foregroundStyle(.teal)
                }
            }
        }
    }

    @ViewBuilder private func nextActionsSection(_ actions: [String]) -> some View {
        if !actions.isEmpty {
            section("待续 · 下一步") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.teal)
                            Text(a).font(.system(size: 13)).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 明细行（可编辑/删除单元）

    private func entryRow(_ entry: WorkLogEntry) -> some View {
        WorkLogEntryRow(
            entry: entry,
            onEdit: { activeSheet = .edit(entry) },
            onDelete: { pendingDelete = entry },
            onCopy: { copyToClipboard(entryMarkdown(entry)) }
        )
    }

    // MARK: - 章节脚手架

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            content()
        }
    }

    // MARK: - 底部操作

    private var footer: some View {
        HStack {
            Button("复制") { copyToClipboard(reportMarkdown) }
                .disabled(entryCount == 0)
            Button("导出 .md…") { exportMarkdown() }
                .disabled(entryCount == 0)
            Button("补录…") { activeSheet = .create }
            Spacer()
            Button("清空…", role: .destructive) { confirmClear() }
                .disabled(entryCount == 0)
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
        .alert("清空全部工作日志？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                store.replaceAll([])
                regenerate()
            }
        } message: {
            Text(clearAlertMessage)
        }
    }

    // MARK: - 编辑 / 新增弹窗

    @ViewBuilder private func sheetForm(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .create:
            let lastEnd = store.loadEntries().last?.endedAt
            WorkLogEntryFormView(
                mode: .create(defaultStart: lastEnd ?? Date().addingTimeInterval(-50 * 60), defaultEnd: Date()),
                onSubmit: { entry in
                    store.append(entry)
                    activeSheet = nil
                    regenerate()
                },
                onCancel: { activeSheet = nil }
            )
        case .edit(let entry):
            WorkLogEntryFormView(
                mode: .edit(entry),
                onSubmit: { updated in
                    store.update(updated)
                    activeSheet = nil
                    regenerate()
                },
                onCancel: { activeSheet = nil }
            )
        }
    }

    // MARK: - 渲染（重算模型 + Markdown）

    private func regenerate() {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let entries = store.loadEntries()
        let scoped = filterWorkLogEntries(entries, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
        entryCount = scoped.count
        model = buildWorkLogReportModel(entries: entries, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
        reportMarkdown = renderWorkLogReport(entries: entries, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
    }

    // MARK: - 复制 / 导出 / 清空

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 单条记录的 Markdown（供「复制本条」右键菜单），对齐报告内明细行格式。
    private func entryMarkdown(_ entry: WorkLogEntry) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: entry.startedAt)
        let hhmm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        var s = "- **\(hhmm)** · \(humanizedDuration(entry.durationSeconds)) — \(entry.summary)"
        if let na = entry.nextAction { s += "\n  > 下一步：\(na)" }
        return s
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportMarkdown.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            NSLog("[GiveMeABreak][worklog] 导出失败：\(error)")
        }
    }

    private func defaultFilename() -> String {
        let cal = Calendar.current
        let now = Date()
        switch scope {
        case .today:
            return "\(dayKeyPublic(now, cal: cal)).md"
        case .week:
            return "\(weekKeyPublic(now, cal: cal)).md"
        case .month:
            return "\(monthKeyPublic(now, cal: cal)).md"
        case .all:
            return "work-log-all.md"
        }
    }

    private func confirmClear() {
        // 提示先导出再清空（AGENTS.md 数据谨慎）
        clearAlertMessage = "将永久删除 \(entryCount) 条记录，且不可恢复。建议先「导出 .md」备份后再清空。"
        showClearConfirm = true
    }
}

// MARK: - 明细行子视图（自持悬停态；右键菜单常驻 + 悬停显隐内联操作）

private struct WorkLogEntryRow: View {
    let entry: WorkLogEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false

    private var clock: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: entry.startedAt)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(clock)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(humanizedDuration(entry.durationSeconds))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("—").foregroundStyle(.secondary)
                Text(entry.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if hovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("编辑")
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("删除")
                }
            }
            if let na = entry.nextAction {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.teal.opacity(0.6)).frame(width: 2)
                    Text("下一步：\(na)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
            Button { onCopy() } label: { Label("复制本条", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
        }
    }
}

// MARK: - 日期键（导出文件名用，对齐 WorkLogReport 内部格式）

private func dayKeyPublic(_ date: Date, cal: Calendar) -> String {
    let p = cal.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
}
private func monthKeyPublic(_ date: Date, cal: Calendar) -> String {
    let p = cal.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", p.year ?? 0, p.month ?? 0)
}
private func weekKeyPublic(_ date: Date, cal: Calendar) -> String {
    var c = cal
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    let y = c.component(.yearForWeekOfYear, from: date)
    let w = c.component(.weekOfYear, from: date)
    return String(format: "%04d-W%02d", y, w)
}
