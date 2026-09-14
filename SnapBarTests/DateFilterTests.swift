import XCTest
@testable import SnapBar

final class DateFilterTests: XCTestCase {
    private let cal = TestCal.calendar
    private let now = TestCal.now

    private func check(_ filter: DateFilter, _ date: Date) -> Bool {
        filter.contains(date, now: now, calendar: cal)
    }

    func testAll() {
        XCTAssertTrue(check(.all, TestCal.date(2001, 1, 1)))
    }

    func testToday() {
        XCTAssertTrue(check(.today, TestCal.date(2026, 9, 10, 0, 1)))
        XCTAssertFalse(check(.today, TestCal.date(2026, 9, 9, 23, 59)))
    }

    func testYesterday() {
        XCTAssertTrue(check(.yesterday, TestCal.date(2026, 9, 9, 8)))
        XCTAssertFalse(check(.yesterday, TestCal.date(2026, 9, 10, 8)))
        XCTAssertFalse(check(.yesterday, TestCal.date(2026, 9, 8, 23)))
    }

    func testLast7DaysIncludesToday() {
        XCTAssertTrue(check(.last7Days, TestCal.date(2026, 9, 4, 0, 5)))
        XCTAssertTrue(check(.last7Days, TestCal.date(2026, 9, 10, 14)))
        XCTAssertFalse(check(.last7Days, TestCal.date(2026, 9, 3, 23)))
    }

    func testLast30Days() {
        XCTAssertTrue(check(.last30Days, TestCal.date(2026, 8, 12, 0, 5)))
        XCTAssertFalse(check(.last30Days, TestCal.date(2026, 8, 11, 23)))
    }

    func testThisMonth() {
        XCTAssertTrue(check(.thisMonth, TestCal.date(2026, 9, 1, 0, 5)))
        XCTAssertFalse(check(.thisMonth, TestCal.date(2026, 8, 31, 23)))
    }

    func testCustomRangeIncludesBothEndDays() {
        let range = DateFilter.custom(from: TestCal.date(2026, 9, 1), to: TestCal.date(2026, 9, 5))
        XCTAssertTrue(check(range, TestCal.date(2026, 9, 1, 0, 1)))
        XCTAssertTrue(check(range, TestCal.date(2026, 9, 5, 23, 59)))
        XCTAssertFalse(check(range, TestCal.date(2026, 9, 6, 0, 1)))
        XCTAssertFalse(check(range, TestCal.date(2026, 8, 31, 23)))
        let reversed = DateFilter.custom(from: TestCal.date(2026, 9, 5), to: TestCal.date(2026, 9, 1))
        XCTAssertTrue(check(reversed, TestCal.date(2026, 9, 3)))
    }
}
