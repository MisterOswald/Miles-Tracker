import SwiftUI
import UIKit

/// UIApplicationDelegate is required so drive tracking restarts when iOS
/// relaunches the app in the background (significant-location-change wake
/// after the app was suspended or terminated).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if launchOptions?[.location] != nil {
            NSLog("Miles: relaunched in background by a location event")
        }
        Task { @MainActor in
            Persistence.seedDefaultRates()
            DriveTrackingEngine.shared.start()
        }
        return true
    }
}

@main
struct MilesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(DriveTrackingEngine.shared)
                .environmentObject(SyncEngine.shared)
        }
        .modelContainer(Persistence.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                DriveTrackingEngine.shared.start()
                NotificationService.requestPermission()
                SyncEngine.shared.requestSync()
                SyncEngine.shared.refreshPendingCount()
            }
        }
    }
}
