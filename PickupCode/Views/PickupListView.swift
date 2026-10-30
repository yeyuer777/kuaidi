import SwiftUI

struct PickupListView: View {

    @EnvironmentObject private var store: PickupStore
    @State private var path: [UUID] = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    StatStrip(
                        pending: store.pendingItems.count,
                        done: store.doneItems.count
                    )
                    .padding(.bottom, 2)

                    if filteredAll.isEmpty {
                        emptyState
                    } else {
                        pendingSection
                        expiredSection
                        doneSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.pageBackground)
            .navigationTitle("取件码")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜取件码、驿站、地址")
            .navigationDestination(for: UUID.self) { id in
                PickupDetailView(itemID: id)
            }
        }
    }

    // MARK: - 分组

    @ViewBuilder
    private var pendingSection: some View {
        if !filteredPending.isEmpty {
            SectionHeader(title: "待取件", count: filteredPending.count)
            ForEach(filteredPending) { item in
                card(item)
            }
        }
    }

    @ViewBuilder
    private var expiredSection: some View {
        if !filteredExpired.isEmpty {
            SectionHeader(title: "已过期", count: filteredExpired.count)
            ForEach(filteredExpired) { item in
                card(item)
            }
        }
    }

    @ViewBuilder
    private var doneSection: some View {
        if !filteredDone.isEmpty {
            SectionHeader(title: "已取件", count: filteredDone.count)
            ForEach(filteredDone) { item in
                card(item)
            }
        }
    }

    private func card(_ item: PickupItem) -> some View {
        PickupCard(
            item: item,
            onOpen: { path.append(item.id) },
            onToggleDone: { store.toggleDone(item) },
            onDelete: { store.delete(item) }
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "还没有取件码",
                message: "去「导入」粘一条快递短信试试，\n或者按「设置」里的说明配好短信自动收集。"
            )
        } else {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "没有匹配的记录",
                message: "换个关键词试试，\n驿站名、地址、运单号都能搜。"
            )
        }
    }

    // MARK: - 筛选

    private var filteredAll: [PickupItem] {
        guard !searchText.isEmpty else { return store.items }
        let q = searchText.lowercased()
        return store.items.filter { item in
            let haystack = [
                item.code,
                item.merchant,
                item.courier ?? "",
                item.station ?? "",
                item.address ?? "",
                item.trackingNumber ?? "",
                item.phoneTail ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(q)
        }
    }

    private var filteredPending: [PickupItem] {
        filteredAll.filter { $0.status() == .pending }
    }

    private var filteredExpired: [PickupItem] {
        filteredAll.filter { $0.status() == .expired }
    }

    private var filteredDone: [PickupItem] {
        filteredAll.filter { $0.isDone }
    }
}
