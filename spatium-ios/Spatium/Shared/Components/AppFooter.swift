import SwiftUI

struct AppFooter: View {
    @Binding var selectedTab: AppTab
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var bounceTrigger: [AppTab: Int] = [:]

    private var usesCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    bounceTrigger[tab, default: 0] += 1
                    selectedTab = tab
                } label: {
                    Group {
                        if usesCompactHeight {
                            HStack(spacing: 6) {
                                tabIcon(tab)
                                tabTitle(tab)
                            }
                        } else {
                            VStack(spacing: 3) {
                                tabIcon(tab)
                                    .frame(height: 24)
                                tabTitle(tab)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: usesCompactHeight ? 32 : 44)
                    .background(
                        selectedTab == tab
                            ? SpatiumTheme.elevatedSurface
                            : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius: usesCompactHeight ? 11 : 16,
                            style: .continuous
                        )
                    )
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: usesCompactHeight ? 11 : 16,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, usesCompactHeight ? 3 : 5)
        .frame(maxWidth: .infinity)
        .spatiumChromeGlass(cornerRadius: usesCompactHeight ? 18 : 24)
        .padding(.horizontal, usesCompactHeight ? 8 : 10)
        .padding(.top, 2)
        .padding(.bottom, usesCompactHeight ? 2 : 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-footer")
        .animation(.spring(response: 0.3, dampingFraction: 0.76), value: selectedTab)
    }

    private func tabIcon(_ tab: AppTab) -> some View {
        Image(systemName: tab.systemImage(selected: selectedTab == tab))
            .font(.system(
                size: usesCompactHeight ? 17 : 20,
                weight: selectedTab == tab ? .semibold : .regular
            ))
            .symbolEffect(.bounce, value: bounceTrigger[tab, default: 0])
            .foregroundStyle(selectedTab == tab ? SpatiumTheme.accent : SpatiumTheme.soft)
    }

    private func tabTitle(_ tab: AppTab) -> some View {
        Text(tab.title)
            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
            .foregroundStyle(selectedTab == tab ? SpatiumTheme.accent : SpatiumTheme.soft)
    }
}
