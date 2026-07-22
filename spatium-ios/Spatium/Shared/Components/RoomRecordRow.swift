import SwiftUI

struct RoomRecordRow: View {
    let room: RoomRecord

    /// 목록에서는 방 이름과 서버의 최근 수정 시각만 보여줘 핵심 정보에 집중합니다.
    private var subtitle: String {
        "마지막 수정 \(DateFormatter.roomRowDateOnly.string(from: room.uploadedAt))"
    }

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [SpatiumTheme.warmPanel, SpatiumTheme.accentLight.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "cube")
                        .foregroundStyle(SpatiumTheme.accent)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomType)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.black))
                .foregroundStyle(SpatiumTheme.soft)
                .frame(width: 24, height: 24)
                .background(SpatiumTheme.background)
                .clipShape(Circle())
        }
        .padding(14)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                .stroke(SpatiumTheme.border.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.015), radius: 6, y: 3)
    }
}
