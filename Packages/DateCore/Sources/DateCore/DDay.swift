public struct Milestone: Equatable, Sendable {
    public var title: String
    public var date: LocalDate
    public var daysLeft: Int
}

public enum DDay {
    /// 사귄 첫날이 1일이다. 시작 전이면 0 이하
    public static func dayNumber(start: LocalDate, today: LocalDate) -> Int {
        today.epochDays - start.epochDays + 1
    }

    /// 앞으로의 기념일을 날짜순으로 `limit`개. 같은 날이면 100일 단위 → N주년 → 생일 → 사용자 기념일 순
    public static func upcoming(start: LocalDate?, members: [Member], custom: [Anniversary],
                                today: LocalDate, limit: Int) -> [Milestone] {
        var all: [Milestone] = []
        func add(_ title: String, _ date: LocalDate) {
            all.append(Milestone(title: title, date: date, daysLeft: date.epochDays - today.epochDays))
        }
        if let start {
            for n in 1...100 where start.adding(days: n * 100 - 1) >= today {
                add("\(n * 100)일", start.adding(days: n * 100 - 1))
            }
            for n in 1...50 {
                let d = sameDay(of: start, inYear: start.year + n)
                if d >= today { add("\(n)주년", d) }
            }
        }
        for m in members {
            if let b = m.birthday { add("\(m.nickname) 생일", nextYearly(b, from: today)) }
        }
        for a in custom {
            if a.repeatsYearly { add(a.title, nextYearly(a.date, from: today)) }
            else if a.date >= today { add(a.title, a.date) }
        }
        // 정렬이 안정적이지 않을 수 있어 입력 순서를 보조 키로 쓴다
        let sorted = all.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
        return sorted.prefix(limit).map(\.element)
    }

    // 2월 29일은 평년에 2월 28일로 센다
    private static func sameDay(of d: LocalDate, inYear y: Int) -> LocalDate {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        return LocalDate(year: y, month: d.month, day: d.month == 2 && d.day == 29 && !leap ? 28 : d.day)
    }

    private static func nextYearly(_ d: LocalDate, from today: LocalDate) -> LocalDate {
        let this = sameDay(of: d, inYear: today.year)
        return this >= today ? this : sameDay(of: d, inYear: today.year + 1)
    }
}
