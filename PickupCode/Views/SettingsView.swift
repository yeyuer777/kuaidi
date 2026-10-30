import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: PickupStore

    @State private var confirmClearDone = false
    @State private var confirmClearAll = false

    private static let stepsText = """
    取件码 · 短信自动收集配置步骤
    1. 打开「快捷指令」，切到底部「自动化」，右上角 +
    2. 选择「信息」，条件设为「信息包含」，填：取件码
    3. 添加操作，搜索「保存取件码」
    4. 把「信息」变量拖到「短信内容」
    5. 关掉「运行前询问」，选「立即运行」
    之后的快递短信会自动进 App，不用再手动粘。
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    autoCollectCard
                    urlCard
                    dataCard
                    aboutCard
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .background(Theme.pageBackground)
            .navigationTitle("设置")
            .alert("清空已取件记录？", isPresented: $confirmClearDone) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { store.clearDone() }
            } message: {
                Text("只删除标记为「已取件」的记录，待取件的不受影响。")
            }
            .alert("清空全部记录？", isPresented: $confirmClearAll) {
                Button("取消", role: .cancel) {}
                Button("全部删除", role: .destructive) { store.clearAll() }
            } message: {
                Text("所有取件码和原始短信内容都会被删除，无法恢复。")
            }
        }
    }

    // MARK: - 自动收集

    private var autoCollectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("短信自动收集", systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text("iOS 不允许 App 直接读短信，但快捷指令可以。配置一次，以后快递短信到了会自动存进来，不用手动粘。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                step(1, "打开「快捷指令」，切到底部「自动化」，点右上角 +")
                step(2, "选择「信息」，条件设为「信息包含」，填「取件码」")
                step(3, "添加操作，搜索「保存取件码」")
                step(4, "把「信息」变量拖到「短信内容」参数上")
                step(5, "关掉「运行前询问」，选「立即运行」")
            }

            Button {
                UIPasteboard.general.string = Self.stepsText
                store.toast = "配置步骤已复制"
            } label: {
                Label("复制这份步骤", systemImage: "doc.on.doc")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                    )
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func step(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - URL 入口

    private var urlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("URL 入口", systemImage: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text("如果你用 Scriptable、Pythonista 之类的工具，可以直接调这个地址把内容送进来：")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("pickupcode://parse?text=<URL编码后的短信>")
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = "pickupcode://parse?text="
                store.toast = "前缀已复制"
            } label: {
                Text("复制前缀")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - 数据

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("数据", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)

            HStack {
                Text("已保存记录")
                    .font(.footnote)
                Spacer()
                Text("\(store.items.count) 条")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                confirmClearDone = true
            } label: {
                HStack {
                    Text("清空已取件记录")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                confirmClearAll = true
            } label: {
                HStack {
                    Text("清空全部记录")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("关于", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text("已支持的取件码格式")
                .font(.footnote.weight(.medium))

            Text("分区码 8-2-3021、丰巢 8 位、兔喜 5 位、带字母的柜码、全角输入、无冒号写法。覆盖菜鸟驿站、丰巢、京东、顺丰、中通、圆通、申通、韵达、极兔、邮政、德邦、百世、妈妈驿站、兔喜、快宝、熊猫快收、速递易。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("所有数据只存在这台手机上，不联网、不上传、没有账号。删掉 App 数据就没了。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.versionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .cardStyle()
    }

    private static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
