import Foundation

// MARK: - 报告日期键（手动拼接，零 locale 依赖，确定性；报告聚合的单一事实源）
//
// 自 WorkLogReport.swift 抽出为 internal 共享工具，供工作日志报告与综合报告（CombinedReport）共用，
// 杜绝多处重复的日期分桶/格式化逻辑（SSOT）。行为与历史逐字节一致（golden 快照守护）。

/// ISO 周历（周一为首日、首周含首个周四）。复用传入 calendar 的 timeZone。
func isoCalendar(base: Calendar, timeZone: TimeZone) -> Calendar {
    var c = base
    c.timeZone = timeZone
    c.firstWeekday = 2                  // 周一
    c.minimumDaysInFirstWeek = 4        // ISO 8601
    return c
}

func dayKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
}

func monthKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", p.year ?? 0, p.month ?? 0)
}

func weekKey(_ date: Date, calendar: Calendar) -> String {
    // calendar 已配置为 ISO 8601（周一首日、首周含首个周四）：
    // yearForWeekOfYear + weekOfYear 即 ISO 周日期（YYYY-Www）。
    let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
    let week = calendar.component(.weekOfYear, from: date)
    return String(format: "%04d-W%02d", yearForWeek, week)
}

/// 季度键「YYYY-Qn」（n=1…4，以自然月划分：1-3→Q1，4-6→Q2，7-9→Q3，10-12→Q4）。
func quarterKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month], from: date)
    let month = p.month ?? 1
    let quarter = (month - 1) / 3 + 1
    return String(format: "%04d-Q%d", p.year ?? 0, quarter)
}

/// 年份键「YYYY」。
func yearKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year], from: date)
    return String(format: "%04d", p.year ?? 0)
}

func hhmm(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
}

func weekdayCN(_ date: Date, calendar: Calendar) -> String {
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

func timeZoneIdentifier(_ tz: TimeZone) -> String {
    tz.identifier
}
