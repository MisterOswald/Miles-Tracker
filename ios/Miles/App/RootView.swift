import SwiftData
import SwiftUI

struct RootView: View {
    @Query(filter: #Predicate<Drive> {
        $0.deletedAt == nil && $0.categoryRaw == "unclassified"
    }) private var unclassified: [Drive]

    var body: some View {
        TabView {
            NavigationStack {
                DriveListView()
            }
            .tabItem {
                Label("Drives", systemImage: "car.fill")
            }
            .badge(unclassified.count)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}
