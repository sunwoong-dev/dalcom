import Testing
@testable import DateCore

// 테스트 타깃이 비면 SwiftPM이 거부하므로 두는 자리 테스트. Task 5에서 실제 테스트로 바꾼다.
@Test func packageBuilds() {
    #expect(Bool(true))
}
