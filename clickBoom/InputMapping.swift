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
