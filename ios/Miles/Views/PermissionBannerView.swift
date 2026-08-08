import CoreLocation
import CoreMotion
import SwiftUI

/// Shown when permissions are missing — automatic detection can't work
/// without Always location + motion access.
struct PermissionBannerView: View {
    @EnvironmentObject private var engine: DriveTrackingEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(buttonTitle) {
                if engine.authorizationStatus == .notDetermined {
                    engine.requestPermissions()
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch engine.authorizationStatus {
        case .notDetermined: return "Set up automatic tracking"
        case .authorizedWhenInUse: return "\u{201C}Always\u{201D} location needed"
        case .denied, .restricted: return "Location access is off"
        default: return "Motion access needed"
        }
    }

    private var message: String {
        switch engine.authorizationStatus {
        case .notDetermined:
            return "Miles needs location and motion access to detect drives automatically at near-zero battery cost."
        case .authorizedWhenInUse:
            return "With \u{201C}While Using\u{201D} only, drives can't be detected while the app is closed. Change location access to \u{201C}Always\u{201D} in Settings."
        case .denied, .restricted:
            return "Enable location access in Settings to record drives."
        default:
            return "Enable Motion & Fitness access so Miles can tell driving from walking — it's what keeps battery use near zero."
        }
    }

    private var buttonTitle: String {
        engine.authorizationStatus == .notDetermined ? "Enable" : "Open Settings"
    }
}
