import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: PickupStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .list

    enum Tab: Hashable {
        case list
        case importer
        case settings
    }

    var body: some View {
        TabView(selection: $selection) {
            PickupListView()
                .tabItem { Label("取件码", systemImage: "shippingbox.fill") }
                .tag(Tab.list)

            ImportView()
                .tabItem { Label("导入", systemImage: "plus.circle.fill") }
                .tag(Tab.importer)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            toastBanner
        }
        .animation(.easeInOut(duration: 0.22), value: store.toast)
        // 快捷指令可能在后台写入了新数据，回到前台时重读磁盘
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                store.reload()
            }
        }
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let message = store.toast {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.toast = nil }
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    store.toast = nil
                }
        }
    }
}
