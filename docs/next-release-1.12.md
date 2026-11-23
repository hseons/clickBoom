# ClickBoom 1.12 规划：输入可视化与演示模式

更新日期：2026-11-23。**状态：已交付，1.12.0（27），146 个 XCTest 通过。** 本文保留当时的取舍与方案，作为后续回溯依据；实际实现与本稿的差异见文末「交付回顾」。

当时的基线：1.11.0（26），108 个 XCTest 通过。

## 结论

1.12 不加第 12 种点击效果，而是补上「输入」里缺的另一半：键盘。

三个判断：

1. 点击效果的数量已经过阈值。11 种效果 + 6 种拖尾，竞品最多 7 种点击样式、7 种拖尾（Mouzz / CursorFlow），继续加同质效果对留存几乎没有边际收益。
2. 键盘可视化是这类产品的分水岭。KeyCastr（★15,215）和 Keyviz（★9,797）整个产品只做「输入可视化」，ClickBoom 完全空缺，而这恰恰是讲解快捷键、演示软件时观众最需要的信息。
3. 现有静默规则在演示场景里是负资产。`autoSilenceInFullScreen` + 免打扰在「防止被打扰」时是对的，但用户全屏做 Keynote / Xcode 演示时，默认行为是「什么都不出现」。目前只能手动关掉全屏静默、关掉免打扰，讲完再手动恢复，忘记恢复就会被投诉「特效时有时无」。

1.12 范围（顺序即实施顺序）：

| # | 内容 | 解决的真实问题 | 预估 |
| --- | --- | --- | --- |
| 1 | 键盘与快捷键 HUD | 观众看不到你按了什么 | 2.5 天 |
| 2 | 演示模式 | 全屏/免打扰把演示时的效果关掉 | 1 天 |
| 3 | 按应用规则 | 只有一个二元排除列表，不同应用不能不同表现 | 1.5 天 |
| 4 | 点击音效 | 会议里只看画面容易错过点击 | 0.5 天 |
| 5 | 拖尾渲染优化 | 移动类场景 8.88–15.58% CPU，是全部高负载所在 | 1 天 |

1.13 预研：屏幕标注、放大镜、预设分享深链、单屏覆盖层改造。本文末尾给出启动条件。

## 现状盘点

### 已有能力（1.11）

- 视觉：11 种点击效果、6 种拖尾、聚光环、双击 / 长按触发、左右中键独立映射、6 个内置预设 + 自定义预设（搜索 / 收藏 / 排序 / 复制 / 导入导出 / 撤销导入）。
- 场景：场景预设（`ScenePreset` 只改视觉参数）、全屏自动静默、免打扰时段（星期掩码 + 本次跳过）、应用排除、性能三档自适应、减弱动态效果跟随。
- 系统：菜单栏快速面板、全局快捷键（默认 ⌃⌥B，带冲突探测）、开机自启、更新检查、设置备份（schema v1）、运行诊断。

### 结构（1.12 要动到的地方）

| 关注点 | 位置 |
| --- | --- |
| 状态与持久化 | `clickBoom/ContentView.swift:300` `AppState`（UserDefaults Key 枚举，逐项 didSet） |
| 状态优先级 | `clickBoom/RuntimeStatus.swift` `resolve(isEnabled:hasPermission:isPaused:quietHours:isQuietHoursSkipped:now:excludedApp:autoSilenceInFullScreen:isFullScreen:appName:)` |
| 全局监听 | `clickBoom/ContentView.swift:4451` `GlobalMouseMonitor` |
| 覆盖层 | `clickBoom/ContentView.swift:3212` `AppDelegate.layoutOverlay()`，单窗口覆盖 `ScreenUnion` 并集 |
| 绘制 | `clickBoom/ContentView.swift:3316` `EffectEngine`、`:3575` `EffectOverlayView`、`:3867` `drawTrail` |
| 快捷键 | `clickBoom/ContentView.swift:1058` `HotKeyManager`，`clickBoom/HotKeySettings.swift:8` `HotKeySpec` |
| 菜单栏面板 | `clickBoom/ContentView.swift:1469` `MenuBarQuickPanel` |
| 控制面板分区 | `:2047` 拖尾、`:2147` 预设、`:2328` 外观、`:2407` 粒子、`:2416` 动画、`:2422` 鼠标聚光、`:2470` 选项、`:2563` 应用排除、`:2651` 系统 |
| 权限 | `clickBoom/ContentView.swift:1331` `InputPermission`（`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`） |

### 约束

- `clickBoom/ContentView.swift` 已 4654 行。1.12 的新逻辑一律放新文件，`ContentView.swift` 只做接线和 UI 挂载，不再增长核心逻辑。
- `Package.swift` 用 `-default-isolation MainActor`，纯逻辑要显式 `nonisolated`（参照 `HotKeySpec`）才能被 XCTest 直接调用。
- Xcode 工程是 objectVersion 77 的同步组（`PBXFileSystemSynchronizedRootGroup`），新文件自动进 target；但 SPM target 要加音频资源必须补 `resources:`，否则 `swift test` 与 `swift build` 拿不到文件。
- 目前只有一项系统权限：输入监控。1.12 不新增权限（放大镜要 Screen Recording，放 1.13）。实测见 [input-permission-matrix.md](input-permission-matrix.md)：鼠标特效零权限，辅助功能是输入监控的超集。

## 竞品对照

2026-11 实测（App Store API / GitHub API），价格为美国区。

| 产品 | 点击特效 | 拖尾 | 聚光 | 键盘 HUD | 标注 | 放大 | 点击音效 | 静默规则 | 预设体系 | 按应用 | 价格 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **ClickBoom 1.11** | 11 种 | 6 种 | ✓ | — | — | — | — | 免打扰 / 全屏 / 排除 | 6 内置 + 自定义 | 仅排除 | 免费开源 |
| ClickLight（★319，MIT） | 4 类高亮 | — | 激光笔 | ✓ | — | — | — | — | 菜单快速预设 | — | 免费开源 |
| KeyCastr（★15,215） | 鼠标点击 | — | — | ✓ 3 种模式 | — | — | — | — | — | — | 免费开源 |
| Keyviz（★9,797） | 鼠标动作 | — | — | ✓ | — | — | — | — | 样式丰富 | — | 免费开源 |
| MFCMouseEffect（★891） | ✓ | ✓ | ✓ | — | — | — | — | — | WASM 插件 | — | 免费开源 |
| FocusCursor（★87） | ✓ | — | ✓ 遮罩 | — | ✓ | — | — | — | — | — | 免费 |
| Presentify | — | — | 光标高亮 | — | ✓ 强 | 描述未列 | — | — | — | — | $14.99 |
| Pro Mouse | 涟漪 | — | ✓ | ✓ | ✓ | ✓ | — | — | Shortcut Sets | **✓ 按 App 绑定** | $7.99 |
| Mouzz | 7 种 | 7 种 | ✓ | — | ✓ | — | — | — | — | — | 免费 |
| CursorFlow | 涟漪 | 7 种 | ✓ | — | ✓ | ✓ 1.5–6× | ✓ | 只暗指针所在屏 | — | — | 免费 + Pro |
| KeyShow | — | — | 遮罩 | ✓ | — | ✓ | — | — | — | — | 免费 |
| ZoomIt（Windows） | — | — | — | — | ✓ | ✓ | — | — | — | — | 免费 |

读表结论：

1. **键盘是唯一所有头部产品都有、ClickBoom 没有的能力**。KeyCastr 靠它拿到 1.5 万星；ClickLight 把它做成可选开关，说明「鼠标为主 + 键盘可选」是可行的产品形态。
2. **按应用配置已经被验证愿意付费**。Pro Mouse 把 Shortcut Sets 当卖点写进描述首屏：「Step into Keynote and your presenting setup switches on automatically」。ClickBoom 现在只有二元排除，等于把这块让出去。
3. **点击音效是最便宜的差异化**。只有 CursorFlow 做，成本半天，会议场景收益直接。
4. **标注 / 放大是下一层，不是这一层**。Presentify、Pro Mouse、CursorFlow、KeyShow 都有，但都要新的交互窗口或 Screen Recording 权限，放进 1.13。
5. ClickBoom 的护城河是「美术质量 + 静默规则 + 性能预算」三者同时具备，没有一个竞品同时覆盖。所以 1.12 的定位是**把输入维度补齐**，而不是去和 ZoomIt 比标注。

### 定位一句话

> 演示和录屏时，观众需要看到三件事：指针在哪、点了什么、按了什么。ClickBoom 已经做好前两件，1.12 补第三件，并且让它在演示场景里不被自己的静默规则挡住。

## 场景与痛点（从现有代码推出来，不是虚构）

1. **全屏演示没有效果**：`RuntimeStatus` 里 `fullScreen` 排在 `running` 之前，`autoSilenceInFullScreen` 默认开。全屏 Keynote、全屏浏览器演示时，特效被自己的规则关掉。
2. **讲快捷键观众跟不上**：没有任何键盘显示，只能口头说「按 ⌘⇧4」。
3. **不同应用需要不同表现**：录 Xcode 想要冷色、无拖尾（省电），Finder 想要彩虹；Keynote 想静默；现在只能整体调或者整体排除。
4. **会议里点击被忽略**：线上会议画面压缩后，涟漪在别人屏幕上可能只剩一帧。
5. **高负载全部集中在移动与拖尾**：1.11 对照里 trail-max 15.58%、trail-move 12.05%、click-trail 11.33%、spotlight-move 8.88%，而所有静止路径 ≤ 0.2%（`paused` 中位数 0.145%，其余 ≤ 0.015%）。拖尾的绘制路径是 `drawTrail` 每段 3–4 次 stroke。

## 参考文献

### 研究与设计依据

| 文献 | 用在哪 |
| --- | --- |
| Guo, P. J., Kim, J., & Rubin, R. (2014). How video production affects student engagement. *L@S '14*. DOI [10.1145/2556325.2566239](https://doi.org/10.1145/2556325.2566239) | 论证「操作可见性」影响教学视频的参与度，是点击/按键可视化的教学价值依据 |
| Gutwin, C., & Greenberg, S. (1998). Effects of awareness support on groupware usability. *CHI '98*. DOI [10.1145/274644.274713](https://doi.org/10.1145/274644.274713) | workspace awareness：他人操作可见性提升协作可用性，支撑「观众需要看到输入」这一产品假设 |
| Gutwin, C., & Greenberg, S. (1999). The effects of workspace awareness support on the usability of real-time distributed groupware. *TOCHI*. DOI [10.1145/329693.329696](https://doi.org/10.1145/329693.329696) | 同上，提供可引用的实验结论而非仅概念 |
| Emmert, M., Schmid, A., Wimmer, R., & Henze, N. (2023). CoShare: a Multi-Pointer Collaborative Screen Sharing Tool. *MuC '23*. DOI [10.1145/3603555.3608524](https://doi.org/10.1145/3603555.3608524) | 多指针屏幕共享里的指针可视化设计，直接对应 HUD 的「谁在按什么」表达 |
| Mayer, R. E. (Ed.). (2014). *The Cambridge Handbook of Multimedia Learning* (2nd ed.). DOI [10.1017/CBO9781139547369](https://doi.org/10.1017/CBO9781139547369) | signaling principle：高亮/聚光/键帽都属于 signaling，指引注意而非增加装饰 |

未采用：Brame (2016) 常被引用的 DOI `10.1187/cbe.16-03-0140` 经 Crossref 查询返回 404，不写进文档；`10.1145/274644.274692` 实际是 Rekimoto 的白板多设备论文，不是 Gutwin，别引错。

### 技术依据

- [`NSEvent.addGlobalMonitorForEvents(matching:handler:)`](https://developer.apple.com/documentation/appkit/nsevent/1535472-addglobalmonitorforevents) —— 全局鼠标/键盘事件回退路径。
- [`CGEvent.tapCreate(place:options:eventsOfInterest:callback:userInfo:)`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(place:options:eventsofinterest:callback:userinfo:)) —— 键盘 HUD 的主路径，`.listenOnly` 不改事件流。
- `IsSecureEventInputEnabled()`（Carbon.HIToolbox）—— 密码框 / 安全输入时抑制显示的依据，KeyShow 与 Pro Mouse 都把「密码框不显示」写进描述，属于同类产品的共识行为。
- `UCKeyTranslate` + `TISCopyCurrentKeyboardLayoutInputSource` —— 按当前键盘布局把 keyCode 转字符，避免硬编码 QWERTY。
- [`ScreenCaptureKit`](https://developer.apple.com/documentation/screencapturekit) —— 1.13 放大镜的抓屏路径。
- [`AVAudioEngine`](https://developer.apple.com/documentation/avfaudio/avaudioengine) —— 点击音效的低延迟播放与设备切换重建。
- [Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion) 与 `accessibilityReduceMotion` —— HUD 进出动画要跟随「减弱动态效果」。

### 竞品原始来源

- [ClickLight](https://github.com/aurorascharff/ClickLight)（MIT，Swift，README 明确区分「现场」与 Screen Studio / CleanShot 的「事后加效果」）
- [KeyCastr](https://github.com/keycastr/keycastr)、[Keyviz](https://github.com/mulaRahul/keyviz)、[MFCMouseEffect](https://github.com/sqmw/MFCMouseEffect)、[FocusCursor](https://github.com/jaywcjlove/focus-cursor)
- [Presentify](https://apps.apple.com/us/app/presentify-screen-annotation/id1507246666)、[Pro Mouse](https://apps.apple.com/us/app/pro-mouse-cursor-highlighter/id1505869474)、[Mouzz](https://apps.apple.com/us/app/mouzz-cursor-highlighter/id6760307235)、[CursorFlow](https://apps.apple.com/us/app/cursorflow-mouse-highlighter/id6744538347)
- [ZoomIt](https://learn.microsoft.com/en-us/sysinternals/downloads/zoomit)

## 1.12 范围

### 1. 键盘与快捷键 HUD

**问题**：演示软件、讲解快捷键时，观众看不到按键。

**取舍**：

- 事件源用 `CGEventTap`（`.cgSessionEventTap`，`.listenOnly`，mask `keyDown / keyUp / flagsChanged`）。已有输入监控权限门禁，不新增权限。tap 创建失败时回退 `NSEvent.addGlobalMonitorForEvents`，诊断里标明来源（「CGEventTap / 回退 NSEvent / 无权限」）。
- 权限实测（[docs/input-permission-matrix.md](input-permission-matrix.md)）：鼠标的 NSEvent 全局监听零权限可用；键盘 tap 只需输入监控；NSEvent 键盘监听由**辅助功能**门控（只有输入监控时收不到 keyDown/keyUp），因此回退前先查 `AXIsProcessTrusted()`，没有辅助功能就不装假监听。辅助功能同时会让 `CGPreflightListenEventAccess()` 返回 true，是输入监控的超集。
- 必须处理 `tapDisabledByTimeout` 与 `tapDisabledByUserInput`：收到后 `CGEvent.tapEnable(tap:enable:)` 重开，连续失败 3 次切回退并把原因写进诊断。
- 隐私：每次事件先查 `IsSecureEventInputEnabled()`，为真则立即清空并暂停显示 1 秒。不落盘、不写日志、诊断只报「最近一次事件时间」。
- 自动重复（按住不放）默认不重复显示，可切「每次重复都闪」。
- 只显示修饰键时不产生画面（默认），可切「按住 ⌘ 也显示」。

**方案**：

- 组合模型：修饰键按 ⌃⌥⇧⌘ 固定顺序 + 主键；主键字符走 `UCKeyTranslate`（跟随当前输入源），特殊键（Tab / Esc / 空格 / Return / Delete / 方向键 / F1–F12 / PageUp / Home）走固定表。
- 显示：键帽 chip（圆角 10、1px 描边、投影），最多 3 个 chip 一行；默认底部居中、距屏幕底 96pt，可切「跟随指针」（偏移 40pt）。
- 生命周期：1.6 秒后淡出；新组合出现时旧组合上移 24pt 并淡出，最多保留 2 行历史（1–3 可配）。
- 尺寸 S/M/L（17/21/26pt 字高），配色跟随当前预设主题，动画跟随「减弱动态效果」。
- 独立 `NSPanel`，不塞进现有覆盖层：`borderless`、`nonactivatingPanel`、`level .screenSaver + 1`、`ignoresMouseEvents`、`collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`，跟随指针所在屏定位。理由：覆盖层是一个跨屏并集窗口（`ScreenUnion.frame`），键盘 HUD 需要每屏独立定位，且不应参与特效清理；1.12 不动覆盖层结构。
- 联动：受「应用排除」控制（被排除的应用不显示），**不受**全屏静默 / 免打扰控制——演示时正是要显示；另有「进入演示模式时自动开启」。

**文件**：

- `clickBoom/KeystrokeMonitor.swift`：tap 生命周期、回退、`KeystrokeEvent` 派发。
- `clickBoom/KeystrokeFormatting.swift`：`nonisolated` 纯逻辑——`KeystrokeComboFormatter`（flags + keyCode → `[KeyToken]`）、`KeystrokeDisplayState`（超时淘汰、堆叠上限、清空）、`KeyToken`（label / isModifier / width 估算）。
- `clickBoom/KeystrokeHUDView.swift`：SwiftUI 渲染 + 控制面板内预览。
- `clickBoom/KeystrokeHUDPanel.swift`：NSPanel 创建 / 定位 / 显隐。

**设置区**：插在 `clickBoom/ContentView.swift:2470`「选项」之后、「应用排除」之前。

**验收**：

- 备忘录里按 ⌃⌥B，出现 `⌃` `⌥` `B` 三个 chip，1.6 秒后消失；连按不叠加成 6 个。
- 密码框聚焦时完全不显示（用系统「锁屏密码」或 1Password 验证）。
- 关掉开关后 tap 释放，`sample` 看不到持续唤醒；撤销输入监控后诊断显示「无权限」，不崩溃、不影响鼠标特效。
- 全屏 Keynote 内，演示模式开 → 显示；演示模式关 → 按「全屏时隐藏」设置生效。
- 混合屏（Retina + 1080p，含负原点副屏）HUD 贴底正确。
- 中文输入法下按字母键显示物理键字符，不显示候选词。

**风险**：`CGEventTap` 在极端情况下拖慢输入（listenOnly 通常不会，但必须实测按键延迟）；Secure Event Input 在部分浏览器密码框不开，需在文档里注明「不作为安全边界」。

### 2. 演示模式

**问题**：演示时全屏静默和免打扰会把效果关掉，用户只能手动关规则、事后手动恢复。

**方案**：

- `AppState.isPresentationMode`（**不持久化**，重启即退出，避免「忘了关」变成长期异常）。
- 进入时快照并覆盖：`autoSilenceInFullScreen = false`、免打扰暂停（`quietHoursSkipUntil` 不动，只加运行时短路）；可选「套用预设」（默认 `ScenePreset.recording`）+「开启键盘 HUD」+「开启聚光环」。
- 退出时按快照恢复，且恢复是幂等的（重复退出无副作用）。
- 规则优先级：`disabled → permissionRequired → paused → 演示模式（跳过 quietHours / fullScreen）→ quietHours → excluded → fullScreen → running`。**应用排除仍然生效**：用户显式排除的应用不该被演示模式打破，界面要写清楚。
- 入口：菜单栏快速面板显眼按钮（`MenuBarQuickPanel`），全局快捷键默认 ⌃⌥P（`HotKeySpec` 支持多实例：`hotKeySpec` 之外新增 `presentationHotKeySpec` + `presentationHotkeyEnabled`，`HotKeyManager` 从单 ref 改成按槽位注册，冲突探测复用 `applyProbed` 逻辑）。快捷键录制代码在 `clickBoom/ContentView.swift:2929` 附近，录制时用槽位区分。
- 可见性：菜单栏图标叠加实心点；控制面板顶部状态卡显示「演示中」；诊断新增一行「演示模式：开（已跳过全屏静默 / 免打扰）」。

**文件**：`clickBoom/PresentationMode.swift`（快照 / 恢复纯逻辑）、`clickBoom/RuntimeStatus.swift`（`resolve` 增加 `ignoresSilence: Bool` 参数，而不是新增枚举分支，保持纯函数可测）、`clickBoom/ContentView.swift`（面板、快捷键槽位、状态卡）、`clickBoom/HotKeySettings.swift`（槽位化）。

**验收**：

- 全屏 PPT 内开启演示模式 → 立即出效果；关闭 → 回到静默；两次切换后 `autoSilenceInFullScreen`、免打扰开关、预设、HUD 开关全部与进入前一致（逐字段对比备份 JSON）。
- 免打扰时段内进入演示模式有效果；退出后仍在免打扰内则继续静默。
- 排除列表里的应用在演示模式下仍不出效果。
- 手动暂停优先于演示模式（暂停是为了「现在别动」，演示模式是「现在要动」以外的一切）。
- 快捷键冲突时提示且不生效；重启后 `isPresentationMode == false`。

### 3. 按应用规则

**问题**：`AppExclusionLogic` 只有「排除 / 不排除」二元，不能「Xcode 用冷色无拖尾，Finder 用彩虹」。

**方案**：

- `AppRule { bundleID, name, silence: Bool, presetID: UUID?, disablesTrail: Bool, hudEnabled: Bool? }`，`AppRuleResolver`（`nonisolated` 纯逻辑）按 frontmost bundleID 解析出有效规则；未命中回退全局设置。
- 与场景预设的关系：场景预设仍是「全局视觉快照」，应用规则是「按应用覆盖」；应用规则只覆盖 `presetID` 指向的自定义预设或内置预设，不复制参数，避免两套真相。
- 迁移：读取旧 `excludedApps` 时转成 `silence: true` 规则；写入只写新键 `appRules`，同时保留旧键写入（`silence` 规则同步进 `excludedApps`）以兼容降级。备份 schema 升 v2：导入 v1 时把 `excludedApps` 转规则，导出 v2 时同时带 `excludedApps` 兼容旧版。
- UI：`:2563`「应用排除」升级为「应用规则」，列表每行：应用图标 + 名称 + 静默开关 + 预设下拉 + 高级（关拖尾 / HUD），底部「添加当前应用」。默认折叠成简洁模式，保持现有观感。

**文件**：`clickBoom/AppRuleLogic.swift`（规则、解析、迁移）、`clickBoom/AppRuleListView.swift`、`clickBoom/AppExclusionLogic.swift`（保留选择器能力，规则化后降级为数据源）、`clickBoom/SettingsBackupLogic.swift`（v2 往返）。

**验收**：

- 三条规则（Xcode 静默冷色、Finder 彩虹、Keynote 静默）切换前台应用后立即生效，无需重启。
- 切到无规则应用回到全局设置。
- 旧备份导入后排除项变成「静默」规则，视觉与行为与 1.11 一致；导出再导入结果一致。
- 排除自己（ClickBoom）仍然被拒绝。
- 规则切换时拖尾被关闭会清空已有点，不残留。

### 4. 点击音效

**问题**：线上会议画面压缩，涟漪容易被漏看。

**方案**：

- `AVAudioEngine` + `AVAudioPlayerNode` + 预加载 `AVAudioPCMBuffer`；3 个内置音色（click / soft / wood），≤120ms，44.1kHz 单声道，峰值 −6 dBFS。
- 首次播放前 start engine 预热，避免首击延迟；监听 `AVAudioEngineConfigurationChange`（切换耳机 / 输出设备）重建节点并重排缓冲。
- 音量映射用对数曲线（`gain(for:)` 纯函数，0 静音、1.0 → 1.0），默认 0.35。
- 与静默联动：静默 / 暂停 / 免打扰时不响（复用 `RuntimeStatus`）。
- 防抖：30ms 内同一按钮只响一次（双击触发的两次 down 不叠成两声）。
- 现实约束写进 UI 副标题：走系统输出，QuickTime / 系统录屏默认不录系统声，需要 BlackHole / Loopback 之类虚拟声卡或录制端支持系统音频。不做虚构承诺。
- 无新权限（不需要麦克风）。

**文件**：`clickBoom/ClickSound.swift`（引擎、缓冲、`nonisolated gain(for:)`）、`clickBoom/Resources/Sounds/*.wav`（`Package.swift` 补 `resources: [.process("Resources")]`；Xcode 同步组自动收）。

**验收**：

- 单击延迟主观无感（连续快速点击不糊成一片）；切换输出设备后仍能响。
- 音量 0 完全静音；免打扰 / 暂停 / 排除时不出声。
- 关闭后引擎停止，`sample` 无持续音频线程唤醒。

### 5. 拖尾渲染优化

**问题**：`drawTrail`（`clickBoom/ContentView.swift:3867`）逐段建 Path 并多次 stroke：classic 每段 3 次、neon 最多 4 次、comet 3 次 + 火星；180 点上限下每帧数百次 stroke。`smoothedTrail`（`:3831`）每帧重建平滑数组，宽度数组也每帧分配。

**方案**（只改绘制，不改观感）：

1. 按年龄分 6–8 个桶，相邻段合并成一个 Path，每桶一次 stroke，透明度取桶内代表值。stroke 次数从 ~600 降到 ~24。
2. 平滑结果增量缓存：只在新增轨迹点时追加计算，保留末尾 5 个点的重算窗口。
3. 宽度数组复用缓冲，避免每帧分配。
4. 分桶产生的色阶用 1.11 包截图逐像素对比，差异超过阈值就加桶数。

**启动条件**（ROADMAP 已定的约定）：先用 `CLICKBOOM_EFFECT_TIER=full|balanced|economy` 做三档对照，确认 144Hz 单屏下 trail-max 的绘制 p90 与 CPU，再动实现。

**验收**：

- 同一 `trail-max` 场景（`docs/performance-baseline.md` 方法，60 秒 ×3）CPU 或绘制 p90 相对 1.11.0 下降 ≥30%，且明显高于 1.9.0 自身的轮间波动（0.2–1.5%）。
- 截图对比：拖尾外观无可感知差异；用户实机确认后才合入。
- 三档 `CLICKBOOM_EFFECT_TIER` 下都不回退。

## 实施顺序

1. 纯逻辑层（无 UI，可先合）：`RuntimeStatus` 加 `ignoresSilence`、`PresentationMode` 快照、`AppRuleLogic`、`KeystrokeFormatting` + 测试。
2. 演示模式：面板按钮、快捷键槽位化、状态提示（依赖 1）。
3. 键盘 HUD：tap + 回退 + 面板定位（依赖 1）。
4. 应用规则 UI + 迁移 + 备份 v2（依赖 1）。
5. 点击音效（独立）。
6. 拖尾优化（独立，最后做，带基线对照）。
7. 文档：README 功能表、CHANGELOG、ROADMAP 收尾。

## 发布与验证

- 版本 1.12.0（27），测试目标 108 → 约 150。
- 每项新增纯逻辑都要有测试；UI 行为写进验收清单，不靠肉眼一次通过。
- 发布流程按现有约定：`swift test` → Xcode Debug + 通用 Release → DMG + `codesign --verify --deep --strict` → GitHub Release `v1.12.0` → `docs/performance-baseline-results.md` 补 1.12 对照。
- 多屏 / 竖屏验收仍依赖外接设备；1.12 键盘 HUD 的多屏定位至少要有单元测试 + 单屏实机，多屏实机标记为条件性验收。

## 开放问题（必须实机验证，不写结论）

1. ~~**全局鼠标监听到底需不需要授权**~~（2026-11-23 实测已解决）：ClickLight 说的 Accessibility 是 CGEventTap 点击检测的成本，CursorFlow 说的零权限对 NSEvent 全局监听成立。本机实测：无任何授权时 NSEvent 鼠标监听照常收事件，鼠标 tap 收不到；键盘 tap 只需输入监控，NSEvent 键盘监听反而要辅助功能。结论与矩阵见 [input-permission-matrix.md](input-permission-matrix.md)。
2. **`CGEventTap` 在 Secure Event Input 下的具体回调**：文档没有保证 tap 一定收到 `tapDisabledByUserInput`，要在密码框里实测是否需要额外的 `IsSecureEventInputEnabled` 轮询兜底（当前方案是每次事件查，代价低）。
3. **中文输入法下的 keyCode 语义**：`UCKeyTranslate` 在输入法激活时是否返回物理键字符，需要实测；若不稳定，退化为固定 QWERTY 表并在设置里说明。
4. **键盘 HUD 的内存/唤醒成本**：tap 常驻与面板常驻都要 `sample` 对照，不能只凭「listenOnly 很轻」。
5. **音效在录屏里的实际收录**：QuickTime、Screen Studio、OBS、Zoom 四种录制方式各测一次，结果写进 README，而不是笼统说「取决于录制方式」。

## 1.13 预研

| 方向 | 启动条件 | 主要成本 |
| --- | --- | --- |
| 屏幕标注（画笔 / 箭头 / 矩形 / 椭圆 / 自动擦除 / 撤销） | 1.12 键盘 HUD 的面板与事件层稳定后 | 交互窗口 + 工具条 + 与点击特效互斥（中，3–4 天） |
| 放大镜（跟随指针，1.5–6×） | 接受新增 Screen Recording 权限 | ScreenCaptureKit 抓屏 + 权限文案 + 隐私说明（中，2–3 天） |
| 预设分享深链 `clickboom://preset/<base64url>` | 有用户主动索取分享 | `CFBundleURLTypes` + 导入预览 + 二维码（小，1 天） |
| 单屏覆盖层改造（每屏一个窗口） | 多屏性能或坐标问题被实机证实 | 覆盖层重写 + 坐标回归（大，3–5 天） |

## 明确不做

- 点击历史图表 / 菜单栏计数：ClickLight 有，但对演示没有帮助，属于另一条产品线。
- 英文界面：等有海外反馈再排，先把中文文案和诊断做扎实。
- 云同步 / 账号体系：与「本地、无账号、不联网」的定位冲突。
- 内置录屏：和 Screen Studio / QuickTime 抢赛道，ROI 最低。

## 交付回顾（2026-11-23）

与本稿的差异，都是实施时发现「按原计划做会留下半个功能」或「原判断不成立」的地方：

1. **快捷键槽位化提前落地**。原计划只新增演示模式的第二个快捷键，实际把 `HotKeyManager` 从单个 `EventHotKeyRef` 改成按 `HotKeySlot` 注册，开关特效与演示模式各自录制、各自探测冲突。否则两套录制 UI 会互相覆盖。
2. **演示模式新增了 `.presenting` 状态**，而不是复用 `.running`。区别在状态行文案与诊断：用户需要知道「现在特效没被静默，是因为我在演示模式里」，而不是「一切正常」。
3. **应用规则没有做成「进 App 套预设、离开还原」**。原稿写的是「进入时套用预设」，实现时保留了「离开不强制还原」——否则用户在该 App 里手调过的参数会被下一次切换覆盖。规则只存预设 id，不复制参数。
4. **点击音效改为运行时合成波形**，不引入音频资源文件：三种音色用正弦分量加噪声合成，包体零增长，也避免了 `Package.swift` 增加 resources 配置。
5. **键盘 HUD 增加了「只显示快捷键组合」与三档尺寸**，原稿只写了位置与保留行数——演示时全量按键噪音太大，这个开关是必需的，不是可选项。
6. **拖尾渲染优化仍未动**。没有 144Hz 单屏 trail-max 的三档实测，按 1.11 的约定不改绘制路径；这一条顺延到 1.13 的条件性任务。
7. **权限问题仍未实测**。`CGEventTap` 被拒时自动回退 `NSEvent`，两条路径都能用，但没有干净账号做「授权 / 不授权」对照，因此文档里不写死「需要什么权限」。

测试从 108 增至 146：演示模式（8）、应用规则与备份（13）、点击音效（6）、按键格式化（9），其余为既有用例适配。
