import ARKit
import CoreImage
import RoomPlan
import SwiftUI
import UIKit

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var isCaptureReady: Bool
    @Binding var triggerCapture: Bool
    var onPhotoCaptured: (UIImage) -> Void
    var onScanCompleted: (CapturedRoom) -> Void
    var onError: (Error) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let roomCaptureView = RoomCaptureView(frame: .zero)
        roomCaptureView.delegate = context.coordinator
        roomCaptureView.captureSession.delegate = context.coordinator
        return roomCaptureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        context.coordinator.parent = self

        if isScanning {
            context.coordinator.startSessionIfNeeded(for: uiView)
        } else {
            context.coordinator.stopSessionIfNeeded(for: uiView)
        }

        if triggerCapture {
            context.coordinator.capturePhoto(from: uiView)
        }
    }

    func makeCoordinator() -> RoomCaptureViewCoordinator {
        RoomCaptureViewCoordinator(self)
    }
}

/// RoomPlan의 비동기 시작·업데이트 순서를 명시적으로 추적한다.
/// 첫 스캔 업데이트 전에는 `stop()`을 호출할 수 없게 해, 준비 화면에서
/// 완료를 누를 때 RoomPlan 내부 precondition이 발생하는 것을 막는다.
struct RoomCaptureSessionLifecycle: Equatable {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case ready
        case stopping
    }

    private(set) var phase: Phase = .idle

    var canFinish: Bool {
        phase == .ready
    }

    @discardableResult
    mutating func requestStart() -> Bool {
        guard phase == .idle else { return false }
        phase = .starting
        return true
    }

    mutating func sessionDidStart() {
        guard phase == .starting else { return }
        phase = .running
    }

    mutating func sessionDidUpdate() {
        guard phase == .running || phase == .ready else { return }
        phase = .ready
    }

    @discardableResult
    mutating func requestStop() -> Bool {
        guard phase == .ready else { return false }
        phase = .stopping
        return true
    }

    mutating func sessionDidEnd() {
        phase = .idle
    }
}

final class RoomCaptureViewCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var parent: RoomCaptureViewRepresentable
    private var lifecycle = RoomCaptureSessionLifecycle()

    init(_ parent: RoomCaptureViewRepresentable) {
        self.parent = parent
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func encode(with coder: NSCoder) {}

    func startSessionIfNeeded(for roomCaptureView: RoomCaptureView) {
        guard lifecycle.requestStart() else { return }
        publishCaptureReadiness(false)
        let config = RoomCaptureSession.Configuration()
        roomCaptureView.captureSession.run(configuration: config)
    }

    func stopSessionIfNeeded(for roomCaptureView: RoomCaptureView) {
        // `isScanning`이 취소 등의 이유로 먼저 false가 되더라도, RoomPlan이
        // 첫 결과를 제공하기 전에는 stop()을 호출하지 않는다.
        guard lifecycle.requestStop() else { return }
        publishCaptureReadiness(false)
        roomCaptureView.captureSession.stop()
    }

    func capturePhoto(from roomCaptureView: RoomCaptureView) {
        guard lifecycle.canFinish else {
            parent.triggerCapture = false
            return
        }
        guard let currentFrame = roomCaptureView.captureSession.arSession.currentFrame else {
            DispatchQueue.main.async {
                self.parent.triggerCapture = false
            }
            return
        }

        let pixelBuffer = currentFrame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let orientedImage = ciImage.oriented(.right)
        let context = CIContext()
        if let cgImage = context.createCGImage(orientedImage, from: orientedImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.parent.onPhotoCaptured(uiImage)
                self.parent.triggerCapture = false
            }
        } else {
            DispatchQueue.main.async {
                self.parent.triggerCapture = false
            }
        }
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didStartWith configuration: RoomCaptureSession.Configuration
    ) {
        lifecycle.sessionDidStart()
    }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        guard parent.isScanning else { return }
        lifecycle.sessionDidUpdate()
        publishCaptureReadiness(lifecycle.canFinish)
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: Error?
    ) {
        lifecycle.sessionDidEnd()
        publishCaptureReadiness(false)
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            parent.onError(error)
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            parent.onError(error)
            return
        }
        parent.onScanCompleted(processedResult)
    }

    private func publishCaptureReadiness(_ isReady: Bool) {
        guard parent.isCaptureReady != isReady else { return }
        DispatchQueue.main.async { [weak self] in
            self?.parent.isCaptureReady = isReady
        }
    }
}
