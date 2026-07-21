import RoomPlan
import SwiftUI

struct ScanCaptureSheet: View {
    @Binding var isScanning: Bool
    var onCompleted: (CapturedRoom) -> Void
    var onError: (Error) -> Void
    var onCancel: () -> Void

    @State private var isCancelled = false
    @State private var isCaptureReady = false

    var body: some View {
        if RoomCaptureSession.isSupported {
            captureContent
        } else {
            unsupportedContent
        }
    }

    private var captureContent: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureViewRepresentable(
                isScanning: $isScanning,
                isCaptureReady: $isCaptureReady,
                onScanCompleted: { room in
                    guard !isCancelled else { return }
                    onCompleted(room)
                },
                onError: { error in
                    guard !isCancelled else { return }
                    onError(error)
                }
            )
            .ignoresSafeArea()

            if isScanning {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            cancelScan()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 1))
                        }
                        .accessibilityLabel("스캔 취소")

                        ScanGuidanceBanner()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer()
                }
            }

            // RoomPlan은 스캔 중 만들어지는 미니 3D 모델을 하단 "중앙"에 그린다.
            // 완료 컨트롤은 오른쪽 모서리에 붙여 중앙을 비워 둔다.
            HStack(alignment: .bottom) {
                Spacer()

                Button {
                    guard isScanning, isCaptureReady else { return }
                    Haptics.impact()
                    isCaptureReady = false
                    isScanning = false
                } label: {
                    Label(
                        isCaptureReady ? "스캔 완료" : "스캔 준비 중",
                        systemImage: isCaptureReady ? "checkmark.circle.fill" : "hourglass"
                    )
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(
                                colors: [SpatiumTheme.sky, SpatiumTheme.sky.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .disabled(!isScanning || !isCaptureReady)
                .opacity(isCaptureReady ? 1 : 0.68)
                .accessibilityIdentifier("scan-finish-button")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .opacity(isScanning ? 1 : 0)

            if !isScanning {
                ProgressView("스캔 데이터 처리 중...")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    .padding(.bottom, 28)
            }
        }
        .interactiveDismissDisabled(isScanning)
    }

    private var unsupportedContent: some View {
        ZStack {
            SpatiumTheme.background.ignoresSafeArea()

            ContentUnavailableView {
                Label("방 스캔을 지원하지 않는 기기예요", systemImage: "viewfinder.circle")
            } description: {
                Text("RoomPlan 방 스캔은 LiDAR가 탑재된 iPhone 또는 iPad에서 사용할 수 있어요. 가구 만들기와 프로젝트의 다른 기능은 계속 사용할 수 있습니다.")
            } actions: {
                Button("돌아가기", action: cancelScan)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    private func cancelScan() {
        Haptics.impact()
        isCancelled = true
        isCaptureReady = false
        isScanning = false
        onCancel()
    }
}

private struct ScanGuidanceBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "door.left.hand.closed")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("지금 있는 방 하나만 스캔하세요")
                    .font(.subheadline.weight(.bold))
                Text("문을 넘어 다른 방으로 이동하지 말고, 다른 방은 완료 후 새 스캔으로 시작하세요.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("지금 있는 방 하나만 스캔하세요. 문을 넘어 다른 방으로 이동하지 말고, 다른 방은 완료 후 새 스캔으로 시작하세요.")
    }
}
