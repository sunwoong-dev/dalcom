import Foundation

public enum ReminderOption: String, Codable, CaseIterable, Sendable {
    case none, day8, at, m10, m60, d1, eve21
}

public struct ReminderRules: Codable, Equatable, Sendable {
    public var mine: ReminderOption
    public var partner: ReminderOption
    public var together: ReminderOption
    public var partnerShift: ReminderOption

    public static let `default` = ReminderRules(mine: .day8, partner: .day8, together: .day8, partnerShift: .day8)
}

public struct PlannedNotification: Equatable, Sendable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
}

public enum ReminderPlanner {
    /// 앞으로 `horizonDays`일 안의 일정에서 로컬 알림 계획을 만든다. 이미 지난 시각은 뺀다
    public static func plan(snapshot: CoupleSnapshot, rules: ReminderRules, overrides: [UUID: ReminderOption],
                            now: Date, calendar: Calendar, horizonDays: Int = 14, limit: Int = 64) -> [PlannedNotification] {
        let today = LocalDate.today(in: calendar, now: now)
        let last = today.adding(days: horizonDays - 1)
        let types = Dictionary(snapshot.shiftTypes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(snapshot.members.map { ($0.id, $0.nickname) }, uniquingKeysWith: { a, _ in a })

        var planned: [PlannedNotification] = []
        for e in snapshot.events where e.day >= today && e.day <= last {
            let option = overrides[e.id] ?? rule(for: e, snapshot: snapshot, rules: rules)
            let type = e.shiftTypeId.flatMap { types[$0] }
            // 도장은 근무 유형의 시각을 따라가서, 유형 시각이 바뀌면 알림도 바뀐다
            let start: LocalTime? = type.map { $0.allDay ? nil : $0.startTime } ?? (e.allDay ? nil : e.startTime)
            guard let (fire, tomorrow) = fireDate(option, day: e.day, start: start, calendar: calendar), fire > now else { continue }

            let who = e.ownerKind == .together ? "함께" : (e.ownerMemberId.flatMap { names[$0] } ?? "")
            let when = start.map { String(format: "%02d:%02d 시작", $0.hour, $0.minute) } ?? "하루 종일"
            planned.append(PlannedNotification(
                id: e.id.uuidString, fireDate: fire, title: type?.name ?? e.title ?? "",
                body: "\(tomorrow ? "내일" : "오늘") · \(who) · \(when)"))
        }
        planned.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(planned.prefix(limit))
    }

    private static func rule(for e: Event, snapshot: CoupleSnapshot, rules: ReminderRules) -> ReminderOption {
        if e.ownerKind == .together { return rules.together }
        if e.ownerMemberId == snapshot.meMemberId { return rules.mine }
        return e.shiftTypeId != nil ? rules.partnerShift : rules.partner
    }

    /// (알림 시각, 알림이 "내일 일정"을 알리는지). none이면 nil
    private static func fireDate(_ option: ReminderOption, day: LocalDate, start: LocalTime?,
                                 calendar: Calendar) -> (Date, Bool)? {
        let morning = day.date(hour: 8, minute: 0, in: calendar)
        let prev = day.adding(days: -1)
        switch option {
        case .none: return nil
        case .day8: return (morning, false)
        case .at, .m10, .m60:
            guard let s = start else { return (morning, false) }
            let minutes = option == .m10 ? 10 : option == .m60 ? 60 : 0
            return (day.date(hour: s.hour, minute: s.minute, in: calendar).addingTimeInterval(-Double(minutes * 60)), false)
        case .d1:
            guard let s = start else { return (prev.date(hour: 8, minute: 0, in: calendar), true) }
            return (prev.date(hour: s.hour, minute: s.minute, in: calendar), true)
        case .eve21: return (prev.date(hour: 21, minute: 0, in: calendar), true)
        }
    }
}
