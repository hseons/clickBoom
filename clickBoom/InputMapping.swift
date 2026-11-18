import Foundation

enum PointerInputKind {
    case leftDown
    case rightDown
    case otherDown
    case mouseMoved
    case leftDrag
    case rightDrag
    case otherDrag
}

enum ClickTriggerMode: String, CaseIterable, Identifiable {
    case singleClick
    case doubleClick
    case longPress

    var id: Self { self }

    var title: String {
        switch self {
        case .singleClick: return "单击"
        case .doubleClick: return "双击"
        case .longPress: return "长按"
        }
    }
}

struct ClickInput {
    enum Phase {
        case down
        case dragged
        case up
    }

    let phase: Phase
    let kind: PointerInputKind
    let buttonNumber: Int
    let clickCount: Int
    let timestamp: TimeInterval
    let location: CGPoint
}

/// 手势只决定是否显示点击特效，实际系统点击/拖拽照常传给前台 App。
struct ClickGesture {
    private struct Press {
        let timestamp: TimeInterval
        let origin: CGPoint

        func movedTooFar(to point: CGPoint) -> Bool {
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            return dx * dx + dy * dy >= 6 * 6
        }
    }

    private var presses: [Int: Press] = [:]

    mutating func reset() {
        presses.removeAll()
    }

    mutating func receive(
        _ input: ClickInput,
        mode: ClickTriggerMode,
        rightClickEnabled: Bool
    ) -> MouseButtonKind? {
        guard InputMapping.supports(input.kind, rightClickEnabled: rightClickEnabled) else { return nil }
        let button = InputMapping.buttonKind(for: input.kind)

        switch mode {
        case .singleClick:
            return input.phase == .down ? button : nil
        case .doubleClick:
            return input.phase == .down && input.clickCount == 2 ? button : nil
        case .longPress:
            switch input.phase {
            case .down:
                presses[input.buttonNumber] = Press(timestamp: input.timestamp, origin: input.location)
            case .dragged, .up:
                guard let press = presses[input.buttonNumber], input.timestamp >= press.timestamp else { return nil }
                let movedTooFar = press.movedTooFar(to: input.location)
                if input.phase == .up || movedTooFar {
                    presses.removeValue(forKey: input.buttonNumber)
                }
                if input.phase == .up, !movedTooFar, input.timestamp - press.timestamp >= 0.5 {
                    return button
                }
            }
            return nil
        }
    }
}

/// 鼠标事件到行为规则的纯映射，避免按钮判断和拖尾触发条件散落在监听器里。
enum InputMapping {
    static func supports(
        _ kind: PointerInputKind,
        rightClickEnabled: Bool
    ) -> Bool {
        switch kind {
        case .rightDown, .otherDown:
            return rightClickEnabled
        default:
            return true
        }
    }

    static func buttonKind(for kind: PointerInputKind) -> MouseButtonKind {
        switch kind {
        case .rightDown:
            return .right
        case .otherDown:
            return .middle
        default:
            return .left
        }
    }

    static func shouldExtendTrail(
        for kind: PointerInputKind,
        triggerMode: TrailTriggerMode,
        optionPressed: Bool,
        commandPressed: Bool,
        trailEnabled: Bool,
        rightClickEnabled: Bool
    ) -> Bool {
        guard trailEnabled else { return false }

        if (kind == .rightDrag || kind == .otherDrag) && !rightClickEnabled {
            return false
        }

        switch triggerMode {
        case .always:
            return true
        case .dragging:
            return kind != .mouseMoved
        case .optionKey:
            return optionPressed
        case .commandKey:
            return commandPressed
        }
    }
}
