import SwiftUI

struct RoomsView: View {
    let rooms: [RoomRecord]
    var onStartScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "내 공간", actionTitle: "새 스캔", action: onStartScan)

            if rooms.isEmpty {
                EmptyStateCard(
                    systemImage: "square.grid.2x2",
                    title: "공간 목록이 비어 있습니다",
                    message: "침실, 거실, 주방처럼 방 단위로 스캔하면 서버와 앱에서 관리하기 쉽습니다."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(rooms) { room in
                        RoomRecordRow(room: room)
                    }
                }
            }
        }
    }
}
