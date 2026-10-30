import SwiftUI
import UIKit

// MARK: - 状态徽标

struct StatusBadge: View {
    let status: PickupItem.Status

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.statusColor(status).opacity(0.12)))
            .foregroundStyle(Theme.statusColor(status))
    }
}

// MARK: - 取件码卡片

/// 列表里的单条记录。
///
/// 没用 NavigationLink 包整卡：卡里有「复制」「勾选」两个按钮，
/// 外层包 NavigationLink 会导致点按钮时同时触发跳转。
/// 改成点击空白区域回调 `onOpen`，按钮各管各的，互不打架。
struct PickupCard: View {

    let item: PickupItem
    var onOpen: () -> Void
    var onToggleDone: () -> Void
    var onDelete: () -> Void

    @State private var copied = false

    private var status: PickupItem.Status { item.status() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            codeRow
            locationText
            footer
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .cardStyle()
        .contextMenu {
            Button {
                copyCode()
            } label: {
                Label("复制取件码", systemImage: "doc.on.doc")
            }
            Button {
                onToggleDone()
            } label: {
                Label(item.isDone ? "标记为未取" : "标记为已取",
                      systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: 组成部分

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.statusColor(status)))

            Text(item.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 4)

            StatusBadge(status: status)
        }
    }

    private var codeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(item.code)
                .font(Theme.codeFont)
                .foregroundStyle(Theme.statusColor(status))
                .strikethrough(status == .done,
                               color: Theme.statusColor(status).opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            Button {
                copyCode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "已复制" : "复制")
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var locationText: some View {
        if !item.displaySubtitle.isEmpty {
            Label(item.displaySubtitle, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let address = item.address, !address.isEmpty {
            Text(address)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(item.receivedDescription)
                .foregroundStyle(.secondary)

            if let expire = item.expireDescription, status == .pending {
                Text("·").foregroundStyle(.secondary)
                Text(expire).foregroundStyle(Theme.warning)
            }

            Spacer(minLength: 0)

            Text(item.source.label)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
    }

    // MARK: 动作

    private func copyCode() {
        UIPasteboard.general.string = item.code
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}

// MARK: - 分组标题

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
    }
}

// MARK: - 顶部统计条

struct StatStrip: View {
    let pending: Int
    let done: Int

    var body: some View {
        HStack(spacing: 0) {
            stat(value: pending, label: "待取件", color: Theme.accent)
            divider
            stat(value: done, label: "已取件", color: Theme.success)
        }
        .cardStyle(padding: 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.cardBorder)
            .frame(width: 1, height: 30)
    }

    private func stat(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
