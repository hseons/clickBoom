import AppKit
import Combine

/// 记住最近一个非 ClickBoom 的前台 App。
///
/// 菜单栏面板一打开，前台 App 就变成 ClickBoom 自己了，
/// 所以只能在别的 App 被激活时先把它记下来，供「一键排除当前 App」使用。
@MainActor
final class FrontmostAppTracker: ObservableObject {
    static let shared = FrontmostAppTracker()

    @Published private(set) var lastActiveApp: ExcludedApp?

    private var observer: NSObjectProtocol?

    private init() {
        refreshFromFrontmost()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                FrontmostAppTracker.shared.record(notification)
            }
        }
    }

    /// 面板打开或 App 启动时主动同步一次，补上通知没覆盖到的场景。
    func refreshFromFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        remember(app)
    }

    private func record(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        remember(app)
    }

    private func remember(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !app.isTerminated else {
            return
        }
        lastActiveApp = ExcludedApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
