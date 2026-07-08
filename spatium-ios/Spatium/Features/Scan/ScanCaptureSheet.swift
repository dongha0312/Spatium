import RoomPlan
import SwiftUI
import UIKit

struct ScanCaptureSheet: View {
    @Binding var isScanning: Bool
    var onCompleted: (CapturedRoom, [UIImage]) -> Void
    var onError: (Error) -> Void

    @State private var triggerCapture = false
    @State private var capturedPhotos: [UIImage] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureViewRepresentable(
                isScanning: $isScanning,
                triggerCapture: $triggerCapture,
                onPhotoCaptured: { photo in
                    capturedPhotos.append(photo)
                },
                onScanCompleted: { room in
                    onCompleted(room, capturedPhotos)
                },
                onError: onError
            )
            .ignoresSafeArea()

            if isScanning {
                VStack(spacing: 10) {
                    ScanGuidanceBanner()
                        .padding(.horizontal)
                        .padding(.top, 12)

                    // 찍은 사진은 상단에 모아, 하단의 RoomPlan 미니 모델을 가리지 않게 한다.
                    if !capturedPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(0..<capturedPhotos.count, id: \.self) { index in
                                    Image(uiImage: capturedPhotos[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm))
                                        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.sm).stroke(.white, lineWidth: 2))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 58)
                    }

                    Spacer()
                }
            }

            // RoomPlan은 스캔 중 만들어지는 미니 3D 모델을 하단 "중앙"에 그린다.
            // 컨트롤은 양쪽 모서리에 컴팩트하게 붙여 중앙을 비워 둔다.
            HStack(alignment: .bottom) {
                Button {
                    triggerCapture = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 1))
                }
                .disabled(!isScanning)
                .accessibilityLabel("사진 촬영")

                Spacer()

                Button {
                    Haptics.impact()
                    isScanning = false
                } label: {
                    Label("스캔 완료", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(
                                colors: [SpatiumTheme.accentLight, SpatiumTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
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
        .animation(.default, value: capturedPhotos.count)
    }
}

private struct ScanGuidanceBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("천천히 방을 비춰주세요")
                    .font(.subheadline.weight(.bold))
                Text("벽, 바닥, 가구가 모두 보이도록 방을 한 바퀴 돌며 스캔하세요.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
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
    }
}
