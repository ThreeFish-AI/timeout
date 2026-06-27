import Foundation

// MARK: - 工作日志报告（纯函数：零副作用、确定性、可单测）

/// 报告周期粒度。`now` + `timeZone` 决定「今日/本周/本月」的边界。
public enum WorkLogReportScope: String, Equatable, Sendable {
    case today
    case week
    case month
    case all
}

/// 将秒数格式化为人类可读时长：「1h 30m」/「45m」/「2h」/「0m」。用于报告与提示上下文。
public func humanizedDuration(_ seconds: TimeInterval) -> String {
    let totalMin = max(0, Int((seconds / 60).rounded()))
    let h = totalMin / 60
    let m = totalMin % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}

/// 按 `scope` 过滤条目（以 `startedAt` 在指定时区分桶）。返回保持时间升序。
public func filterWorkLogEntries(
    _ entries: [WorkLogEntry],
    scope: WorkLogReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> [WorkLogEntry] {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let nowDay = dayKey(now, calendar: cal)
    let nowMonth = monthKey(now, calendar: cal)
    let nowWeek = weekKey(now, calendar: cal)
    return entries.filter { e in
        switch scope {
        case .today:  return dayKey(e.startedAt, calendar: cal) == nowDay
        case .week:   return weekKey(e.startedAt, calendar: cal) == nowWeek
        case .month:  return monthKey(e.startedAt, calendar: cal) == nowMonth
        case .all:    return true
        }
    }.sorted { $0.startedAt < $1.startedAt }
}

// MARK: - 结构化报告模型（单一事实源：聚合逻辑只此一处）
//
// 同一模型由两个渲染器消费：`renderWorkLogReport` 序列化为导出 Markdown 字符串；
// `WorkLogReportView`（UI 层）原生渲染为层级化阅读器。明细分组携带原始 `WorkLogEntry`（含 id），
// 使阅读器的逐条编辑/删除可精确定位记录。聚合行（Top 3 / 按月汇总）为派生统计，不可逆编辑。

/// 「按日」分组（周报用）。
public struct WorkLogDayGroup: Equatable, Sendable {
    public let dayKey: String          // "2026-06-22"
    public let weekday: String         // "周一"
    public let totalSeconds: TimeInterval
    public let entries: [WorkLogEntry] // 组内按 startedAt 升序
    public init(dayKey: String, weekday: String, totalSeconds: TimeInterval, entries: [WorkLogEntry]) {
        self.dayKey = dayKey; self.weekday = weekday; self.totalSeconds = totalSeconds; self.entries = entries
    }
}

/// 「按周」分组（月报用）。
public struct WorkLogWeekGroup: Equatable, Sendable {
    public let weekKey: String         // "2026-W23"
    public let count: Int
    public let totalSeconds: TimeInterval
    public let entries: [WorkLogEntry] // 组内按 startedAt 升序
    public init(weekKey: String, count: Int, totalSeconds: TimeInterval, entries: [WorkLogEntry]) {
        self.weekKey = weekKey; self.count = count; self.totalSeconds = totalSeconds; self.entries = entries
    }
}

/// 「按月汇总」行（全部记录用，纯聚合统计，无逐条 entry）。
public struct WorkLogMonthSummary: Equatable, Sendable {
    public let monthKey: String        // "2026-06"
    public let count: Int
    public let totalSeconds: TimeInterval
    public init(monthKey: String, count: Int, totalSeconds: TimeInterval) {
        self.monthKey = monthKey; self.count = count; self.totalSeconds = totalSeconds
    }
}

/// 周期专属明细：今日=完成清单；本周=按日；本月=按周；全部=按月汇总表。
public enum WorkLogReportDetail: Equatable, Sendable {
    case completion([WorkLogEntry])    // today：逐条（可编辑/删除）
    case byDay([WorkLogDayGroup])      // week
    case byWeek([WorkLogWeekGroup])    // month
    case byMonth([WorkLogMonthSummary]) // all：聚合表
}

/// 结构化工作日志报告模型（纯数据、确定性、可单测）。
public struct WorkLogReportModel: Equatable, Sendable {
    public let scope: WorkLogReportScope
    public let title: String           // 纯文本标题（无 "# " 前缀），如「今日工作回顾 · 2026-06-25 周四」
    public let meta: String            // 纯文本元数据（无 "> " 前缀），如「周期 2026-06-25（GMT） · 2 条记录 · 专注 1h 40m」
    public let isEmpty: Bool
    public let topThreeTitle: String   // 「今日 Top 3」/「本周三件事」/…
    public let topThree: [WorkLogEntry] // 已按时长降序（并列时间升序）取前 3
    public let detail: WorkLogReportDetail
    public let nextActions: [String]   // 按 scoped 时间升序提取的非空 nextAction

    public init(scope: WorkLogReportScope, title: String, meta: String, isEmpty: Bool,
                topThreeTitle: String, topThree: [WorkLogEntry],
                detail: WorkLogReportDetail, nextActions: [String]) {
        self.scope = scope; self.title = title; self.meta = meta; self.isEmpty = isEmpty
        self.topThreeTitle = topThreeTitle; self.topThree = topThree
        self.detail = detail; self.nextActions = nextActions
    }
}

/// 构建结构化报告模型（确定性幂等）：所有过滤/分组/排序/统计逻辑的唯一来源。
public func buildWorkLogReportModel(
    entries: [WorkLogEntry],
    scope: WorkLogReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> WorkLogReportModel {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let scoped = filterWorkLogEntries(entries, scope: scope, now: now, calendar: calendar, timeZone: timeZone)
    let tz = timeZoneIdentifier(timeZone)

    let title = reportTitleText(scope: scope, now: now, calendar: cal)
    let meta = metaText(scope: scope, entries: scoped, now: now, calendar: cal, timeZone: tz)
    let top3Title = topThreeTitle(scope: scope)

    if scoped.isEmpty {
        return WorkLogReportModel(scope: scope, title: title, meta: meta, isEmpty: true,
                                  topThreeTitle: top3Title, topThree: [],
                                  detail: emptyDetail(for: scope), nextActions: [])
    }

    // Top 3（按时长降序，并列按时间升序）
    let topThree = Array(scoped.sorted { lhs, rhs in
        lhs.durationSeconds != rhs.durationSeconds
            ? lhs.durationSeconds > rhs.durationSeconds
            : lhs.startedAt < rhs.startedAt
    }.prefix(3))

    let detail: WorkLogReportDetail
    switch scope {
    case .today:
        detail = .completion(scoped)
    case .week:
        detail = .byDay(groupByDay(scoped, calendar: cal).map { key, list in
            WorkLogDayGroup(dayKey: key,
                            weekday: weekdayCN(list.first!.startedAt, calendar: cal),
                            totalSeconds: totalSeconds(list),
                            entries: list)
        })
    case .month:
        detail = .byWeek(groupByWeek(scoped, calendar: cal).map { key, list in
            WorkLogWeekGroup(weekKey: key, count: list.count,
                             totalSeconds: totalSeconds(list), entries: list)
        })
    case .all:
        detail = .byMonth(groupByMonth(scoped, calendar: cal).map { key, list in
            WorkLogMonthSummary(monthKey: key, count: list.count, totalSeconds: totalSeconds(list))
        })
    }

    let nextActions = scoped.compactMap { $0.nextAction }

    return WorkLogReportModel(scope: scope, title: title, meta: meta, isEmpty: false,
                              topThreeTitle: top3Title, topThree: topThree,
                              detail: detail, nextActions: nextActions)
}

/// 空 scoped 时的明细占位容器（与 scope 对应；不会被序列化/渲染，仅满足模型完整性）。
private func emptyDetail(for scope: WorkLogReportScope) -> WorkLogReportDetail {
    switch scope {
    case .today: return .completion([])
    case .week:  return .byDay([])
    case .month: return .byWeek([])
    case .all:   return .byMonth([])
    }
}

private func totalSeconds(_ entries: [WorkLogEntry]) -> TimeInterval {
    entries.reduce(0) { $0 + $1.durationSeconds }
}

// MARK: - Markdown 序列化（消费模型 → 字符串；与历史产物逐字节一致，golden 快照守护）

/// 渲染 Markdown 报告（确定性幂等：同 entries + 同 now/cal/tz → 字节一致）。
/// 结构：恰好一个 H1（标题+周期）+ blockquote 元数据 + 周期专属章节（Top 3 / 按日或按周拆解 / 待续·下一步）。
public func renderWorkLogReport(
    entries: [WorkLogEntry],
    scope: WorkLogReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> String {
    let model = buildWorkLogReportModel(entries: entries, scope: scope, now: now, calendar: calendar, timeZone: timeZone)
    let cal = isoCalendar(base: calendar, timeZone: timeZone)  // hhmm 用 ISO 周历（与历史一致）

    var out = ""
    out += "# " + model.title + "\n\n"
    out += "> " + model.meta + "\n\n"

    if model.isEmpty {
        out += "\n_（暂无记录）_\n"
        return out
    }

    // Top 3
    out += "## \(model.topThreeTitle)\n\n"
    if model.topThree.isEmpty {
        out += "_（暂无）_\n\n"
    } else {
        for e in model.topThree {
            out += "- \(e.summary)（\(humanizedDuration(e.durationSeconds))）\n"
        }
        out += "\n"
    }

    // 周期专属明细（today=完成清单 / week=按日 / month=按周 / all=按月汇总表）
    out += serializeDetail(model.detail, calendar: cal)

    // 待续 · 下一步
    if !model.nextActions.isEmpty {
        out += "## 待续 · 下一步\n\n"
        for a in model.nextActions { out += "- \(a)\n" }
        out += "\n"
    }
    return out
}

private func serializeDetail(_ detail: WorkLogReportDetail, calendar: Calendar) -> String {
    switch detail {
    case .completion(let entries):
        return "## 完成清单\n\n" + entryBullets(entries, calendar: calendar) + "\n"
    case .byDay(let groups):
        var s = "## 按日拆解\n\n"
        for g in groups {
            s += "### \(g.dayKey) \(g.weekday) · \(humanizedDuration(g.totalSeconds))\n\n"
            s += entryBullets(g.entries, calendar: calendar)
            s += "\n"
        }
        return s
    case .byWeek(let groups):
        var s = "## 按周拆解\n\n"
        for g in groups {
            s += "### \(g.weekKey) · \(g.count) 条 · \(humanizedDuration(g.totalSeconds))\n\n"
            s += entryBullets(g.entries, calendar: calendar)
            s += "\n"
        }
        return s
    case .byMonth(let rows):
        var s = "## 按月汇总\n\n"
        s += "| 月份 | 条数 | 专注 |\n"
        s += "|---|---:|---:|\n"
        for r in rows {
            s += "| \(r.monthKey) | \(r.count) | \(humanizedDuration(r.totalSeconds)) |\n"
        }
        s += "\n"
        return s
    }
}

/// 单条记录的 Markdown 项目符号（时间序）：`- **HH:mm** · {时长} — {summary}`，nextAction 以引用块附。
private func entryBullets(_ entries: [WorkLogEntry], calendar: Calendar) -> String {
    var s = ""
    for e in entries {
        s += "- **\(hhmm(e.startedAt, calendar: calendar))** · \(humanizedDuration(e.durationSeconds)) — \(e.summary)\n"
        if let na = e.nextAction {
            s += "  > 下一步：\(na)\n"
        }
    }
    return s
}

// MARK: - 标题 / 元数据（纯文本，无 Markdown 前缀；供模型与序列化器共用）

private func reportTitleText(scope: WorkLogReportScope, now: Date, calendar: Calendar) -> String {
    switch scope {
    case .today:
        return "今日工作回顾 · \(dayKey(now, calendar: calendar)) \(weekdayCN(now, calendar: calendar))"
    case .week:
        return "本周工作回顾 · \(weekKey(now, calendar: calendar))"
    case .month:
        return "本月工作回顾 · \(monthKey(now, calendar: calendar))"
    case .all:
        return "工作日志 · 全部记录"
    }
}

private func metaText(scope: WorkLogReportScope, entries: [WorkLogEntry], now: Date, calendar: Calendar, timeZone: String) -> String {
    let count = entries.count
    let total = totalSeconds(entries)
    let days = Set(entries.map { dayKey($0.startedAt, calendar: calendar) }).count
    switch scope {
    case .today:
        return "周期 \(dayKey(now, calendar: calendar))（\(timeZone)） · \(count) 条记录 · 专注 \(humanizedDuration(total))"
    case .week:
        return "周期 \(weekKey(now, calendar: calendar))（\(timeZone)） · \(count) 条 · 专注 \(humanizedDuration(total)) · \(days) 天"
    case .month:
        return "周期 \(monthKey(now, calendar: calendar))（\(timeZone)） · \(count) 条 · 专注 \(humanizedDuration(total)) · \(days) 天"
    case .all:
        if let earliest = entries.map(\.startedAt).min(), let latest = entries.map(\.startedAt).max() {
            return "\(timeZone) · \(count) 条 · 专注 \(humanizedDuration(total)) · \(days) 天 · 自 \(dayKey(earliest, calendar: calendar)) 至 \(dayKey(latest, calendar: calendar))"
        }
        return "\(timeZone) · 0 条 · 专注 0m"
    }
}

private func topThreeTitle(scope: WorkLogReportScope) -> String {
    switch scope {
    case .today: return "今日 Top 3"
    case .week:  return "本周三件事"
    case .month: return "本月 Top 3"
    case .all:   return "全部 Top 3"
    }
}

// MARK: - 分组（保持键升序）

private func groupByDay(_ entries: [WorkLogEntry], calendar: Calendar) -> [(String, [WorkLogEntry])] {
    var dict: [String: [WorkLogEntry]] = [:]
    for e in entries {
        let key = dayKey(e.startedAt, calendar: calendar)
        dict[key, default: []].append(e)
    }
    return dict.sorted { $0.key < $1.key }
}

private func groupByWeek(_ entries: [WorkLogEntry], calendar: Calendar) -> [(String, [WorkLogEntry])] {
    var dict: [String: [WorkLogEntry]] = [:]
    for e in entries {
        let key = weekKey(e.startedAt, calendar: calendar)
        dict[key, default: []].append(e)
    }
    return dict.sorted { $0.key < $1.key }
}

private func groupByMonth(_ entries: [WorkLogEntry], calendar: Calendar) -> [(String, [WorkLogEntry])] {
    var dict: [String: [WorkLogEntry]] = [:]
    for e in entries {
        let key = monthKey(e.startedAt, calendar: calendar)
        dict[key, default: []].append(e)
    }
    return dict.sorted { $0.key < $1.key }
}

// MARK: - 日期格式化（手动拼接，零 locale 依赖，确定性）

/// ISO 周历（周一为首日、首周含首个周四）。复用传入 calendar 的 timeZone。
private func isoCalendar(base: Calendar, timeZone: TimeZone) -> Calendar {
    var c = base
    c.timeZone = timeZone
    c.firstWeekday = 2                  // 周一
    c.minimumDaysInFirstWeek = 4        // ISO 8601
    return c
}

private func dayKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
}

private func monthKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", p.year ?? 0, p.month ?? 0)
}

private func weekKey(_ date: Date, calendar: Calendar) -> String {
    // calendar 已配置为 ISO 8601（周一首日、首周含首个周四）：
    // yearForWeekOfYear + weekOfYear 即 ISO 周日期（YYYY-Www）。
    let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
    let week = calendar.component(.weekOfYear, from: date)
    return String(format: "%04d-W%02d", yearForWeek, week)
}

private func hhmm(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
}

private func weekdayCN(_ date: Date, calendar: Calendar) -> String {
    // Calendar.weekday：1=周日 … 7=周六
    switch calendar.component(.weekday, from: date) {
    case 1: return "周日"
    case 2: return "周一"
    case 3: return "周二"
    case 4: return "周三"
    case 5: return "周四"
    case 6: return "周五"
    case 7: return "周六"
    default: return ""
    }
}

private func timeZoneIdentifier(_ tz: TimeZone) -> String {
    tz.identifier
}
