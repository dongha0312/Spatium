import SwiftUI
import RoomPlan
import UIKit

/// 앱 진입 게이트. 로그인 상태(또는 게스트 선택) 전에는 로그인 화면을 먼저 보여주고,
/// 통과하면 메인 탭 화면으로 전환합니다. 로그아웃하면 다시 로그인 화면으로 돌아옵니다.
struct ContentView: View {
    @ObservedObject private var tokenStore = AuthTokenStore.shared
    @State private var isGuestSession = false

    var body: some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let requestedScanID: String? = {
            guard let index = arguments.firstIndex(of: "-UITestScan"),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }()
        let testScan = TestRoomData.scans.first(where: { $0.id == requestedScanID })
            ?? TestRoomData.scans.first

        if arguments.contains("-UITestEditor"),
           let scan = testScan,
           let test = scan.load() {
            // 스크린샷 검증용: 로그인 없이 내장 테스트 스캔으로 3D 에디터를 바로 연다.
            RoomEditorView(
                scanItems: test.items,
                roomName: scan.roomName,
                usdzURL: test.usdzURL,
                area: scan.area,
                ceilingHeight: scan.ceilingHeight
            )
        } else if ProcessInfo.processInfo.arguments.contains("-UITestSettings")
                    || ProcessInfo.processInfo.arguments.contains("-UITestHome")
                    || ProcessInfo.processInfo.arguments.contains("-UITestImgTo3D") {
            // 스크린샷 검증용: 로그인 게이트를 건너뛰고 메인 탭(설정·홈·가구만들기)으로 바로 진입.
            MainTabView()
        } else {
            gate
        }
        #else
        gate
        #endif
    }

    @ViewBuilder
    private var gate: some View {
        Group {
            if tokenStore.isLoggedIn || isGuestSession {
                MainTabView()
                    .transition(.opacity)
            } else {
                LoginView(
                    onLoggedIn: {},
                    onContinueAsGuest: { isGuestSession = true }
                )
                .transition(.opacity)
            }
        }
        .onChange(of: tokenStore.isLoggedIn) { _, newValue in
            if !newValue {
                isGuestSession = false
            }
        }
    }
}

struct MainTabView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var selectedTab: AppTab = .home
    /// 스크롤 컨테이너가 보여줄 탭. 가구 만들기(고정 레이아웃) 탭으로 가 있는 동안에는
    /// 마지막 스크롤 탭 화면을 유지해, 페이드 아웃 중에 내용이 사라지지 않게 한다.
    @State private var scrollContentTab: AppTab = .home
    @State private var selectedProjectID: String?
    @State private var activeProjectID: String?
    @State private var activeRoomID: String?
    @State private var showNewProjectSheet = false
    @State private var shouldStartScanAfterProjectSheetDismiss = false
    @State private var scanProject: ScanProject?
    @State private var showScanner = false
    @State private var isScanning = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var exporting = false
    @State private var uploading = false
    @State private var exportError: String?
    @State private var uploadMessage: String?

    var body: some View {
        ZStack {
            ModernBackground().ignoresSafeArea()

            // 가구 만들기(고정 레이아웃)와 나머지 탭(스크롤)을 if/else로 갈아끼우면
            // 분기 교체가 transition 없이 하드 컷으로 끝난다(프레임 캡처로 확인).
            // 두 컨테이너를 상시 겹쳐두고 opacity/scale로 전환해 다른 탭 간 이동과
            // 동일한 페이드+스케일을 보장한다. 부수 효과로 가구 만들기 진행 상태도
            // 탭을 오가도 유지된다.
            ZStack {
                ScrollView {
                    VStack(spacing: 18) {
                        screen(for: scrollContentTab)
                            .id(scrollContentTab)
                            .transition(tabContentTransition)
                    }
                    .id("main-screen-top")
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .opacity(selectedTab == .imgTo3D ? 0 : 1)
                .scaleEffect(selectedTab == .imgTo3D ? 0.97 : 1)
                .allowsHitTesting(selectedTab != .imgTo3D)

                ImgTo3DView()
                    .frame(maxWidth: 520, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .opacity(selectedTab == .imgTo3D ? 1 : 0)
                    .scaleEffect(selectedTab == .imgTo3D ? 1 : 0.97)
                    .allowsHitTesting(selectedTab == .imgTo3D)
            }
            .animation(tabContentAnimation, value: selectedTab)
            .onChange(of: selectedTab) { _, newValue in
                if newValue != .imgTo3D {
                    scrollContentTab = newValue
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                AppHeader(selectedTab: selectedTab)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppFooter(selectedTab: $selectedTab)
            }
            // 가구 만들기 탭: 입력 필드가 모두 화면 위쪽이라 키보드 회피가 필요 없고,
            // 키보드가 올라올 때 푸터가 따라 올라오며 카드가 찌그러지는 것을 막는다.
            // (다른 탭은 화면 아래쪽 필드가 있어 기본 키보드 회피를 유지)
            .ignoresSafeArea(.keyboard, edges: selectedTab == .imgTo3D ? .bottom : [])
        }
        .sheet(isPresented: $showNewProjectSheet, onDismiss: {
            if shouldStartScanAfterProjectSheetDismiss {
                shouldStartScanAfterProjectSheetDismiss = false
                startNewScan()
            }
        }) {
            NewProjectSheet(onCreate: handleProjectCreated)
        }
        .sheet(isPresented: $showScanner) {
            ScanCaptureSheet(
                isScanning: $isScanning,
                onCompleted: { room, photos in
                    let project = ScanProject(room: room, photos: photos)
                    scanProject = project
                    selectedTab = .scan
                    showScanner = false
                    registerRoom(for: project)
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
        .tint(SpatiumTheme.accent)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-UITestSettings") {
                selectedTab = .settings
            }
            if ProcessInfo.processInfo.arguments.contains("-UITestImgTo3D") {
                selectedTab = .imgTo3D
            }
            // 탭 전환 애니메이션 검증용: 앱 실행 후 자동으로 홈 → 가구만들기 → 스캔 순으로 전환한다.
            if ProcessInfo.processInfo.arguments.contains("-UITestTabToggle") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    selectedTab = .imgTo3D
                    try? await Task.sleep(for: .seconds(2))
                    selectedTab = .scan
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeDashboardView(
                projects: projectStore.projects,
                onStartScan: startNewProjectFlow,
                onOpenRooms: { selectedTab = .rooms },
                onOpenSettings: { selectedTab = .settings },
                onOpenProject: { project in
                    selectedProjectID = project.id
                    selectedTab = .rooms
                    Task { await projectStore.loadRooms(projectID: project.id) }
                }
            )
        case .rooms:
            if let project = projectStore.project(withID: selectedProjectID) {
                ProjectDetailView(
                    project: project,
                    onBack: { selectedProjectID = nil },
                    onAddRoom: { startScan(for: project) },
                    onRenameProject: { newName in
                        Task { await projectStore.renameProject(projectID: project.id, newName: newName) }
                    },
                    onRenameRoom: { room, newName in
                        Task { await projectStore.renameRoom(roomID: room.id, projectID: project.id, newName: newName) }
                    },
                    onDeleteRoom: { room in
                        Task { await projectStore.deleteRoom(roomID: room.id, projectID: project.id) }
                    }
                )
            } else {
                ProjectListView(
                    projects: projectStore.projects,
                    onCreateProject: startNewProjectFlow,
                    onOpenProject: { project in
                        selectedProjectID = project.id
                        Task { await projectStore.loadRooms(projectID: project.id) }
                    }
                )
            }
        case .scan:
            if let projectBinding = Binding($scanProject) {
                ScanReviewView(
                    project: projectBinding,
                    projectID: activeProjectID,
                    projectName: activeProjectID.flatMap { projectStore.project(withID: $0)?.resolvedName },
                    exporting: exporting,
                    uploading: uploading,
                    exportError: exportError,
                    uploadMessage: uploadMessage,
                    onStartScan: startNewScan,
                    onExport: exportScanPackage,
                    onUpload: uploadScanPackage,
                    onOpenSettings: { selectedTab = .settings },
                    onRoomUploaded: handleEditorCreatedRoom
                )
            } else {
                EmptyScanView(onStartScan: startNewProjectFlow)
            }
        case .imgTo3D:
            // 가구 만들기는 스크롤 컨테이너가 아니라 body의 상시 레이어로 렌더링된다.
            EmptyView()
        case .settings:
            SettingsView()
        }
    }

    private var tabContentTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }

    private var tabContentAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.85)
    }

    private func startNewProjectFlow() {
        shouldStartScanAfterProjectSheetDismiss = false
        showNewProjectSheet = true
    }

    private func handleProjectCreated(name: String) async {
        let project = await projectStore.createProject(name: name)
        activeProjectID = project.id
        selectedProjectID = project.id
        shouldStartScanAfterProjectSheetDismiss = true
    }

    private func startScan(for project: SpatiumProject) {
        activeProjectID = project.id
        startNewScan()
    }

    private func startNewScan() {
        scanProject = nil
        activeRoomID = nil
        exportError = nil
        uploadMessage = nil
        isScanning = true
        showScanner = true
    }

    /// 스캔 직후 즉시 UI에 보여줄 로컬 룸을 만듭니다. 서버 룸은 업로드 시점에 파일과 함께 생성됩니다.
    private func registerRoom(for project: ScanProject) {
        guard let activeProjectID else { return }
        let footprint = project.estimatedFootprint
        let record = projectStore.registerLocalRoom(
            projectID: activeProjectID,
            roomName: project.resolvedRoomType,
            area: footprint.width * footprint.depth
        )
        activeRoomID = record.id
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

    /// 3D 에디터가 저장하며 서버 룸을 새로 만들었을 때: 로컬 placeholder를 서버 룸으로 교체하고
    /// activeRoomID를 갱신해, 같은 스캔이 "서버로 업로드"로 중복 생성되지 않게 한다.
    private func handleEditorCreatedRoom(_ room: RoomRecord) {
        var adopted = room
        adopted.itemCount = scanProject?.items.count ?? 0
        adopted.photoCount = scanProject?.photos.count ?? 0
        if let activeProjectID {
            projectStore.adoptUploadedRoom(adopted, projectID: activeProjectID, replacingLocalRoomID: activeRoomID)
        }
        activeRoomID = adopted.id
        uploadMessage = "3D 에디터에서 저장되어 서버에 업로드되었습니다."
    }

    private func uploadScanPackage() {
        guard let scanProject else { return }
        guard let activeProjectID else {
            uploadMessage = "먼저 프로젝트를 선택/생성해 주세요."
            return
        }
        // 이미 서버 룸이 된 스캔(에디터 저장 또는 이전 업로드)은 다시 올리면 중복 룸이 생긴다.
        if let activeRoomID, !activeRoomID.hasPrefix("local-") {
            uploadMessage = "이미 서버에 저장된 스캔입니다."
            return
        }

        uploading = true
        exportError = nil
        uploadMessage = nil

        Task {
            do {
                let urls = try scanProject.exportPackage()
                guard let usdzURL = urls.first(where: { $0.pathExtension.lowercased() == "usdz" }),
                      let jsonURL = urls.first(where: { $0.pathExtension.lowercased() == "json" }) else {
                    uploadMessage = "업로드할 USDZ 또는 JSON 파일을 찾지 못했습니다."
                    uploading = false
                    return
                }

                // 백엔드 룸 생성은 파일과 함께하는 multipart 한 번으로 처리됩니다.
                let room = try await projectStore.uploadRoom(
                    projectID: activeProjectID,
                    replacingLocalRoomID: activeRoomID,
                    roomName: scanProject.resolvedRoomType,
                    metadataURL: jsonURL,
                    usdzURL: usdzURL,
                    itemCount: scanProject.items.count,
                    photoCount: scanProject.photos.count
                )
                activeRoomID = room.id
                selectedProjectID = activeProjectID

                uploadMessage = "룸이 저장되었습니다."
                uploading = false
                Haptics.success()
                selectedTab = .rooms
            } catch {
                uploadMessage = "업로드 실패: \(error.localizedDescription)"
                uploading = false
                Haptics.error()
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

private struct ModernBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                SpatiumTheme.background,
                SpatiumTheme.backgroundGradientMid,
                SpatiumTheme.backgroundGradientEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    ContentView()
}
