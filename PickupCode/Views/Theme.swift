import SwiftUI

enum Theme {

    /// 主色：偏冷的靛蓝，在浅色和深色背景下对比度都够
    static let accent = Color(red: 0.16, green: 0.41, blue: 0.96)
    /// 已取件
    static let success = Color(red: 0.11, green: 0.62, blue: 0.40)
    /// 临期提醒
    static let warning = Color(red: 0.90, green: 0.55, blue: 0.16)

    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardBorder = Color.primary.opacity(0.06)

    static func statusColor(_ status: PickupItem.Status) -> Color {
        switch status {
        case .pending: return accent
        case .done: return success
        case .expired: return Color(uiColor: .tertiaryLabel)
        }
    }

    /// 取件码字体：等宽，位数对齐，一屏扫下来最容易读
    static let codeFont = Font.system(size: 30, weight: .bold, design: .monospaced)
    static let codeFontSmall = Font.system(size: 22, weight: .semibold, design: .monospaced)
}

extension View {
    /// 统一的卡片容器样式
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}
