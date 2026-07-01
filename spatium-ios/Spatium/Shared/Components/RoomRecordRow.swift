import SwiftUI

struct RoomRecordRow: View {
    let room: RoomRecord

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.88, blue: 0.82), Color(red: 0.83, green: 0.76, blue: 0.69)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "cube")
                        .foregroundStyle(SpatiumTheme.brown)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomType)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)
                Text("\(room.itemCount)개 항목 · 사진 \(room.photoCount)장 · \(room.uploadedAt, formatter: DateFormatter.roomRow)")
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(SpatiumTheme.soft)
        }
        .padding(14)
        .background(SpatiumTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SpatiumTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
