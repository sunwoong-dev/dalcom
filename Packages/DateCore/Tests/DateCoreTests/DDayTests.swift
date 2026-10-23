import Foundation
import Testing
@testable import DateCore

private let jieun = Member(id: UUID(), coupleId: UUID(), userId: UUID(), role: "owner",
                           nickname: "지은", birthday: d(1998, 5, 3), color: .pink)

@Test func dayNumber() {
    #expect(DDay.dayNumber(start: d(2026, 1, 1), today: d(2026, 1, 1)) == 1)
    #expect(DDay.dayNumber(start: d(2026, 1, 1), today: d(2026, 4, 10)) == 100)
    #expect(DDay.dayNumber(start: d(2026, 1, 1), today: d(2025, 12, 31)) == 0)
}

@Test func upcomingHundreds() {
    let r = DDay.upcoming(start: d(2026, 1, 1), members: [], custom: [], today: d(2026, 4, 1), limit: 2)
    #expect(r == [Milestone(title: "100일", date: d(2026, 4, 10), daysLeft: 9),
                  Milestone(title: "200일", date: d(2026, 7, 19), daysLeft: 109)])
}

@Test func upcomingAnniversaryBirthdayCustom() {
    let r = DDay.upcoming(start: d(2026, 1, 1), members: [], custom: [], today: d(2026, 12, 1), limit: 10)
    #expect(r.contains(Milestone(title: "1주년", date: d(2027, 1, 1), daysLeft: 31)))

    let b = DDay.upcoming(start: nil, members: [jieun], custom: [], today: d(2026, 5, 4), limit: 5)
    #expect(b == [Milestone(title: "지은 생일", date: d(2027, 5, 3), daysLeft: 364)])

    let past = Anniversary(id: UUID(), coupleId: UUID(), title: "여행", date: d(2026, 1, 10), repeatsYearly: false)
    var yearly = past
    yearly.repeatsYearly = true
    #expect(DDay.upcoming(start: nil, members: [], custom: [past], today: d(2026, 3, 1), limit: 5).isEmpty)
    #expect(DDay.upcoming(start: nil, members: [], custom: [yearly], today: d(2026, 3, 1), limit: 5)
            == [Milestone(title: "여행", date: d(2027, 1, 10), daysLeft: 315)])
}

@Test func leapDayFallsBackToFeb28() {
    let r = DDay.upcoming(start: d(2024, 2, 29), members: [], custom: [], today: d(2025, 2, 1), limit: 10)
    #expect(r.contains(Milestone(title: "1주년", date: d(2025, 2, 28), daysLeft: 27)))
}
