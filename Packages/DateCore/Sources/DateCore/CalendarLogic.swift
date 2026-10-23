import Foundation

public enum CalendarLogic {
    /// 월 달력 칸. 앞쪽은 nil, 길이는 7의 배수. `firstWeekday`는 1=일요일 (Calendar 규약)
    public static func monthGrid(year: Int, month: Int, firstWeekday: Int = 1) -> [LocalDate?] {
        let first = LocalDate(year: year, month: month, day: 1)
        let next = month == 12 ? LocalDate(year: year + 1, month: 1, day: 1) : LocalDate(year: year, month: month + 1, day: 1)
        let count = next.epochDays - first.epochDays
        // 1970-01-01은 목요일(=5). 일요일=1 기준 요일
        let weekday = ((first.epochDays + 4) % 7 + 7) % 7 + 1
        let blanks = (weekday - firstWeekday + 7) % 7
        var cells: [LocalDate?] = Array(repeating: nil, count: blanks)
        cells += (0..<count).map { first.adding(days: $0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    public enum StampAction: Equatable {
        case insert
        case delete(UUID)
    }

    /// 같은 (날짜, 주인, 근무 유형) 도장이 이미 있으면 지우고, 없으면 찍는다
    public static func stampAction(events: [Event], day: LocalDate, ownerMemberId: UUID, shiftTypeId: UUID) -> StampAction {
        if let e = events.first(where: { $0.day == day && $0.ownerMemberId == ownerMemberId && $0.shiftTypeId == shiftTypeId }) {
            return .delete(e.id)
        }
        return .insert
    }

    /// 그날에 걸친 일정(endDay 범위 포함). 하루 종일 먼저, 그다음 시작 시각순
    public static func events(on day: LocalDate, in events: [Event]) -> [Event] {
        let hits = events.enumerated().filter { _, e in e.day <= day && day <= (e.endDay ?? e.day) }
        return hits.sorted { a, b in
            if a.element.allDay != b.element.allDay { return a.element.allDay }
            let ta = minutes(a.element.startTime), tb = minutes(b.element.startTime)
            return ta != tb ? ta < tb : a.offset < b.offset
        }.map(\.element)
    }

    private static func minutes(_ t: LocalTime?) -> Int { t.map { $0.hour * 60 + $0.minute } ?? 0 }

    /// 상대가 만든 일정 중 새로 생겼거나 updatedAt이 바뀐 것. old가 nil(첫 로드)이면 빈 집합
    public static func partnerChanges(old: CoupleSnapshot?, new: CoupleSnapshot) -> Set<UUID> {
        guard let old else { return [] }
        let before = Dictionary(old.events.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
        return Set(new.events.filter { $0.createdByMemberId != new.meMemberId && before[$0.id] != $0.updatedAt }.map(\.id))
    }
}
