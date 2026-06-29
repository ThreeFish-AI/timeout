import Foundation

/// 运动记录持久化（纯 Foundation，可单测）。镜像 `WorkLogStore` 范式：原子写 + 容错读。
/// 路径：~/Library/Application Support/<bundleId>/exercise-log.json
///
/// 与 `WorkLogStore` / `ConfigStore` 职责正交（运动记录 vs 工作记录 vs 配置/状态），故独立成类、
/// 独立文件，但复用同一 Application Support 目录与同一原子写惯用法（单一事实源：写盘范式）。
/// 规模量级（数条/日、数百条/年）下全量读-改-写即可；原子写防半写损坏。
public final class ExerciseStore {
    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var exerciseLogURL: URL { directory.appendingPathComponent("exercise-log.json") }

    // MARK: - 读

    /// 读取全部条目（按时间升序）。缺失/损坏 → `[]`，绝不抛出到调用方。
    public func loadEntries() -> [ExerciseEntry] {
        guard let data = try? Data(contentsOf: exerciseLogURL) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([ExerciseEntry].self, from: data)
            return decoded.sorted { $0.startedAt < $1.startedAt }
        } catch {
            NSLog("[GiveMeABreak][exercise] 解码失败，回退空列表：\(error)")
            return []
        }
    }

    // MARK: - 写

    /// 追加一条记录（读-改-写，原子落盘）。
    public func append(_ entry: ExerciseEntry) {
        var entries = loadEntries()
        entries.append(entry)
        saveAll(entries)
    }

    /// 用新列表整体替换（供「清空」等批量操作）。
    public func replaceAll(_ entries: [ExerciseEntry]) {
        saveAll(entries.sorted { $0.startedAt < $1.startedAt })
    }

    /// 按 `id` 原地更新一条记录（读-改-写，原子落盘，重排升序）。未命中 id → no-op（防御，不抛错）。
    public func update(_ entry: ExerciseEntry) {
        var entries = loadEntries()
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else {
            NSLog("[GiveMeABreak][exercise] update 未命中 id=\(entry.id)，忽略")
            return
        }
        entries[idx] = entry
        saveAll(entries.sorted { $0.startedAt < $1.startedAt })
    }

    /// 按 `id` 删除一条记录（读-改-写，原子落盘）。删不存在的 id → 列表不变。
    public func delete(id: String) {
        var entries = loadEntries()
        let before = entries.count
        entries.removeAll { $0.id == id }
        guard entries.count != before else { return }
        saveAll(entries)
    }

    // MARK: - Private

    private func saveAll(_ entries: [ExerciseEntry]) {
        do {
            try write(entries, to: exerciseLogURL)
        } catch {
            NSLog("[GiveMeABreak][exercise] 持久化失败：\(error)")
        }
    }

    /// 原子写：pretty-printed + sorted keys（确定性、可读、可 diff），原子落盘防半写损坏。
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
