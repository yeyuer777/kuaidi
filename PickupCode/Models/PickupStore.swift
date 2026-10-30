import Foundation
import Combine

/// 界面状态。只做一件事：把磁盘数据读进 `@Published`，把用户操作写回磁盘。
/// 解析逻辑全部在 PickupParser，持久化全部在 PickupRepository，这里不掺业务。
@MainActor
final class PickupStore: ObservableObject {

    @Published private(set) var items: [PickupItem] = []
    /// 一次性提示语，消费后置空
    @Published var toast: String?

    init() {
        items = PickupRepository.load()
    }

    func reload() {
        items = PickupRepository.load()
    }

    // MARK: - 分组

    var pendingItems: [PickupItem] {
        items.filter { $0.status() == .pending }
    }

    var doneItems: [PickupItem] {
        items.filter { $0.isDone }
    }

    var expiredItems: [PickupItem] {
        items.filter { $0.status() == .expired }
    }

    // MARK: - 写入

    @discardableResult
    func add(_ newItems: [PickupItem]) -> Int {
        let added = PickupRepository.append(newItems)
        reload()
        return added
    }

    /// 解析一段文本并入库，返回结果摘要，给各个入口复用
    @discardableResult
    func ingest(text: String, source: PickupItem.Source, receivedAt: Date = Date()) -> (parsed: Int, added: Int) {
        let parsed = PickupParser.parse(text: text, source: source, receivedAt: receivedAt)
        guard !parsed.isEmpty else { return (0, 0) }
        let added = add(parsed)
        return (parsed.count, added)
    }

    func toggleDone(_ item: PickupItem) {
        var copy = item
        copy.isDone.toggle()
        PickupRepository.update(copy)
        reload()
    }

    func update(_ item: PickupItem) {
        PickupRepository.update(item)
        reload()
    }

    func delete(_ item: PickupItem) {
        PickupRepository.delete(id: item.id)
        reload()
    }

    func clearDone() {
        PickupRepository.clearDone()
        reload()
    }

    func clearAll() {
        PickupRepository.clearAll()
        reload()
    }
}
