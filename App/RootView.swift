import SwiftUI

// 지금은 빈 화면. 이후 태스크에서 로그인·달력 화면으로 바뀐다.
struct RootView: View {
    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            Text("달콤")
                .font(.largeTitle)
                .foregroundStyle(Color("TextPrimary"))
        }
    }
}

#Preview {
    RootView()
}
