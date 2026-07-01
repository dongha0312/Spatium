import SwiftUI

struct HomeDashboardView: View {
    let uploadedRooms: [RoomRecord]
    var onStartScan: () -> Void
    var onOpenRooms: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HeroPanel(onStartScan: onStartScan)

            LazyVGrid(columns: MetricTile.gridColumns, spacing: 10) {
                MetricTile(title: "업로드 공간", value: "\(uploadedRooms.count)")
                MetricTile(title: "기본 플랜", value: "무료")
                MetricTile(title: "전송 형식", value: "USDZ")
            }

            SectionHeader(title: "최근 공간", actionTitle: "전체 보기", action: onOpenRooms)

            if uploadedRooms.isEmpty {
                EmptyStateCard(
                    systemImage: "cube.transparent",
                    title: "아직 업로드된 공간이 없습니다",
                    message: "방 하나를 스캔한 뒤 RoomPlan JSON과 USDZ를 서버로 전송하세요."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(uploadedRooms.prefix(3)) { room in
                        RoomRecordRow(room: room)
                    }
                }
            }
        }
    }
}

private struct HeroPanel: View {
    var onStartScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("3D 인테리어 시뮬레이터")
                .font(.caption.weight(.black))
                .tracking(1)
                .foregroundStyle(SpatiumTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(SpatiumTheme.accent.opacity(0.28), lineWidth: 1))
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 10) {
                Text("나만의 공간을\n직접 스캔하세요")
                    .font(.system(size: 36, weight: .black))
                    .lineSpacing(1)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)

                Text("RoomPlan으로 방을 스캔하고, 서버에서 3D 모델과 원본 공간 데이터를 관리할 수 있게 준비합니다.")
                    .font(.subheadline)
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onStartScan) {
                Label("방 스캔 시작", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [SpatiumTheme.accent, SpatiumTheme.brown],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                SpatiumTheme.ink
                RadialGradient(
                    colors: [SpatiumTheme.accent.opacity(0.18), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 360
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
