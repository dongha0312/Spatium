import SwiftUI

struct ProjectListView: View {
    let projects: [SpatiumProject]
    let userFurniture: [UserFurniture]
    var onCreateProject: () -> Void
    var onOpenProject: (SpatiumProject) -> Void
    var onDeleteFurniture: (UserFurniture) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProjectLibrarySummary(projects: projects, onCreateProject: onCreateProject)

            UserFurnitureLibrary(items: userFurniture, onDelete: onDeleteFurniture)

            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("모든 프로젝트")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)

                    LazyVStack(spacing: 10) {
                        ForEach(projects) { project in
                            ProjectRow(project: project) {
                                onOpenProject(project)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct UserFurnitureLibrary: View {
    let items: [UserFurniture]
    var onDelete: (UserFurniture) async throws -> Void

    @State private var pendingDeletion: UserFurniture?
    @State private var deletingID: String?
    @State private var deletionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("내 가구")
                    .font(.headline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                Text("\(items.count)개")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                Spacer()
                Text("3D 에디터에서 사용 가능")
                    .font(.caption2)
                    .foregroundStyle(SpatiumTheme.soft)
            }

            if items.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "cube.transparent")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SpatiumTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(SpatiumTheme.warmPanel, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("아직 만든 가구가 없습니다")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SpatiumTheme.text)
                        Text("가구 만들기에서 저장하면 여기에 추가됩니다.")
                            .font(.caption)
                            .foregroundStyle(SpatiumTheme.soft)
                    }
                    Spacer()
                }
                .padding(14)
                .background(SpatiumTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            UserFurnitureCard(item: item, isDeleting: deletingID == item.id) {
                                pendingDeletion = item
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .confirmationDialog(
            "가구를 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                guard let furniture = pendingDeletion else { return }
                pendingDeletion = nil
                deletingID = furniture.id
                Task {
                    do {
                        try await onDelete(furniture)
                    } catch {
                        deletionError = error.localizedDescription
                    }
                    deletingID = nil
                }
            }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("서버와 이 기기의 내 가구 목록에서 삭제됩니다.")
        }
        .alert("가구 삭제 실패", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("확인", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }
}

private struct UserFurnitureCard: View {
    let item: UserFurniture
    let isDeleting: Bool
    var onDelete: () -> Void

    private var dimensions: String {
        String(format: "%.2f × %.2f × %.2fm", item.width, item.height, item.depth)
    }

    private var icon: String {
        switch item.category {
        case "bathtub": "bathtub.fill"
        case "bed": "bed.double.fill"
        case "chair": "chair.fill"
        case "dishwasher", "washerDryer": "washer.fill"
        case "fireplace": "fireplace.fill"
        case "oven", "stove": "oven.fill"
        case "refrigerator": "refrigerator.fill"
        case "sink": "sink.fill"
        case "sofa": "sofa.fill"
        case "stairs": "stairs"
        case "storage": "cabinet.fill"
        case "table": "table.furniture.fill"
        case "television": "tv.fill"
        case "toilet": "toilet.fill"
        case "lamp": "lamp.table.fill"
        default: "cube.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(SpatiumTheme.warmPanel, in: RoundedRectangle(cornerRadius: 11))
                Spacer()
                Text("직접 제작")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(SpatiumTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(SpatiumTheme.accent.opacity(0.09), in: Capsule())
                Button(action: onDelete) {
                    Image(systemName: isDeleting ? "hourglass" : "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpatiumTheme.coral)
                        .frame(width: 28, height: 28)
                        .background(SpatiumTheme.coral.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityLabel("\(item.name) 삭제")
            }
            Text(item.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SpatiumTheme.text)
                .lineLimit(1)
            Text("\(item.categoryLabel) · \(dimensions)")
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.soft)
                .lineLimit(1)
        }
        .padding(13)
        .frame(width: 190, alignment: .leading)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SpatiumRadius.lg).stroke(SpatiumTheme.border, lineWidth: 1))
    }
}

private struct ProjectLibrarySummary: View {
    let projects: [SpatiumProject]
    var onCreateProject: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("프로젝트")
                                .font(.title3.weight(.black))
                                .foregroundStyle(SpatiumTheme.text)

                            Text("\(projects.count)개")
                                .font(.caption.weight(.black))
                                .foregroundStyle(SpatiumTheme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(SpatiumTheme.accent.opacity(0.10), in: Capsule())
                        }

                        Text(projects.isEmpty ? "방을 정리할 첫 공간을 만들어 보세요." : "프로젝트마다 여러 방을 모아 관리하세요.")
                            .font(.subheadline)
                            .foregroundStyle(SpatiumTheme.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "folder.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: [SpatiumTheme.accent, SpatiumTheme.accentLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.sm, style: .continuous))
                }

                Button(action: onCreateProject) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.black))
                            .frame(width: 30, height: 30)
                            .background(SpatiumTheme.onCta.opacity(0.14), in: Circle())

                        Text(projects.isEmpty ? "첫 프로젝트 만들기" : "새 프로젝트 추가")
                            .font(.subheadline.weight(.black))

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.black))
                    }
                    .foregroundStyle(SpatiumTheme.onCta)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(SpatiumTheme.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                    .shadow(color: SpatiumTheme.ctaFill.opacity(0.16), radius: 10, y: 5)
                }
                .buttonStyle(.pressable)
                .contentShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                .accessibilityLabel(projects.isEmpty ? "새 프로젝트 만들기" : "새 프로젝트 추가")
                .accessibilityHint("방을 모아 관리할 새 공간을 만듭니다.")
            }
        }
    }
}

private struct ProjectRow: View {
    let project: SpatiumProject
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [SpatiumTheme.warmPanel, SpatiumTheme.accentLight.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(SpatiumTheme.accent)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.resolvedName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("방 \(project.displayRoomCount)개 · \(project.lastUpdatedAt, formatter: DateFormatter.roomRowDateOnly) 업데이트")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(SpatiumTheme.soft)
                    .frame(width: 24, height: 24)
                    .background(SpatiumTheme.background)
                    .clipShape(Circle())
            }
            .padding(14)
            .background(SpatiumTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                    .stroke(SpatiumTheme.border.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.015), radius: 6, y: 3)
        }
        .buttonStyle(.pressable)
    }
}
