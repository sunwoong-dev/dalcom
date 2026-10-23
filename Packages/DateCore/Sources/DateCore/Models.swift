import Foundation

public struct Couple: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startDate: LocalDate?
    enum CodingKeys: String, CodingKey { case id, startDate = "start_date" }
}

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var coupleId: UUID
    public var userId: UUID
    public var role: String
    public var nickname: String
    public var birthday: LocalDate?
    public var color: PaletteColor
    enum CodingKeys: String, CodingKey {
        case id, role, nickname, birthday, color
        case coupleId = "couple_id", userId = "user_id"
    }
}

public struct ShiftType: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var coupleId: UUID
    public var ownerMemberId: UUID?
    public var name: String
    public var shortLabel: String
    public var color: PaletteColor
    public var allDay: Bool
    public var startTime: LocalTime?
    public var endTime: LocalTime?
    public var sortOrder: Int
    enum CodingKeys: String, CodingKey {
        case id, name, color
        case coupleId = "couple_id", ownerMemberId = "owner_member_id", shortLabel = "short_label"
        case allDay = "all_day", startTime = "start_time", endTime = "end_time", sortOrder = "sort_order"
    }
}

public enum OwnerKind: String, Codable, Sendable { case member, together }

public struct Event: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var coupleId: UUID
    public var ownerKind: OwnerKind
    public var ownerMemberId: UUID?
    public var createdByMemberId: UUID?
    public var shiftTypeId: UUID?
    public var title: String?
    public var day: LocalDate
    public var endDay: LocalDate?
    public var allDay: Bool
    public var startTime: LocalTime?
    public var endTime: LocalTime?
    public var memo: String?
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, day, memo
        case coupleId = "couple_id", ownerKind = "owner_kind", ownerMemberId = "owner_member_id"
        case createdByMemberId = "created_by_member_id", shiftTypeId = "shift_type_id"
        case endDay = "end_day", allDay = "all_day", startTime = "start_time", endTime = "end_time"
        case updatedAt = "updated_at"
    }

    public init(id: UUID, coupleId: UUID, ownerKind: OwnerKind, ownerMemberId: UUID?, createdByMemberId: UUID?,
                shiftTypeId: UUID?, title: String?, day: LocalDate, endDay: LocalDate?, allDay: Bool,
                startTime: LocalTime?, endTime: LocalTime?, memo: String?, updatedAt: Date) {
        self.id = id
        self.coupleId = coupleId
        self.ownerKind = ownerKind
        self.ownerMemberId = ownerMemberId
        self.createdByMemberId = createdByMemberId
        self.shiftTypeId = shiftTypeId
        self.title = title
        self.day = day
        self.endDay = endDay
        self.allDay = allDay
        self.startTime = startTime
        self.endTime = endTime
        self.memo = memo
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        coupleId = try c.decode(UUID.self, forKey: .coupleId)
        ownerKind = try c.decode(OwnerKind.self, forKey: .ownerKind)
        ownerMemberId = try c.decodeIfPresent(UUID.self, forKey: .ownerMemberId)
        createdByMemberId = try c.decodeIfPresent(UUID.self, forKey: .createdByMemberId)
        shiftTypeId = try c.decodeIfPresent(UUID.self, forKey: .shiftTypeId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        day = try c.decode(LocalDate.self, forKey: .day)
        endDay = try c.decodeIfPresent(LocalDate.self, forKey: .endDay)
        allDay = try c.decode(Bool.self, forKey: .allDay)
        startTime = try c.decodeIfPresent(LocalTime.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(LocalTime.self, forKey: .endTime)
        memo = try c.decodeIfPresent(String.self, forKey: .memo)
        let s = try c.decode(String.self, forKey: .updatedAt)
        guard let d = Event.parseTimestamp(s) else {
            throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: c, debugDescription: "시각 형식 오류: \(s)")
        }
        updatedAt = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(coupleId, forKey: .coupleId)
        try c.encode(ownerKind, forKey: .ownerKind)
        try c.encode(ownerMemberId, forKey: .ownerMemberId)
        try c.encode(createdByMemberId, forKey: .createdByMemberId)
        try c.encode(shiftTypeId, forKey: .shiftTypeId)
        try c.encode(title, forKey: .title)
        try c.encode(day, forKey: .day)
        try c.encode(endDay, forKey: .endDay)
        try c.encode(allDay, forKey: .allDay)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(memo, forKey: .memo)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try c.encode(f.string(from: updatedAt), forKey: .updatedAt)
    }

    // PostgREST는 마이크로초 6자리 + "+00:00"으로 보낸다. 소수초는 밀리초 3자리로 잘라 파싱한다 (R6)
    static func parseTimestamp(_ s: String) -> Date? {
        var str = s
        var hasFraction = false
        if let dot = str.firstIndex(of: ".") {
            hasFraction = true
            var end = str.index(after: dot)
            while end < str.endIndex, str[end].isNumber { end = str.index(after: end) }
            let digits = String(str[str.index(after: dot)..<end]).padding(toLength: 3, withPad: "0", startingAt: 0)
            str.replaceSubrange(dot..<end, with: "." + digits.prefix(3))
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = hasFraction ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f.date(from: str)
    }
}

public struct Anniversary: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var coupleId: UUID
    public var title: String
    public var date: LocalDate
    public var repeatsYearly: Bool
    enum CodingKeys: String, CodingKey {
        case id, title, date
        case coupleId = "couple_id", repeatsYearly = "repeats_yearly"
    }
}

public struct CoupleSnapshot: Codable, Equatable, Sendable {
    public var couple: Couple
    public var members: [Member]
    public var shiftTypes: [ShiftType]
    public var events: [Event]
    public var anniversaries: [Anniversary]
    public var meMemberId: UUID
}
