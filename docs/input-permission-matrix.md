# 全局鼠标 / 键盘监听的权限矩阵（实测）

> 实测日期：2026-11-23　系统：macOS 27.2.1（Build 26B131，arm64）
> 方法：独立 bundle id 的探针 App（ad-hoc 签名），在系统设置里逐项增删授权，
> 用 `CGEvent(post: .cghidEventTap)` 合成鼠标/键盘事件；键盘事件必须使用
> `CGEventSource(stateID: .hidSystemState)`，否则系统静默丢弃。
> 每个状态都重新启动探针进程，读 `AXIsProcessTrusted()` 与
> `CGPreflightListenEventAccess()` 确认状态，再统计 NSEvent 全局监听与
> 两个 `CGEventTap`（listenOnly：鼠标 / 键盘）的收包数。

## 结论矩阵

| 授权状态 | NSEvent 鼠标 | NSEvent keyDown/Up | NSEvent flagsChanged | 鼠标 tap | 键盘 tap | tapCreate | tapIsEnabled |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 什么都没有 | ✅ 全部收到 | ❌ 0 | ✅ 收到 | ❌ 0 | ❌ 0 | 非 nil | **false** |
| 只有输入监控 | ✅ | ❌ 0 | ✅ | ✅ | ✅ | 非 nil | true |
| 只有辅助功能 | ✅ | ✅ | ✅ | ✅ | ✅ | 非 nil | true |
| 两者都有 | ✅ | ✅ | ✅ | ✅ | ✅ | 非 nil | true |

补充事实：

- **辅助功能隐含输入监控**：只把探针加进「辅助功能」、输入监控列表里没有条目，
  `CGPreflightListenEventAccess()` 仍返回 `true`，键盘 tap 正常工作。
  反过来不成立：只有输入监控时 `AXIsProcessTrusted()` 为 `false`。
- **鼠标 NSEvent 全局监听不需要任何授权**，未授权状态下左键、右键、移动全部收到。
  鼠标 `CGEventTap` 则需要输入监控（无授权时 0 事件）。
- **键盘 NSEvent 全局监听由辅助功能门控**，不是输入监控：只有输入监控时
  只能收到 `flagsChanged`，普通 `keyDown` / `keyUp` 一个都没有。
- `CGEvent.tapCreate` 在没有权限时**也返回非 nil**，但 `CGEvent.tapIsEnabled(tap:)`
  立刻就是 `false`（创建后 0.6s 再查仍是 false），且收不到任何事件。
  所以「tap != nil」不能当作授权成功；`tapIsEnabled` 可以。

## 对 clickBoom 的含义

1. 点击、拖尾、聚光环继续走 NSEvent 全局鼠标监听：**零权限**，与
   ClickLight「点击检测需要辅助功能」的说法不矛盾——那是 CGEventTap 实现的代价，
   不是点击检测的必要条件。CursorFlow 宣称的「都不需要」对 NSEvent 实现成立。
2. 键盘 HUD 只需要**输入监控**：主路径 `CGEventTap` 在只有输入监控时完整可用。
   `RuntimeStatus` 不再持有权限状态、`permissionRequired` 文案只出现在键盘 HUD
   卡片，方向正确。
3. NSEvent 键盘回退只在**辅助功能**下有效。1.12.2 的回退在只有输入监控时会
   装上一个只能收修饰键的监听，界面还显示「兼容模式」；现在 `installFallback()`
   先查 `AXIsProcessTrusted()`，没有辅助功能就不装，让 HUD 如实报失败。
4. 顺带修掉「假装监听成功」的最后一处：`installTap()` 创建后立刻检查
   `CGEvent.tapIsEnabled`，禁用态直接按失败处理。

## 复现

探针源码与工具保留在 `/tmp/permprobe`（`AppMain.swift`、`emitter`、`keytest`、
`axdump` / `axpress` / `axclick` / `axgeom` / `axaction` / `click`）。流程：

1. `swiftc -O AppMain.swift -o /Applications/PermProbe.app/Contents/MacOS/PermProbe`
   后 `codesign --force --sign - --identifier mumu.AIGG.clickBoom.permprobe`；
2. 系统设置 → 隐私与安全性 → 输入监控 / 辅助功能，增删条目；
3. `open -n /Applications/PermProbe.app`，再跑 `./emitter all 3` 与 `./keytest`；
4. 读 `/tmp/permprobe/latest.log` 的 `BOOT`、`TICK` 与逐事件行。

注意：ad-hoc 签名每次重签都会换 cdhash，系统里的旧授权立刻失效（表现为
`BOOT ... listen=false`），必须删掉条目重新添加；正式包用固定证书签名，
不受这个影响。
