/// 멤버 색 팔레트. 키는 서버 컬럼 값과 같다.
public enum PaletteColor: String, Codable, CaseIterable, Sendable {
    case pink, sky, mint, lilac, peach, lemon

    public var hex: String {
        switch self {
        case .pink: "#F7C6D3"
        case .sky: "#C9E2F5"
        case .mint: "#CDEBDD"
        case .lilac: "#DCD3F2"
        case .peach: "#FAD6C4"
        case .lemon: "#FBEAB0"
        }
    }

    public static func available(taken: Set<PaletteColor>) -> [PaletteColor] {
        allCases.filter { !taken.contains($0) }
    }
}
