import Foundation

/// 一条取件码记录。
///
/// 设计上把「原始文本」完整保留：解析规则总会遇到没覆盖到的新格式，
/// 保留原文意味着以后升级规则库可以对历史数据重新解析，不用重装重录。
struct PickupItem: Identifiable, Codable, Hashable {

    enum Source: String, Codable, CaseIterable {
        case sms
        case shortcut
        case paste
        case ocr
        case manual

        var label: String {
            switch self {
            case .sms: return "短信"
            case .shortcut: return "快捷指令"
            case .paste: return "粘贴"
            case .ocr: return "识别"
            case .manual: return "手动"
            }
        }

        var symbol: String {
            switch self {
            case .sms: return "message.fill"
            case .shortcut: return "wand.and.stars"
            case .paste: return "doc.on.clipboard"
            case .ocr: return "text.viewfinder"
            case .manual: return "square.and.pencil"
            }
        }
    }

    var id: UUID = UUID()
    /// 取件码本体，如 `8-2-3021` 或 `87654321`
    var code: String
    /// 取件点品牌，如「菜鸟驿站」「丰巢」「快宝驿站」——用户实际要去的地方
    var merchant: String
    /// 快递公司，如「极兔」「中通」，查物流用；可能与取件点品牌不同，也可能识别不到
    var courier: String? = nil
    /// 具体网点名，如「杭州西湖文三路店」
    var station: String?
    /// 取件地址
    var address: String?
    /// 收件人手机尾号，用于现场核对
    var phoneTail: String?
    /// 运单号
    var trackingNumber: String?
    /// 柜机号 / 货架号
    var locationHint: String?
    /// 原始短信或通知全文
    var rawText: String
    var source: Source
    /// 短信到达时间
    var receivedAt: Date
    var createdAt: Date = Date()
    /// 免费保管到期时间，可空
    var expireAt: Date?
    var isDone: Bool = false
    /// 用户备注，如「大件，要带身份证」
    var note: String?

    /// 相对当前时刻的状态
    func status(now: Date = Date()) -> Status {
        if isDone { return .done }
        if let expireAt, expireAt < now { return .expired }
        return .pending
    }

    enum Status {
        case pending
        case done
        case expired

        var label: String {
            switch self {
            case .pending: return "待取件"
            case .done: return "已取件"
            case .expired: return "已过期"
            }
        }
    }

    /// 去重指纹：同一个码 + 同一个网点视为同一条。
    /// 不把时间算进去，是因为同一条短信可能被「快捷指令」和「手动粘贴」各触发一次。
    var fingerprint: String {
        let a = code.replacingOccurrences(of: " ", with: "").lowercased()
        let b = (station ?? merchant).trimmingCharacters(in: .whitespacesAndNewlines)
        return a + "|" + b
    }
}

// MARK: - 展示辅助

extension PickupItem {

    /// 主标题：优先显示取件点（用户要去的），识别不到才退回快递公司
    var displayTitle: String {
        if merchant != "未知快递" { return merchant }
        return courier ?? "未知快递"
    }

    /// 副标题：网点名 + 快递公司，重复的去掉
    var displaySubtitle: String {
        var parts: [String] = []
        if let station, !station.isEmpty { parts.append(station) }
        if let courier, courier != merchant, !parts.contains(courier) { parts.append(courier) }
        return parts.joined(separator: " · ")
    }

    /// 分享给代取人的文本
    var shareText: String {
        var lines: [String] = ["【\(displayTitle)】取件码 \(code)"]
        if let station, !station.isEmpty { lines.append("网点：\(station)") }
        if let address, !address.isEmpty { lines.append("地址：\(address)") }
        if let phoneTail { lines.append("手机尾号：\(phoneTail)") }
        if let trackingNumber { lines.append("运单号：\(trackingNumber)") }
        return lines.joined(separator: "\n")
    }

    /// 短信里常见的「请于 X 小时内取件」推算出来的剩余时间描述
    var expireDescription: String? {
        guard let expireAt else { return nil }
        let now = Date()
        if expireAt < now { return "已超时" }
        let seconds = expireAt.timeIntervalSince(now)
        let hours = Int(seconds / 3600)
        if hours >= 24 {
            return "剩余 \(hours / 24) 天"
        }
        if hours >= 1 {
            return "剩余 \(hours) 小时"
        }
        return "剩余 \(max(1, Int(seconds / 60))) 分钟"
    }

    var receivedDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: receivedAt, relativeTo: Date())
    }
}
