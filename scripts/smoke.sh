#!/bin/bash
# 真机冒烟：每次改完功能先跑这个，别等用户来报「没效果」。
#
#   ./scripts/smoke.sh            # 构建 + 单测 + 启动 + 窗口/日志/性能断言
#   ./scripts/smoke.sh --no-build # 跳过构建和单测，只跑运行时断言
#
# 断言内容：
#   1. 进程活着
#   2. 覆盖层窗口存在（layer 1000，覆盖整个屏幕）
#   3. 键盘 HUD：HUD 开着时按一个键必须出现 layer 1001 浮层；HUD 关着就跳过
#   4. 日志里没有 error 级记录，也没有 tap 安装失败
#   5. 鼠标移动时 CPU 不超过阈值（默认 12%）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/ClickBoom.app"
BUNDLE_ID="mumu.AIGG.clickBoom"
TOOL_DIR="/tmp/clickboom-smoke"
CPU_LIMIT="${CPU_LIMIT:-12}"
SKIP_BUILD=0
[[ "${1:-}" == "--no-build" ]] && SKIP_BUILD=1

fail() { echo "❌ $*" >&2; exit 1; }
ok()   { echo "✅ $*"; }

if [[ $SKIP_BUILD -eq 0 ]]; then
  echo "==> 构建"
  ( cd "$ROOT" && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build ) || fail "构建失败"
  echo "==> 单测"
  ( cd "$ROOT" && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | tail -3 | grep -q "0 failures" ) \
    || fail "测试没有全绿"
  ok "构建与单测通过"
fi

mkdir -p "$TOOL_DIR"
cat > "$TOOL_DIR/winlist.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ClickBoom"
if let infos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
    for w in infos {
        guard let name = w[kCGWindowOwnerName as String] as? String, name == owner else { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        let onscreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = b["Width"] as? Double ?? 0
        let height = b["Height"] as? Double ?? 0
        print("\(layer) \(onscreen) \(Int(width)) \(Int(height))")
    }
}
SWIFT
cat > "$TOOL_DIR/move.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let count = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 300
for i in 0..<count {
    let x = 500 + CGFloat(i % 150) * 6
    let y = 400 + CGFloat(i % 100) * 5
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(6000)
}
SWIFT
cat > "$TOOL_DIR/click.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let p = CGPoint(x: 700, y: 500)
for _ in 0..<3 {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(50000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(250000)
}
SWIFT
for tool in winlist move click; do
  [[ -x "$TOOL_DIR/$tool" && "$TOOL_DIR/$tool.swift" -ot "$TOOL_DIR/$tool" ]] || \
    swiftc -O "$TOOL_DIR/$tool.swift" -o "$TOOL_DIR/$tool" || fail "辅助工具 $tool 编译失败"
done

echo "==> 重启 App"
osascript -e 'quit app "ClickBoom"' >/dev/null 2>&1
sleep 1
[[ -d "$APP" ]] || fail "没有安装到 $APP"
open -a "$APP" || fail "启动失败"
sleep 3
PID="$(pgrep -f "$APP/Contents/MacOS/ClickBoom" | head -1)"
[[ -n "$PID" ]] || fail "进程没起来"
ok "进程运行中 (pid $PID)"

echo "==> 覆盖层窗口"
WINDOWS="$("$TOOL_DIR/winlist" ClickBoom)"
echo "$WINDOWS" | sed 's/^/    /'
echo "$WINDOWS" | grep -qE "^1000 true [0-9]{3,} [0-9]{3,}$" || fail "覆盖层窗口不存在（layer 1000 / 全屏）"
ok "覆盖层窗口存在"

echo "==> 点击特效"
"$TOOL_DIR/click" || true
sleep 0.5
ok "点击事件已派发（无回显，靠下面的日志与 CPU 断言兜底）"

echo "==> 键盘 HUD"
HUD_ENABLED="$(defaults read "$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Preferences/$BUNDLE_ID" keystrokeHUDEnabled 2>/dev/null || echo 0)"
if [[ "$HUD_ENABLED" == "1" ]]; then
  osascript -e 'tell application "System Events" to keystroke "j" using {command down, shift down}' >/dev/null 2>&1 &
  sleep 0.6
  "$TOOL_DIR/winlist" ClickBoom | grep -qE "^1001 true" || fail "HUD 开着但按键后没有浮层（可能没有输入监控授权）"
  ok "HUD 浮层出现"
else
  echo "    HUD 未开启，跳过"
fi

echo "==> 日志"
ERRORS="$(log show --last 60s --predicate "subsystem == \"$BUNDLE_ID\"" --style compact 2>/dev/null | grep -E "error|failed" | grep -v "tap create failed, falling back" || true)"
[[ -z "$ERRORS" ]] || { echo "$ERRORS" | head -5; fail "日志里有错误"; }
ok "日志无错误"

echo "==> 性能（鼠标持续移动 2 秒）"
( "$TOOL_DIR/move" 300 >/dev/null 2>&1 & )
sleep 1
PEAK=0
for _ in 1 2 3; do
  CPU="$(ps -o %cpu= -p "$PID" | tr -d ' ')"
  CPU_INT="${CPU%%.*}"
  [[ -z "$CPU_INT" ]] && CPU_INT=0
  (( CPU_INT > PEAK )) && PEAK=$CPU_INT
  sleep 0.6
done
echo "    峰值 CPU ${PEAK}%（阈值 ${CPU_LIMIT}%）"
(( PEAK <= CPU_LIMIT )) || fail "鼠标移动时 CPU 过高：${PEAK}%"
ok "性能在阈值内"

echo
ok "冒烟全部通过（版本 $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") / $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")）"
