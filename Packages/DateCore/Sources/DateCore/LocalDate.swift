import Foundation

/// 시간대 없는 날짜. 서버 `date` 컬럼과 같은 "yyyy-MM-dd" 문자열로 주고받는다.
public struct LocalDate: Codable, Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, s.count == 10 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "날짜 형식 오류: \(s)"))
        }
        self.init(year: p[0], month: p[1], day: p[2])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }

    // 1970-01-01부터 센 일수(Hinnant civil 알고리즘). Calendar·시간대 없이 날짜 산수를 한다
    var epochDays: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    init(epochDays z0: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: doy - (153 * mp + 2) / 5 + 1)
    }

    public func adding(days: Int) -> LocalDate { LocalDate(epochDays: epochDays + days) }

    public static func today(in calendar: Calendar, now: Date = Date()) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    public func date(hour: Int, minute: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

/// 시각. 서버 `time`은 "HH:mm:ss"로 오지만 "HH:mm"도 받는다.
public struct LocalTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "시각 형식 오류: \(s)"))
        }
        self.init(hour: p[0], minute: p[1])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%02d:%02d:00", hour, minute))
    }
}
