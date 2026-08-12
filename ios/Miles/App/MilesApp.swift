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
        let locationWake = launchOptions?[.location] != nil
        if locationWake {
            NSLog("Miles: relaunched in background by a location event")
        }
        // Must register before the app finishes launching.
        BackgroundSync.register()
        // Synchronous on purpose: on a background location relaunch the
        // engine must arm continuous updates before the launch window closes,
        // or iOS re-suspends us and the drive is missed.
        Persistence.seedDefaultRates()
        DriveTrackingEngine.shared.start(fromLocationWake: locationWake)
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
                // The Soft SaaS design is light-only; without this, dark mode
                // flips system text/card colors and breaks contrast.
                .preferredColorScheme(.light)
        }
        .modelContainer(Persistence.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                DriveTrackingEngine.shared.start()
                NotificationService.requestPermission()
                SyncEngine.shared.requestSync()
                SyncEngine.shared.refreshPendingCount()
            case .background:
                BackgroundSync.schedule()
            default:
                break
            }
        }
    }
}
