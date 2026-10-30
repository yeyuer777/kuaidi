# 取件码 · PickupCode

一款只做一件事的 iOS App：**把快递短信里的取件码抽出来，整理成一个一眼能扫完的列表。**

原生 SwiftUI，无第三方依赖，所有数据只存在本机。不联网、不上传、没有账号。

---

## 它解决什么问题

取件码散落在几十条 106 开头的短信里，要用的时候得从头翻。这个 App 让它们集中到一个界面：

```
待取件
┌─────────────────────────────────────┐
│ 📦 菜鸟驿站              待取件      │
│ 8-2-3021                    复制     │
│ 文三路478号 · 尾号8823              │
│ 2小时前 · 剩余2天                   │
└─────────────────────────────────────┘
```

点一下卡片复制取件码，长按标记已取件，右上角可以把整条信息分享给代取的人。

---

## 三个数据入口

iOS 系统层面禁止第三方 App 读短信，所以自动收集走的是快捷指令：

| 入口 | 触发方式 | 自动化程度 |
|---|---|---|
| **快捷指令** | 「收到信息」自动化把短信正文传进来 | 短信到了自动入库，无感 |
| **粘贴** | App 内粘一段文本，多条也行 | 手动 |
| **截图识别** | 相册选一张取件码截图，Vision OCR 识别 | 半自动 |

还有 URL 入口 `pickupcode://parse?text=...`，方便接自己的自动化脚本。

---

## 运行环境

- **iOS 16.0 或更高**
- 通过 **TrollStore** 安装（无需 7 天续签，永久有效）

TrollStore 支持 iOS 14.0–16.6.1（arm64e 机型，即 iPhone XS/XR 及以后）。如果系统低于 iOS 16，看下面[降级到 iOS 15](#降级到-ios-15)。

---

## 从 CI 拿 ipa 并装到手机

代码在 GitHub 上由 macOS runner 自动编译，产出一个未签名的 `.ipa`，TrollStore 会自己处理签名。

1. 把仓库推到 GitHub，进入仓库页面的 **Actions** 标签
2. 等 `build-ipa` 跑完（首次约 3–5 分钟），展开 **Upload ipa artifact** 下载 `PickupCode-ipa`
3. 把 ipa 传到 iPhone：AirDrop、隔空投送、或者 iCloud Drive、微信文件传输助手都行
4. 在文件里点这个 ipa，选择**用 TrollStore 打开**
5. 回到 TrollStore 点 **Install**，桌面出现图标即完成

装好后打开一次 App——这一步是必须的，iOS 需要 App 至少运行过一次，快捷指令的操作列表里才会出现「保存取件码」。

### 如果 TrollStore 提示签名错误

说明这个 ipa 里带了无效签名信息，清一下再打包：

```bash
rm -rf Payload/PickupCode.app/_CodeSignature
rm -f Payload/PickupCode.app/embedded.mobileprovision
# 重新 zip
```

---

## 配置短信自动收集

在「快捷指令」App 里配一次，之后快递短信到了会自动进 App。

1. 打开「快捷指令」→ 底部「自动化」→ 右上角 **+**
2. 选 **信息**，条件设为「信息包含」，填 `取件码`
3. 点「添加操作」，搜索 **保存取件码**
4. 把自动化顶部的 **「信息」变量**拖到操作的「短信内容」参数上
5. 关掉「运行前询问」，选「立即运行」→ 完成

> 想只收某家驿站，就把第 2 步的条件改成 `菜鸟驿站`、`丰巢` 之类，多个条件用「或」。

这个 App 的 intent 是 `openAppWhenRun = false`，执行时不会把你从当前界面弹走。

---

## 支持哪些格式

规则库在 `PickupCode/Parser/PickupRules.swift`，改规则不用动解析主流程。

| 类型 | 例子 |
|---|---|
| 分区码 | `8-2-3021`、`2-2-2018`、`3-2-1024` |
| 丰巢 8 位 | `87654321` |
| 短码 | 兔喜 5 位、邮政 4 位 |
| 带字母的柜码 | `A-12` 类格口号 |
| 全角输入 | `取件码：８－２－３０２１` |
| 无冒号 | `取件码8-2-3021` |

覆盖的取件点：菜鸟驿站、丰巢、妈妈驿站、兔喜生活、快宝驿站、熊猫快收、速递易，以及京东、顺丰、中通、圆通、申通、韵达、极兔、德邦、百世、邮政等快递公司。

顺带还会提取网点名、地址、手机尾号、运单号、柜位号，以及「免费保管 3 天」这类描述推算出的过期时间。

### 规则是验证过的

`Scripts/verify_rules.py` 是规则库的等价实现，跑 20 条真实风格的样本（16 条应提取 + 4 条应拒绝）：

```bash
python Scripts/verify_rules.py
```

当前 **20/20 通过**。改规则库之前先跑这个，通过率掉了就说明改坏了。

其中最难的一类是**拒绝误提取**：验证码、营销短信、物流在途通知都长得像取件通知；手机号、运单号、日期长得都像取件码。这些都在 `sanitizeCode()` 里挡掉了。

---

## 目录结构

```
project.yml                      XcodeGen 工程定义（不用装 Xcode 也能改）
.github/workflows/build-ipa.yml  云编译流水线
PickupCode/
├── App/PickupCodeApp.swift      入口 + URL scheme
├── Models/
│   ├── PickupItem.swift          数据模型
│   ├── PickupRepository.swift    本地 JSON 持久化
│   └── PickupStore.swift         界面状态
├── Parser/
│   ├── PickupRules.swift         规则库（正则）
│   └── PickupParser.swift        解析引擎
├── Intents/SavePickupTextIntent.swift  快捷指令入口
├── Services/TextRecognizer.swift        Vision OCR
└── Views/                         列表 / 详情 / 导入 / 设置
Scripts/verify_rules.py          规则回归测试
```

---

## 在 Mac 上本地开发

```bash
brew install xcodegen
xcodegen generate
open PickupCode.xcodeproj
```

在 Xcode 里选一个 iOS 16+ 的真机或模拟器直接跑。

---

## 降级到 iOS 15

App 依赖两个 iOS 16 才有的 API：`AppIntents`（快捷指令 intent）和 `PhotosUI`（截图选择器）。iOS 15 上可以这样改：

- **自动收集**：删掉 `Intents/SavePickupTextIntent.swift`，改用快捷指令「打开 URL」动作，地址填 `pickupcode://parse?text=[信息]`。URL 入口本身是 iOS 13 就有的，代码已经在。
- **截图识别**：`PhotosPicker` 换成 `UIImagePickerController`，包一层 `UIViewControllerRepresentable`。
- `project.yml` 里 `deploymentTarget` 改成 `15.0`。

改完识别能力、存储、列表、详情都不受影响，核心的解析引擎不依赖 iOS 16。

---

## 已知限制

- **不能按手机号去各家平台查包裹**：菜鸟、京东、顺丰都没有开放的手机号查件接口，网页端要登录态和短信验证且有风控。所以本 App 只处理主动到达的短信和截图，不做主动查询。
- **「一柜多件」只取第一个码**：短信里同时给两个取件码时，解析出第一个，第二个能在详情页的「原始内容」里看到。
- **规则库不可能覆盖所有文案**：遇到没识别出来的短信，直接贴到「导入」页就能用，同时也欢迎把那条短信加到 `Scripts/verify_rules.py` 的样本里补规则。

---

## 常见问题

**装好了但快捷指令里搜不到「保存取件码」？**
先打开一次 App。然后下拉刷新快捷指令的操作列表，或在搜索框里输「取件码」。确认手机是 iOS 16+。

**为什么短信来了没有自动存进去？**
按上面的步骤检查自动化有没有关掉「运行前询问」。另外自动化在锁屏时也可能不执行。

**数据会丢吗？**
存在 App 沙盒的 `Documents/pickups.json`。卸载 App 会连数据一起删。iCloud 备份时会一并备份，但换机恢复后文件位置不变，App 会直接读回来。

**怎么导出？**
目前没有导出功能，可以在「详情」页右上角分享单条，或者用「分享」功能把文本发给自己的备忘录。
