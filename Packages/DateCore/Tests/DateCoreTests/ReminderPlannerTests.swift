import Foundation
import Testing
@testable import DateCore

private let seoul: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
}()

private func at(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    seoul.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
}

private struct Fixture {
    let me = UUID(), partner = UUID(), cid = UUID()
    var shiftTypes: [ShiftType] = []

    func snapshot(_ events: [Event]) -> CoupleSnapshot {
        CoupleSnapshot(
            couple: Couple(id: cid, startDate: nil),
            members: [
                Member(id: me, coupleId: cid, userId: UUID(), role: "owner", nickname: "선웅", birthday: nil, color: .sky),
                Member(id: partner, coupleId: cid, userId: UUID(), role: "member", nickname: "지은", birthday: nil, color: .pink),
            ],
            shiftTypes: shiftTypes, events: events, anniversaries: [], meMemberId: me)
    }

    func shiftType(name: String = "오전 당직", allDay: Bool, start: LocalTime?) -> ShiftType {
        ShiftType(id: UUID(), coupleId: cid, ownerMemberId: partner, name: name, shortLabel: "오",
                  color: .pink, allDay: allDay, startTime: start, endTime: nil, sortOrder: 0)
    }
}

private func plan(_ s: CoupleSnapshot, rules: ReminderRules = .default, overrides: [UUID: ReminderOption] = [:],
                  now: Date = at(2026, 10, 21)) -> [PlannedNotification] {
    ReminderPlanner.plan(snapshot: s, rules: rules, overrides: overrides, now: now, calendar: seoul)
}

@Test func default_all_day8() {
    let f = Fixture()
    let e = makeEvent(day: d(2026, 10, 22), owner: f.partner, createdBy: f.partner, title: "데이트")
    let r = plan(f.snapshot([e]))
    #expect(r.count == 1)
    #expect(r[0].id == e.id.uuidString)
    #expect(r[0].fireDate == at(2026, 10, 22, 8, 0))
    #expect(r[0].body == "오늘 · 지은 · 하루 종일")
}

@Test func per_person_override() {
    let f = Fixture()
    let e = makeEvent(day: d(2026, 10, 22), owner: f.partner)
    #expect(plan(f.snapshot([e]), overrides: [e.id: .none]).isEmpty)
}

@Test func partner_shift_eve21() {
    var f = Fixture()
    let t = f.shiftType(allDay: true, start: nil)
    f.shiftTypes = [t]
    let e = makeEvent(day: d(2026, 10, 23), owner: f.partner, shiftTypeId: t.id, title: nil)
    var rules = ReminderRules.default
    rules.partnerShift = .eve21
    let r = plan(f.snapshot([e]), rules: rules)
    #expect(r.count == 1)
    #expect(r[0].fireDate == at(2026, 10, 22, 21, 0))
    #expect(r[0].title == "오전 당직")
    #expect(r[0].body == "내일 · 지은 · 하루 종일")
}

@Test func shift_time_from_type() {
    var f = Fixture()
    let t = f.shiftType(allDay: false, start: LocalTime(hour: 9, minute: 0))
    f.shiftTypes = [t]
    let e = makeEvent(day: d(2026, 10, 23), owner: f.partner, shiftTypeId: t.id, title: nil, allDay: false)
    var rules = ReminderRules.default
    rules.partnerShift = .m60
    #expect(plan(f.snapshot([e]), rules: rules)[0].fireDate == at(2026, 10, 23, 8, 0))

    // 유형의 시작 시각을 바꾸면 이미 찍힌 도장의 알림 시각도 따라 바뀐다
    var moved = f
    moved.shiftTypes = [ShiftType(id: t.id, coupleId: t.coupleId, ownerMemberId: t.ownerMemberId, name: t.name,
                                  shortLabel: t.shortLabel, color: t.color, allDay: false,
                                  startTime: LocalTime(hour: 13, minute: 0), endTime: nil, sortOrder: 0)]
    #expect(plan(moved.snapshot([e]), rules: rules)[0].fireDate == at(2026, 10, 23, 12, 0))
}

@Test func together_and_mine_use_own_rules() {
    let f = Fixture()
    let together = makeEvent(day: d(2026, 10, 22), title: "여행", kind: .together)
    let mine = makeEvent(day: d(2026, 10, 22), owner: f.me, title: "내 일정")
    var rules = ReminderRules.default
    rules.together = .none
    let r = plan(f.snapshot([together, mine]), rules: rules)
    #expect(r.map(\.id) == [mine.id.uuidString])
}

@Test func skips_past_fire_dates() {
    let f = Fixture()
    let e = makeEvent(day: d(2026, 10, 21), owner: f.partner)
    #expect(plan(f.snapshot([e]), now: at(2026, 10, 21, 9, 0)).isEmpty)
}

@Test func horizon_and_limit() {
    let f = Fixture()
    let daily = (0..<30).map { makeEvent(day: d(2026, 10, 21).adding(days: $0), owner: f.partner) }
    #expect(plan(f.snapshot(daily)).count == 14)

    let many = (0..<30).flatMap { i in
        (0..<10).map { _ in makeEvent(day: d(2026, 10, 21).adding(days: i), owner: f.partner) }
    }
    let r = plan(f.snapshot(many))
    #expect(r.count == 64)
    #expect(r.map(\.fireDate) == r.map(\.fireDate).sorted())
}
