import SwiftData
import SwiftUI

struct RootView: View {
    enum Tab {
        case drives
        case settings
    }

    @State private var tab: Tab = .drives

    @Query(filter: #Predicate<Drive> {
        $0.deletedAt == nil && $0.categoryRaw == "unclassified"
    }) private var unclassified: [Drive]

    var body: some View {
        Group {
            switch tab {
            case .drives:
                NavigationStack {
                    DriveListView()
                }
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(selected: $tab, toClassify: unclassified.count)
        }
        .tint(Theme.accent)
    }
}

/// Floating pill tab bar from the Soft SaaS design.
struct FloatingTabBar: View {
    @Binding var selected: RootView.Tab
    let toClassify: Int

    var body: some View {
        HStack(spacing: 6) {
            tabButton(.drives, label: "Drives", badge: toClassify)
            tabButton(.settings, label: "Settings", badge: 0)
        }
        .padding(8)
        .background(Theme.card, in: Capsule())
        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.12), radius: 15, y: 10)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: RootView.Tab, label: String, badge: Int) -> some View {
        let isOn = selected == tab
        return Button {
            selected = tab
        } label: {
            HStack(spacing: 8) {
                if isOn {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: 13, weight: isOn ? .bold : .semibold))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isOn ? Theme.accent : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(isOn ? .white : Theme.unclassified, in: Capsule())
                }
            }
            .foregroundStyle(isOn ? .white : Theme.muted)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(isOn ? Theme.accent : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
