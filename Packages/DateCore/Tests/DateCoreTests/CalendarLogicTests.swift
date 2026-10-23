import Foundation
import Testing
@testable import DateCore

func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day) }

func makeEvent(day: LocalDate, endDay: LocalDate? = nil, owner: UUID? = nil, createdBy: UUID? = nil,
               shiftTypeId: UUID? = nil, title: String? = "일정", allDay: Bool = true,
               start: LocalTime? = nil, kind: OwnerKind = .member, updatedAt: Date = Date(timeIntervalSince1970: 0)) -> Event {
    Event(id: UUID(), coupleId: UUID(), ownerKind: kind, ownerMemberId: owner, createdByMemberId: createdBy,
          shiftTypeId: shiftTypeId, title: title, day: day, endDay: endDay, allDay: allDay,
          startTime: start, endTime: nil, memo: nil, updatedAt: updatedAt)
}

@Test func monthGridOctober2026() {
    let g = CalendarLogic.monthGrid(year: 2026, month: 10)
    #expect(g.count == 35)
    #expect(g.prefix(4).allSatisfy { $0 == nil })
    #expect(g[4] == d(2026, 10, 1))
    #expect(g.last! == d(2026, 10, 31))
}

@Test func stampActionTogglesBySameOwnerAndType() {
    let owner = UUID(), other = UUID(), type = UUID()
    let e = makeEvent(day: d(2026, 10, 21), owner: owner, shiftTypeId: type)
    #expect(CalendarLogic.stampAction(events: [e], day: d(2026, 10, 21), ownerMemberId: owner, shiftTypeId: type) == .delete(e.id))
    #expect(CalendarLogic.stampAction(events: [e], day: d(2026, 10, 21), ownerMemberId: other, shiftTypeId: type) == .insert)
    #expect(CalendarLogic.stampAction(events: [e], day: d(2026, 10, 22), ownerMemberId: owner, shiftTypeId: type) == .insert)
}

@Test func eventsOnDayIncludesRangeAndSortsAllDayFirst() {
    let range = makeEvent(day: d(2026, 10, 20), endDay: d(2026, 10, 22), title: "여행")
    let timed = makeEvent(day: d(2026, 10, 21), title: "점심", allDay: false, start: LocalTime(hour: 9, minute: 0))
    let outside = makeEvent(day: d(2026, 10, 23))
    let r = CalendarLogic.events(on: d(2026, 10, 21), in: [timed, outside, range])
    #expect(r.map(\.title) == ["여행", "점심"])
}

@Test func partnerChangesOnlyPartnerNewOrUpdated() {
    let me = UUID(), partner = UUID()
    let cid = UUID()
    func snap(_ events: [Event]) -> CoupleSnapshot {
        CoupleSnapshot(couple: Couple(id: cid, startDate: nil), members: [], shiftTypes: [],
                       events: events, anniversaries: [], meMemberId: me)
    }
    let theirs = makeEvent(day: d(2026, 10, 21), createdBy: partner)
    let mine = makeEvent(day: d(2026, 10, 21), createdBy: me)
    #expect(CalendarLogic.partnerChanges(old: nil, new: snap([theirs, mine])).isEmpty)
    #expect(CalendarLogic.partnerChanges(old: snap([]), new: snap([theirs, mine])) == [theirs.id])
    var touched = theirs
    touched.updatedAt = Date(timeIntervalSince1970: 100)
    #expect(CalendarLogic.partnerChanges(old: snap([theirs]), new: snap([touched])) == [theirs.id])
    #expect(CalendarLogic.partnerChanges(old: snap([theirs]), new: snap([theirs])).isEmpty)
}
