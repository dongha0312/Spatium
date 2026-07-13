import SwiftUI

struct ProjectDetailView: View {
    let project: SpatiumProject
    var onBack: () -> Void
    var onAddRoom: () -> Void
    var onRenameProject: (String) -> Void
    var onRenameRoom: (RoomRecord, String) -> Void
    var onDeleteProject: () -> Void
    var onDeleteRoom: (RoomRecord) -> Void

    @State private var renderingRoom: RoomRecord?
    @State private var isEditingProjectName = false
    @State private var editingRoom: RoomRecord?
    @State private var pendingRoomDeletion: RoomRecord?
    @State private var showProjectDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProjectDetailHeader(
                project: project,
                onBack: onBack,
                onEditName: {
                    isEditingProjectName = true
                },
                onDelete: { showProjectDeletion = true }
            )

            PrimaryButton(title: "이 프로젝트에 방 추가", systemImage: "camera.viewfinder", action: onAddRoom)

            if project.rooms.isEmpty {
                EmptyStateCard(
                    systemImage: "square.grid.2x2",
                    title: "아직 스캔한 방이 없습니다",
                    message: "위 버튼을 눌러 이 프로젝트의 첫 방을 스캔해 보세요."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("스캔된 방 (\(project.displayRoomCount)개)")
                            .font(.headline.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                        Spacer()
                        Text("탭하면 열고, 길게 누르면 수정합니다")
                            .font(.caption2)
                            .foregroundStyle(SpatiumTheme.soft)
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(project.rooms) { room in
                            EditableRoomRow(
                                room: room,
                                onOpen: {
                                    renderingRoom = room
                                },
                                onRename: {
                                    editingRoom = room
                                },
                                onDelete: {
                                    pendingRoomDeletion = room
                                }
                            )
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $renderingRoom) { room in
            RoomRenderLoaderView(room: room, projectID: project.id, projectName: project.resolvedName, rooms: project.rooms)
        }
        .sheet(isPresented: $isEditingProjectName) {
            NameEditSheet(
                title: "프로젝트 이름 수정",
                hint: "프로젝트 목록과 3D 에디터에 함께 표시됩니다",
                placeholder: "프로젝트 이름을 입력하세요",
                initialName: project.resolvedName,
                onSave: onRenameProject
            )
        }
        .sheet(item: $editingRoom) { room in
            NameEditSheet(
                title: "방 이름 수정",
                hint: "방 목록과 3D 에디터에 함께 표시됩니다",
                placeholder: "방 이름을 입력하세요",
                initialName: room.roomType,
                onSave: { onRenameRoom(room, $0) }
            )
        }
        .sheet(item: $pendingRoomDeletion) { room in
            ConfirmSheet(
                title: "방을 삭제할까요?",
                message: "‘\(room.roomType)’ 방과 저장된 3D 데이터를 삭제합니다. 이 작업은 되돌릴 수 없습니다.",
                confirmTitle: "방 삭제",
                onConfirm: { onDeleteRoom(room) }
            )
        }
        .sheet(isPresented: $showProjectDeletion) {
            ConfirmSheet(
                title: "프로젝트를 삭제할까요?",
                message: "‘\(project.resolvedName)’ 프로젝트와 포함된 모든 방을 삭제합니다. 이 작업은 되돌릴 수 없습니다.",
                confirmTitle: "프로젝트 삭제",
                onConfirm: onDeleteProject
            )
        }
    }
}

private struct EditableRoomRow: View {
    let room: RoomRecord
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    @State private var committedOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let actionWidth: CGFloat = 86
    private var displayOffset: CGFloat {
        min(0, max(-actionWidth, committedOffset + dragOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(SpatiumTheme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.trailing, 4)
            .opacity(displayOffset < -8 ? 1 : 0)

            RoomRecordRow(room: room)
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                .offset(x: displayOffset)
                .simultaneousGesture(swipeGesture)
                .onTapGesture {
                    if committedOffset < 0 {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                            committedOffset = 0
                        }
                    } else {
                        onOpen()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.45, perform: onRename)
                .contextMenu {
                    Button(action: onRename) {
                        Label("방 이름 수정", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("방 삭제", systemImage: "trash")
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "방 이름 수정", onRename)
                .accessibilityAction(named: "방 삭제", onDelete)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: committedOffset)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -150 {
                    onDelete()
                } else if value.translation.width < -44 {
                    committedOffset = -actionWidth
                } else {
                    committedOffset = 0
                }
            }
    }
}

private struct RoomRenderLoaderView: View {
    let projectID: String
    let projectName: String
    /// 에디터 안 드롭다운으로 전환할 수 있는 이 프로젝트의 전체 방 목록.
    let rooms: [RoomRecord]

    @Environment(\.dismiss) private var dismiss
    @State private var currentRoom: RoomRecord
    @State private var state: LoadState = .loading

    init(room: RoomRecord, projectID: String, projectName: String, rooms: [RoomRecord]) {
        self.projectID = projectID
        self.projectName = projectName
        self.rooms = rooms
        _currentRoom = State(initialValue: room)
    }

    private enum LoadState {
        case loading
        case loaded(RoomScanPackage)
        case fallback
        case failed(String)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                loadingView
            case let .loaded(package):
                RoomEditorView(
                    scanItems: package.items,
                    roomName: currentRoom.roomType,
                    usdzURL: package.usdzURL,
                    initialFloorColor: package.floorColor,
                    area: currentRoom.area ?? 16,
                    ceilingHeight: 2.4,
                    roomID: currentRoom.id,
                    projectID: projectID,
                    projectName: projectName,
                    availableRooms: rooms,
                    onSelectRoom: switchRoom
                )
                .id(currentRoom.id) // 방이 바뀌면 에디터 상태를 새로 만든다
            case .fallback:
                RoomEditorView(
                    room: currentRoom,
                    projectID: projectID,
                    projectName: projectName,
                    availableRooms: rooms,
                    onSelectRoom: switchRoom
                )
                .id(currentRoom.id)
            case let .failed(message):
                failureView(message: message)
            }
        }
        .task(id: currentRoom.id) { await loadRoomScan() }
    }

    private func switchRoom(_ room: RoomRecord) {
        guard room.id != currentRoom.id else { return }
        state = .loading
        currentRoom = room
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(SpatiumTheme.accent)
            Text("방 렌더를 불러오는 중")
                .font(.headline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
            Text(currentRoom.roomType)
                .font(.subheadline)
                .foregroundStyle(SpatiumTheme.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpatiumTheme.background.ignoresSafeArea())
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: "방 렌더를 불러오지 못했습니다",
                message: message
            )

            PrimaryButton(title: "기본 에디터 열기", systemImage: "square.grid.2x2") {
                state = .fallback
            }

            Button("닫기") {
                dismiss()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(SpatiumTheme.soft)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpatiumTheme.background.ignoresSafeArea())
    }

    private func loadRoomScan() async {
        // 서버에 저장된 룸이면 scene 엔드포인트로 편집 확정본 + 3D 메시를 받아온다.
        if !currentRoom.id.hasPrefix("local-") {
            do {
                let scene = try await ProjectService().fetchRoomScene(roomID: currentRoom.id)
                state = .loaded(RoomScanPackage(
                    items: scene.items,
                    usdzURL: scene.usdzURL,
                    floorColor: scene.floorColor
                ))
                return
            } catch {
                // scene 실패(구버전 룸/파일 없음 등) 시 아래 로컬 자산 경로로 폴백.
            }
        }

        do {
            if let package = try await RoomScanAssetService().loadPackage(for: currentRoom) {
                state = .loaded(package)
            } else {
                state = .fallback
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct ProjectDetailHeader: View {
    let project: SpatiumProject
    var onBack: () -> Void
    var onEditName: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(SpatiumTheme.accent.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("프로젝트 목록으로")

            VStack(alignment: .leading, spacing: 4) {
                Text(project.resolvedName)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("방 \(project.displayRoomCount)개 · \(project.createdAt, formatter: DateFormatter.roomRow) 생성")
                    .font(.subheadline)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            Spacer()

            Button(action: onEditName) {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(SpatiumTheme.accent.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("프로젝트 이름 수정")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SpatiumTheme.coral)
                    .frame(width: 42, height: 42)
                    .background(SpatiumTheme.coral.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("프로젝트 삭제")
        }
    }
}
