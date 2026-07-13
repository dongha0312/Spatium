import SwiftUI

struct HomeDashboardView: View {
    let projects: [SpatiumProject]
    var onStartScan: () -> Void
    var onOpenRooms: () -> Void
    var onOpenSettings: () -> Void
    var onOpenProject: (SpatiumProject) -> Void

    @State private var isPulseAnimating = false
    @State private var animateItems = false

    private var totalRooms: Int {
        projects.reduce(0) { $0 + $1.displayRoomCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MZ Style Greeting Header using theme colors
            VStack(alignment: .leading, spacing: 6) {
                Text("SPATIAL SCANNER")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [SpatiumTheme.accent, SpatiumTheme.accentLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                
                Text("공간을 3D로 스캔해볼까요?")
                    .font(.title2.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
            }
            .padding(.bottom, 2)
            .offset(y: animateItems ? 0 : 12)
            .opacity(animateItems ? 1.0 : 0.0)

            // Main Scan Banner (ScanCommandCard)
            ScanCommandCard(projects: projects, onStartScan: onStartScan)
                .offset(y: animateItems ? 0 : 16)
                .opacity(animateItems ? 1.0 : 0.0)

            // Status Dashboard Widgets (Tiles)
            HStack(spacing: 12) {
                HomeStatusTile(
                    title: "진행 중인 프로젝트",
                    value: "\(projects.count)개",
                    systemImage: "folder.fill.badge.gearshape",
                    tint: SpatiumTheme.sage
                )
                HomeStatusTile(
                    title: "스캔 완료된 방",
                    value: "\(totalRooms)개",
                    systemImage: "cube.transparent.fill",
                    tint: SpatiumTheme.sky
                )
            }
            .offset(y: animateItems ? 0 : 20)
            .opacity(animateItems ? 1.0 : 0.0)

            // 3D Scan Guide Cards Carousel
            HomeScanGuideSection()
                .offset(y: animateItems ? 0 : 24)
                .opacity(animateItems ? 1.0 : 0.0)

            // Recent Space Records
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "최근 기록한 스페이스",
                    actionTitle: projects.isEmpty ? nil : "전체보기",
                    action: projects.isEmpty ? nil : onOpenRooms
                )

                if projects.isEmpty {
                    HomeEmptyProjectsCard(onStartScan: onStartScan)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(projects.prefix(3).enumerated()), id: \.offset) { _, project in
                            Button {
                                onOpenProject(project)
                            } label: {
                                HomeRecentProjectRow(project: project)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
            .offset(y: animateItems ? 0 : 28)
            .opacity(animateItems ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                animateItems = true
            }
        }
    }
}

private struct ScanCommandCard: View {
    let projects: [SpatiumProject]
    var onStartScan: () -> Void

    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                commandCopy
                Spacer(minLength: 8)
                SpatialScannerGraphic()
            }

            Button(action: onStartScan) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.headline.weight(.bold))
                    Text("새 공간 스캔 시작하기")
                        .font(.headline.weight(.black))
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3.weight(.bold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(SpatiumTheme.creamSurface)
                .foregroundStyle(SpatiumTheme.onCream)
                .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.md, style: .continuous))
                .shadow(color: SpatiumTheme.shadow.opacity(0.16), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.pressable)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [SpatiumTheme.ink, SpatiumTheme.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                .stroke(SpatiumTheme.accentLight.opacity(0.3), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .shadow(color: SpatiumTheme.shadow.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private var commandCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
                Text(projects.isEmpty ? "READY TO SCAN" : "\(projects.count)개 프로젝트 진행 중")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
            .onAppear {
                isPulsing = true
            }

            Text("새 프로젝트 만들기")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text("AR 카메라를 사용하여 방 전체를 입체적으로 스캔하고 도면을 저장합니다.")
                .font(.caption)
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SpatialScannerGraphic: View {
    @State private var rotationDegree: Double = 0.0
    @State private var pulseState: CGFloat = 0.0
    @State private var scanPulseState: CGFloat = 0.0

    var body: some View {
        ZStack {
            // Pulsing scanning concentric circles - Loop 1 (Fades out seamlessly at end of loop)
            Circle()
                .stroke(Color.white.opacity(0.12 * (1.0 - Double(scanPulseState))), lineWidth: 1.5)
                .scaleEffect(0.6 + (scanPulseState * 0.8))
            
            // Pulsing scanning concentric circles - Loop 2 (Offset by 0.5 phase for organic double ripples)
            Circle()
                .stroke(Color.white.opacity(0.24 * (1.0 - Double((scanPulseState + 0.5).truncatingRemainder(dividingBy: 1.0)))), lineWidth: 1.5)
                .scaleEffect(0.6 + (((scanPulseState + 0.5).truncatingRemainder(dividingBy: 1.0)) * 0.8))
            
            // Dotted scan orbit (Rotates counter-clockwise)
            Circle()
                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-rotationDegree))
            
            // Rotating scanner gradient line (Rotates clockwise)
            Circle()
                .trim(from: 0.0, to: 0.25)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.85), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                )
                .frame(width: 76, height: 76)
                .rotationEffect(.degrees(rotationDegree))
            
            // Floating sparkles - EaseInOut Pulse (Autoreverses)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SpatiumTheme.accentLight)
                .offset(x: 28, y: -22)
                .scaleEffect(0.85 + (pulseState * 0.4))
            
            // Floating transparent cube (Rotates back and forth)
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .offset(x: -26, y: 22)
                .rotationEffect(.degrees(-15 + (pulseState * 30)))

            // Center Viewfinder (Smooth pulse)
            Image(systemName: "viewfinder")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.6), radius: 6)
                .scaleEffect(0.94 + (pulseState * 0.12))
        }
        .frame(width: 96, height: 96)
        .onAppear {
            // 1. Continuous Linear rotation for scanner sweep (No jump on loop boundary)
            withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                rotationDegree = 360.0
            }
            
            // 2. Smooth bouncing pulse (Autoreverses) for sparkles, cube, and viewfinder
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseState = 1.0
            }
            
            // 3. Continuous fade out pulse for concentric circles
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                scanPulseState = 1.0
            }
        }
    }
}

private struct HomeStatusTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(tint.opacity(0.35))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SpatiumTheme.soft)
                
                Text(value)
                    .font(.title3.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                .stroke(tint.opacity(0.24), lineWidth: 1.5)
        )
        .shadow(color: tint.opacity(0.08), radius: 10, x: 0, y: 6)
    }
}



private struct HomeRecentProjectRow: View {
    let project: SpatiumProject

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SpatiumTheme.accentLight.opacity(0.12), SpatiumTheme.sage.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SpatiumTheme.accent, SpatiumTheme.accentLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.resolvedName)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
                
                HStack(spacing: 6) {
                    Text("방 \(project.displayRoomCount)개")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SpatiumTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(SpatiumTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                    
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                    
                    Text("\(project.lastUpdatedAt, formatter: DateFormatter.roomRow) 업데이트")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(SpatiumTheme.soft)
        }
        .padding(14)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                .stroke(SpatiumTheme.border.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
    }
}

private struct HomeEmptyProjectsCard: View {
    var onStartScan: () -> Void

    var body: some View {
        Button(action: onStartScan) {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SpatiumTheme.accent)
                    .frame(width: 54, height: 54)
                    .background(SpatiumTheme.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(spacing: 4) {
                    Text("아직 저장된 프로젝트가 없습니다")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(SpatiumTheme.text)
                    Text("첫 3D 공간 스캔을 시작하고 도면을 만들어 보세요!")
                        .font(.caption)
                        .foregroundStyle(SpatiumTheme.soft)
                }
                .multilineTextAlignment(.center)
                
                HStack(spacing: 6) {
                    Text("첫 프로젝트 시작하기")
                        .font(.footnote.weight(.bold))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(SpatiumTheme.onCta)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(SpatiumTheme.ctaFill)
                .clipShape(Capsule())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(SpatiumTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                    .stroke(SpatiumTheme.accent.opacity(0.2), lineWidth: 1.5)
            )
            .shadow(color: SpatiumTheme.accent.opacity(0.04), radius: 10, y: 6)
        }
        .buttonStyle(.pressable)
    }
}

private struct HomeScanGuideSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("성공적인 3D 스캔을 위한 가이드")
                .font(.headline.weight(.black))
                .foregroundStyle(SpatiumTheme.text)
                .padding(.horizontal, 18)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    GuideCard(
                        title: "밝은 조명 유지",
                        description: "조명이 너무 어두우면 스캐너가 방의 모서리를 정확하게 인식하지 못할 수 있습니다.",
                        systemImage: "lightbulb.fill",
                        tint: SpatiumTheme.sage
                    )
                    
                    GuideCard(
                        title: "천천히 부드럽게",
                        description: "카메라를 급하게 흔들면 정밀도가 떨어집니다. 스페이스가 완성될 때까지 천천히 움직이세요.",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: SpatiumTheme.sky
                    )
                    
                    GuideCard(
                        title: "장애물 정돈",
                        description: "가려진 벽이나 가구가 너무 많으면 도면이 정확하지 않을 수 있으니 미리 가볍게 정리해 주세요.",
                        systemImage: "sparkles",
                        tint: SpatiumTheme.accentLight
                    )
                }
                .padding(.horizontal, 18)
            }
            .padding(.horizontal, -18)
        }
    }
}

private struct GuideCard: View {
    let title: String
    let description: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(SpatiumTheme.text)
            }
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(SpatiumTheme.soft)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 220, height: 120)
        .padding(14)
        .background(SpatiumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SpatiumRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SpatiumRadius.lg)
                .stroke(SpatiumTheme.border.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.015), radius: 6, y: 3)
    }
}
