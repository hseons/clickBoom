# clickBoom

一个轻量、原生的 macOS 全局鼠标点击特效工具。它会监听鼠标点击，并在点击位置绘制即时动画，让演示、录屏、直播和日常操作更有反馈感。

项目使用 SwiftUI 和 macOS 原生 API 编写，不依赖第三方运行库。

## 📸 界面预览

<p align="center">
  <img src="docs/images/clickboom-menu-preview.png" alt="ClickBoom 菜单栏快速面板" width="396">
</p>

## ✨ 功能特性

- 全局监听鼠标点击与滑动（左键、右键与中键，右键/中键可单独关闭）
- 11 种可切换的点击效果：
  - 火花：短线条向外散开
  - 圆环：一段圆弧从点击位置展开
  - 光线：几条细光线快速划过
  - 彩纸：小块彩纸轻轻飘开
  - 表情：点击弹出自定义 Emoji，带轻微弹性、漂浮和旋转动画
  - 水波：三圈涟漪依次向外扩散、逐圈变淡
  - 星芒：四长四短的尖细星芒 + 中心高光，像镜头光晕
  - 像素：8-bit 小方块四散旋转、边飞边缩小
  - 爱心：小爱心错峰上浮，带轻微摇摆与旋转
  - 烟花：焰火炸开后拖尾下坠，中心带一圈闪光
  - 闪电：锯齿电弧向外劈开，外层发光、内层亮芯
- 独立的「滑动拖尾」开关：移动或拖动鼠标时留下渐隐光带，可与任意点击效果同时开启；内置光带、毛笔、霓虹、彗星、丝带、星尘 6 种拖尾样式，单击时补一个光点；拖尾有独立颜色、粗细、透明度和停留时长，默认跟随点击颜色
- 支持自定义效果颜色，并提供 6 个常用色块一键切换
- 支持输入一个或多个自定义 Emoji，多个 Emoji 会在每次点击时随机选择；也可点选常用 Emoji 快速加入
- 内置 6 组快捷预设：默认、蓝光、圆环、彩纸、赛博、烟花
- 支持把自己的整套参数保存成自定义预设（同名覆盖），随时一键套用或删除
- 支持把自定义预设导出为版本化 JSON 文件，并重新导入或跨设备合并；同名预设会自动保留副本
- 支持暂停 15 / 30 / 60 分钟：演示中途临时关掉效果，到点自动恢复
- 支持自定义全局快捷键（默认 ⌃⌥B）：点一下直接按新的组合键，需包含 ⌃ / ⌥ / ⌘，可在任意 App 里快速开关特效；录制时会先探测组合是否被占用，冲突时保留原快捷键
- 支持「应用排除」列表：把录屏、会议或游戏 App 加进去后，在这些 App 里不出点击特效和拖尾，其他 App 照常工作；菜单栏可一键排除当前 App，列表支持搜索并自动刷新
- 支持「全屏时自动静默」：前台 App 全屏时自动暂停特效和拖尾，退出全屏立即恢复，看电影、演示时不用手动关
- 支持「设置备份」：把快捷键、排除列表和全屏静默开关导出成 JSON，换机或重装后一键导入
- 支持调整粒子数量、大小、扩散半径、动画时长和缩放比例
- 新增鼠标聚光环：录屏和演示时持续标出指针位置，支持自定义颜色、大小、透明度和点击脉冲
- 支持区分左键、右键和中键，右键与中键可使用独立颜色
- 拖尾支持始终跟随、仅拖动、按住 Option 或按住 Command 四种触发方式
- 内置教程、录屏、直播、极简四类演示场景，一键切换整套效果
- Emoji 模式支持在控制面板或菜单栏直接编辑自定义表情
- 菜单栏提供快速面板，可直接开关、预览、定时暂停、套用预设，并快速调整常用参数；图标会随开关变暗，暂停时显示暂停标记
- 面板内可一键「预览」当前效果，调完参数立刻看到结果，也能一键「恢复默认设置」
- 跟随系统「减弱动态效果」：开启后自动收起旋转与摇摆
- 随机样式：每次点击自动抽取一种样式
- 连续点击放大：短时间连续点击会逐步增加粒子数量和范围
- 支持开机自启（基于系统登录项，可随时在控制面板或菜单栏开关）
- 自动检测「输入监控」权限，未授权时直接在面板里提示并一键跳转设置，授权后立即生效、无需重启
- 支持多显示器：覆盖层铺满所有屏幕，副屏/竖屏点击同样有效，插拔显示器自动适配
- 启动时只留在菜单栏，不弹面板（开机自启也不会打断登录），点 Dock 图标可随时叫回
- 空闲时暂停动画渲染，不点击就不占绘图资源
- 控制面板可拖拽调整窗口大小
- 内置「检查更新」，直接对比 GitHub 上最新 Release；启动后每天自动检查一次，有新版本时菜单栏图标显示小圆点
- 设置会自动保存，下次启动时继续使用
- 使用透明悬浮层绘制，不影响鼠标正常操作
- 原生 SwiftUI 界面，轻量且易于扩展

## 🖥️ 系统要求

- macOS 26.0 或更高版本
- Xcode 26.0 或更高版本（仅编译时需要）

首次运行时，系统会请求「输入监控」权限，用于接收其他应用中的全局鼠标点击事件。路径：系统设置 → 隐私与安全性 → 输入监控 → 勾选 ClickBoom。授权后无需重启 App，点击效果会立即生效。

## 📦 安装

1. 到 [Releases](https://github.com/hseons/clickBoom/releases) 下载最新的 `ClickBoom-x.y.z.dmg`。
2. 打开 DMG，把 ClickBoom 拖进「应用程序」。
3. 首次打开时，如果看到「无法验证开发者」的提示，说明安装包还没有经过 Apple 公证。任选一种方式放行：
   - 在「应用程序」里 **右键点击 ClickBoom → 打开 → 再点「打开」**；
   - 打开 系统设置 → 隐私与安全性，在底部点「仍要打开」；
   - 或者用命令行去掉隔离标记：
     ```bash
     xattr -dr com.apple.quarantine /Applications/ClickBoom.app
     ```
4. 按提示授予「输入监控」权限，然后随便点几下鼠标即可看到效果。

> 面板默认不再随启动弹出（开机自启时也不会打断登录），从菜单栏图标或 Dock 图标进入即可。

## 🚀 快速开始

### 使用 Xcode

1. 克隆仓库并进入项目目录：

   ```bash
   git clone https://github.com/hseons/clickBoom.git
   cd clickBoom
   ```

2. 使用 Xcode 打开 `clickBoom.xcodeproj`。
3. 选择 `clickBoom` scheme，点击运行。
4. 点击 macOS 菜单栏中的 ClickBoom 图标，可快速开关效果、切换样式并调整常用参数；也可以打开完整控制面板。
5. 在任意应用中点击鼠标，查看点击特效。

### 新颖玩法

- 点击“快捷预设”可以快速切换一整套颜色、粒子和动画参数。
- 调出满意的效果后，在「预设 → 我的预设」点「保存当前」，给它起个名字；之后就能一键套用，右键（或点小叉）可删除。
- 按 `⌃⌥B` 可以在任意 App 里开关特效，不用切回菜单栏。
- 演示或录屏中途想临时关掉效果，用菜单里的「暂停 15 / 30 / 60 分钟」；到点自动恢复，也可以随时点「立即恢复」。
- 开启“随机样式”后，每次点击都会从现有 11 种效果中随机选择一种。
- 开启“连续点击放大”后，在 1 秒内连续点击会逐步增加粒子数量、尺寸和扩散范围；停止点击后会自动归零。
- 打开“滑动拖尾”开关后，鼠标不用按住也会跟随滑动留下光带，点击时的效果照常播放；拖动窗口、圈选文件或在白板上写字时尤其明显。开关下方可以在光带、毛笔、霓虹、彗星、丝带、星尘 6 种笔触之间切换，还能单独调颜色、粗细、透明度和停留时长（默认跟随点击颜色）；快速滑动时轨迹会自动平滑，右键/中键拖动同样受右键开关控制。
- 选择“Emoji 表情”后，在控制面板或菜单栏输入 `✨🔥💖` 这类 Emoji 串；每次点击只弹出一个表情，动画更轻巧。下面的快捷 Emoji 点一下就能加入或移除。

### 命令行构建

```bash
xcodebuild \
  -project clickBoom.xcodeproj \
  -scheme clickBoom \
  -configuration Debug \
  -sdk macosx \
  build
```

核心逻辑测试使用 XCTest，直接编译真实 App 模块：

```bash
swift test
```

如果 `xcode-select -p` 指向 CommandLineTools，需要先 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`，或者临时指定：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

另外，仓库如果放在 iCloud Drive、网盘同步目录等 File Provider 路径下，产物会被写入 FinderInfo 等扩展属性，签名时会报
`resource fork, Finder information, or similar detritus not allowed`。把构建目录指到系统临时目录即可：

```bash
xcodebuild ... -derivedDataPath "${TMPDIR}/clickboom-build"
```

### 打安装包

```bash
./scripts/release.sh          # 输出 dist/ClickBoom-<版本>.dmg（arm64 + x86_64 通用二进制）

PUBLISH=1 ./scripts/release.sh   # 构建完成后直接传到 GitHub Release（需 gh 已登录）
```

推 `v*` 标签时，GitHub Actions 也会自动构建一次并把 DMG 补到 Release；如果 Release 里已经有 DMG 附件，CI 不会覆盖（保留本地签名版本）。Release 说明由 `scripts/changelog-notes.sh` 从 `CHANGELOG.md` 提取当前版本段落。

需要正式分发（不再被 Gatekeeper 拦截）时，用 Developer ID 证书签名并公证：

```bash
xcrun notarytool store-credentials clickboom \
  --apple-id <你的 Apple ID> --team-id <TEAMID> --password <App 专用密码>

SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=clickboom \
./scripts/release.sh
```

## 🎛️ 参数说明

| 参数 | 说明 |
| --- | --- |
| 效果颜色 | 设置当前点击动画的颜色 |
| 数量 | 每次点击生成的粒子数量 |
| 大小 | 火花、光束或彩纸的基础尺寸 |
| 半径 | 动画向外扩散的范围 |
| 持续时间 | 单次点击动画的显示时长 |
| 缩放 | 整体效果的放大或缩小比例 |
| 随机样式 | 每次点击随机选择一种效果样式 |
| 滑动拖尾 | 独立开关；开启后移动鼠标留下渐隐光带，可与点击效果同时使用 |
| 拖尾样式 | 光带 / 毛笔 / 霓虹 / 彗星 / 丝带 / 星尘，6 种不同笔触的拖尾；毛笔的粗细随滑动速度变化 |
| 跟随点击颜色 | 打开时拖尾使用点击效果的颜色；关闭后单独选色 |
| 拖尾颜色 | 拖尾自己的颜色，仅在关闭「跟随点击颜色」后生效 |
| 拖尾粗细 | 光带和笔触的基准宽度 |
| 拖尾透明度 | 拖尾整体的透明度，不影响点击效果 |
| 拖尾停留 | 拖尾在屏幕上停留的时长，与点击动画时长分开设置 |
| 连续点击放大 | 连续点击时逐步增加效果范围 |
| 自定义 Emoji | 输入一个或多个 Emoji，点击时随机弹出一个 |
| 全局快捷键 | `⌃⌥B`，在任意 App 中开关特效；可自行录制，冲突会提示 |
| 全屏静默 | 前台 App 全屏时自动暂停特效，默认开启 |
| 定时暂停 | 暂停 15 / 30 / 60 分钟后自动恢复 |
| 我的预设 | 保存当前整套参数，同名覆盖，可一键套用或删除 |

## 🧩 项目结构

```text
clickBoom/
├── ContentView.swift       # SwiftUI 控制面板、全局监听和特效渲染
├── PresetArchiveLogic.swift # 预设文件校验、规范化与合并
├── AppVersion.swift        # 更新检查版本比较
├── InputMapping.swift      # 鼠标按键与拖尾触发映射
├── HotKeySettings.swift    # 全局快捷键的组合规则、文案与持久化
├── AppExclusionLogic.swift # 应用排除列表的规范化与增删
├── FullScreenDetector.swift # 全屏检测与窗口几何判定
├── SettingsBackupLogic.swift # 设置备份的编码、校验与合并
├── FrontmostAppTracker.swift # 记录最近的非自身前台 App
└── Assets.xcassets/        # 应用图标和颜色资源
clickBoom.xcodeproj/        # Xcode 工程文件
Tests/ClickBoomTests/       # 核心逻辑单元测试
Package.swift               # SwiftPM 测试入口
scripts/release.sh          # 打包 DMG（通用二进制，可选签名/公证）
```

界面、监听和渲染主体仍集中在 `ContentView.swift`，可独立验证的规则已拆到纯逻辑文件：

- `AppState`：保存开关和特效参数
- `EffectStyle`：管理可用的效果样式
- `EffectEngine`：创建和清理点击粒子，维护滑动拖尾轨迹
- `EffectOverlayView`：通过 `Canvas` 和 `TimelineView` 绘制动画
- `PresetArchiveCodec`：预设归档校验、参数规范化和合并
- `AppVersionComparator`：语义化版本的逐段比较
- `InputMapping`：鼠标按钮权限与拖尾触发规则
- `HotKeySpec`：全局快捷键的合法组合、展示文案和存储格式
- `AppExclusionLogic`：应用排除列表的规范化、去重与增删
- `FullScreenLogic` / `FullScreenDetector`：窗口是否铺满屏幕的几何判定与带缓存的查询
- `SettingsBackupLogic`：设置备份的编解码、schema 校验与排除列表合并
- `FrontmostAppTracker`：菜单栏面板打开前记住最近的前台 App

## 🗒️ 更新日志

完整历史见 [CHANGELOG.md](CHANGELOG.md)，这里只保留最近两个版本。

### 1.5.0

- 新增「全屏时自动静默」：前台 App 全屏时暂停点击特效和拖尾，退出全屏自动恢复，默认开启
- 菜单栏快速面板可一键「在「当前 App」中静默 / 取消静默」
- 应用排除列表支持搜索，并跟随 App 启动、退出和面板激活自动刷新
- 新增「设置备份」：快捷键、排除列表与全屏静默开关可导出为 JSON 并重新导入
- 录制快捷键时先探测组合是否可用，被占用时提示「已被占用」并保留原组合
- 新增独立 CHANGELOG.md；Release 说明自动从 CHANGELOG 提取当前版本段落
- 测试总数从 23 个增加到 33 个

### 1.4.0

- 全局快捷键可以自己改了：点控制面板或菜单栏里的按键框，直接按新的组合键即可，支持字母、数字、符号、方向键和 F1–F12；修饰键需包含 ⌃ / ⌥ / ⌘，Esc 取消录制，非默认组合可一键恢复
- 快捷键设置会持久化保存，重启 App 后继续沿用；换到被占用的组合时会给出「注册失败」提示
- 新增「应用排除」：把录屏、视频会议或全屏游戏 App 加入列表后，在这些 App 里不再显示点击特效和滑动拖尾，前台切换即时生效
- 排除列表按 bundle id 记录，导出/导入预设不受影响；列表来自当前运行中的 App，重新打开面板即可刷新
- 修正仓库与更新检查链接（`hhse` → `hseons`），「检查更新」重新可用
- 新增快捷键与应用排除的单元测试，测试总数从 11 个增加到 23 个

## 🔗 开源地址

- GitHub：<https://github.com/hseons/clickBoom>
- 灵感来源：<https://reactbits.dev/animations/click-spark>

欢迎提交 Issue、建议和 Pull Request，一起完善更多点击效果。

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。
