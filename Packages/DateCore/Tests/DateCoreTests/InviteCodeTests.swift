import Testing
@testable import DateCore

@Test func inviteNormalize() {
    #expect(InviteCode.normalize("abcd-efgh") == "ABCDEFGH")
    #expect(InviteCode.normalize("dateapp://join?code=ABCDEFGH") == "ABCDEFGH")
    #expect(InviteCode.normalize("초대 코드 ABCD-EFGH / dateapp://join?code=ABCDEFGH") == "ABCDEFGH")
    #expect(InviteCode.normalize("ABCD0FGH") == nil)
    #expect(InviteCode.normalize("ABCDIFGH") == nil)
    #expect(InviteCode.normalize("ABC") == nil)
    #expect(InviteCode.normalize("ABCDEFGHJ") == nil)
    #expect(InviteCode.display("ABCDEFGH") == "ABCD-EFGH")
}
