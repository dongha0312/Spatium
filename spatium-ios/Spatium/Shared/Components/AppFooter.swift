import SwiftUI

struct AppFooter: View {
    @Binding var selectedTab: AppTab
    @State private var bounceTrigger: [AppTab: Int] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    bounceTrigger[tab, default: 0] += 1
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage(selected: selectedTab == tab))
                            .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                            .symbolEffect(.bounce, value: bounceTrigger[tab, default: 0])
                            .foregroundStyle(selectedTab == tab ? SpatiumTheme.accent : SpatiumTheme.soft)
                            .frame(height: 24)
                        
                        Text(tab.title)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? SpatiumTheme.accent : SpatiumTheme.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        selectedTab == tab
                            ? SpatiumTheme.elevatedSurface
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background(SpatiumTheme.chromeSurface)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SpatiumTheme.border.opacity(0.7))
                .frame(height: 0.5)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.76), value: selectedTab)
    }
}
