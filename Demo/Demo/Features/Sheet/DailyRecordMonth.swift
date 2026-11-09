import Foundation

/// 公历月份快照；按设备时区确定今天，周一固定为日历首列。
struct DailyRecordMonth {
    let calendar: Calendar
    let today: Date
    let dates: [Date]
    let leadingEmptyDays: Int

    init(now: Date = Date(), timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let dayRange = calendar.range(of: .day, in: .month, for: now)!
        dates = dayRange.map { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
        }
        // Calendar 的星期日为 1，星期一为 2。
        leadingEmptyDays = (calendar.component(.weekday, from: monthStart) + 5) % 7
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: today)
    }

    /// 日期下方显示农历；初一显示月份，其余日期显示日名。
    func lunarText(for date: Date) -> String {
        var lunarCalendar = Calendar(identifier: .chinese)
        lunarCalendar.timeZone = calendar.timeZone
        let components = lunarCalendar.dateComponents(in: calendar.timeZone, from: date)
        let day = components.day!
        if day == 1 {
            let months = ["正月", "二月", "三月", "四月", "五月", "六月",
                          "七月", "八月", "九月", "十月", "冬月", "腊月"]
            return (components.isLeapMonth == true ? "闰" : "") + months[components.month! - 1]
        }
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        switch day {
        case 2...10: return "初" + digits[day - 1]
        case 11...19: return "十" + digits[day - 11]
        case 20: return "二十"
        case 21...29: return "廿" + digits[day - 21]
        default: return "三十"
        }
    }
}
