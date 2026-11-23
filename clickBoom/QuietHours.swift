import Foundation

/// 免打扰时段里的一天。用固定的「周一 = 0 … 周日 = 6」作为掩码位，
/// 和 `Calendar` 的 `weekday`（周日 = 1）分开，避免两套序号在界面和测试里混用。
nonisolated enum QuietWeekday: Int, CaseIterable, Identifiable {
    case monday = 0
    case tuesday = 1
    case wednesday = 2
    case thursday = 3
    case friday = 4
    case saturday = 5
    case sunday = 6

    var id: Int { rawValue }

    var bit: Int { 1 << rawValue }

    /// 界面上的短标签：一、二 … 日
    var shortTitle: String {
        ["一", "二", "三", "四", "五", "六", "日"][rawValue]
    }

    var fullTitle: String { "周" + shortTitle }

    /// Calendar 的 weekday（1 = 周日）换算成掩码位。
    static func bit(forCalendarWeekday weekday: Int) -> Int {
        1 << ((weekday + 5) % 7)
    }
}

/// 「免打扰时段」：每周选定日子的固定起止分钟，命中时自动暂停全局特效。
///
/// 判断保持纯函数，面板、菜单栏、运行时和测试读同一份规则；
/// 跨零点的时段（例如 22:00 – 08:00）与普通时段走同一个入口。
/// 跨零点时按「起点所在日」判断是否属于选中的日子：周一 22:00 – 周二 08:00
/// 只要求周一被选中，周二凌晨的这几个小时仍算周一的时段。
nonisolated struct QuietHours: Equatable {
    static let defaultStartMinutes = 22 * 60
    static let defaultEndMinutes = 8 * 60

    /// 周一至周日全选。
    static let everyDayMask = 0b111_1111
    /// 周一至周五。
    static let weekdaysMask = 0b001_1111
    /// 周六、周日。
    static let weekendMask = 0b110_0000

    var isEnabled: Bool
    /// 当天第几分钟：0 = 00:00，1439 = 23:59。
    var startMinutes: Int
    var endMinutes: Int
    /// 位掩码：bit 0 = 周一 … bit 6 = 周日。
    var weekdayMask: Int

    init(
        isEnabled: Bool = false,
        startMinutes: Int = QuietHours.defaultStartMinutes,
        endMinutes: Int = QuietHours.defaultEndMinutes,
        weekdayMask: Int = QuietHours.everyDayMask
    ) {
        self.isEnabled = isEnabled
        self.startMinutes = Self.clamped(startMinutes)
        self.endMinutes = Self.clamped(endMinutes)
        self.weekdayMask = weekdayMask & Self.everyDayMask
    }

    /// 起止相同无法表达「一整天」，按未配置处理，避免误判成全天静默；
    /// 一天都没选同样视为未配置，否则开关打开却永远不会静默。
    var isConfigured: Bool {
        isEnabled && startMinutes != endMinutes && weekdayMask != 0
    }

    var crossesMidnight: Bool { startMinutes > endMinutes }

    var rangeLabel: String {
        let start = Self.timeLabel(startMinutes)
        let end = Self.timeLabel(endMinutes)
        return crossesMidnight ? "\(start) – 次日 \(end)" : "\(start) – \(end)"
    }

    /// 选了哪些日子：整周 / 工作日 / 周末，或逐个列出。
    var weekdayLabel: String {
        if weekdayMask == Self.everyDayMask { return "每天" }
        if weekdayMask == Self.weekdaysMask { return "工作日" }
        if weekdayMask == Self.weekendMask { return "周末" }
        if weekdayMask == 0 { return "未选日子" }
        return QuietWeekday.allCases
            .filter { weekdayMask & $0.bit != 0 }
            .map(\.fullTitle)
            .joined(separator: "、")
    }

    /// 面板和运行状态共用的一句规则描述，例如「工作日 22:00 – 次日 08:00」。
    var scheduleLabel: String { "\(weekdayLabel) \(rangeLabel)" }

    /// 起点包含、终点不包含：22:00 开始静默，08:00 整点恢复。
    /// 跨零点时先找到「起点所在日」，再用那一天判断星期掩码。
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isConfigured else { return false }
        let minute = Self.minuteOfDay(date, calendar: calendar)
        let startDay: Date
        if startMinutes < endMinutes {
            guard minute >= startMinutes, minute < endMinutes else { return false }
            startDay = calendar.startOfDay(for: date)
        } else if minute >= startMinutes {
            startDay = calendar.startOfDay(for: date)
        } else if minute < endMinutes {
            guard let yesterday = calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.startOfDay(for: date)
            ) else {
                return false
            }
            startDay = yesterday
        } else {
            return false
        }
        let weekday = calendar.component(.weekday, from: startDay)
        return weekdayMask & QuietWeekday.bit(forCalendarWeekday: weekday) != 0
    }

    /// 下一次开始或结束的时刻，用来安排一次性的刷新计时器，平时不轮询。
    /// 只考虑被选中的日子；周末跳过时可能落到下周一。
    func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isConfigured else { return nil }
        let today = calendar.startOfDay(for: date)
        var candidates: [Date] = []
        // 昨天用来覆盖「当前仍在跨零点时段内」的结束点；往后多扫一周覆盖整周掩码。
        for dayOffset in -1...8 {
            guard let startDay = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: startDay)
            guard weekdayMask & QuietWeekday.bit(forCalendarWeekday: weekday) != 0 else {
                continue
            }
            if let start = calendar.date(byAdding: .minute, value: startMinutes, to: startDay),
               start > date {
                candidates.append(start)
            }
            let endDay = crossesMidnight
                ? calendar.date(byAdding: .day, value: 1, to: startDay)
                : startDay
            if let endDay,
               let end = calendar.date(byAdding: .minute, value: endMinutes, to: endDay),
               end > date {
                candidates.append(end)
            }
        }
        return candidates.min()
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
