import SwiftUI

/// 两个面板复用同一行状态与处理入口。
struct RuntimeStatusView: View {
    @ObservedObject private var runtime = RuntimeController.shared
    @ObservedObject private var state = AppState.shared
    @State private var showingDiagnostics = false
    @State private var showingSilenceSettings = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: runtime.status.icon)
                .foregroundStyle(runtime.status.isRunning ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let actionTitle {
                Button(actionTitle, action: resolveStatus)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .fixedSize()
                    .popover(isPresented: $showingSilenceSettings) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("全屏时自动静默", isOn: $state.autoSilenceInFullScreen)
                                .toggleStyle(.switch)
                            Text("开启后，前台应用全屏时暂停全局特效，退出全屏自动恢复。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            QuietHoursControls(state: state)
                        }
                        .padding(16)
                        .frame(width: 290)
                        .preferredColorScheme(.dark)
                    }
            }
            Button { showingDiagnostics = true } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .help("查看运行诊断")
            .accessibilityLabel("查看运行诊断")
        }
        .sheet(isPresented: $showingDiagnostics) { RuntimeDiagnosticsView() }
        .onAppear {
            InputPermission.shared.refresh()
            runtime.refresh(forceFullScreen: true)
        }
    }

    private var detail: String {
        switch runtime.status {
        case .disabled: return "打开总开关后恢复全局特效；预览仍可使用。"
        case .permissionRequired: return "在系统设置中开启输入监控，授权后自动生效。"
        case .paused: return state.pauseRemainingText
        case .quietHours(let range): return "每天 \(range) 自动静默，结束时间到点恢复；预览仍可使用。"
        case .excluded: return "切换到其他应用时自动恢复；预览仍可使用。"
        case .fullScreen: return "退出全屏时自动恢复；预览仍可使用。"
        case .running:
            return runtime.targetApp.map { "作用应用：\($0.name)" } ?? "等待鼠标点击，可随时预览。"
        }
    }

    private var actionTitle: String? {
        switch runtime.status {
        case .disabled: return "开启"
        case .permissionRequired: return "去授权"
        case .paused: return "恢复"
        case .quietHours: return "免打扰设置"
        case .excluded: return "取消静默"
        case .fullScreen: return "静默设置"
        case .running: return nil
        }
    }

    private func resolveStatus() {
        switch runtime.status {
        case .disabled: state.isEnabled = true
        case .permissionRequired:
            InputPermission.shared.request()
            if !InputPermission.shared.isGranted { InputPermission.shared.openSettings() }
        case .paused: state.resume()
        case .excluded:
            if let app = runtime.targetApp { state.removeExcludedApp(app) }
        case .quietHours, .fullScreen: showingSilenceSettings = true
        case .running: break
        }
        runtime.refresh(forceFullScreen: true)
    }
}

struct RuntimeDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: RuntimeDiagnostics?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("运行诊断")
                .font(.headline)
            Text("只在打开和点击刷新时读取，不保存文件或上传。面板显示最近外部应用的状态；帧耗时为最近一段动画的绘制分位值，仅供排查。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let snapshot {
                VStack(spacing: 10) {
                    row("运行状态", snapshot.status)
                    row("输入监控", snapshot.permissionGranted ? "已授权" : "未授权")
                    row("作用应用", snapshot.appName)
                    row("应用标识", snapshot.bundleID)
                    row("免打扰时段", snapshot.quietHours)
                    row("显示器数量", "\(snapshot.screenCount)")
                    row("移动监听", snapshot.motionActive ? "监听中" : "已停止")
                    row("粒子数量", "\(snapshot.particleCount)")
                    row("轨迹点数", "\(snapshot.trailPointCount)")
                    row("性能档位", snapshot.performanceTier)
                    row("帧绘制耗时", snapshot.frameCost)
                    row("预算上限", snapshot.budgetLimits)
                }
                Text("读取时间：\(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("刷新") { refresh() }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
    }

    private func refresh() {
        snapshot = RuntimeController.shared.diagnostics()
    }
}
