import SwiftUI
import RoomPlan
import UIKit

/// 앱 진입 게이트. 로그인 상태(또는 게스트 선택) 전에는 로그인 화면을 먼저 보여주고,
/// 통과하면 메인 탭 화면으로 전환합니다. 로그아웃하면 다시 로그인 화면으로 돌아옵니다.
struct ContentView: View {
    @ObservedObject private var tokenStore = AuthTokenStore.shared
    @State private var isGuestSession = false
    /// 첫 실행 온보딩을 봤는지 여부. 한 번 완료(또는 건너뛰기)하면 다시 보여주지 않는다.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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

        if arguments.contains("-UITestOnboarding") {
            // 가로모드·큰 글씨 검증용: 저장된 첫 실행 여부와 무관하게 온보딩을 바로 연다.
            OnboardingView(onFinished: {})
        } else if arguments.contains("-UITestEditor"),
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
                    || ProcessInfo.processInfo.arguments.contains("-UITestImgTo3D")
                    || ProcessInfo.processInfo.arguments.contains("-UITestGuestRestrictions")
                    || ProcessInfo.processInfo.arguments.contains("-UITestGuestCreate") {
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
            if !hasSeenOnboarding {
                // 첫 실행: 로그인보다 먼저 기능 소개 온보딩을 보여준다.
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasSeenOnboarding = true
                    }
                }
                .transition(.opacity)
            } else if tokenStore.isLoggedIn || isGuestSession {
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
    @EnvironmentObject private var userFurnitureStore: UserFurnitureStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject private var tokenStore = AuthTokenStore.shared
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
    @State private var scanReturnTab: AppTab = .home
    @State private var flowErrorMessage: String?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var exporting = false
    @State private var uploading = false
    @State private var isRefreshing = false
    @State private var exportError: String?
    @State private var uploadMessage: String?
    @State private var guestRestriction: GuestRestrictedAction?
    @State private var showGuestLogin = false

    private var usesCompactHeight: Bool {
        verticalSizeClass == .compact
    }

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
                    .padding(.horizontal, usesCompactHeight ? 14 : 18)
                    .padding(.top, usesCompactHeight ? 10 : 18)
                    .padding(.bottom, usesCompactHeight ? 16 : 28)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await refreshVisibleContent()
                }
                .opacity(selectedTab == .imgTo3D ? 0 : 1)
                .scaleEffect(selectedTab == .imgTo3D ? 0.97 : 1)
                .allowsHitTesting(selectedTab != .imgTo3D)

                Group {
                    if showsGuestRestrictions {
                        GuestFeatureRestrictionView(
                            title: "가구 만들기는 로그인이 필요해요",
                            message: "게스트 모드에서는 AI 배경 제거와 3D 모델 생성을 사용할 수 없어요. 로그인 후 이용해 주세요.",
                            onLogin: { showGuestLogin = true }
                        )
                    } else {
                        ImgTo3DView(isActive: selectedTab == .imgTo3D) {
                            selectedProjectID = nil
                            selectedTab = .rooms
                        }
                    }
                }
                    .frame(
                        maxWidth: usesCompactHeight ? .infinity : 520,
                        maxHeight: .infinity
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, usesCompactHeight ? 10 : 12)
                    .padding(.vertical, usesCompactHeight ? 5 : 8)
                    .opacity(selectedTab == .imgTo3D ? 1 : 0)
                    .scaleEffect(selectedTab == .imgTo3D ? 1 : 0.97)
                    .allowsHitTesting(selectedTab == .imgTo3D)
            }
            .animation(tabContentAnimation, value: selectedTab)
            .onChange(of: selectedTab) { _, newValue in
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                if newValue != .imgTo3D {
                    // 실제 중앙 콘텐츠는 selectedTab이 아니라 scrollContentTab으로
                    // 결정된다. 이 상태 변경도 같은 트랜잭션에서 애니메이션해야
                    // 프로젝트·스캔 등 스크롤 탭 사이의 transition이 하드 컷이 되지 않는다.
                    withAnimation(tabContentAnimation) {
                        scrollContentTab = newValue
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppFooter(selectedTab: $selectedTab)
            }
            // 가구 만들기 탭은 입력 필드가 화면 위쪽에 있어 키보드에 맞춰
            // 전체 화면과 푸터를 압축하지 않는다. 입력 모달은 fullScreenCover가
            // 자체 안전영역을 관리한다.
            .ignoresSafeArea(.keyboard, edges: selectedTab == .imgTo3D ? .bottom : [])
            .safeAreaInset(edge: .top, spacing: 0) {
                AppHeader(selectedTab: selectedTab)
            }
        }
        .fullScreenCover(isPresented: $showNewProjectSheet, onDismiss: {
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
                onCompleted: { room in
                    let project = ScanProject(room: room)
                    scanProject = project
                    selectedTab = .scan
                    isScanning = false
                    showScanner = false
                    registerRoom(for: project)
                },
                onError: { error in
                    flowErrorMessage = "스캔 실패: \(error.localizedDescription)"
                    isScanning = false
                    showScanner = false
                    selectedTab = scanReturnTab
                },
                onCancel: {
                    isScanning = false
                    showScanner = false
                    selectedTab = scanReturnTab
                }
            )
        }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupSharedFiles) {
            ShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showGuestLogin) {
            LoginView(onLoggedIn: {
                showGuestLogin = false
            })
        }
        .tint(SpatiumTheme.accent)
        .task(id: tokenStore.accessToken) {
            await userFurnitureStore.refreshFromBackend()
        }
        .alert(
            activeErrorTitle,
            isPresented: Binding(
                get: { activeErrorMessage != nil },
                set: { isPresented in
                    guard !isPresented else { return }
                    dismissActiveError()
                }
            )
        ) {
            if isShowingLocalPersistenceError {
                Button("다시 시도") {
                    // Alert가 먼저 닫힌 다음 재시도 결과를 반영해야, 다시 실패했을 때
                    // 동일한 경고와 재시도 버튼이 정상적으로 다시 나타난다.
                    Task { @MainActor in
                        await Task.yield()
                        _ = await projectStore.retryLocalPersistence()
                    }
                }
            }
            // 실제 상태 정리는 alert binding의 dismiss 경로에서 한 번만 수행한다.
            Button(isShowingLocalPersistenceError ? "나중에" : "확인", role: .cancel) {}
        } message: {
            Text(activeErrorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
        .alert(item: $guestRestriction) { restriction in
            Alert(
                title: Text(restriction.title),
                message: Text(restriction.message),
                primaryButton: .default(Text("로그인")) {
                    showGuestLogin = true
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-UITestSettings") {
                selectedTab = .settings
            }
            if ProcessInfo.processInfo.arguments.contains("-UITestImgTo3D") {
                selectedTab = .imgTo3D
            }
            if ProcessInfo.processInfo.arguments.contains("-UITestGuestRestrictions") {
                selectedTab = .imgTo3D
            }
            // 게스트 프로젝트 생성 크래시 재현용: 게스트 상태로 로컬 프로젝트를 자동 생성한다.
            if ProcessInfo.processInfo.arguments.contains("-UITestGuestCreate") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    selectedTab = .rooms
                    _ = try? await projectStore.createProject(name: "게스트 테스트 프로젝트")
                    try? await Task.sleep(for: .milliseconds(500))
                    _ = try? await projectStore.createProject(name: "게스트 테스트 프로젝트 2")
                }
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

    private var activeErrorMessage: String? {
        flowErrorMessage
            ?? projectStore.localPersistenceErrorMessage
            ?? projectStore.lastErrorMessage
    }

    private var showsGuestRestrictions: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGuestRestrictions") {
            return true
        }
        // 기존 가구 만들기 UI 테스트는 네트워크 없이 단계별 화면을 직접 검증한다.
        if ProcessInfo.processInfo.arguments.contains("-UITestImgTo3D") {
            return false
        }
        #endif
        return !tokenStore.isLoggedIn
    }

    private var isShowingLocalPersistenceError: Bool {
        flowErrorMessage == nil && projectStore.localPersistenceErrorMessage != nil
    }

    private var activeErrorTitle: String {
        isShowingLocalPersistenceError
            ? "기기에 저장하지 못했습니다"
            : "요청을 완료하지 못했습니다"
    }

    /// 동시에 여러 오류가 발생해도 현재 표시 중인 오류만 닫아 다음 오류가 이어서 보이게 한다.
    private func dismissActiveError() {
        if flowErrorMessage != nil {
            flowErrorMessage = nil
        } else if projectStore.localPersistenceErrorMessage != nil {
            projectStore.dismissLocalPersistenceError()
        } else {
            projectStore.lastErrorMessage = nil
        }
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
                    onDeleteProject: {
                        let projectID = project.id
                        Task {
                            await projectStore.deleteProject(projectID: projectID)
                            guard projectStore.project(withID: projectID) == nil else { return }
                            selectedProjectID = nil
                            if activeProjectID == projectID {
                                activeProjectID = nil
                                activeRoomID = nil
                                scanProject = nil
                            }
                        }
                    },
                    onDeleteRoom: { room in
                        Task { await projectStore.deleteRoom(roomID: room.id, projectID: project.id) }
                    }
                )
            } else {
                ProjectListView(
                    projects: projectStore.projects,
                    userFurniture: userFurnitureStore.items,
                    onCreateProject: startNewProjectFlow,
                    onOpenProject: { project in
                        selectedProjectID = project.id
                        Task { await projectStore.loadRooms(projectID: project.id) }
                    },
                    onDeleteFurniture: { furniture in
                        try await userFurnitureStore.delete(furniture)
                    }
                )
            }
        case .scan:
            if let scanProjectValue = scanProject {
                // Binding($scanProject) 강제 언래핑 바인딩은 리뷰 화면이 떠 있는 동안
                // scanProject가 nil이 되면 크래시한다. 마지막 값으로 폴백하는 안전한 바인딩 사용.
                ScanReviewView(
                    project: Binding(
                        get: { scanProject ?? scanProjectValue },
                        set: { scanProject = $0 }
                    ),
                    projectID: activeProjectID,
                    projectName: activeProjectID.flatMap { projectStore.project(withID: $0)?.resolvedName },
                    exporting: exporting,
                    uploading: uploading,
                    exportError: exportError,
                    uploadMessage: uploadMessage,
                    isGuestMode: !tokenStore.isLoggedIn,
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

    /// 홈·프로젝트·스캔·설정 탭의 공통 당겨서 새로고침 동작.
    /// 화면별로 서로 다른 캐시가 남지 않도록 프로젝트, 가구, 프로필을 함께 갱신하고
    /// 프로젝트 상세 화면에서는 선택한 프로젝트의 방 목록까지 다시 불러온다.
    private func refreshVisibleContent() async {
        // 빠르게 여러 번 당겨도 동일한 동기화 작업과 보류 중인 가구 업로드가
        // 중복 실행되지 않도록 한 번의 새로고침만 허용한다.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 당겨서 새로고침은 캐시를 유지하는 비차단 동작이다. 일시적인 네트워크
        // 실패를 전역 오류 팝업으로 바꾸지 않고 현재 화면의 데이터를 그대로 둔다.
        async let projects: Void = projectStore.refresh(silently: true)
        async let furniture: Void = userFurnitureStore.refreshFromBackend()
        async let profile: Void = CurrentUserStore.shared.refresh()
        _ = await (projects, furniture, profile)

        guard scrollContentTab == .rooms,
              let selectedProjectID,
              projectStore.project(withID: selectedProjectID) != nil else {
            return
        }
        await projectStore.loadRooms(projectID: selectedProjectID, silently: true)
    }

    private func startNewProjectFlow() {
        shouldStartScanAfterProjectSheetDismiss = false
        showNewProjectSheet = true
    }

    private func handleProjectCreated(name: String) async throws {
        let project = try await projectStore.createProject(name: name)
        activeProjectID = project.id
        selectedProjectID = project.id
        shouldStartScanAfterProjectSheetDismiss = true
    }

    private func startScan(for project: SpatiumProject) {
        activeProjectID = project.id
        startNewScan()
    }

    private func startNewScan() {
        guard RoomCaptureSession.isSupported else {
            flowErrorMessage = "이 기기는 RoomPlan 방 스캔을 지원하지 않아요. LiDAR가 탑재된 iPhone 또는 iPad에서 다시 시도해 주세요."
            return
        }
        scanReturnTab = selectedTab
        // 주의: 여기서 scanProject를 nil로 만들면 안 된다. 리뷰 화면(ScanReviewView)이
        // Binding($scanProject) 강제 언래핑 바인딩을 들고 있어서, "다시 스캔"을 누르는 순간
        // nil을 읽으며 EXC_BREAKPOINT로 크래시한다. 기존 스캔은 새 스캔이 "완료"될 때
        // onCompleted에서 교체된다 — 덕분에 다시 스캔을 취소해도 이전 스캔이 유지된다.
        exportError = nil
        uploadMessage = nil
        isScanning = true
        showScanner = true
    }

    /// 스캔 직후 즉시 UI에 보여줄 로컬 룸을 만듭니다. 서버 룸은 업로드 시점에 파일과 함께 생성됩니다.
    /// "다시 스캔"이면 이전 스캔의 로컬 placeholder를 교체해 목록에 중복으로 쌓이지 않게 합니다.
    private func registerRoom(for project: ScanProject) {
        guard let activeProjectID else { return }
        let footprint = project.estimatedFootprint
        let record = projectStore.registerLocalRoom(
            projectID: activeProjectID,
            roomName: project.resolvedRoomType,
            area: footprint.width * footprint.depth,
            replacingLocalRoomID: activeRoomID
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
                shareItems = try await scanProject.exportPackage()
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
        adopted.photoCount = 0
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
        guard tokenStore.isLoggedIn else {
            guestRestriction = .scanUpload
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
                let urls = try await scanProject.exportPackage()
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
                    photoCount: 0
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

private enum GuestRestrictedAction: String, Identifiable {
    case scanUpload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanUpload: "게스트 모드에서는 업로드할 수 없어요"
        }
    }

    var message: String {
        switch self {
        case .scanUpload: "스캔 파일을 서버 프로젝트에 저장하려면 로그인이 필요해요. 파일 공유와 로컬 편집은 게스트 모드에서도 사용할 수 있습니다."
        }
    }
}

private struct GuestFeatureRestrictionView: View {
    let title: String
    let message: String
    var onLogin: () -> Void

    var body: some View {
        VStack {
            Card {
                VStack(spacing: 18) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(SpatiumTheme.accent)
                        .frame(width: 78, height: 78)
                        .background(SpatiumTheme.warmPanel, in: Circle())

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                            .multilineTextAlignment(.center)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(SpatiumTheme.soft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PrimaryButton(
                        title: "로그인하고 사용하기",
                        systemImage: "person.crop.circle.badge.checkmark",
                        action: onLogin
                    )
                }
                .padding(.vertical, 14)
            }
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("guest-img-to-3d-restriction")
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
        .environmentObject(UserFurnitureStore())
}
