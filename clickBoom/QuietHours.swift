import Foundation

/// 「免打扰时段」：每天固定的起止分钟，命中时自动暂停全局特效。
///
/// 判断保持纯函数，面板、菜单栏、运行时和测试读同一份规则；
/// 跨零点的时段（例如 22:00 – 08:00）与普通时段走同一个入口。
nonisolated struct QuietHours: Equatable {
    static let defaultStartMinutes = 22 * 60
    static let defaultEndMinutes = 8 * 60

    var isEnabled: Bool
    /// 当天第几分钟：0 = 00:00，1439 = 23:59。
    var startMinutes: Int
    var endMinutes: Int

    init(
        isEnabled: Bool = false,
        startMinutes: Int = QuietHours.defaultStartMinutes,
        endMinutes: Int = QuietHours.defaultEndMinutes
    ) {
        self.isEnabled = isEnabled
        self.startMinutes = Self.clamped(startMinutes)
        self.endMinutes = Self.clamped(endMinutes)
    }

    /// 起止相同无法表达「一整天」，按未配置处理，避免误判成全天静默。
    var isConfigured: Bool { isEnabled && startMinutes != endMinutes }

    var crossesMidnight: Bool { startMinutes > endMinutes }

    var rangeLabel: String {
        let start = Self.timeLabel(startMinutes)
        let end = Self.timeLabel(endMinutes)
        return crossesMidnight ? "\(start) – 次日 \(end)" : "\(start) – \(end)"
    }

    /// 起点包含、终点不包含：22:00 开始静默，08:00 整点恢复。
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isConfigured else { return false }
        let minute = Self.minuteOfDay(date, calendar: calendar)
        if startMinutes < endMinutes {
            return minute >= startMinutes && minute < endMinutes
        }
        return minute >= startMinutes || minute < endMinutes
    }

    /// 下一次开始或结束的时刻，用来安排一次性的刷新计时器，平时不轮询。
    func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isConfigured else { return nil }
        let today = calendar.startOfDay(for: date)
        var candidates: [Date] = []
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            for minutes in [startMinutes, endMinutes] {
                if let boundary = calendar.date(byAdding: .minute, value: minutes, to: day) {
                    candidates.append(boundary)
                }
            }
        }
        return candidates.filter { $0 > date }.min()
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func timeLabel(_ minutes: Int) -> String {
        let value = clamped(minutes)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, 0), 23 * 60 + 59)
    }
}
