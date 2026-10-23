import Foundation
import Testing
@testable import DateCore

@Test func localDateRoundTripAndAdding() throws {
    let d = try JSONDecoder().decode(LocalDate.self, from: Data("\"2026-02-28\"".utf8))
    #expect(d == LocalDate(year: 2026, month: 2, day: 28))
    let next = d.adding(days: 1)
    #expect(String(data: try JSONEncoder().encode(next), encoding: .utf8) == "\"2026-03-01\"")
    #expect(next.adding(days: -1) == d)
}

@Test func localTimeAcceptsBothFormats() throws {
    let a = try JSONDecoder().decode(LocalTime.self, from: Data("\"08:30:00\"".utf8))
    let b = try JSONDecoder().decode(LocalTime.self, from: Data("\"08:30\"".utf8))
    #expect(a == b)
    #expect(String(data: try JSONEncoder().encode(a), encoding: .utf8) == "\"08:30:00\"")
}

@Test func eventDecodesPostgrestFormat() throws {
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111","couple_id":"22222222-2222-2222-2222-222222222222",
     "owner_kind":"member","owner_member_id":"33333333-3333-3333-3333-333333333333",
     "created_by_member_id":null,"shift_type_id":null,"title":"회의","day":"2026-10-21","end_day":null,
     "all_day":false,"start_time":"08:30:00","end_time":"17:00:00","memo":null,
     "updated_at":"2026-10-21T07:54:00.123456+00:00"}
    """
    let e = try JSONDecoder().decode(Event.self, from: Data(json.utf8))
    #expect(e.ownerKind == .member)
    #expect(e.startTime == LocalTime(hour: 8, minute: 30))
    #expect(e.day == LocalDate(year: 2026, month: 10, day: 21))
    #expect(abs(e.updatedAt.timeIntervalSince1970 - 1792569240.123) < 0.01)
    // 소수초가 없는 형식도 받는다
    let plain = json.replacingOccurrences(of: ".123456", with: "")
    #expect(try JSONDecoder().decode(Event.self, from: Data(plain.utf8)).updatedAt.timeIntervalSince1970 == 1792569240)
}
