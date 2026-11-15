import AppKit
import CoreGraphics

/// 全屏判定里可以单独测试的几何部分：窗口是否完整盖住某块屏幕。
enum FullScreenLogic {
    /// 窗口边缘和屏幕边缘允许 1pt 的误差（不同缩放比例下偶尔会差一点）。
    nonisolated static let tolerance: CGFloat = 1

    nonisolated static func isCoveringScreen(windowFrame: CGRect, screenFrame: CGRect) -> Bool {
        guard screenFrame.width > 0, screenFrame.height > 0,
              windowFrame.width > 0, windowFrame.height > 0 else {
            return false
        }
        return windowFrame.minX <= screenFrame.minX + tolerance
            && windowFrame.minY <= screenFrame.minY + tolerance
            && windowFrame.maxX >= screenFrame.maxX - tolerance
            && windowFrame.maxY >= screenFrame.maxY - tolerance
    }

    nonisolated static func isCoveringAnyScreen(windowFrame: CGRect, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { isCoveringScreen(windowFrame: windowFrame, screenFrame: $0) }
    }

    /// CGWindowList 的 bounds 以主屏左上角为原点（y 向下），
    /// NSScreen.frame 以主屏左下角为原点（y 向上），这里做一次翻转。
    nonisolated static func appKitFrame(
        fromCGWindowBounds bounds: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: primaryScreenHeight - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }
}

/// 判断前台 App 是否全屏，供「全屏时自动静默」使用。
///
/// 只用 CGWindowList 的窗口位置，不需要辅助功能或录屏权限。
/// 鼠标事件很密集，结果缓存 0.5 秒，避免每个事件都扫一遍窗口列表。
@MainActor
final class FullScreenDetector {
    static let shared = FullScreenDetector()

    private let cacheInterval: TimeInterval = 0.5
    private var cachedResult = false
    private var cachedAt = Date.distantPast

    func isFrontmostAppFullScreen(forceRefresh: Bool = false) -> Bool {
        let now = Date()
        if !forceRefresh, now.timeIntervalSince(cachedAt) < cacheInterval {
            return cachedResult
        }
        cachedAt = now
        cachedResult = queryFrontmostAppFullScreen()
        return cachedResult
    }

    private func queryFrontmostAppFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return false
        }

        let screenFrames = NSScreen.screens.map(\.frame)
        let pid = app.processIdentifier

        for info in windows {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let x = (boundsDict["X"] as? NSNumber)?.doubleValue,
                  let y = (boundsDict["Y"] as? NSNumber)?.doubleValue,
                  let width = (boundsDict["Width"] as? NSNumber)?.doubleValue,
                  let height = (boundsDict["Height"] as? NSNumber)?.doubleValue else {
                continue
            }

            let cgFrame = CGRect(x: x, y: y, width: width, height: height)
            let appKitFrame = FullScreenLogic.appKitFrame(
                fromCGWindowBounds: cgFrame,
                primaryScreenHeight: primaryHeight
            )
            if FullScreenLogic.isCoveringAnyScreen(windowFrame: appKitFrame, screenFrames: screenFrames) {
                return true
            }
        }
        return false
    }
}
