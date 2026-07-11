import SwiftUI

/// 앱 공용 브랜드 로고 — favicon 큐브를 크림 타일 위에 얹은, 앱 아이콘과 동일한 마크.
/// 로그인·앱 헤더·편집기 네비가 모두 이 하나를 공유한다. `size`는 타일 한 변(pt).
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        // 로고 이미지는 흰 배경에 큐브가 여백을 두고 그려져 있어, 그대로 둥근 사각형으로 클립하면
        // 흰 타일 위 큐브(앱 아이콘과 동일)가 된다. 어두운 배경에서도 흰 타일 덕분에 또렷하다.
        Image("SpatiumCube")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }
}
