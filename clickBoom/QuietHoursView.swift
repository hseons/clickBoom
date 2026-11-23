import SwiftUI

/// 免打扰时段的编辑控件：控制面板「系统」区和状态弹窗共用同一份实现。
struct QuietHoursControls: View {
    @ObservedObject var state: AppState

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("免打扰时段", isOn: ruleBinding($state.quietHoursEnabled))
                .toggleStyle(.switch)
                .tint(.green)

            Text("在设定时段内自动暂停点击特效和拖尾，适合会议、夜间录屏；跨零点按一段处理，凌晨算作起点那天的时段")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if state.quietHoursEnabled {
                HStack(spacing: 14) {
                    timePicker("开始", minutes: ruleBinding($state.quietHoursStartMinutes))
                    timePicker("结束", minutes: ruleBinding($state.quietHoursEndMinutes))
                }

                weekdayRow

                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(state.quietHours.isConfigured
                                     ? .white.opacity(0.55) : .orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if state.quietHours.isConfigured, state.quietHours.isActive(at: Date()) {
                    if state.isQuietHoursSkipped(at: Date()) {
                        Label("本次已跳过，\(boundaryText) 恢复静默", systemImage: "moon.zzz")
                            .font(.system(size: 11))
                            .foregroundColor(.orange.opacity(0.9))
                    } else {
                        Button {
                            RuntimeController.shared.skipQuietHoursOnce()
                        } label: {
                            Label("本次跳过", systemImage: "forward.end")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("只在这一次时段放行，规则不变；到 \(boundaryText) 后继续静默")
                    }
                }
            }
        }
    }

    /// 星期几：点一下切换；右侧菜单给「每天 / 工作日 / 周末」三个常用组合。
    private var weekdayRow: some View {
        HStack(spacing: 5) {
            ForEach(QuietWeekday.allCases) { day in
                let selected = state.quietHoursWeekdayMask & day.bit != 0
                Button {
                    state.quietHoursWeekdayMask ^= day.bit
                    state.clearQuietHoursSkip()
                } label: {
                    Text(day.shortTitle)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? Color.accentColor.opacity(0.85)
                                      : Color.white.opacity(0.08))
                        )
                        .foregroundColor(selected ? .white : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(day.fullTitle)
                .accessibilityLabel(day.fullTitle)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Menu {
                Button("每天") { setMask(QuietHours.everyDayMask) }
                Button("工作日") { setMask(QuietHours.weekdaysMask) }
                Button("周末") { setMask(QuietHours.weekendMask) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("常用组合：每天、工作日、周末")
            .accessibilityLabel("常用星期组合")
        }
    }

    private var summary: String {
        let quietHours = state.quietHours
        guard quietHours.isConfigured else {
            return quietHours.weekdayMask == 0
                ? "至少要选一天才会生效。"
                : "起止时间相同不会静默；改成不同时间才会生效。"
        }
        let active = quietHours.isActive(at: Date())
        let skipped = state.isQuietHoursSkipped(at: Date())
        return "当前规则：\(quietHours.scheduleLabel)\(active ? (skipped ? "（本次已跳过）" : "（生效中）") : "")"
    }

    private var boundaryText: String {
        guard let boundary = state.quietHours.nextBoundary(after: Date()) else { return "下一个边界" }
        return Self.clock.string(from: boundary)
    }

    private func setMask(_ mask: Int) {
        state.quietHoursWeekdayMask = mask
        state.clearQuietHoursSkip()
    }

    /// 任何规则改动都让旧的「本次跳过」失效，避免新规则被旧截止时间压住。
    private func ruleBinding<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                state.clearQuietHoursSkip()
            }
        )
    }

    private func timePicker(_ title: String, minutes: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
            DatePicker("", selection: dateBinding(minutes), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
                .frame(width: 104)
        }
    }

    /// UserDefaults 存「当天第几分钟」，DatePicker 用当天日期承载时分。
    private func dateBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let minuteOfDay = min(max(minutes.wrappedValue, 0), 23 * 60 + 59)
                return calendar.date(
                    bySettingHour: minuteOfDay / 60,
                    minute: minuteOfDay % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}
