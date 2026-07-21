import Foundation
import OSLog

/// Instruments(os_signpost) 성능 기준선 계측용 공용 signposter.
/// Instruments가 붙지 않은 실행에서는 비용이 거의 0이라 Release 빌드에도 유지한다.
///
/// 계측 구간(앱 후속 개선 계획 P0):
/// - Editor: `editor.load`(씬 전체 생성), `editor.shell.parse`(USDZ 셸 콜드 파싱),
///   `editor.furniture.template.parse`(GLB 템플릿 콜드 파싱),
///   `editor.furniture.nodes.rebuild`(가구 노드 재생성), `editor.firstFrame`(첫 렌더 이벤트)
/// - RoomScene: `roomScene.download`(서버 룸 씬 JSON 수신), `roomScene.materialize`(USDZ 캐시 복원)
/// - ImgTo3D: `imgTo3D.model.parse`(뷰어 GLB 파싱), `imgTo3D.autoAlign`(정점 기반 자동 정렬)
nonisolated enum PerformanceSignposts {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Spatium"

    static let editor = OSSignposter(subsystem: subsystem, category: "Editor")
    static let roomScene = OSSignposter(subsystem: subsystem, category: "RoomScene")
    static let imgTo3D = OSSignposter(subsystem: subsystem, category: "ImgTo3D")
}
