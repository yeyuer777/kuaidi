import SwiftUI

@main
struct PickupCodeApp: App {

    @StateObject private var store = PickupStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    handle(url)
                }
        }
    }

    /// pickupcode://parse?text=<percent-encoded>
    /// 给其他自动化工具（快捷指令「打开 URL」、Scriptable 等）留的入口
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "pickupcode" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        let content = components.queryItems?
            .first(where: { $0.name == "text" })?.value
            ?? components.queryItems?.first(where: { $0.name == "raw" })?.value

        guard let content, !content.isEmpty else { return }

        let result = store.ingest(text: content, source: .shortcut)
        if result.added > 0 {
            store.toast = "已添加 \(result.added) 个取件码"
        } else if result.parsed > 0 {
            store.toast = "这些取件码已经在列表里了"
        } else {
            store.toast = "没识别到取件码"
        }
    }
}
