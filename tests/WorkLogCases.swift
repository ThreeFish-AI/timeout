import Foundation
import GiveMeABreakEngine

// MARK: - Helpers

private var dirCounter = 0
private func makeTempDir() -> URL {
    dirCounter += 1
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("givemeabreak-worklog-test-\(dirCounter)-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.removeItem(at: dir)
    return dir
}

private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func utcTZ() -> TimeZone { TimeZone(identifier: "UTC")! }

// MARK: - WorkLogStore

func runWorkLogCases() {
    let s = minutes__

    test("WorkLogStore round-trip + 顺序保持") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(50)),
                                  summary: "调试登录 bug", nextAction: "补单测",
                                  durationSeconds: s(50)))
        store.append(WorkLogEntry(startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(110)),
                                  summary: "写周报", durationSeconds: s(50)))

        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2)
        expectEqual(loaded[0].summary, "调试登录 bug")
        expectEqual(loaded[1].summary, "写周报")
        expectEqual(loaded[0].nextAction, "补单测")
        expectEqual(loaded[1].nextAction, nil, "空 nextAction 应规约为 nil")
    }

    test("补录工作日志：追加过去时段条目，按 startedAt 升序落库") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // 已有一条较晚的记录
        store.append(WorkLogEntry(startedAt: t0.addingTimeInterval(3600), endedAt: t0.addingTimeInterval(4200),
                                  summary: "上午的活", durationSeconds: 600))
        // 补录一条更早的漏记时段（模拟菜单「补录工作日志」落库路径）
        store.append(WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(600),
                                  summary: "更早漏掉的", nextAction: "接着调", durationSeconds: 600))

        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2)
        expectEqual(loaded[0].summary, "更早漏掉的", "补录的更早条目应按 startedAt 排到最前")
        expectEqual(loaded[1].summary, "上午的活")
        expectEqual(loaded[0].startedAt, t0)
        expectEqual(loaded[0].nextAction, "接着调", "补录条目的可选「下一步」应保留")
    }

    test("WorkLogStore 缺失/损坏文件 → 空列表") {
        let dir = makeTempDir()
        let store = try! WorkLogStore(directory: dir)
        expectEqual(store.loadEntries().count, 0, "无文件应返回空")

        let url = dir.appendingPathComponent("work-log.json")
        try! "{not json".data(using: .utf8)!.write(to: url, options: .atomic)
        expectEqual(store.loadEntries().count, 0, "损坏 JSON 应回退空")
    }

    test("WorkLogStore replaceAll 清空 + 排序") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(WorkLogEntry(startedAt: t0.addingTimeInterval(s(3)), endedAt: t0.addingTimeInterval(s(4)),
                                  summary: "b", durationSeconds: s(10)))
        store.append(WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(1)),
                                  summary: "a", durationSeconds: s(10)))
        expectEqual(store.loadEntries().count, 2)

        store.replaceAll([])
        expectEqual(store.loadEntries().count, 0, "replaceAll([]) 应清空")

        // replaceAll 应按 startedAt 升序规整
        store.replaceAll([
            WorkLogEntry(startedAt: t0.addingTimeInterval(s(3)), endedAt: t0.addingTimeInterval(s(4)), summary: "late", durationSeconds: s(10)),
            WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(1)), summary: "early", durationSeconds: s(10)),
        ])
        let loaded = store.loadEntries()
        expectEqual(loaded.first?.summary, "early", "应按 startedAt 升序")
    }

    test("WorkLogStore update 按 id 改写并重排升序；未命中 no-op") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(WorkLogEntry(id: "a", startedAt: t0, endedAt: t0.addingTimeInterval(s(50)),
                                  summary: "原", durationSeconds: s(50)))
        store.append(WorkLogEntry(id: "b", startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(110)),
                                  summary: "二", durationSeconds: s(50)))
        // 改 a 的 summary + nextAction，并把 startedAt 推到 b 之后（验证保留 id + 重排）
        store.update(WorkLogEntry(id: "a", startedAt: t0.addingTimeInterval(s(120)), endedAt: t0.addingTimeInterval(s(170)),
                                  summary: "改后", nextAction: "继续", durationSeconds: s(50)))
        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2, "update 不应改变条数")
        expectEqual(loaded[0].id, "b", "a 起始推后应重排到 b 之后")
        expectEqual(loaded[1].id, "a")
        expectEqual(loaded[1].summary, "改后")
        expectEqual(loaded[1].nextAction, "继续")

        store.update(WorkLogEntry(id: "zzz", startedAt: t0, endedAt: t0, summary: "鬼", durationSeconds: 0))
        expectEqual(store.loadEntries().count, 2, "未命中 id 不应新增")
        expect(!store.loadEntries().contains { $0.summary == "鬼" }, "未命中 id 不应写入")
    }

    test("WorkLogStore delete 按 id 删除；删不存在不变") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(WorkLogEntry(id: "a", startedAt: t0, endedAt: t0.addingTimeInterval(s(1)),
                                  summary: "a", durationSeconds: s(10)))
        store.append(WorkLogEntry(id: "b", startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(61)),
                                  summary: "b", durationSeconds: s(10)))
        store.delete(id: "a")
        let loaded = store.loadEntries()
        expectEqual(loaded.count, 1)
        expectEqual(loaded[0].id, "b", "删除 a 后仅余 b")
        store.delete(id: "nope")
        expectEqual(store.loadEntries().count, 1, "删不存在 id 列表不变")
    }

    test("WorkLogEntry 容错解码（缺字段补默认）") {
        // 手写缺字段的 JSON（无 nextAction/modelVersion）
        let json = """
        [{"id":"x","startedAt":0,"endedAt":0,"summary":"ok","durationSeconds":600}]
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode([WorkLogEntry].self, from: json)
        expectEqual(decoded.count, 1)
        expectEqual(decoded[0].nextAction, nil, "缺 nextAction → nil")
        expectEqual(decoded[0].modelVersion, WorkLogEntry.currentModelVersion, "缺 modelVersion → 补当前版本")
    }

    // MARK: - humanizedDuration

    test("humanizedDuration 格式") {
        expectEqual(humanizedDuration(0), "0m")
        expectEqual(humanizedDuration(45 * 60), "45m")
        expectEqual(humanizedDuration(60 * 60), "1h")
        expectEqual(humanizedDuration(90 * 60), "1h 30m")
        expectEqual(humanizedDuration(50 * 60), "50m")
        expectEqual(humanizedDuration(125 * 60), "2h 5m")
    }

    // MARK: - filterWorkLogEntries（分桶边界）

    test("filterWorkLogEntries today/week/month/all 分桶") {
        // 固定 now = 2026-06-25 12:00 UTC（周四）；构造跨日/跨周/跨月条目
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12))!
        let d = { (year: Int, month: Int, day: Int, hour: Int) in
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let entries = [
            WorkLogEntry(startedAt: d(2026, 6, 25, 9), endedAt: d(2026, 6, 25, 9), summary: "今日上午", durationSeconds: s(50)),   // 今日
            WorkLogEntry(startedAt: d(2026, 6, 24, 9), endedAt: d(2026, 6, 24, 9), summary: "昨日", durationSeconds: s(50)),       // 本周非今日
            WorkLogEntry(startedAt: d(2026, 6, 1, 9), endedAt: d(2026, 6, 1, 9), summary: "本月早", durationSeconds: s(50)),       // 本月非本周
            WorkLogEntry(startedAt: d(2026, 5, 20, 9), endedAt: d(2026, 5, 20, 9), summary: "上月", durationSeconds: s(50)),       // 上月
        ]
        expectEqual(filterWorkLogEntries(entries, scope: .today, now: now, calendar: cal, timeZone: tz).count, 1)
        expectEqual(filterWorkLogEntries(entries, scope: .month, now: now, calendar: cal, timeZone: tz).count, 3, "本月 = 今日+昨日+本月早")
        expectEqual(filterWorkLogEntries(entries, scope: .all, now: now, calendar: cal, timeZone: tz).count, 4)
        // 周：2026-06-25 为周四，ISO 周（周一起）覆盖 06-22~06-28 → 含今日+昨日，不含 06-01
        expectEqual(filterWorkLogEntries(entries, scope: .week, now: now, calendar: cal, timeZone: tz).count, 2, "本周含今日+昨日")
    }

    // MARK: - renderWorkLogReport（结构 + 幂等）

    test("renderWorkLogReport 日报结构与幂等") {
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let t0 = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 9))!
        let entries = [
            WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(50)), summary: "调试登录 bug", nextAction: "补单测", durationSeconds: s(50)),
            WorkLogEntry(startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(110)), summary: "写周报第一稿", durationSeconds: s(50)),
        ]
        let md1 = renderWorkLogReport(entries: entries, scope: .today, now: now, calendar: cal, timeZone: tz)
        let md2 = renderWorkLogReport(entries: entries, scope: .today, now: now, calendar: cal, timeZone: tz)

        expect(md1 == md2, "同输入两次渲染必须字节幂等")
        expect(md1.contains("# 今日工作回顾 · 2026-06-25"), "应有 H1 标题与日期")
        expect(md1.contains("2 条记录"), "blockquote 应含条数")
        expect(md1.contains("今日 Top 3"), "应有 Top 3 节")
        expect(md1.contains("完成清单"), "应有完成清单节")
        expect(md1.contains("调试登录 bug"), "应含摘要正文")
        expect(md1.contains("下一步：补单测"), "应含 nextAction 引用块")
        expect(md1.contains("待续 · 下一步"), "应有待续·下一步节")
    }

    test("renderWorkLogReport 空条目不崩且含占位") {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let md = renderWorkLogReport(entries: [], scope: .week, now: now, calendar: cal, timeZone: utcTZ())
        expect(md.contains("暂无记录"), "空应含占位文案")
        expect(md.contains("# 本周工作回顾"), "空也应渲染 H1")
    }

    test("renderWorkLogReport 月报含按周拆解；全部含按月汇总表") {
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let t0 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let entries = [
            WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(50)), summary: "月初", durationSeconds: s(50)),
            WorkLogEntry(startedAt: cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 9))!,
                         endedAt: cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 9))!,
                         summary: "今日", durationSeconds: s(50)),
            WorkLogEntry(startedAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 9))!,
                         endedAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 9))!,
                         summary: "上月", durationSeconds: s(50)),
        ]
        let monthly = renderWorkLogReport(entries: entries, scope: .month, now: now, calendar: cal, timeZone: tz)
        expect(monthly.contains("按周拆解"), "月报应有按周拆解")
        expect(monthly.contains("W"), "按周拆解应含 ISO 周键（YYYY-Www）")

        let all = renderWorkLogReport(entries: entries, scope: .all, now: now, calendar: cal, timeZone: tz)
        expect(all.contains("按月汇总"), "全部应有按月汇总表")
        expect(all.contains("|---|---:|---:|"), "按月汇总应为时长右对齐 Markdown 表")
        expect(all.contains("2026-05") && all.contains("2026-06"), "按月汇总应跨月分行")
    }

    // MARK: - buildWorkLogReportModel（结构化模型：单一事实源）

    test("buildWorkLogReportModel 结构（Top3 排序 / 明细分组 / nextActions / 空态）") {
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let entries = goldenFixtureEntries(cal: cal)

        // today：完成清单含当日 2 条（startedAt 升序）；nextActions 取 scoped 升序
        let today = buildWorkLogReportModel(entries: entries, scope: .today, now: now, calendar: cal, timeZone: tz)
        expect(!today.isEmpty)
        expectEqual(today.topThreeTitle, "今日 Top 3")
        expectEqual(today.topThree.count, 2, "今日仅 2 条")
        if case .completion(let list) = today.detail {
            expectEqual(list.count, 2)
            expectEqual(list[0].summary, "调试登录 bug", "完成清单按 startedAt 升序")
        } else {
            expect(false, "today 明细应为 .completion")
        }
        expectEqual(today.nextActions, ["补单测"])

        // all：Top3 取全局前 3（50/50/40，并列按时间升序）；按月汇总两月
        let all = buildWorkLogReportModel(entries: entries, scope: .all, now: now, calendar: cal, timeZone: tz)
        expectEqual(all.topThree.count, 3)
        expectEqual(all.topThree[0].durationSeconds, s(50))
        if case .byMonth(let rows) = all.detail {
            expectEqual(rows.count, 2)
            expectEqual(rows[0].monthKey, "2026-05")
            expectEqual(rows[1].monthKey, "2026-06")
            expectEqual(rows[1].count, 4)
        } else {
            expect(false, "all 明细应为 .byMonth")
        }
        expectEqual(all.nextActions, ["排期", "补单测"], "nextActions 按 scoped 时间升序")

        // month：按周分组（W23 / W26），W26 含 3 条
        let month = buildWorkLogReportModel(entries: entries, scope: .month, now: now, calendar: cal, timeZone: tz)
        if case .byWeek(let groups) = month.detail {
            expectEqual(groups.count, 2)
            expectEqual(groups[0].weekKey, "2026-W23")
            expectEqual(groups[1].weekKey, "2026-W26")
            expectEqual(groups[1].entries.count, 3)
        } else {
            expect(false, "month 明细应为 .byWeek")
        }

        // 空条目：isEmpty=true，且 detail 为对应空容器
        let empty = buildWorkLogReportModel(entries: [], scope: .today, now: now, calendar: cal, timeZone: tz)
        expect(empty.isEmpty, "空条目 isEmpty=true")
    }

    // MARK: - golden 快照（重构安全网：锁定导出 Markdown 逐字节不变）

    test("renderWorkLogReport golden 快照（四周期，重构前后字节一致）") {
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let entries = goldenFixtureEntries(cal: cal)
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scope in [WorkLogReportScope.today, .week, .month, .all] {
            let md = renderWorkLogReport(entries: entries, scope: scope, now: now, calendar: cal, timeZone: tz)
            let file = dir.appendingPathComponent("worklog_\(scope.rawValue).md")
            if let golden = try? String(contentsOf: file, encoding: .utf8) {
                expectEqual(md, golden, "renderWorkLogReport(\(scope.rawValue)) 偏离 golden 快照——重构破坏了导出 Markdown")
            } else {
                try? md.data(using: .utf8)?.write(to: file, options: .atomic)
                print("  · golden bootstrap 写入 fixtures/\(file.lastPathComponent)")
            }
        }
    }
}

/// golden 快照固定 fixture：跨日(本周)/跨周(本月)/跨月(全部)，覆盖完成清单/按日/按周/按月表与 nextAction 各序列化分支。
private func goldenFixtureEntries(cal: Calendar) -> [WorkLogEntry] {
    func d(_ y: Int, _ mo: Int, _ da: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: da, hour: h, minute: mi))!
    }
    return [
        WorkLogEntry(id: "g1", startedAt: d(2026, 6, 25, 9), endedAt: d(2026, 6, 25, 9, 50), summary: "调试登录 bug", nextAction: "补单测", durationSeconds: 50 * 60),
        WorkLogEntry(id: "g2", startedAt: d(2026, 6, 25, 10), endedAt: d(2026, 6, 25, 10, 50), summary: "写周报第一稿", durationSeconds: 50 * 60),
        WorkLogEntry(id: "g3", startedAt: d(2026, 6, 22, 9), endedAt: d(2026, 6, 22, 9, 30), summary: "周一立项", nextAction: "排期", durationSeconds: 30 * 60),
        WorkLogEntry(id: "g4", startedAt: d(2026, 6, 1, 9), endedAt: d(2026, 6, 1, 9, 40), summary: "月初规划", durationSeconds: 40 * 60),
        WorkLogEntry(id: "g5", startedAt: d(2026, 5, 20, 9), endedAt: d(2026, 5, 20, 9, 20), summary: "上月收尾", durationSeconds: 20 * 60),
    ]
}

private func minutes__(_ m: TimeInterval) -> TimeInterval { m * 60 }
