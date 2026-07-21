import SwiftUI

struct RoomRecordRow: View {
    let room: RoomRecord

    /// 서버 룸에는 사진이 저장되지 않으므로, 0장일 땐 표기를 생략해 노이즈를 줄인다.
    private var subtitle: String {
        var parts = [
            DateFormatter.roomRow.string(from: room.uploadedAt),
            "항목 \(room.itemCount)개"
        ]
        if room.photoCount > 0 {
            parts.append("사진 \(room.photoCount)장")
        }
        return parts.joined(separator: " · ")
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
