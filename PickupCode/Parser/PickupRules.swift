import Foundation

/// 正则小工具。不做缓存：一条短信只解析一次，编译开销可以忽略，
/// 换来的是无共享可变状态、任何线程都能安全调用。
enum RegexTool {

    static func matches(_ pattern: String, in text: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }

    /// 取第一个匹配的指定分组，自动 trim，空串当 nil
    static func first(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range) else { return nil }
        return capture(match, group: group, in: text)
    }

    /// 取所有匹配的指定分组
    static func all(_ pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = re.matches(in: text, options: [], range: range)
        return matches.compactMap { capture($0, group: group, in: text) }
    }

    private static func capture(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < match.numberOfRanges else { return nil }
        let nsRange = match.range(at: group)
        guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: text) else { return nil }
        let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - 规则库

/// 国内快递取件场景的规则集合。
///
/// 维护思路：新增一家快递，只需要往 `brands` 里加关键词、往 `codePatterns` 里
/// 加它的码格式，不用动解析主流程。
enum PickupRules {

    struct Brand {
        let name: String
        let keywords: [String]
    }

    /// 取件点品牌——用户实际要去的那个地方。顺序即优先级。
    static let stationBrands: [Brand] = [
        Brand(name: "菜鸟驿站", keywords: ["菜鸟驿站", "菜鸟裹裹", "菜鸟"]),
        Brand(name: "丰巢", keywords: ["丰巢", "蜂巢", "hive box"]),
        Brand(name: "妈妈驿站", keywords: ["妈妈驿站"]),
        Brand(name: "兔喜生活", keywords: ["兔喜"]),
        Brand(name: "快宝驿站", keywords: ["快宝"]),
        Brand(name: "熊猫快收", keywords: ["熊猫快收"]),
        Brand(name: "速递易", keywords: ["速递易"]),
    ]

    /// 快递公司——包裹是谁承运的。
    ///
    /// 必须和取件点分开：「极兔速递的件放在快宝驿站」两个信息都真实存在。
    /// 用户去取件看前者，查物流看后者，合成一个字段必然丢掉一个。
    static let couriers: [Brand] = [
        Brand(name: "京东", keywords: ["京东物流", "京喜", "京东快递", "京东"]),
        Brand(name: "顺丰", keywords: ["顺丰", "sf express", "sf-express"]),
        Brand(name: "中通", keywords: ["中通"]),
        Brand(name: "圆通", keywords: ["圆通"]),
        Brand(name: "申通", keywords: ["申通"]),
        Brand(name: "韵达", keywords: ["韵达"]),
        Brand(name: "极兔", keywords: ["极兔", "j&t", "jnt"]),
        Brand(name: "德邦", keywords: ["德邦"]),
        Brand(name: "百世", keywords: ["百世"]),
        Brand(name: "邮政", keywords: ["中国邮政", "邮政ems", "ems"]),
    ]

    /// 判定「这条文本是不是取件通知」的强信号词
    static let noticeKeywords = [
        "取件码", "提货码", "取货码", "取物码", "取件凭证", "取件号",
        "开箱码", "取件密码", "凭码取件", "已到驿站", "已存放至",
    ]

    /// 弱信号：出现这些词 + 数字串，也算取件通知
    static let weakKeywords = ["驿站", "快递柜", "智能柜", "丰巢", "自提柜", "代收点"]

    struct CodePattern {
        let name: String
        let regex: String
        /// 1 = 取第一个匹配即可
        let group: Int
    }

    /// 取件码正则，按优先级从高到低尝试。
    static let codePatterns: [CodePattern] = [
        // 分区码：菜鸟/驿站最常见的 8-2-3021、2-2-2018
        CodePattern(
            name: "分区码",
            regex: "(?:取件码|提货码|取货码|取物码|取件凭证|取件号|开箱码|取件密码|密码)\\s*[:：]?\\s*(\\d{1,3}\\s*[-－—–]\\s*\\d{1,3}(?:\\s*[-－—–]\\s*\\d{1,4})?)",
            group: 1
        ),
        // 带前缀的短码：丰巢 8 位、兔喜 5 位、含字母的柜码
        CodePattern(
            name: "前缀短码",
            regex: "(?:取件码|提货码|取货码|取物码|取件凭证|取件号|开箱码|取件密码)\\s*(?:是|为)?\\s*[:：]?\\s*([0-9A-Za-z]{4,10})(?![0-9A-Za-z])",
            group: 1
        ),
        // 无前缀但有驿站上下文的分区码
        CodePattern(
            name: "裸分区码",
            regex: "(?<![0-9])(\\d{1,3}\\s*[-－—–]\\s*\\d{1,3}\\s*[-－—–]\\s*\\d{1,4})(?![0-9])",
            group: 1
        ),
        // 兜底：「码」后面跟 4-8 位数字
        CodePattern(
            name: "码字兜底",
            regex: "(?:码|code)\\s*[:：]?\\s*(\\d{4,8})(?![0-9])",
            group: 1
        ),
    ]

    /// 地址
    static let addressPatterns = [
        "(?:取件地址|存放地址|地址|网点地址|存放位置|柜机位置)\\s*[:：]\\s*([^\\n，,。；;！!]{4,60})",
        "(?:已存放至|已放至|已投递至|已送达|已送到|寄存于|暂存于|放在)\\s*([^\\n，,。；;！!]{4,40}?)(?:[，,。；;！!\\n]|$)",
        "(?:请|可)\\s*(?:到|至|前往)\\s*([^\\n，,。；;！!]{4,40}?)(?:取件|领取|自取|凭)",
    ]

    /// 网点名。
    ///
    /// 关键是第一条：用「已到 / 存放至 / 放入」这类动词做锚点，只抓动词之后的名词短语。
    /// 之前直接从任意中文串开始匹配，结果把「您的快递已放入丰巢智能柜」整句当成了网点名。
    static let stationPatterns = [
        "(?:已到|已存放至|已放至|已投递至|已存入|已放入|存放至|投递至|存入|放入|寄存在|暂存于|在)\\s*([^，,。；;！!\\n]{1,25}?(?:驿站|快递柜|智能柜|自提柜|服务点|代收点|快递超市))",
        "【([^】]*?(?:驿站|快递柜|智能柜|自提柜|服务点|代收点|快递超市)[^】]*?)】",
        "(?<![至入在到])([\\u4e00-\\u9fa5A-Za-z0-9（）()·]{2,20}?(?:驿站|快递柜|智能柜|自提柜|服务点|代收点|快递超市))",
    ]

    /// 手机尾号
    static let phoneTailPatterns = [
        "(?:手机|电话)?\\s*尾号\\s*[:：]?\\s*(\\d{4})",
        "(?:后四位|末四位|后4位)\\s*[:：]?\\s*(\\d{4})",
        "(\\d{4})\\s*号?\\s*尾号",
    ]

    /// 运单号
    static let trackingPatterns = [
        "(?:运单号|快递单号|运单编号|物流单号|单号)\\s*[:：]?\\s*([A-Za-z0-9]{8,24})",
    ]

    /// 柜机 / 货架 / 格口
    static let locationPatterns = [
        "(?:柜机号|柜号|柜机|货架号|货架|层号|格口|箱门)\\s*[:：]?\\s*([0-9A-Za-z\\-]{1,12})",
    ]

    /// 保管时长 → 用于推算过期时间
    struct HoldPattern {
        let regex: String
        let unitHours: Double
    }

    static let holdPatterns: [HoldPattern] = [
        HoldPattern(regex: "(?:免费)?保管\\s*(\\d+)\\s*(?:个)?小时", unitHours: 1),
        HoldPattern(regex: "(?:免费)?保管\\s*(\\d+)\\s*天", unitHours: 24),
        HoldPattern(regex: "请在\\s*(\\d+)\\s*小时内", unitHours: 1),
        HoldPattern(regex: "(\\d+)\\s*小时内\\s*(?:免费)?取件", unitHours: 1),
        HoldPattern(regex: "超过\\s*(\\d+)\\s*小时", unitHours: 1),
    ]
}
