import Foundation
import AppIntents

/// 快捷指令入口：「收到信息」自动化把短信正文传进来，解析后静默入库。
///
/// `openAppWhenRun = false` 是有意的——短信到达时不该把用户从当前界面弹走。
/// 系统会拉起 App 的后台进程执行这个 intent，沙盒容器和前台是同一个，
/// 所以能直接写 Documents 里的数据文件。
struct SavePickupTextIntent: AppIntent {

    static var title: LocalizedStringResource { "保存取件码" }

    static var description: IntentDescription? {
        IntentDescription("从短信正文中提取取件码、驿站、地址并保存到取件码本。")
    }

    static var openAppWhenRun: Bool { false }

    @Parameter(
        title: "短信内容",
        description: "把「收到信息」自动化里的「信息」变量拖到这里"
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("解析 \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: IntentDialog("短信内容是空的"))
        }

        let parsed = PickupParser.parse(text: trimmed, source: .shortcut, receivedAt: Date())
        guard !parsed.isEmpty else {
            return .result(dialog: IntentDialog("这段内容里没找到取件码"))
        }

        let added = PickupRepository.append(parsed)
        if added == 0 {
            return .result(dialog: IntentDialog("已存在，没有重复保存"))
        }
        if parsed.count == 1 {
            let item = parsed[0]
            return .result(dialog: IntentDialog("已保存 \(item.merchant) 的取件码 \(item.code)"))
        }
        return .result(dialog: IntentDialog("已保存 \(added) 个取件码"))
    }
}
