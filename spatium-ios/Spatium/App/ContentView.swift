import SwiftUI
import RoomPlan
import UIKit

/// 앱 진입 게이트. 로그인 상태(또는 게스트 선택) 전에는 로그인 화면을 먼저 보여주고,
/// 통과하면 메인 탭 화면으로 전환합니다. 로그아웃하면 다시 로그인 화면으로 돌아옵니다.
struct ContentView: View {
    let userFurnitureStore: UserFurnitureStore
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

        if arguments.contains("-UITestScanKeyboardHeader") {
            ScanKeyboardHeaderUITestHost()
        } else if arguments.contains("-UITestRoomAddFlow") {
            RoomAddFlowUITestHost()
        } else if arguments.contains("-UITestDetectedItems") {
            DetectedItemsUITestHost()
        } else if arguments.contains("-UITestScanSaveReminder") {
            ScanEditorSaveReminderUITestHost(
                isGuestMode: arguments.contains("-UITestGuestMode")
            )
        } else if arguments.contains("-UITestScanPreparation") {
            // 실제 하단 시트 높이와 고정 CTA까지 RoomPlan 지원 여부와 무관하게 검증한다.
            ScanPreparationUITestHost()
        } else if arguments.contains("-UITestOnboardingFlow") {
            OnboardingFlowUITestHost()
        } else if arguments.contains("-UITestOnboarding") {
            // 가로모드·큰 글씨 검증용: 저장된 첫 실행 여부와 무관하게 온보딩을 바로 연다.
            OnboardingView(onFinished: {})
        } else if arguments.contains("-UITestLogin") {
            LoginView(onLoggedIn: {}, onContinueAsGuest: {})
        } else if arguments.contains("-UITestEditor"),
           let scan = testScan,
           let test = scan.load() {
            // 스크린샷 검증용: 로그인 없이 내장 테스트 스캔으로 3D 에디터를 바로 연다.
            RoomEditorView(
                scanItems: test.items,
                roomName: scan.roomName,
                usdzURL: test.usdzURL,
                area: scan.area,
                ceilingHeight: scan.ceilingHeight,
                projectID: arguments.contains("-UITestEditorInitialSave") ? "project-ui-test" : nil,
                projectName: arguments.contains("-UITestEditorInitialSave") ? "UI 테스트 프로젝트" : nil
            )
        } else if ProcessInfo.processInfo.arguments.contains("-UITestSettings")
                    || ProcessInfo.processInfo.arguments.contains("-UITestHome")
                    || ProcessInfo.processInfo.arguments.contains("-UITestImgTo3D")
                    || ProcessInfo.processInfo.arguments.contains("-UITestGuestRestrictions")
                    || ProcessInfo.processInfo.arguments.contains("-UITestGuestCreate") {
            // 스크린샷 검증용: 로그인 게이트를 건너뛰고 메인 탭(설정·홈·가구만들기)으로 바로 진입.
            MainTabView(userFurnitureStore: userFurnitureStore)
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
                MainTabView(userFurnitureStore: userFurnitureStore)
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

#if DEBUG
/// UI 테스트가 준비 화면을 전체 화면 뷰가 아닌 실제 presentation detent로 검증하도록 한다.
private struct ScanPreparationUITestHost: View {
    @State private var showsPreparation = false

    var body: some View {
        SpatiumTheme.background
            .ignoresSafeArea()
            .task {
                showsPreparation = true
            }
            .sheet(isPresented: $showsPreparation) {
                ScanPreparationSheet(onStart: {})
            }
    }
}

private struct RoomAddFlowUITestHost: View {
    @State private var showsFlow = false

    var body: some View {
        SpatiumTheme.background
            .ignoresSafeArea()
            .task { showsFlow = true }
            .sheet(isPresented: $showsFlow) {
                RoomAddFlowSheet(
                    projectName: "UI 테스트 프로젝트",
                    canUploadFiles: true,
                    onChooseScan: {},
                    onRequestLogin: {},
                    onUpload: { _, _, _ in }
                )
            }
    }
}

private struct ScanEditorSaveReminderUITestHost: View {
    let isGuestMode: Bool
    @State private var showsReminder = false

    var body: some View {
        SpatiumTheme.background
            .ignoresSafeArea()
            .task { showsReminder = true }
            .sheet(isPresented: $showsReminder) {
                ScanEditorSaveReminderSheet(isGuestMode: isGuestMode, onContinue: {})
            }
    }
}

private struct DetectedItemsUITestHost: View {
    @State private var items = (1...8).map { index in
        EditableScanItem(
            userAddedNamed: "감지 요소 \(index)",
            width: Double(index) * 0.1,
            height: 0.8,
            depth: 0.5
        )
    }

    var body: some View {
        ScrollView {
            DetectedItemsCard(items: $items)
                .padding(18)
        }
        .background(SpatiumTheme.background.ignoresSafeArea())
    }
}

/// 키보드가 올라온 세로 화면에서도 iOS 26 safe-area bar가 상태바 위로 밀리지 않는지 검증한다.
private struct ScanKeyboardHeaderUITestHost: View {
    @State private var selectedTab: AppTab = .scan
    @State private var roomName = ""
    @FocusState private var roomNameFocused: Bool

    var body: some View {
        ZStack {
            ModernBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("이름 없는 공간")
                            .font(.title2.weight(.black))
                        Text("15개 요소")
                            .foregroundStyle(SpatiumTheme.soft)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("방 정보")
                                .font(.headline)

                            TextField("예: 침실, 거실, 주방, 서재", text: $roomName)
                                .focused($roomNameFocused)
                                .padding(12)
                                .background(SpatiumTheme.elevatedSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SpatiumRadius.sm)
                                        .stroke(SpatiumTheme.border, lineWidth: 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
                                .accessibilityIdentifier("scan-room-name-field")

                            Text("입력한 값은 metadata JSON 파일의 roomType으로 함께 전송됩니다.")
                                .font(.footnote)
                                .foregroundStyle(SpatiumTheme.soft)
                        }
                    }

                    ForEach(0..<5, id: \.self) { index in
                        Text("감지 요소 \(index + 1)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(SpatiumTheme.surface, in: RoundedRectangle(cornerRadius: SpatiumRadius.md))
                    }
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .spatiumHeaderBar(selectedTab: selectedTab)
            .spatiumFooterBar(selectedTab: $selectedTab)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-UITestAutoKeyboard") else { return }
            try? await Task.sleep(for: .milliseconds(350))
            roomNameFocused = true
        }
    }
}

private struct OnboardingFlowUITestHost: View {
    @State private var finishedOnboarding = false

    var body: some View {
        if finishedOnboarding {
            LoginView(onLoggedIn: {}, onContinueAsGuest: {})
        } else {
            OnboardingView {
                finishedOnboarding = true
            }
        }
    }
}
#endif

struct MainTabView: View {
    @StateObject private var projectStore = ProjectStore()
    let userFurnitureStore: UserFurnitureStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var showScanPreparation = false
    @State private var shouldOpenScannerAfterPreparationDismiss = false
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

            // iOS 26의 safeAreaBar가 헤더·푸터의 안전 영역과 스크롤 경계 효과를
            // 직접 관리한다. 콘텐츠를 수동으로 겹치거나 마스킹하지 않아 큰 카드가
            // 헤더 주변에서 잘린 박스처럼 보이지 않는다.
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
                .scrollDismissesKeyboard(.interactively)
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
            .spatiumHeaderBar(selectedTab: selectedTab)
            .spatiumFooterBar(selectedTab: $selectedTab)
            // 키보드 안전영역이 iOS 26 safeAreaBar까지 압축하면 상단 헤더가 상태바와
            // 겹친다. 메인 크롬은 기기 안전영역에 고정하고, 입력 화면은 ScrollView로
            // 키보드 위 콘텐츠 접근과 대화형 닫기를 처리한다.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .fullScreenCover(isPresented: $showNewProjectSheet, onDismiss: {
            if shouldStartScanAfterProjectSheetDismiss {
                shouldStartScanAfterProjectSheetDismiss = false
                startNewScan()
            }
        }) {
            NewProjectSheet(onCreate: handleProjectCreated)
        }
        .sheet(
            isPresented: $showScanPreparation,
            onDismiss: {
                guard shouldOpenScannerAfterPreparationDismiss else { return }
                shouldOpenScannerAfterPreparationDismiss = false
                beginRoomScan()
            }
        ) {
            ScanPreparationSheet {
                shouldOpenScannerAfterPreparationDismiss = true
            }
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
        .task(id: tokenStore.accessToken, priority: .utility) {
            guard tokenStore.accessToken != nil else { return }
            // 콜드 실행 첫 프레임에서 프로젝트·프로필 복원과 가구 카탈로그 동기화가
            // 한꺼번에 화면을 갱신하지 않도록, 홈이 안정된 뒤 서버 동기화를 시작한다.
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
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
                isLoggedIn: tokenStore.isLoggedIn,
                // 가구 만들기 탭에서는 홈이 opacity 0으로 계층에 남는다. 숨겨진 동안
                // 반복 애니메이션이 CPU/GPU를 계속 쓰지 않도록 실제 표시 여부를 내려준다.
                isActive: selectedTab == .home,
                onStartScan: startNewProjectFlow,
                onOpenRooms: { selectedTab = .rooms },
                onOpenSettings: { selectedTab = .settings },
                onLogin: { showGuestLogin = true },
                onOpenProject: { project in
                    openProject(project)
                    selectedTab = .rooms
                }
            )
        case .rooms:
            roomsScreen
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

    @ViewBuilder
    private var roomsScreen: some View {
        ZStack(alignment: .topLeading) {
            if let project = projectStore.project(withID: selectedProjectID) {
                ProjectDetailView(
                    project: project,
                    onBack: closeProject,
                    onAddRoom: { startScan(for: project) },
                    onUploadRoom: { roomName, jsonURL, usdzURL in
                        guard tokenStore.isLoggedIn else {
                            throw RoomFileUploadFlowError.loginRequired
                        }
                        guard !project.id.hasPrefix("local-") else {
                            throw RoomFileUploadFlowError.localProject
                        }
                        let itemCount = await UploadFilePreparation.roomItemCount(at: jsonURL)
                        _ = try await projectStore.uploadRoom(
                            projectID: project.id,
                            replacingLocalRoomID: nil,
                            roomName: roomName,
                            metadataURL: jsonURL,
                            usdzURL: usdzURL,
                            itemCount: itemCount,
                            photoCount: 0
                        )
                        activeProjectID = project.id
                    },
                    canUploadRoomFiles: tokenStore.isLoggedIn && !project.id.hasPrefix("local-"),
                    onRequestLogin: {
                        if tokenStore.isLoggedIn {
                            flowErrorMessage = RoomFileUploadFlowError.localProject.localizedDescription
                        } else {
                            showGuestLogin = true
                        }
                    },
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
                            closeProject()
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
                .id("project-detail-\(project.id)")
                .transition(projectDetailTransition)
                .zIndex(1)
            } else {
                ProjectListWithUserFurniture(
                    projects: projectStore.projects,
                    userFurnitureStore: userFurnitureStore,
                    onCreateProject: startNewProjectFlow,
                    onOpenProject: openProject
                )
                .id("project-list")
                .transition(projectListTransition)
                .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(projectNavigationAnimation, value: selectedProjectID)
        .animation(
            projectNavigationAnimation,
            value: projectStore.project(withID: selectedProjectID) != nil
        )
    }

    private var projectListTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .leading).combined(with: .opacity)
    }

    private var projectDetailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .trailing).combined(with: .opacity)
    }

    private var projectNavigationAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private func openProject(_ project: SpatiumProject) {
        withAnimation(projectNavigationAnimation) {
            selectedProjectID = project.id
        }
        Task { await projectStore.loadRooms(projectID: project.id) }
    }

    private func closeProject() {
        withAnimation(projectNavigationAnimation) {
            selectedProjectID = nil
        }
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
        shouldOpenScannerAfterPreparationDismiss = false
        showScanPreparation = true
    }

    private func beginRoomScan() {
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

/// 가구 스토어의 변경 구독을 실제로 가구 목록을 표시하는 프로젝트 탭에만 한정합니다.
/// 서버 카탈로그가 갱신돼도 홈 전체가 다시 계산되지 않고 이 작은 경계만 갱신됩니다.
private struct ProjectListWithUserFurniture: View {
    let projects: [SpatiumProject]
    @ObservedObject var userFurnitureStore: UserFurnitureStore
    var onCreateProject: () -> Void
    var onOpenProject: (SpatiumProject) -> Void

    var body: some View {
        ProjectListView(
            projects: projects,
            userFurniture: userFurnitureStore.items,
            onCreateProject: onCreateProject,
            onOpenProject: onOpenProject,
            onDeleteFurniture: { furniture in
                try await userFurnitureStore.delete(furniture)
            }
        )
    }
}

private extension View {
    /// iOS 26은 상단 크롬을 네이티브 safe-area bar로 등록해 스크롤 콘텐츠의
    /// 배치·굴절·soft edge를 시스템에 맡긴다. 이전 버전은 Material 헤더를
    /// 일반 safe-area inset으로 배치한다.
    @ViewBuilder
    func spatiumHeaderBar(selectedTab: AppTab) -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaBar(edge: .top, spacing: 6) {
                    AppHeader(selectedTab: selectedTab)
                }
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) {
                AppHeader(selectedTab: selectedTab)
            }
        }
    }

    /// iOS 26의 커스텀 하단 바로 등록해 스크롤 콘텐츠가 풋터 아래에서 바로 잘리거나
    /// 글자 형태로 선명하게 비치지 않고 부드러운 blur 경계로 사라지게 한다.
    @ViewBuilder
    func spatiumFooterBar(selectedTab: Binding<AppTab>) -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    AppFooter(selectedTab: selectedTab)
                }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                AppFooter(selectedTab: selectedTab)
            }
        }
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

private enum RoomFileUploadFlowError: LocalizedError {
    case loginRequired
    case localProject

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            "USDZ와 JSON을 서버에 저장하려면 로그인이 필요해요."
        case .localProject:
            "게스트로 만든 로컬 프로젝트에는 파일을 업로드할 수 없어요. 로그인 후 서버 프로젝트를 새로 만들어주세요."
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
        // 컨테이너를 하나의 접근성 요소 그룹으로 유지해 식별자가 자식들로
        // 흩어지지 않게 한다 (UI 테스트가 otherElements로 카드를 찾는다).
        .accessibilityElement(children: .contain)
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
    let userFurnitureStore = UserFurnitureStore()
    ContentView(userFurnitureStore: userFurnitureStore)
        .environmentObject(userFurnitureStore)
}
