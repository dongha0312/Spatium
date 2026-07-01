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

            VStack(spacing: 12) {
                if !capturedPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<capturedPhotos.count, id: \.self) { index in
                                Image(uiImage: capturedPhotos[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 68)
                }

                HStack(spacing: 12) {
                    Button {
                        triggerCapture = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                            Text("사진")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.white)
                        .frame(width: 78, height: 66)
                        .background(SpatiumTheme.brown)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!isScanning)

                    Button {
                        isScanning = false
                    } label: {
                        Label("스캔 완료", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 66)
                            .background(SpatiumTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                .opacity(isScanning ? 1 : 0)
            }

            if !isScanning {
                ProgressView("스캔 데이터 처리 중...")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 28)
            }
        }
        .animation(.default, value: capturedPhotos.count)
    }
}
