import XCTest
@testable import ClickBoom

final class QuietHoursTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute
        ))!
    }

    func testDisabledOrUnconfiguredNeverMatches() {
        XCTAssertFalse(QuietHours(isEnabled: false, startMinutes: 22 * 60, endMinutes: 8 * 60)
            .isActive(at: date(23, 30), calendar: calendar))
        XCTAssertFalse(QuietHours(isEnabled: true, startMinutes: 9 * 60, endMinutes: 9 * 60)
            .isActive(at: date(9, 0), calendar: calendar))
        XCTAssertNil(QuietHours(isEnabled: true, startMinutes: 600, endMinutes: 600)
            .nextBoundary(after: date(9, 0), calendar: calendar))
    }

    func testSameDayRangeIncludesStartAndExcludesEnd() {
        let quiet = QuietHours(isEnabled: true, startMinutes: 9 * 60 + 30, endMinutes: 11 * 60)
        XCTAssertFalse(quiet.isActive(at: date(9, 29), calendar: calendar))
        XCTAssertTrue(quiet.isActive(at: date(9, 30), calendar: calendar))
        XCTAssertTrue(quiet.isActive(at: date(10, 59), calendar: calendar))
        XCTAssertFalse(quiet.isActive(at: date(11, 0), calendar: calendar))
        XCTAssertFalse(quiet.crossesMidnight)
        XCTAssertEqual(quiet.rangeLabel, "09:30 – 11:00")
    }

    func testOvernightRangeWrapsAcrossMidnight() {
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)
        XCTAssertTrue(quiet.isActive(at: date(22, 0), calendar: calendar))
        XCTAssertTrue(quiet.isActive(at: date(23, 59), calendar: calendar))
        XCTAssertTrue(quiet.isActive(at: date(0, 0, day: 21), calendar: calendar))
        XCTAssertTrue(quiet.isActive(at: date(7, 59, day: 21), calendar: calendar))
        XCTAssertFalse(quiet.isActive(at: date(8, 0, day: 21), calendar: calendar))
        XCTAssertFalse(quiet.isActive(at: date(21, 59), calendar: calendar))
        XCTAssertTrue(quiet.crossesMidnight)
        XCTAssertEqual(quiet.rangeLabel, "22:00 – 次日 08:00")
    }

    func testNextBoundaryPicksTheNearestStartOrEnd() {
        let quiet = QuietHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)
        // 白天：下一次是当天 22:00。
        XCTAssertEqual(
            quiet.nextBoundary(after: date(12, 0), calendar: calendar),
            date(22, 0)
        )
        // 静默中：下一次是次日 08:00。
        XCTAssertEqual(
            quiet.nextBoundary(after: date(23, 10), calendar: calendar),
            date(8, 0, day: 21)
        )
        // 刚过结束点：下一次是当天 22:00。
        XCTAssertEqual(
            quiet.nextBoundary(after: date(8, 1, day: 21), calendar: calendar),
            date(22, 0, day: 21)
        )
    }

    func testNextBoundaryHandlesSameDayRanges() {
        let quiet = QuietHours(isEnabled: true, startMinutes: 9 * 60, endMinutes: 11 * 60)
        XCTAssertEqual(quiet.nextBoundary(after: date(8, 0), calendar: calendar), date(9, 0))
        XCTAssertEqual(quiet.nextBoundary(after: date(10, 0), calendar: calendar), date(11, 0))
        XCTAssertEqual(quiet.nextBoundary(after: date(12, 0), calendar: calendar), date(9, 0, day: 21))
    }

    func testMinutesAreClampedAndFormatted() {
        let quiet = QuietHours(isEnabled: true, startMinutes: -90, endMinutes: 5000)
        XCTAssertEqual(quiet.startMinutes, 0)
        XCTAssertEqual(quiet.endMinutes, 23 * 60 + 59)
        XCTAssertEqual(QuietHours.timeLabel(0), "00:00")
        XCTAssertEqual(QuietHours.timeLabel(8 * 60 + 5), "08:05")
        XCTAssertEqual(QuietHours.timeLabel(23 * 60 + 59), "23:59")
        XCTAssertEqual(QuietHours.minuteOfDay(date(7, 45), calendar: calendar), 7 * 60 + 45)
    }

    // MARK: - 星期掩码

    func testWeekdayMaskUsesStartDayAcrossMidnight() {
        // 2026-11-20 是周五；工作日规则下，周五 22:00 到周六 08:00 算周五这一段。
        let weekdays = QuietHours(
            isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60,
            weekdayMask: QuietHours.weekdaysMask
        )
        XCTAssertTrue(weekdays.isActive(at: date(22, 30, day: 20), calendar: calendar))
        XCTAssertTrue(weekdays.isActive(at: date(2, 0, day: 21), calendar: calendar))
        XCTAssertFalse(weekdays.isActive(at: date(22, 30, day: 21), calendar: calendar))
        XCTAssertFalse(weekdays.isActive(at: date(2, 0, day: 22), calendar: calendar))
        XCTAssertTrue(weekdays.isActive(at: date(22, 30, day: 23), calendar: calendar))
    }

    func testSameDayRangeRespectsWeekdayMask() {
        let weekend = QuietHours(
            isEnabled: true, startMinutes: 9 * 60, endMinutes: 11 * 60,
            weekdayMask: QuietHours.weekendMask
        )
        XCTAssertFalse(weekend.isActive(at: date(10, 0, day: 20), calendar: calendar))
        XCTAssertTrue(weekend.isActive(at: date(10, 0, day: 21), calendar: calendar))
        XCTAssertTrue(weekend.isActive(at: date(10, 0, day: 22), calendar: calendar))
    }

    func testNextBoundarySkipsUnselectedDays() {
        let weekdays = QuietHours(
            isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60,
            weekdayMask: QuietHours.weekdaysMask
        )
        // 周五深夜：结束点是周六 08:00，之后要等到周一 22:00。
        XCTAssertEqual(
            weekdays.nextBoundary(after: date(23, 0, day: 20), calendar: calendar),
            date(8, 0, day: 21)
        )
        XCTAssertEqual(
            weekdays.nextBoundary(after: date(9, 0, day: 21), calendar: calendar),
            date(22, 0, day: 23)
        )

        let weekdayDaytime = QuietHours(
            isEnabled: true, startMinutes: 9 * 60, endMinutes: 11 * 60,
            weekdayMask: QuietHours.weekdaysMask
        )
        XCTAssertEqual(
            weekdayDaytime.nextBoundary(after: date(12, 0, day: 20), calendar: calendar),
            date(9, 0, day: 23)
        )
    }

    func testEmptyWeekdayMaskIsNotConfigured() {
        let quiet = QuietHours(
            isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60, weekdayMask: 0
        )
        XCTAssertFalse(quiet.isConfigured)
        XCTAssertFalse(quiet.isActive(at: date(23, 0), calendar: calendar))
        XCTAssertNil(quiet.nextBoundary(after: date(12, 0), calendar: calendar))
        XCTAssertEqual(quiet.weekdayLabel, "未选日子")
    }

    func testWeekdayLabelsAndScheduleLabel() {
        XCTAssertEqual(QuietHours(weekdayMask: QuietHours.everyDayMask).weekdayLabel, "每天")
        XCTAssertEqual(QuietHours(weekdayMask: QuietHours.weekdaysMask).weekdayLabel, "工作日")
        XCTAssertEqual(QuietHours(weekdayMask: QuietHours.weekendMask).weekdayLabel, "周末")
        XCTAssertEqual(
            QuietHours(weekdayMask: QuietWeekday.monday.bit | QuietWeekday.wednesday.bit).weekdayLabel,
            "周一、周三"
        )
        XCTAssertEqual(
            QuietHours(
                isEnabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60,
                weekdayMask: QuietHours.weekdaysMask
            ).scheduleLabel,
            "工作日 22:00 – 次日 08:00"
        )
    }

    func testQuietWeekdayBitsMatchCalendar() {
        XCTAssertEqual(QuietWeekday.bit(forCalendarWeekday: 2), QuietWeekday.monday.bit)
        XCTAssertEqual(QuietWeekday.bit(forCalendarWeekday: 7), QuietWeekday.saturday.bit)
        XCTAssertEqual(QuietWeekday.bit(forCalendarWeekday: 1), QuietWeekday.sunday.bit)
        // 全选掩码要正好铺满七天，不能再多出高位。
        XCTAssertEqual(QuietWeekday.allCases.reduce(0) { $0 | $1.bit }, QuietHours.everyDayMask)
    }
}
