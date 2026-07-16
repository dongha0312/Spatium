import SwiftUI

/// 뷰 바의 도움말 버튼으로 여는 3D 시점·가구 편집 사용법 안내 시트.
struct EditorViewHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentMode: RoomViewMode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    modeCard(
                        mode: .threeD,
                        summary: "방 전체를 비스듬히 내려다보는 기본 시점이에요.",
                        rows: [
                            ("hand.draw", "한 손가락 드래그 — 방 돌려보기"),
                            ("hand.raised.fingers.spread", "두 손가락 드래그 — 화면 이동"),
                            ("arrow.up.left.and.arrow.down.right", "핀치 — 확대 / 축소")
                        ]
                    )
                    modeCard(
                        mode: .skyView,
                        summary: "천장에서 수직으로 내려다보는 도면 시점이에요.",
                        rows: [
                            ("hand.raised.fingers.spread", "두 손가락 드래그 — 화면 이동"),
                            ("arrow.up.left.and.arrow.down.right", "핀치 — 확대 / 축소"),
                            ("ruler", "측정 버튼(자)을 켜면 방 치수가 표시돼요")
                        ]
                    )
                    modeCard(
                        mode: .person,
                        summary: "방 안에 서서 눈높이로 걸어다니며 둘러보는 시점이에요.",
                        rows: [
                            ("hand.draw", "한 손가락 드래그 — 좌우 / 위아래 둘러보기"),
                            ("hand.tap", "바닥 탭 — 그 위치로 이동"),
                            ("hand.raised.fingers.spread", "두 손가락 드래그 — 보조 이동"),
                            ("figure.walk", "벽과 가구는 뚫고 지나갈 수 없어요")
                        ]
                    )
                    editCard
                }
                .padding(16)
            }
            .background(SpatiumTheme.background.ignoresSafeArea())
            .navigationTitle("사용법 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func modeCard(
        mode: RoomViewMode,
        summary: String,
        rows: [(String, String)]
    ) -> some View {
        card {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                Text(mode.title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                if mode == currentMode {
                    Text("현재 뷰")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SpatiumTheme.accent, in: Capsule())
                }
                Spacer()
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.soft)
            ForEach(rows, id: \.1) { row in
                helpRow(systemImage: row.0, text: row.1)
            }
        }
    }

    private var editCard: some View {
        card {
            HStack(spacing: 8) {
                Image(systemName: "sofa")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                Text("가구 편집 (모든 뷰 공통)")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Spacer()
            }
            helpRow(systemImage: "hand.tap", text: "가구를 탭 — 선택 / 빈 곳을 탭 — 선택 해제")
            helpRow(
                systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                text: "선택 후 '이동'을 켜고 가구를 드래그 — 벽에 닿으면 딱 붙어요"
            )
            helpRow(systemImage: "rotate.right", text: "선택하면 나오는 슬라이더로 회전")
            helpRow(systemImage: "arrow.up.and.down", text: "높이 슬라이더로 가구를 바닥에서 띄우기 (천장까지)")
            helpRow(systemImage: "arrow.triangle.2.circlepath", text: "교체 버튼으로 다른 가구로 바꾸기")
            helpRow(
                systemImage: "door.left.hand.open",
                text: "문·창문을 제거하면 개구부로 남길지 벽으로 메울지 고를 수 있어요"
            )
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(SpatiumTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md)
                    .stroke(SpatiumTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }

    private func helpRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(SpatiumTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
