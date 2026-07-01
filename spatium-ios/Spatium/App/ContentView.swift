import SwiftUI
import RoomPlan
import UIKit

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var scanProject: ScanProject?
    @State private var showScanner = false
    @State private var isScanning = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var exporting = false
    @State private var uploading = false
    @State private var exportError: String?
    @State private var uploadMessage: String?
    @State private var showPreview = false
    @State private var previewURL: URL?
    @State private var uploadedRooms: [RoomRecord] = []
    @State private var apiEndpoint = "http://210.119.12.115:8080/api/models"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SpatiumTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    AppHeader()

                    ScrollView {
                        VStack(spacing: 18) {
                            currentScreen
                        }
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }

                    AppFooter(selectedTab: $selectedTab)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showScanner) {
                ScanCaptureSheet(
                    isScanning: $isScanning,
                    onCompleted: { room, photos in
                        scanProject = ScanProject(room: room, photos: photos)
                        selectedTab = .scan
                        showScanner = false
                    },
                    onError: { error in
                        exportError = error.localizedDescription
                        selectedTab = .scan
                        showScanner = false
                    }
                )
            }
            .sheet(isPresented: $showShareSheet, onDismiss: cleanupSharedFiles) {
                ShareSheet(activityItems: shareItems)
            }
            .sheet(isPresented: $showPreview) {
                if let url = previewURL {
                    ARQuickLookView(fileURL: url) {
                        showPreview = false
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedTab {
        case .home:
            HomeDashboardView(
                uploadedRooms: uploadedRooms,
                onStartScan: startNewScan,
                onOpenRooms: { selectedTab = .rooms }
            )
        case .rooms:
            RoomsView(
                rooms: uploadedRooms,
                onStartScan: startNewScan
            )
        case .scan:
            if let projectBinding = Binding($scanProject) {
                ScanReviewView(
                    project: projectBinding,
                    endpoint: apiEndpoint,
                    exporting: exporting,
                    uploading: uploading,
                    exportError: exportError,
                    uploadMessage: uploadMessage,
                    onStartScan: startNewScan,
                    onPreview: previewScanResults,
                    onExport: exportScanPackage,
                    onUpload: uploadScanPackage,
                    onOpenSettings: { selectedTab = .settings }
                )
            } else {
                EmptyScanView(onStartScan: startNewScan)
            }
        case .settings:
            SettingsView(apiEndpoint: $apiEndpoint)
        }
    }

    private func startNewScan() {
        scanProject = nil
        exportError = nil
        uploadMessage = nil
        isScanning = true
        showScanner = true
    }

    private func previewScanResults() {
        guard let scanProject else { return }

        exporting = true
        exportError = nil

        Task {
            do {
                let urls = try scanProject.exportPackage()
                previewURL = urls.first { $0.lastPathComponent == "room-scan.usdz" }
                showPreview = previewURL != nil
                exporting = false
            } catch {
                exportError = error.localizedDescription
                exporting = false
            }
        }
    }

    private func exportScanPackage() {
        guard let scanProject else { return }

        exporting = true
        exportError = nil
        uploadMessage = nil

        Task {
            do {
                shareItems = try scanProject.exportPackage()
                showShareSheet = true
                exporting = false
            } catch {
                exportError = error.localizedDescription
                exporting = false
            }
        }
    }

    private func uploadScanPackage() {
        guard let scanProject else { return }
        guard let endpoint = URL(string: apiEndpoint), endpoint.scheme != nil, endpoint.host != nil else {
            uploadMessage = "서버 주소를 확인해 주세요."
            return
        }

        uploading = true
        exportError = nil
        uploadMessage = nil

        Task {
            do {
                // 저장/공유와 같은 결과물을 만든 뒤, 서버 API 명세의 파트 이름으로 업로드합니다.
                let urls = try scanProject.exportPackage()
                guard let usdzURL = urls.first(where: { $0.pathExtension.lowercased() == "usdz" }),
                      let jsonURL = urls.first(where: { $0.pathExtension.lowercased() == "json" }) else {
                    uploadMessage = "업로드할 USDZ 또는 JSON 파일을 찾지 못했습니다."
                    uploading = false
                    return
                }

                let response = try await ModelUploadService().uploadModel(
                    endpoint: endpoint,
                    metadataURL: jsonURL,
                    usdzFileURL: usdzURL
                )

                uploadedRooms.insert(
                    RoomRecord(
                        roomType: scanProject.resolvedRoomType,
                        itemCount: scanProject.items.count,
                        photoCount: scanProject.photos.count,
                        uploadedAt: Date(),
                        fileName: response.data?.fileName ?? usdzURL.lastPathComponent
                    ),
                    at: 0
                )
                uploadMessage = "\(response.statusCode): \(response.message)"
                uploading = false
                selectedTab = .rooms
            } catch {
                uploadMessage = "업로드 실패: \(error.localizedDescription)"
                uploading = false
            }
        }
    }

    private func cleanupSharedFiles() {
        for item in shareItems {
            guard let url = item as? URL else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        shareItems = []
    }
}

#Preview {
    ContentView()
}
