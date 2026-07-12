import ARKit
import CoreImage
import RoomPlan
import SwiftUI
import UIKit

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var triggerCapture: Bool
    var onPhotoCaptured: (UIImage) -> Void
    var onScanCompleted: (CapturedRoom) -> Void
    var onError: (Error) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let roomCaptureView = RoomCaptureView(frame: .zero)
        roomCaptureView.delegate = context.coordinator
        return roomCaptureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
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

final class RoomCaptureViewCoordinator: NSObject, RoomCaptureViewDelegate {
    var parent: RoomCaptureViewRepresentable
    private var isSessionRunning = false

    init(_ parent: RoomCaptureViewRepresentable) {
        self.parent = parent
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func encode(with coder: NSCoder) {}

    func startSessionIfNeeded(for roomCaptureView: RoomCaptureView) {
        guard !isSessionRunning else { return }
        let config = RoomCaptureSession.Configuration()
        roomCaptureView.captureSession.run(configuration: config)
        isSessionRunning = true
    }

    func stopSessionIfNeeded(for roomCaptureView: RoomCaptureView) {
        guard isSessionRunning else { return }
        roomCaptureView.captureSession.stop()
        isSessionRunning = false
    }

    func capturePhoto(from roomCaptureView: RoomCaptureView) {
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
}
