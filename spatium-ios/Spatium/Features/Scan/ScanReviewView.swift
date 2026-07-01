import SwiftUI
import UIKit

struct EmptyScanView: View {
    var onStartScan: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            EmptyStateCard(
                systemImage: "camera.metering.center.weighted",
                title: "검토할 스캔이 없습니다",
                message: "새 방을 스캔하면 RoomPlan 결과를 확인하고 서버로 업로드할 수 있습니다."
            )

            PrimaryButton(title: "방 스캔 시작", systemImage: "camera.viewfinder", action: onStartScan)
        }
    }
}

struct ScanReviewView: View {
    @Binding var project: ScanProject
    let endpoint: String
    var exporting: Bool
    var uploading: Bool
    var exportError: String?
    var uploadMessage: String?
    var onStartScan: () -> Void
    var onPreview: () -> Void
    var onExport: () -> Void
    var onUpload: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "스캔 결과", actionTitle: "다시 스캔", action: onStartScan)

            SummaryCard(project: project)
            RoomTypeCard(project: $project)
            CapturedPhotosCard(photos: project.photos)
            DetectedItemsCard(items: $project.items)
            ExportCard(
                exporting: exporting,
                uploading: uploading,
                endpoint: endpoint,
                exportError: exportError,
                uploadMessage: uploadMessage,
                onPreview: onPreview,
                onExport: onExport,
                onUpload: onUpload,
                onOpenSettings: onOpenSettings
            )
        }
    }
}

private struct SummaryCard: View {
    let project: ScanProject

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.resolvedRoomType)
                            .font(.title2.bold())
                            .foregroundStyle(SpatiumTheme.text)
                        Text("RoomPlan 원본 category, dimensions, transform 기반")
                            .font(.footnote)
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    Spacer()
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(SpatiumTheme.accent)
                }

                LazyVGrid(columns: MetricTile.gridColumns, spacing: 10) {
                    MetricTile(title: "감지 항목", value: "\(project.items.count)")
                    MetricTile(title: "사진", value: "\(project.photos.count)")
                    MetricTile(title: "JSON", value: "원본")
                }
            }
        }
    }
}

private struct RoomTypeCard: View {
    @Binding var project: ScanProject

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("방 정보")
                    .font(.headline)
                    .foregroundStyle(SpatiumTheme.text)

                TextField("예: 침실, 거실, 주방, 서재", text: $project.roomType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.white)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(SpatiumTheme.border, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text("입력한 값은 metadata JSON 파일의 roomType으로 함께 전송됩니다.")
                    .font(.footnote)
                    .foregroundStyle(SpatiumTheme.soft)
            }
        }
    }
}

private struct CapturedPhotosCard: View {
    let photos: [UIImage]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("촬영된 방 사진 (\(photos.count)장)")
                    .font(.headline)
                    .foregroundStyle(SpatiumTheme.text)

                if photos.isEmpty {
                    Text("스캔 중 촬영된 사진이 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(SpatiumTheme.soft)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<photos.count, id: \.self) { index in
                                Image(uiImage: photos[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 98, height: 126)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DetectedItemsCard: View {
    @Binding var items: [EditableScanItem]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("감지된 공간 요소")
                    .font(.headline)
                    .foregroundStyle(SpatiumTheme.text)

                if items.isEmpty {
                    ContentUnavailableView("감지된 항목 없음", systemImage: "cube.transparent", description: Text("스캔을 다시 시도해 주세요."))
                        .frame(minHeight: 180)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach($items) { $item in
                            EditableScanItemRow(item: $item)
                        }
                    }
                }
            }
        }
    }
}

private struct ExportCard: View {
    var exporting: Bool
    var uploading: Bool
    var endpoint: String
    var exportError: String?
    var uploadMessage: String?
    var onPreview: () -> Void
    var onExport: () -> Void
    var onUpload: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("내보내기")
                    .font(.headline)
                    .foregroundStyle(SpatiumTheme.text)

                SecondaryButton(title: exporting ? "스캔 데이터 준비 중..." : "앱에서 3D/AR로 보기", systemImage: "arkit", action: onPreview)
                    .disabled(exporting || uploading)

                PrimaryButton(title: exporting ? "저장 준비 중..." : "스캔 데이터 저장/공유", systemImage: "square.and.arrow.up", action: onExport)
                    .disabled(exporting || uploading)

                Divider().background(SpatiumTheme.border)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(SpatiumTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spring Boot API")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SpatiumTheme.text)
                        Text(endpoint)
                            .font(.caption)
                            .foregroundStyle(SpatiumTheme.soft)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("수정", action: onOpenSettings)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.brown)
                }

                PrimaryButton(title: uploading ? "업로드 중..." : "Spring Boot로 업로드", systemImage: "arrow.up.doc", action: onUpload)
                    .disabled(exporting || uploading)

                Text("metadata에는 ai-edit-request.json, file에는 room-scan.usdz가 전송됩니다.")
                    .font(.footnote)
                    .foregroundStyle(SpatiumTheme.soft)

                if let exportError {
                    Text(exportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let uploadMessage {
                    Text(uploadMessage)
                        .font(.footnote)
                        .foregroundStyle(uploadMessage.hasPrefix("업로드 실패") ? .red : SpatiumTheme.muted)
                }
            }
        }
    }
}

private struct EditableScanItemRow: View {
    @Binding var item: EditableScanItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.iconName)
                .font(.title3)
                .frame(width: 34, height: 34)
                .foregroundStyle(SpatiumTheme.accent)
                .background(Color(red: 0.95, green: 0.91, blue: 0.87))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.text)

                Text(item.measurementSummary)
                    .font(.caption)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()
        }
        .padding(12)
        .background(SpatiumTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
