import SwiftUI

/// RoomPlan은 여러 방을 한 세션에 이어 담으면 벽 경계와 가구 분류가 불안정해질 수 있다.
/// 실제 카메라를 열기 전에 방 하나 단위의 스캔 원칙을 반드시 확인하게 한다.
struct ScanPreparationSheet: View {
    var onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesLargeDetent: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                reasonCard
                checklist
                actions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpatiumTheme.background.ignoresSafeArea())
        .presentationDetents(usesLargeDetent ? [.large] : [.height(520)])
        .presentationDragIndicator(.visible)
        .presentationBackground(SpatiumTheme.background)
        .accessibilityIdentifier("scan-one-room-guidance")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "viewfinder.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(SpatiumTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("정확한 인식을 위해")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)

                Text("한 번에 방 하나만 스캔해 주세요")
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var reasonCard: some View {
        Text("거실과 주방처럼 여러 방을 한 번에 이어서 스캔하면 벽 경계, 가구 위치와 카테고리 인식이 부정확해질 수 있어요.")
            .font(.subheadline)
            .lineSpacing(4)
            .foregroundStyle(SpatiumTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpatiumTheme.warmPanel)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    .stroke(SpatiumTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScanPreparationRule(
                systemImage: "door.left.hand.closed",
                title: "현재 방 안에서만 이동하기",
                detail: "출입문 너머의 다른 방까지 이어서 스캔하지 마세요."
            )
            ScanPreparationRule(
                systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                title: "벽과 가구를 천천히 비추기",
                detail: "방 안을 한 바퀴 돌며 벽, 바닥과 가구가 충분히 보이게 해주세요."
            )
            ScanPreparationRule(
                systemImage: "plus.square.on.square",
                title: "다른 방은 새 스캔으로 시작하기",
                detail: "현재 방의 스캔을 완료한 뒤 방마다 새 스캔을 만들어 주세요."
            )
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("취소") {
                dismiss()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(SpatiumTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SpatiumTheme.warmPanel)
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                    .stroke(SpatiumTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            .buttonStyle(.pressable)

            Button {
                Haptics.selection()
                onStart()
                dismiss()
            } label: {
                Label("이 방 스캔 시작", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SpatiumTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("scan-preparation-start-button")
        }
    }
}

private struct ScanPreparationRule: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.accent)
                .frame(width: 36, height: 36)
                .background(SpatiumTheme.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
