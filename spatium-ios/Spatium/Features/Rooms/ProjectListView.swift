import SwiftUI

struct ProjectListView: View {
    let projects: [SpatiumProject]
    var onCreateProject: () -> Void
    var onOpenProject: (SpatiumProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProjectLibrarySummary(projects: projects, onCreateProject: onCreateProject)

            if projects.isEmpty {
                EmptyStateCard(
                    systemImage: "folder",
                    title: "프로젝트가 아직 없습니다",
                    message: "위의 '새 프로젝트' 버튼으로 첫 프로젝트를 만들어 보세요."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("모든 프로젝트")
                        .font(.headline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)

                    LazyVStack(spacing: 10) {
                        ForEach(Array(projects.enumerated()), id: \.offset) { _, project in
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

private struct ProjectLibrarySummary: View {
    let projects: [SpatiumProject]
    var onCreateProject: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(
                                colors: [SpatiumTheme.accent, SpatiumTheme.accentLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(projects.count)개 프로젝트")
                            .font(.title3.weight(.black))
                            .foregroundStyle(SpatiumTheme.text)
                        Text(projects.isEmpty ? "아직 만든 프로젝트가 없습니다." : "프로젝트마다 여러 방을 모아 관리하세요.")
                            .font(.subheadline)
                            .foregroundStyle(SpatiumTheme.soft)
                    }

                    Spacer()
                }

                ActionCTAButton(
                    title: "새 프로젝트",
                    subtitle: "방을 모아 관리할 새 공간을 만드세요",
                    systemImage: "folder.badge.plus",
                    tint: SpatiumTheme.accent,
                    action: onCreateProject
                )
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
                    Text("방 \(project.displayRoomCount)개 · \(project.lastUpdatedAt, formatter: DateFormatter.roomRow) 업데이트")
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
