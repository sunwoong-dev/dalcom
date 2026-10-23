/// 초대 코드: 서버 `gen_invite_code()`와 같은 32자 알파벳 8자리.
public enum InviteCode {
    private static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// 코드, "ABCD-EFGH", `dateapp://join?code=…`, 공유 문구 전체 중 무엇이 와도 정규화한다. 형식이 틀리면 nil
    public static func normalize(_ input: String) -> String? {
        var s = input
        if let r = s.range(of: "code=") {
            s = String(s[r.upperBound...])
        } else if let r = s.range(of: "/") {
            s = String(s[..<r.lowerBound]) // 공유 문구에서 링크 앞 코드 부분만
        }
        // 한글 안내("초대 코드")는 걸러내고 ASCII 영숫자만 본다
        let chars = s.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard chars.count == 8, chars.allSatisfy(alphabet.contains) else { return nil }
        return chars
    }

    public static func display(_ code: String) -> String {
        "\(code.prefix(4))-\(code.dropFirst(4))"
    }
}
