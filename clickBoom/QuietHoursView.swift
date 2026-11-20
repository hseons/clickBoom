import SwiftUI

/// 免打扰时段的编辑控件：控制面板「系统」区和状态弹窗共用同一份实现。
struct QuietHoursControls: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("免打扰时段", isOn: $state.quietHoursEnabled)
                .toggleStyle(.switch)
                .tint(.green)

            Text("每天在设定时段内自动暂停点击特效和拖尾，适合会议、夜间录屏；跨零点按一段处理")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if state.quietHoursEnabled {
                HStack(spacing: 14) {
                    timePicker("开始", minutes: $state.quietHoursStartMinutes)
                    timePicker("结束", minutes: $state.quietHoursEndMinutes)
                }

                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(state.quietHours.isConfigured
                                     ? .white.opacity(0.55) : .orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summary: String {
        let quietHours = state.quietHours
        guard quietHours.isConfigured else {
            return "起止时间相同不会静默；改成不同时间才会生效。"
        }
        let active = quietHours.isActive(at: Date())
        return "当前规则：\(quietHours.rangeLabel)\(active ? "（生效中）" : "")"
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
