import SwiftUI
import UIKit

struct PickupDetailView: View {

    let itemID: UUID

    @EnvironmentObject private var store: PickupStore
    @Environment(\.dismiss) private var dismiss

    @State private var noteDraft = ""
    @State private var noteInitialized = false
    @State private var showRawText = false
    @State private var confirmDelete = false

    private var item: PickupItem? {
        store.items.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                EmptyStateView(
                    icon: "trash",
                    title: "记录已删除",
                    message: "这条取件码已经不在列表里了。"
                )
            }
        }
        .background(Theme.pageBackground)
        .navigationTitle("取件详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !noteInitialized, let item {
                noteDraft = item.note ?? ""
                noteInitialized = true
            }
        }
        .onDisappear {
            saveNote()
        }
        .alert("删除这条取件码？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let item { store.delete(item) }
                dismiss()
            }
        } message: {
            Text("删除后无法恢复。原始短信内容也会一起删除。")
        }
    }

    // MARK: - 主体

    private func content(_ item: PickupItem) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                codeCard(item)
                infoCard(item)
                noteCard
                rawCard(item)
                actionButtons(item)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: item.shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func codeCard(_ item: PickupItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(item.displayTitle, systemImage: "shippingbox.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(status: item.status())
            }

            Text(item.code)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.statusColor(item.status()))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = item.code
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    store.toast = "取件码已复制"
                } label: {
                    Label("复制取件码", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                if let expire = item.expireDescription, item.status() == .pending {
                    Text(expire)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.warning)
                }

                Spacer(minLength: 0)
            }
        }
        .cardStyle()
    }

    private func infoCard(_ item: PickupItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            InfoRow(label: "取件点", value: item.merchant)
            if let courier = item.courier, courier != item.merchant {
                InfoRow(label: "快递", value: courier)
            }
            if let station = item.station {
                InfoRow(label: "网点", value: station)
            }
            if let address = item.address {
                InfoRow(label: "地址", value: address)
            }
            if let tail = item.phoneTail {
                InfoRow(label: "手机尾号", value: tail)
            }
            if let tracking = item.trackingNumber {
                InfoRow(label: "运单号", value: tracking, mono: true)
            }
            if let hint = item.locationHint {
                InfoRow(label: "柜位", value: hint)
            }

            Divider().padding(.vertical, 2)

            InfoRow(label: "来源", value: item.source.label)
            InfoRow(label: "到达", value: Self.dateFormatter.string(from: item.receivedAt))
            if let expireAt = item.expireAt {
                InfoRow(
                    label: "保管到",
                    value: Self.dateFormatter.string(from: expireAt)
                )
            }
        }
        .cardStyle()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("比如「大件，要带身份证」", text: $noteDraft, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .onSubmit { saveNote() }
        }
        .cardStyle()
    }

    private func rawCard(_ item: PickupItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRawText.toggle()
                }
            } label: {
                HStack {
                    Text("原始内容")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showRawText ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showRawText {
                Text(item.rawText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func actionButtons(_ item: PickupItem) -> some View {
        VStack(spacing: 10) {
            Button {
                store.toggleDone(item)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label(
                    item.isDone ? "改回未取件" : "标记为已取件",
                    systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(item.isDone ? Color.primary.opacity(0.07) : Theme.success)
                )
                .foregroundStyle(item.isDone ? Color.primary : Color.white)
            }
            .buttonStyle(.plain)

            Button {
                confirmDelete = true
            } label: {
                Label("删除这条记录", systemImage: "trash")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 辅助

    private func saveNote() {
        guard let item else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (item.note ?? "") else { return }
        var copy = item
        copy.note = trimmed.isEmpty ? nil : trimmed
        store.update(copy)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
}

// MARK: - 信息行

struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
