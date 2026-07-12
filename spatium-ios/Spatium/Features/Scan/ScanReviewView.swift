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

            ActionCTAButton(
                title: "방 스캔 시작",
                subtitle: "카메라로 공간을 스캔해 3D 도면을 만드세요",
                systemImage: "camera.viewfinder",
                tint: SpatiumTheme.sky,
                action: onStartScan
            )
        }
    }
}

struct ScanReviewView: View {
    @Binding var project: ScanProject
    /// 3D 에디터에서 저장 시 자동 업로드에 쓰는 소속 프로젝트 정보.
    var projectID: String? = nil
    var projectName: String? = nil
    var exporting: Bool
    var uploading: Bool
    var exportError: String?
    var uploadMessage: String?
    var onStartScan: () -> Void
    var onExport: () -> Void
    var onUpload: () -> Void
    var onOpenSettings: () -> Void
    /// 3D 에디터가 저장 과정에서 서버 룸을 새로 만들었을 때 바깥 상태(activeRoomID 등)를 갱신하는 콜백.
    var onRoomUploaded: ((RoomRecord) -> Void)? = nil

    @State private var showScanEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScanStatusHeader(project: project, onStartScan: onStartScan)
            RoomTypeCard(project: $project)
            ScanEditEntryCard(itemCount: project.items.count) {
                showScanEditor = true
            }
            DetectedItemsCard(items: $project.items)
            CapturedPhotosCard(photos: project.photos)
            ExportCard(
                exporting: exporting,
                uploading: uploading,
                exportError: exportError,
                uploadMessage: uploadMessage,
                onExport: onExport,
                onUpload: onUpload,
                onOpenSettings: onOpenSettings
            )
        }
        .fullScreenCover(isPresented: $showScanEditor) {
            RoomEditorView(
                scanItems: project.items,
                roomName: project.resolvedRoomType,
                usdzURL: try? project.exportUSDZForEditing(),
                area: project.estimatedFootprint.width * project.estimatedFootprint.depth,
                ceilingHeight: project.estimatedCeilingHeight,
                projectID: projectID,
                projectName: projectName,
                onRoomCreated: onRoomUploaded
            )
        }
    }
}

/// 스캔 결과를 실제 3D로 열어 객체를 편집하는 진입 카드.
private struct ScanEditEntryCard: View {
    let itemCount: Int
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "cube.transparent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("3D로 편집하기")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("스캔된 방에서 객체 \(itemCount)개를 이동·수정·추가·삭제")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
            }
            .padding(16)
            .background(SpatiumTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.accentLight.opacity(0.5), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .shadow(color: SpatiumTheme.shadow.opacity(0.12), radius: 14, y: 6)
        }
        .buttonStyle(.pressable)
    }
}

private struct ScanStatusHeader: View {
    let project: ScanProject
    var onStartScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.resolvedRoomType)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("\(project.items.count)개 요소 · 사진 \(project.photos.count)장")
                    .font(.subheadline)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Button(action: onStartScan) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.sky)
                    .frame(width: 44, height: 44)
                    .background(SpatiumTheme.sky.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("다시 스캔")
        }
        .padding(.horizontal, 2)
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
                    .background(SpatiumTheme.elevatedSurface)
                    .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(SpatiumTheme.border, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))

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
                                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
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
    var exportError: String?
    var uploadMessage: String?
    var onExport: () -> Void
    var onUpload: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("출력")
                            .font(.headline.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                        // 내부 서버 주소를 그대로 노출하지 않고 동작 설명만 보여준다.
                        Text("스캔 파일을 공유하거나 프로젝트에 저장합니다")
                            .font(.caption)
                            .foregroundStyle(SpatiumTheme.soft)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SpatiumTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(SpatiumTheme.accent.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("서버 설정")
                }

                OutputActionButton(
                    title: exporting ? "준비 중" : "파일 공유 (USDZ + JSON)",
                    systemImage: "square.and.arrow.up",
                    tint: SpatiumTheme.sage,
                    action: onExport
                )
                .disabled(exporting || uploading)

                Button(action: onUpload) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.doc")
                            .font(.headline.weight(.bold))
                        Text(uploading ? "업로드 중..." : "서버로 업로드")
                            .font(.headline.weight(.bold))
                        Spacer()
                        if uploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.black))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(SpatiumTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(exporting || uploading)

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

private struct OutputActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.11))
            .foregroundStyle(tint)
            .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.md).stroke(tint.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
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
                .background(SpatiumTheme.warmPanel)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))

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
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
    }
}
