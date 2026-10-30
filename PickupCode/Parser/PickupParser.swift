import Foundation

/// 取件码解析引擎。
///
/// 单向数据流：原始文本 → 归一化 → 判定是否取件通知 → 按优先级套规则 → PickupItem。
/// 任何一步没命中就返回 nil，绝不猜——猜错的取件码比没有更浪费时间。
enum PickupParser {

    // MARK: - 对外入口

    static func parse(
        text: String,
        source: PickupItem.Source = .paste,
        receivedAt: Date = Date()
    ) -> [PickupItem] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        // 多行且多行都是独立通知 → 逐行解析（用户把好几条短信一起粘进来的场景）
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let noticeLines = lines.filter { looksLikeNotice($0) }
        if noticeLines.count >= 2 {
            let items = noticeLines.compactMap {
                parseBlock($0, source: source, receivedAt: receivedAt)
            }
            if !items.isEmpty { return items }
        }

        if let item = parseBlock(normalized, source: source, receivedAt: receivedAt) {
            return [item]
        }
        return []
    }

    /// 只判定、不产出：用于「这条短信值不值得弹提醒」
    static func looksLikeNotice(_ text: String) -> Bool {
        let lower = text.lowercased()
        if PickupRules.noticeKeywords.contains(where: { lower.contains($0.lowercased()) }) {
            return true
        }
        let hasWeak = PickupRules.weakKeywords.contains { lower.contains($0.lowercased()) }
        if hasWeak, RegexTool.matches("\\d{4,}", in: text) {
            return true
        }
        return false
    }

    // MARK: - 单块解析

    private static func parseBlock(
        _ block: String,
        source: PickupItem.Source,
        receivedAt: Date
    ) -> PickupItem? {
        guard looksLikeNotice(block) else { return nil }

        guard let code = extractCode(block) else { return nil }

        let stationBrand = detectStationBrand(block)
        let courier = detectCourier(block)
        // 取件点品牌优先；识别不到就退回快递公司，两者都没有才算未知
        let merchant = stationBrand ?? courier ?? "未知快递"

        var station = detectStation(block)
        // 网点名如果只是品牌名的复述，就没有信息量，丢掉
        if let s = station, s.replacingOccurrences(of: " ", with: "") == merchant {
            station = nil
        }

        var address = detectAddress(block)
        // 地址和网点名撞车时只留一份，否则界面上会出现「丰巢智能柜 · 丰巢智能柜」
        if let a = address, a == station {
            address = nil
        }

        let phoneTail = firstMatch(PickupRules.phoneTailPatterns, in: block)
        let tracking = firstMatch(PickupRules.trackingPatterns, in: block)
        let location = firstMatch(PickupRules.locationPatterns, in: block)
        let expireAt = computeExpire(block, from: receivedAt)

        return PickupItem(
            code: code,
            merchant: merchant,
            courier: courier,
            station: station,
            address: address,
            phoneTail: phoneTail,
            trackingNumber: tracking,
            locationHint: location,
            rawText: block,
            source: source,
            receivedAt: receivedAt,
            expireAt: expireAt
        )
    }

    // MARK: - 字段提取

    private static func extractCode(_ text: String) -> String? {
        for pattern in PickupRules.codePatterns {
            guard let raw = RegexTool.first(pattern.regex, in: text, group: pattern.group) else {
                continue
            }
            if let cleaned = sanitizeCode(raw) {
                return cleaned
            }
        }
        return nil
    }

    /// 清洗并校验取件码。这里是防误提取的最后一道闸：
    /// 手机号、运单号、日期长得都像取件码，必须在这里挡掉。
    private static func sanitizeCode(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }

        // 分区码：2-3 段数字，如 8-2-3021
        if s.contains("-") {
            let parts = s.split(separator: "-", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count) else { return nil }
            let valid = parts.allSatisfy { part in
                !part.isEmpty && part.count <= 4 && part.allSatisfy { $0.isNumber }
            }
            return valid ? s : nil
        }

        // 纯码：数字或字母数字混合
        let digits = s.filter { $0.isNumber }
        if digits.count >= 12 { return nil }                       // 运单号
        if digits.count == 11 && s.hasPrefix("1") { return nil }   // 手机号
        guard digits.count >= 4 else { return nil }

        // 日期形态（20261030）几乎不可能是取件码，挡掉
        if digits.count == 8,
           let year = Int(digits.prefix(4)), (2015...2035).contains(year),
           let month = Int(digits.dropFirst(4).prefix(2)), (1...12).contains(month),
           let day = Int(digits.suffix(2)), (1...31).contains(day) {
            return nil
        }
        return s
    }

    private static func detectStationBrand(_ text: String) -> String? {
        detect(PickupRules.stationBrands, in: text)
    }

    private static func detectCourier(_ text: String) -> String? {
        detect(PickupRules.couriers, in: text)
    }

    private static func detect(_ brands: [PickupRules.Brand], in text: String) -> String? {
        let lower = text.lowercased()
        for brand in brands {
            for keyword in brand.keywords where lower.contains(keyword.lowercased()) {
                return brand.name
            }
        }
        return nil
    }

    private static func detectStation(_ text: String) -> String? {
        for pattern in PickupRules.stationPatterns {
            if let value = RegexTool.first(pattern, in: text), value.count >= 3 {
                return value
            }
        }
        return nil
    }

    private static func detectAddress(_ text: String) -> String? {
        for pattern in PickupRules.addressPatterns {
            if let value = RegexTool.first(pattern, in: text), value.count >= 4 {
                return value
            }
        }
        return nil
    }

    private static func firstMatch(_ patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            if let value = RegexTool.first(pattern, in: text) { return value }
        }
        return nil
    }

    private static func computeExpire(_ text: String, from date: Date) -> Date? {
        for pattern in PickupRules.holdPatterns {
            if let raw = RegexTool.first(pattern.regex, in: text), let amount = Double(raw) {
                return date.addingTimeInterval(amount * pattern.unitHours * 3600)
            }
        }
        return nil
    }

    // MARK: - 归一化

    /// 全角转半角。短信里 "取件码：" 和 "取件码:" 混着来，
    /// 不统一的话每条正则都要写两遍，规则库会迅速失控。
    static func normalize(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                if let converted = Unicode.Scalar(scalar.value - 0xFEE0) {
                    result.unicodeScalars.append(converted)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            case 0x3000:
                result.append(" ")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
