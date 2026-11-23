# 1.13 规划：屏幕标注、预设分享与同类产品对照

更新日期：2026-11-23。1.12.0 已交付键盘与快捷键 HUD、演示模式、按应用规则、点击音效；本文只规划下一版，不重复已做的部分。

## 一句话结论

1.13 的主线是「讲解」：让录屏观众看到的不只是指针、点击和按键，还有「我要说的是这块区域」。先做标注（无新权限、纯本地绘制），放大镜与预设分享按条件推进。拖尾渲染优化继续挂在「先测量再改」的条件下。

## 现状

1.12.0 之后，ClickBoom 的输入可视化已经齐了：

- 指针：聚光环、放大镜缺口（未做）
- 点击：11 种效果、6 种拖尾、右键/中键独立、连击放大
- 按键：键盘与快捷键 HUD（CGEventTap，安全输入隐藏）
- 场景：演示模式、按应用规则、免打扰时段、全屏静默

对照竞品，剩下的能力缺口集中在两侧：讲解侧（标注、放大镜）与分发侧（预设分享）。

## 竞品对照（2026-11，App Store API / GitHub API 实测）

| 产品 | 价格 | 标注 | 放大 | 键盘 | 按应用配置 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| Presentify | $14.99 | 强：形状、文字、荧光笔、Shift 直线、自动擦除 | 无 | 无 | 无 | 能在全屏应用上画，按住 Fn 与底层应用交互；Sidecar |
| CursorFlow | 免费 + Pro | 有屏幕绘制 | 1.5–6× | 无 | 无 | 点击与拖尾宣称不需要辅助功能权限，只有放大镜要 Screen Recording |
| Pro Mouse | $7.99 | 有 drawing | zoom glass | 有（密码框不显示） | 有，Shortcut Sets 整套配置绑定 App | halo / spotlight 放在卖点首屏 |
| Mouzz | 免费 | 有 | 无 | 无 | 无 | 7 种点击样式 + 7 种拖尾 |
| KeyShow | 免费 | 无 | 有 | 有 | 无 | 放大镜用 Screen Recording |
| ClickLight | 开源 ★319 | 无 | 无 | 有 | 无 | 点击需 Accessibility、键盘需 Input Monitoring |
| KeyCastr | 开源 ★15,215 | 无 | 无 | 有，3 种模式 | 无 | 只做键盘就成立的产品 |
| Keyviz | 开源 ★9,797 | 无 | 无 | 有，含鼠标动作 | 无 | 样式与过滤最细 |
| ClickBoom 1.12 | 免费开源 | **无** | **无** | 有 | **有** | 效果数量、拖尾笔触、静默规则、性能预算领先 |

读法：标注是付费产品普遍具备、开源同类普遍缺失的能力；放大镜在免费产品里更常见，但都要 Screen Recording 权限。ClickBoom 的差异化仍是「输入可视化 + 规则体系」，标注是补全这条线，不是转向做白板。

## 痛点推演

1. **讲解时说不清位置**。录屏里说「点这里」，观众要在小窗口里找指针；聚光环只能指一个点，指不了一个区域。这是标注要解决的问题，不是放大镜。
2. **标注工具与演示工具割裂**。现在要标注得另开 Presentify 或系统预览，两个 App 抢焦点、快捷键打架，录屏窗口还多一层。
3. **放大镜的隐私成本被低估**。Screen Recording 是系统级权限，弹窗文案是「可以录制屏幕上的所有内容」；把它和标注一起塞进首次授权，会让用户在第一屏就遇到最吓人的那个弹窗。
4. **预设只能文件传**。现在导出 JSON 再发给别人，对方要找到导入入口；深链可以把「一套配色」变成一条可点击的链接。

## 方案

### 1. 标注层（主线）

- 新文件：`clickBoom/AnnotationModel.swift`（纯逻辑：笔画、形状、命中、自动擦除计时）、`clickBoom/AnnotationGeometry.swift`（箭头 / 矩形 / 椭圆的路径与端点约束）、`clickBoom/AnnotationOverlayView.swift`（SwiftUI Canvas）、`clickBoom/AnnotationController.swift`（模式切换、窗口、快捷键）。
- 工具：画笔（自由曲线，按 1/120 s 采样、距离阈值 2pt 合并）、箭头（起点拖到终点，`⇧` 约束 15°）、矩形、椭圆、文字（点一下输入，回车落笔）。
- 颜色取当前点击效果颜色，另给 6 个常用色；线宽三档（2 / 4 / 7pt）。
- 自动擦除：最后一笔结束后 N 秒淡出（默认 3 秒，可关、可设 1–10 秒）；「清空」快捷键立即清除全部。
- 窗口：复用覆盖层的 collectionBehavior，但进入标注模式时 `ignoresMouseEvents = false` 并成为 key window 接收绘制事件；退出后恢复 `ignoresMouseEvents = true`。标注模式期间点击特效暂停（避免自己画一笔就炸一堆粒子），退出后恢复。
- 快捷键：`HotKeySlot.annotation = 3`，默认 ⌃⌥D；按下切换「标注开 / 关」，`Esc` 退出，`⌘Z` 撤销上一笔。
- 状态：`AppState.isAnnotating` 不持久化；标注模式下运行状态显示「标注中」，优先级与演示模式同级。

### 2. 预设分享深链（小）

- URL scheme `clickboom://preset?id=...&name=...&v=1`，payload 为 base64url 的 `PresetSnapshot` JSON。
- 校验：schema 版本、字段范围、长度上限（8KB），非法直接拒绝并提示原因；导入前显示「来自谁 / 名称 / 主要参数」摘要，确认后才写入。
- 复用现有 `PresetArchive` 的合并与同名副本策略，不新增第四套导入逻辑。

### 3. 放大镜（条件性）

- 仅在标注交付后单独评估。技术路线：`ScreenCaptureKit` 单帧轮询（指针周围 160×160，5–10 fps），或 `CGWindowListCreateImage` 等价 API；权限文案单独一屏解释「只为放大指针周围，不保存、不上传」。
- 触发：`HotKeySlot.magnifier = 4`，按住显示、松开隐藏；倍率 2× / 4× / 6×。
- 不做的理由若成立：权限弹窗的观感成本 > 功能收益，且 CursorFlow / KeyShow 已经免费提供。

### 4. 拖尾渲染优化（条件性）

- 仍是 1.11 的约定：先按 `docs/performance-baseline.md` 跑 `CLICKBOOM_EFFECT_TIER` 三档对照，拿到 144Hz 单屏 trail-max 的 p90 与 CPU，再决定是否按年龄分桶合并 Path。
- 没有数据就不动绘制路径，避免用结构推断代替证据。

## 实施顺序

1. `AnnotationModel` + `AnnotationGeometry` + 单元测试（无 UI，可离线验证）。
2. `AnnotationOverlayView` 接到覆盖层，标注模式开关与快捷键槽位。
3. 自动擦除、撤销、清空、线宽与颜色。
4. 预设深链解析 + 导入摘要（先做解析与校验，再做 UI）。
5. 文档与发版：README 功能段、CHANGELOG、ROADMAP、备份 schema 若新增字段则升 v3。

## 验收

- 标注：画笔 / 箭头 / 矩形 / 椭圆 / 文字都能画，`⇧` 约束生效，`⌘Z` 撤销，`Esc` 退出，自动擦除按设定时间淡出；标注期间点击特效不触发，退出后立即恢复；多屏与竖屏坐标正确（单元测试覆盖坐标换算，实机标记条件性验收）。
- 深链：合法链接导入成功并显示摘要；超长、错版本、缺字段、非法 JSON 四类都被拒绝且提示原因；重复导入不产生重复预设。
- 回归：146 个既有测试全绿；1.12 的演示模式、应用规则、键盘 HUD、点击音效行为不变。

## 风险

- 标注模式接管鼠标可能与「覆盖层忽略鼠标」的既有假设冲突，需要显式状态机，不能靠 `ignoresMouseEvents` 单开关。
- 标注模式下的键盘事件会被 HUD 捕获，需要在标注中屏蔽 HUD，否则画一笔就刷一排键帽。
- 深链是外部输入，必须当成不可信数据解析：限长、限版本、限字段，不走 `NSKeyedUnarchiver`。

## 明确不做

- 白板 / 无限画布：那是另一个产品。
- 云同步、账号体系：与本地优先的定位冲突。
- 视频编辑式的后期标注：Screen Studio 的领域，ClickBoom 做「现场」。
- 英文界面：等交互稳定后统一做，避免两套文案反复改。

## 参考文献

- Mayer, R. E. (ed.). *The Cambridge Handbook of Multimedia Learning* (2nd ed.). Cambridge University Press, 2014. DOI: 10.1017/CBO9781139547369。signaling principle：箭头、圈选、高亮这类「信号」降低无关负荷，是标注有效性的理论依据。
- Guo, P. J., Kim, J., & Rubin, R. *How video production affects student engagement: an empirical study of MOOC videos*. L@S 2014. DOI: 10.1145/2556325.2566239。短于 6 分钟、讲解者出镜、语速快的视频参与度更高，支撑「现场标注优于事后剪辑」。
- Gutwin, C., & Greenberg, S. *Effects of awareness support on groupware usability*. CHI 1998. DOI: 10.1145/274644.274713；*The effects of workspace awareness support on the usability of real-time distributed group workspaces*. TOCHI 1999. DOI: 10.1145/329693.329696。远端指针与痕迹（telepointer / artifact）如何降低协作中的理解成本。
- CoShare: *a Multi-Pointer Collaborative Screen Sharing Tool*. 2023. DOI: 10.1145/3603555.3608524。多指针共享屏幕时的指针可视化设计。
