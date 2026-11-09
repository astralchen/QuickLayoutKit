import Foundation
import Testing
@testable import Demo

struct DailyRecordMonthTests {
    @Test func monthLengthsAndMondayOffsets() {
        let cases = [(2024, 2, 29, 3), (2025, 2, 28, 5), (2026, 11, 30, 6), (2026, 12, 31, 1)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        for (year, month, count, offset) in cases {
            let now = calendar.date(from: DateComponents(year: year, month: month, day: 9, hour: 12))!
            let snapshot = DailyRecordMonth(now: now, timeZone: calendar.timeZone)
            #expect(snapshot.dates.count == count)
            #expect(snapshot.leadingEmptyDays == offset)
            #expect(snapshot.dates.filter(snapshot.isToday).count == 1)
            #expect(snapshot.isToday(snapshot.dates[8]))
            #expect(calendar.component(.day, from: snapshot.dates.last!) == count)
        }
    }

    @Test func todayUsesLocalDateAcrossYearBoundary() {
        let instant = ISO8601DateFormatter().date(from: "2026-12-31T16:30:00Z")!
        let shanghai = DailyRecordMonth(now: instant, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        let utc = DailyRecordMonth(now: instant, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(shanghai.calendar.component(.year, from: shanghai.today) == 2027)
        #expect(shanghai.calendar.component(.month, from: shanghai.today) == 1)
        #expect(shanghai.isToday(shanghai.dates[0]))
        #expect(utc.calendar.component(.month, from: utc.today) == 12)
        #expect(utc.isToday(utc.dates[30]))
        let yesterday = shanghai.calendar.date(byAdding: .day, value: -1, to: shanghai.today)!
        #expect(!shanghai.isToday(yesterday))
        let nextMonth = shanghai.calendar.date(byAdding: .month, value: 1, to: shanghai.today)!
        #expect(!shanghai.isToday(nextMonth))
    }

    @Test func lunarSubtitlesMatchMonthBoundaryAndDayNames() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshot = DailyRecordMonth(now: now, timeZone: calendar.timeZone)
        for (day, expected) in [(1, "廿三"), (8, "三十"), (9, "十月"), (10, "初二"),
                                (18, "初十"), (19, "十一"), (28, "二十"), (29, "廿一")] {
            #expect(snapshot.lunarText(for: snapshot.dates[day - 1]) == expected)
        }
        let leapMonthStart = calendar.date(from: DateComponents(year: 2025, month: 7, day: 25, hour: 12))!
        #expect(snapshot.lunarText(for: leapMonthStart) == "闰六月")
    }

}
