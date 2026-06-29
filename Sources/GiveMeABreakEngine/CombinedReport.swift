import Foundation

// MARK: - 综合报告（工作日志 + 运动记录，纯函数：零副作用、确定性、可单测）
//
// 将工作日志（WorkLogEntry）与运动记录（ExerciseEntry）一并按 周 / 月 / 季 / 年 合成。
// 与 WorkLogReport 同范式：结构化模型（buildCombinedReportModel，单一事实源）由两个渲染器消费——
// `renderCombinedReport` 序列化为导出 Markdown；UI 层（CombinedReportView）原生层级渲染。
// 复用 ReportDateKeys.swift 的日期键与 humanizedDuration，不改动 WorkLogReportScope（既有工作日志窗零回归）。

/// 综合报告周期粒度。`now` + `timeZone` 决定「本周/本月/本季/本年」边界。
public enum CombinedReportScope: String, Equatable, Sendable, CaseIterable {
    case week
    case month
    case quarter
    case year
}

// MARK: - 结构化模型（单一事实源）

/// 工作侧子周期分布行（周→按日、月→按周、季/年→按月）。
public struct CombinedPeriodRow: Equatable, Sendable {
    public let key: String          // "2026-06-25" / "2026-W26" / "2026-06"
    public let label: String        // "2026-06-25 周四" / "2026-W26" / "2026-06"
    public let count: Int
    public let totalSeconds: TimeInterval
    public init(key: String, label: String, count: Int, totalSeconds: TimeInterval) {
        self.key = key; self.label = label; self.count = count; self.totalSeconds = totalSeconds
    }
}

/// 通用「条数 + 数量」聚合行（按运动类型，或运动按月汇总复用）。
public struct CombinedCountRepRow: Equatable, Sendable {
    public let key: String          // 运动类型名 或 monthKey
    public let sessions: Int        // 记录条数
    public let reps: Int            // 总数量
    public init(key: String, sessions: Int, reps: Int) {
        self.key = key; self.sessions = sessions; self.reps = reps
    }
}

/// 工作回顾段。
public struct CombinedWorkSection: Equatable, Sendable {
    public let sessionCount: Int
    public let totalFocusSeconds: TimeInterval
    public let top: [WorkLogEntry]          // 按时长降序前 3（只读展示）
    public let byPeriod: [CombinedPeriodRow]
    public init(sessionCount: Int, totalFocusSeconds: TimeInterval, top: [WorkLogEntry], byPeriod: [CombinedPeriodRow]) {
        self.sessionCount = sessionCount; self.totalFocusSeconds = totalFocusSeconds
        self.top = top; self.byPeriod = byPeriod
    }
    public var isEmpty: Bool { sessionCount == 0 }
}

/// 运动概览段。
public struct CombinedExerciseSection: Equatable, Sendable {
    public let sessionCount: Int            // 运动记录条数
    public let totalReps: Int               // 总数量
    public let byType: [CombinedCountRepRow] // key = 类型名（按总数量降序、并列类型名升序）
    public let sessions: [ExerciseEntry]    // 逐条明细（week/month 填充；quarter/year 为空）
    public let byMonth: [CombinedCountRepRow] // 按月汇总（quarter/year 填充；week/month 为空，key = monthKey 升序）
    public init(sessionCount: Int, totalReps: Int, byType: [CombinedCountRepRow],
                sessions: [ExerciseEntry], byMonth: [CombinedCountRepRow]) {
        self.sessionCount = sessionCount; self.totalReps = totalReps
        self.byType = byType; self.sessions = sessions; self.byMonth = byMonth
    }
    public var isEmpty: Bool { sessionCount == 0 }
}

/// 结构化综合报告模型（纯数据、确定性、可单测）。
public struct CombinedReportModel: Equatable, Sendable {
    public let scope: CombinedReportScope
    public let title: String        // 纯文本标题（无 "# " 前缀），如「综合报告 · 本周 · 2026-W26」
    public let meta: String         // 纯文本元数据（无 "> " 前缀）
    public let isEmpty: Bool        // 工作与运动均空
    public let work: CombinedWorkSection
    public let exercise: CombinedExerciseSection
    public init(scope: CombinedReportScope, title: String, meta: String, isEmpty: Bool,
                work: CombinedWorkSection, exercise: CombinedExerciseSection) {
        self.scope = scope; self.title = title; self.meta = meta; self.isEmpty = isEmpty
        self.work = work; self.exercise = exercise
    }
}

// MARK: - 过滤（按 scope 以 startedAt 在指定时区分桶；返回保持时间升序）

/// 综合报告分桶键（按 scope）。
private func combinedPeriodKey(_ date: Date, scope: CombinedReportScope, calendar: Calendar) -> String {
    switch scope {
    case .week:    return weekKey(date, calendar: calendar)
    case .month:   return monthKey(date, calendar: calendar)
    case .quarter: return quarterKey(date, calendar: calendar)
    case .year:    return yearKey(date, calendar: calendar)
    }
}

/// 按 scope 过滤运动记录（以 `startedAt` 分桶）。返回保持时间升序。
public func filterExerciseEntries(
    _ entries: [ExerciseEntry],
    scope: CombinedReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> [ExerciseEntry] {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let nowKey = combinedPeriodKey(now, scope: scope, calendar: cal)
    return entries
        .filter { combinedPeriodKey($0.startedAt, scope: scope, calendar: cal) == nowKey }
        .sorted { $0.startedAt < $1.startedAt }
}

/// 按 scope 过滤工作日志（综合报告专用，以 `startedAt` 分桶）。返回保持时间升序。
public func filterWorkLogEntriesForCombined(
    _ entries: [WorkLogEntry],
    scope: CombinedReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> [WorkLogEntry] {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let nowKey = combinedPeriodKey(now, scope: scope, calendar: cal)
    return entries
        .filter { combinedPeriodKey($0.startedAt, scope: scope, calendar: cal) == nowKey }
        .sorted { $0.startedAt < $1.startedAt }
}

// MARK: - 聚合

/// 按运动类型聚合：sessions = 含该类型的记录条数；reps = 该类型总数量。
/// 排序：总数量降序，并列按类型名升序（确定性）。
public func exerciseTypeSummary(_ entries: [ExerciseEntry]) -> [CombinedCountRepRow] {
    var repsByType: [String: Int] = [:]
    var sessionsByType: [String: Int] = [:]
    for e in entries {
        var typesInEntry = Set<String>()
        for set in e.sets where !set.type.isEmpty {
            repsByType[set.type, default: 0] += set.reps
            typesInEntry.insert(set.type)
        }
        for t in typesInEntry { sessionsByType[t, default: 0] += 1 }
    }
    return repsByType.keys.map {
        CombinedCountRepRow(key: $0, sessions: sessionsByType[$0] ?? 0, reps: repsByType[$0] ?? 0)
    }.sorted { lhs, rhs in
        lhs.reps != rhs.reps ? lhs.reps > rhs.reps : lhs.key < rhs.key
    }
}

/// 运动按月汇总（季/年报用）：key = monthKey 升序，sessions = 记录条数，reps = 总数量。
private func exerciseByMonth(_ entries: [ExerciseEntry], calendar: Calendar) -> [CombinedCountRepRow] {
    var dict: [String: (sessions: Int, reps: Int)] = [:]
    for e in entries {
        let key = monthKey(e.startedAt, calendar: calendar)
        var v = dict[key] ?? (0, 0)
        v.sessions += 1
        v.reps += e.totalReps
        dict[key] = v
    }
    return dict.sorted { $0.key < $1.key }
        .map { CombinedCountRepRow(key: $0.key, sessions: $0.value.sessions, reps: $0.value.reps) }
}

/// 工作子周期分布（周→按日、月→按周、季/年→按月）。返回键升序。
private func workByPeriod(_ entries: [WorkLogEntry], scope: CombinedReportScope, calendar: Calendar) -> [CombinedPeriodRow] {
    var dict: [String: (count: Int, seconds: TimeInterval, firstDate: Date)] = [:]
    for e in entries {
        let key: String
        switch scope {
        case .week:                 key = dayKey(e.startedAt, calendar: calendar)
        case .month:                key = weekKey(e.startedAt, calendar: calendar)
        case .quarter, .year:       key = monthKey(e.startedAt, calendar: calendar)
        }
        var v = dict[key] ?? (0, 0, e.startedAt)
        v.count += 1
        v.seconds += e.durationSeconds
        v.firstDate = min(v.firstDate, e.startedAt)
        dict[key] = v
    }
    return dict.sorted { $0.key < $1.key }.map { key, v in
        let label: String
        switch scope {
        case .week:                 label = "\(key) \(weekdayCN(v.firstDate, calendar: calendar))"
        case .month, .quarter, .year: label = key
        }
        return CombinedPeriodRow(key: key, label: label, count: v.count, totalSeconds: v.seconds)
    }
}

private func workTotalSeconds(_ entries: [WorkLogEntry]) -> TimeInterval {
    entries.reduce(0) { $0 + $1.durationSeconds }
}

// MARK: - 构建模型（确定性幂等：过滤/分组/排序/统计逻辑的唯一来源）

public func buildCombinedReportModel(
    workEntries: [WorkLogEntry],
    exerciseEntries: [ExerciseEntry],
    scope: CombinedReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> CombinedReportModel {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let tz = timeZoneIdentifier(timeZone)

    let work = filterWorkLogEntriesForCombined(workEntries, scope: scope, now: now, calendar: calendar, timeZone: timeZone)
    let exercise = filterExerciseEntries(exerciseEntries, scope: scope, now: now, calendar: calendar, timeZone: timeZone)

    // 工作：Top 3（时长降序，并列时间升序）+ 子周期分布
    let workTop = Array(work.sorted { lhs, rhs in
        lhs.durationSeconds != rhs.durationSeconds
            ? lhs.durationSeconds > rhs.durationSeconds
            : lhs.startedAt < rhs.startedAt
    }.prefix(3))
    let workSection = CombinedWorkSection(
        sessionCount: work.count,
        totalFocusSeconds: workTotalSeconds(work),
        top: workTop,
        byPeriod: workByPeriod(work, scope: scope, calendar: cal)
    )

    // 运动：按类型聚合 + （week/month 逐条明细 / quarter/year 按月汇总）
    let detailedSessions = (scope == .week || scope == .month) ? exercise : []
    let monthRollup = (scope == .quarter || scope == .year) ? exerciseByMonth(exercise, calendar: cal) : []
    let exerciseSection = CombinedExerciseSection(
        sessionCount: exercise.count,
        totalReps: exercise.reduce(0) { $0 + $1.totalReps },
        byType: exerciseTypeSummary(exercise),
        sessions: detailedSessions,
        byMonth: monthRollup
    )

    let title = combinedTitle(scope: scope, now: now, calendar: cal)
    let meta = combinedMeta(scope: scope, now: now, calendar: cal, timeZone: tz, work: workSection, exercise: exerciseSection)

    return CombinedReportModel(
        scope: scope, title: title, meta: meta,
        isEmpty: workSection.isEmpty && exerciseSection.isEmpty,
        work: workSection, exercise: exerciseSection
    )
}

// MARK: - Markdown 序列化（消费模型 → 字符串；确定性幂等，golden 快照守护）

/// 把一次记录的若干组渲染为「深蹲×20 + 俯卧撑×15」（跳过空类型组）。
public func exerciseSetsText(_ entry: ExerciseEntry) -> String {
    entry.sets
        .filter { !$0.type.isEmpty }
        .map { "\($0.type)×\($0.reps)" }
        .joined(separator: " + ")
}

public func renderCombinedReport(
    workEntries: [WorkLogEntry],
    exerciseEntries: [ExerciseEntry],
    scope: CombinedReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> String {
    let model = buildCombinedReportModel(
        workEntries: workEntries, exerciseEntries: exerciseEntries,
        scope: scope, now: now, calendar: calendar, timeZone: timeZone
    )
    let cal = isoCalendar(base: calendar, timeZone: timeZone)

    var out = ""
    out += "# " + model.title + "\n\n"
    out += "> " + model.meta + "\n\n"

    if model.isEmpty {
        out += "\n_（暂无记录）_\n"
        return out
    }

    // 工作回顾
    out += "## 工作回顾\n\n"
    if model.work.isEmpty {
        out += "_（暂无工作记录）_\n\n"
    } else {
        out += "### Top 3\n\n"
        for e in model.work.top {
            out += "- \(e.summary)（\(humanizedDuration(e.durationSeconds))）\n"
        }
        out += "\n"
        out += "### 周期分布\n\n"
        for r in model.work.byPeriod {
            out += "- \(r.label) · \(r.count) 条 · \(humanizedDuration(r.totalSeconds))\n"
        }
        out += "\n"
    }

    // 运动概览
    out += "## 运动概览\n\n"
    if model.exercise.isEmpty {
        out += "_（暂无运动记录）_\n"
        return out
    }
    out += "### 按类型\n\n"
    out += "| 动作 | 记录数 | 总数量 |\n"
    out += "|---|---:|---:|\n"
    for r in model.exercise.byType {
        out += "| \(r.key) | \(r.sessions) | \(r.reps) |\n"
    }
    out += "\n"

    if scope == .week || scope == .month {
        out += "### 明细\n\n"
        for e in model.exercise.sessions {
            out += "- **\(hhmm(e.startedAt, calendar: cal))** · \(exerciseSetsText(e))\n"
            if let note = e.note { out += "  > 备注：\(note)\n" }
        }
        out += "\n"
    } else {
        out += "### 按月\n\n"
        out += "| 月份 | 记录数 | 总数量 |\n"
        out += "|---|---:|---:|\n"
        for r in model.exercise.byMonth {
            out += "| \(r.key) | \(r.sessions) | \(r.reps) |\n"
        }
        out += "\n"
    }
    return out
}

// MARK: - 标题 / 元数据（纯文本，无 Markdown 前缀；供模型与序列化器共用）

private func combinedScopeLabel(_ scope: CombinedReportScope) -> String {
    switch scope {
    case .week:    return "本周"
    case .month:   return "本月"
    case .quarter: return "本季"
    case .year:    return "本年"
    }
}

private func combinedTitle(scope: CombinedReportScope, now: Date, calendar: Calendar) -> String {
    "综合报告 · \(combinedScopeLabel(scope)) · \(combinedPeriodKey(now, scope: scope, calendar: calendar))"
}

private func combinedMeta(scope: CombinedReportScope, now: Date, calendar: Calendar, timeZone: String,
                          work: CombinedWorkSection, exercise: CombinedExerciseSection) -> String {
    let period = combinedPeriodKey(now, scope: scope, calendar: calendar)
    return "周期 \(period)（\(timeZone)） · 工作 \(work.sessionCount) 条 · 专注 \(humanizedDuration(work.totalFocusSeconds)) · 运动 \(exercise.sessionCount) 次 · 共 \(exercise.totalReps) 个"
}
