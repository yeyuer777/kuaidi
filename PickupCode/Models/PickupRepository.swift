import Foundation

/// 无状态的持久化层。
///
/// 刻意做成 `enum` + 静态方法：App Intent 会在自己的执行上下文里跑，
/// 如果这里持有单例又标了 `@MainActor`，跨上下文访问就要到处 `await`，
/// 而且一旦 App 没启动，单例状态会和磁盘脱节。直接用「每次读写文件」
/// 最笨也最可靠——几十条记录的 JSON 读写开销可以忽略。
enum PickupRepository {

    private static let fileName = "pickups.json"

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - 基础读写

    static func load() -> [PickupItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let items = try decoder.decode([PickupItem].self, from: data)
            return items.sorted { $0.receivedAt > $1.receivedAt }
        } catch {
            // 数据损坏时不要让 App 直接崩掉或白屏：备份坏文件，返回空列表，
            // 用户至少还能继续用，原始数据也还能人工救回来。
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("pickups.corrupted-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return []
        }
    }

    static func save(_ items: [PickupItem]) {
        do {
            let data = try encoder.encode(items)
            // 原子写入，避免中途被杀进程留下半个 JSON
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PickupRepository] save failed: \(error)")
        }
    }

    // MARK: - 合并

    /// 追加并去重，返回真正新增的条数。
    ///
    /// 同一个取件码第二次出现时不丢弃：如果新解析出来的信息更全
    /// （比如手动粘贴那次只拿到码，快捷指令那次带上了地址和尾号），
    /// 就把缺失字段补进去。所以这里不能用 Set 去重，必须逐条比对指纹。
    @discardableResult
    static func append(_ newItems: [PickupItem]) -> Int {
        var current = load()
        var added = 0
        var enriched = false

        for item in newItems {
            if let index = current.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
                var merged = current[index]
                if merged.address == nil, item.address != nil {
                    merged.address = item.address
                    enriched = true
                }
                if merged.phoneTail == nil, item.phoneTail != nil {
                    merged.phoneTail = item.phoneTail
                    enriched = true
                }
                if merged.station == nil, item.station != nil {
                    merged.station = item.station
                    enriched = true
                }
                if merged.trackingNumber == nil, item.trackingNumber != nil {
                    merged.trackingNumber = item.trackingNumber
                    enriched = true
                }
                if merged.locationHint == nil, item.locationHint != nil {
                    merged.locationHint = item.locationHint
                    enriched = true
                }
                if merged.expireAt == nil, item.expireAt != nil {
                    merged.expireAt = item.expireAt
                    enriched = true
                }
                if merged != current[index] {
                    current[index] = merged
                }
                continue
            }

            current.append(item)
            added += 1
        }

        if added > 0 || enriched {
            current.sort { $0.receivedAt > $1.receivedAt }
            save(current)
        }
        return added
    }

    static func update(_ item: PickupItem) {
        var current = load()
        guard let index = current.firstIndex(where: { $0.id == item.id }) else { return }
        current[index] = item
        save(current)
    }

    static func delete(id: UUID) {
        var current = load()
        current.removeAll { $0.id == id }
        save(current)
    }

    static func clearAll() {
        save([])
    }

    /// 删除所有已取件的记录
    static func clearDone() {
        var current = load()
        current.removeAll { $0.isDone }
        save(current)
    }

    static var count: Int {
        load().count
    }
}
