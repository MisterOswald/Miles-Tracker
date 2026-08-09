import CoreLocation
import CoreMotion
import Foundation
import SwiftData

/// The MileIQ-style drive detection state machine.
///
///     idle ──(automotive activity / SLC while moving / visit departure)──▶ evaluating
///     evaluating ──(sustained driving speed or automotive)──▶ active
///     evaluating ──(timeout, no movement)──▶ idle
///     active ──(stationary/walking ≥ 3 min OR speed < 2 m/s ≥ 5 min)──▶ finalize ──▶ idle
///
/// Idle costs near-zero battery: only Significant Location Changes, CLVisit
/// monitoring, and the motion coprocessor are live — all of which can wake
/// the app from suspended or terminated state. Continuous GPS runs only
/// while a drive is actually in progress.
@MainActor
final class DriveTrackingEngine: NSObject, ObservableObject {

    enum State: Equatable {
        case off            // permissions missing or auto-tracking disabled
        case idle           // low-power monitoring, waiting for a drive
        case evaluating     // something moved — confirming it's a drive
        case active         // recording a drive
    }

    static let shared = DriveTrackingEngine()

    @Published private(set) var state: State = .off
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var motionAvailable = CMMotionActivityManager.isActivityAvailable()
    @Published private(set) var currentDrivePointCount = 0
    @Published private(set) var currentDriveStartedAt: Date?

    // MARK: - Tuning constants

    /// Speed treated as "definitely driving" when deciding to start (m/s).
    private let drivingSpeedThreshold = 4.5
    /// Speed below which the vehicle counts as stopped (m/s) — spec: 2 m/s.
    private let stationarySpeedThreshold = 2.0
    /// Discard GPS points with worse horizontal accuracy than this (meters).
    private let accuracyLimit = 50.0
    /// End the drive after this long of sustained walking — a positive
    /// pedestrian signal is the fastest reliable "drive over" indicator
    /// (and can't fire in traffic, unlike time-based rules).
    private let walkingEndInterval: TimeInterval = 90
    /// End the drive after this long without automotive motion activity
    /// (requires a positive non-automotive signal since, so a long red
    /// light can't false-end the drive).
    private let motionEndInterval: TimeInterval = 3 * 60
    /// End the drive after this long below the stationary speed threshold.
    private let speedEndInterval: TimeInterval = 5 * 60
    /// Never end a drive in its first minute (traffic lights at the start).
    private let minimumActiveInterval: TimeInterval = 60
    /// Give up on an evaluation that never turns into a drive.
    private let evaluationTimeout: TimeInterval = 3 * 60
    /// A persisted drive whose last point is older than this is closed out
    /// rather than resumed after relaunch.
    private let staleResumeInterval: TimeInterval = 10 * 60
    /// Drives shorter than this are considered GPS noise and dropped.
    private let minimumDriveMiles = 0.3
    private let minimumDriveDuration: TimeInterval = 120

    // MARK: - Internals

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let store = ActiveDriveStore()
    private let geocoder = GeocodingService()

    private var activeDrive: ActiveDriveState?
    private var evaluationStartedAt: Date?
    private var evaluationSpeedHits = 0
    private var endCheckTimer: Timer?
    private var evaluationTimer: Timer?
    private var isFinalizing = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Lifecycle

    /// Called from app launch (including background relaunches via SLC).
    func start() {
        authorizationStatus = locationManager.authorizationStatus
        recoverPersistedDriveIfNeeded()

        guard AppSettings.autoTrackingEnabled else {
            if state != .active { transitionToOff() }
            return
        }
        guard authorizationStatus == .authorizedAlways
            || authorizationStatus == .authorizedWhenInUse else {
            transitionToOff()
            return
        }
        if state == .off {
            enterIdle()
        }
        startMotionUpdates()
        // If we were relaunched by the system after movement, check whether
        // the motion coprocessor saw automotive activity in the last few
        // minutes and skip straight to evaluation.
        queryRecentAutomotiveActivity()
    }

    func requestPermissions() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
        // Prompt for motion permission by starting updates once.
        startMotionUpdates()
        NotificationService.requestPermission()
    }

    func setAutoTracking(enabled: Bool) {
        AppSettings.autoTrackingEnabled = enabled
        if enabled {
            start()
        } else if state != .active {
            transitionToOff()
        }
        // If a drive is active, let it finish; the next idle period respects
        // the switch.
    }

    /// Manually force-end an in-progress drive (Settings escape hatch).
    func endCurrentDriveNow() {
        guard state == .active else { return }
        finalizeActiveDrive(endedAt: Date())
    }

    // MARK: - State transitions

    private func transitionToOff() {
        stopAllLocationActivity()
        state = .off
    }

    private func enterIdle() {
        endCheckTimer?.invalidate()
        endCheckTimer = nil
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        evaluationStartedAt = nil
        evaluationSpeedHits = 0
        currentDrivePointCount = 0
        currentDriveStartedAt = nil

        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        state = .idle
    }

    private func beginEvaluation(reason: String) {
        guard state == .idle, AppSettings.autoTrackingEnabled else { return }
        NSLog("Miles: evaluating possible drive (\(reason))")
        state = .evaluating
        evaluationStartedAt = Date()
        evaluationSpeedHits = 0

        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 20
        applyBackgroundUpdatesFlag()
        locationManager.startUpdatingLocation()

        evaluationTimer?.invalidate()
        evaluationTimer = Timer.scheduledTimer(
            withTimeInterval: evaluationTimeout, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .evaluating else { return }
                NSLog("Miles: evaluation timed out, returning to idle")
                self.enterIdle()
            }
        }
    }

    private func beginActiveTracking(seedLocation: CLLocation?) {
        guard state != .active else { return }
        NSLog("Miles: drive started")
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        state = .active
        isFinalizing = false

        let now = Date()
        var drive = ActiveDriveState(
            id: UUID(),
            startedAt: seedLocation?.timestamp ?? now,
            points: [],
            lastMovementAt: now,
            lastAutomotiveAt: now
        )
        if let seed = seedLocation, seed.horizontalAccuracy <= accuracyLimit,
           seed.horizontalAccuracy >= 0 {
            drive.points.append(DrivePoint(location: seed))
        }
        activeDrive = drive
        currentDriveStartedAt = drive.startedAt
        currentDrivePointCount = drive.points.count
        store.save(drive)

        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        applyBackgroundUpdatesFlag()
        locationManager.startUpdatingLocation()

        endCheckTimer?.invalidate()
        endCheckTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkEndConditions()
            }
        }
    }

    private func applyBackgroundUpdatesFlag() {
        // Only legal with Always authorization + the location background mode.
        locationManager.allowsBackgroundLocationUpdates =
            locationManager.authorizationStatus == .authorizedAlways
        locationManager.showsBackgroundLocationIndicator = true
    }

    private func stopAllLocationActivity() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        locationManager.allowsBackgroundLocationUpdates = false
        endCheckTimer?.invalidate()
        endCheckTimer = nil
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        motionManager.stopActivityUpdates()
    }

    // MARK: - Motion activity

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionAvailable = false
            return
        }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                self.handleMotionActivity(activity)
            }
        }
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        guard activity.confidence != .low else { return }
        let now = Date()

        if activity.automotive {
            if activeDrive != nil {
                activeDrive?.lastAutomotiveAt = now
                activeDrive?.firstWalkingAt = nil
            }
            switch state {
            case .idle:
                beginEvaluation(reason: "automotive motion activity")
            case .evaluating where activity.confidence == .high:
                beginActiveTracking(seedLocation: locationManager.location)
            default:
                break
            }
            return
        }

        // Non-automotive signal while a drive is active: evidence the drive
        // may be over.
        guard state == .active, activeDrive != nil else { return }
        activeDrive?.lastNonAutomotiveAt = now
        if activity.walking || activity.running {
            if activeDrive?.firstWalkingAt == nil {
                activeDrive?.firstWalkingAt = now
            }
            checkEndConditions()
        }
    }

    /// After a background wake, ask the motion coprocessor what happened in
    /// the recent past — the wake itself may have been the only signal.
    private func queryRecentAutomotiveActivity() {
        guard CMMotionActivityManager.isActivityAvailable(), state == .idle else { return }
        let from = Date().addingTimeInterval(-5 * 60)
        motionManager.queryActivityStarting(from: from, to: Date(), to: .main) {
            [weak self] activities, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .idle else { return }
                let wasDriving = (activities ?? []).contains {
                    $0.automotive && $0.confidence != .low
                }
                if wasDriving {
                    self.beginEvaluation(reason: "recent automotive activity query")
                }
            }
        }
    }

    // MARK: - Location handling

    fileprivate func handleLocations(_ locations: [CLLocation]) {
        switch state {
        case .idle:
            // A significant-location-change fired. If we're clearly moving,
            // start evaluating (the SLC fix itself is often coarse).
            if let last = locations.last {
                if last.speed >= drivingSpeedThreshold {
                    beginEvaluation(reason: "SLC with driving speed")
                } else {
                    queryRecentAutomotiveActivity()
                }
            }
        case .evaluating:
            for location in locations where location.speed >= drivingSpeedThreshold {
                evaluationSpeedHits += 1
            }
            if evaluationSpeedHits >= 2 {
                beginActiveTracking(seedLocation: locations.last)
            }
        case .active:
            recordActivePoints(locations)
        case .off:
            break
        }
    }

    private func recordActivePoints(_ locations: [CLLocation]) {
        guard var drive = activeDrive else { return }
        var appended = false
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= accuracyLimit else { continue }
            drive.points.append(DrivePoint(location: location))
            appended = true
            if location.speed >= stationarySpeedThreshold {
                drive.lastMovementAt = max(drive.lastMovementAt, location.timestamp)
            }
        }
        activeDrive = drive
        if appended {
            currentDrivePointCount = drive.points.count
            store.save(drive)
        }
        checkEndConditions()
    }

    private func checkEndConditions() {
        guard state == .active, let drive = activeDrive, !isFinalizing else { return }
        let now = Date()
        guard now.timeIntervalSince(drive.startedAt) >= minimumActiveInterval else { return }

        let noMovementFor = now.timeIntervalSince(drive.lastMovementAt)
        let noAutomotiveFor = now.timeIntervalSince(drive.lastAutomotiveAt)

        // 1. Sustained walking — you got out of the car (MileIQ-fast, and
        //    impossible while stuck in traffic).
        let walkingRule: Bool = {
            guard let walkingSince = drive.firstWalkingAt else { return false }
            return now.timeIntervalSince(walkingSince) >= walkingEndInterval
        }()
        // 2. Stationary: no automotive signal for a while AND a positive
        //    non-automotive signal since AND no GPS movement — a long red
        //    light keeps reporting automotive, so it can't trip this.
        let motionRule: Bool = {
            guard motionAvailable,
                  let nonAutomotive = drive.lastNonAutomotiveAt,
                  nonAutomotive > drive.lastAutomotiveAt else { return false }
            return noAutomotiveFor >= motionEndInterval && noMovementFor >= 120
        }()
        // 3. Speed fallback for when motion data is unavailable or silent.
        let speedRule = noMovementFor >= speedEndInterval

        if walkingRule || motionRule || speedRule {
            NSLog("Miles: ending drive (walking=\(walkingRule) motion=\(motionRule) speed=\(speedRule))")
            finalizeActiveDrive(endedAt: drive.points.last?.timestamp ?? drive.lastMovementAt)
        }
    }

    // MARK: - Finalization

    private func finalizeActiveDrive(endedAt: Date) {
        guard let drive = activeDrive, !isFinalizing else { return }
        isFinalizing = true
        locationManager.stopUpdatingLocation()

        Task { @MainActor in
            await self.saveDrive(from: drive, endedAt: endedAt)
            self.activeDrive = nil
            self.store.clear()
            self.isFinalizing = false
            if AppSettings.autoTrackingEnabled,
               self.authorizationStatus == .authorizedAlways
                || self.authorizationStatus == .authorizedWhenInUse {
                self.enterIdle()
            } else {
                self.transitionToOff()
            }
            SyncEngine.shared.requestSync()
        }
    }

    private func saveDrive(from state: ActiveDriveState, endedAt: Date) async {
        var points = state.points.filter { $0.horizontalAccuracy <= accuracyLimit }
        // Trim the walk away from the car: drop trailing points recorded
        // after the last real vehicle movement (+ a small buffer), so the
        // stroll into the store isn't counted as route or distance.
        let cutoff = state.lastMovementAt.addingTimeInterval(15)
        if let lastDrivingIndex = points.lastIndex(where: { $0.timestamp <= cutoff }) {
            points = Array(points[...lastDrivingIndex])
        }
        let finalEndedAt = min(endedAt, points.last?.timestamp ?? endedAt)
        let miles = Geo.routeMiles(points: points)
        let duration = finalEndedAt.timeIntervalSince(state.startedAt)

        guard points.count >= 2, miles >= minimumDriveMiles,
              duration >= minimumDriveDuration else {
            NSLog("Miles: discarding drive (\(points.count) pts, \(miles) mi, \(Int(duration)) s)")
            return
        }

        let start = points.first!
        let end = points.last!
        let context = Persistence.container.mainContext

        let startAddress = await geocoder.reverseGeocode(
            latitude: start.latitude, longitude: start.longitude
        )
        let endAddress = await geocoder.reverseGeocode(
            latitude: end.latitude, longitude: end.longitude
        )

        let year = Calendar.current.component(.year, from: state.startedAt)
        let rate = RateStore.rate(forYear: year, context: context)
        let classification = AutoClassifier.classify(
            startLat: start.latitude, startLng: start.longitude,
            endLat: end.latitude, endLng: end.longitude,
            startedAt: state.startedAt, context: context
        )

        let record = Drive(
            id: state.id,
            startedAt: state.startedAt,
            endedAt: finalEndedAt,
            distanceMiles: (miles * 10).rounded() / 10,
            startLatitude: start.latitude,
            startLongitude: start.longitude,
            endLatitude: end.latitude,
            endLongitude: end.longitude,
            startAddress: startAddress,
            endAddress: endAddress,
            category: classification.category,
            purposeNote: classification.note,
            rateCentsPerMile: rate,
            encodedPolyline: Polyline.encode(coordinates: points.map(\.coordinate)),
            source: .auto
        )
        context.insert(record)
        do {
            try context.save()
            NSLog("Miles: saved drive \(record.id) — \(record.distanceMiles) mi")
            NotificationService.notifyDriveTracked(
                miles: record.distanceMiles,
                endAddress: endAddress,
                potentialDeductionDollars: record.distanceMiles * rate / 100.0,
                category: record.category
            )
        } catch {
            NSLog("Miles: failed to save drive: \(error)")
        }
    }

    // MARK: - Kill / relaunch recovery

    private func recoverPersistedDriveIfNeeded() {
        guard state != .active, activeDrive == nil,
              let persisted = store.load() else { return }

        let lastTimestamp = persisted.points.last?.timestamp ?? persisted.startedAt
        if Date().timeIntervalSince(lastTimestamp) > staleResumeInterval {
            // The app was killed and the drive clearly ended while we were
            // dead — close it out from persisted state.
            NSLog("Miles: closing out stale persisted drive from relaunch")
            activeDrive = persisted
            finalizeActiveDrive(endedAt: lastTimestamp)
        } else {
            // Killed mid-drive and relaunched quickly (SLC wake): resume.
            NSLog("Miles: resuming persisted drive after relaunch")
            activeDrive = persisted
            currentDriveStartedAt = persisted.startedAt
            currentDrivePointCount = persisted.points.count
            state = .active
            isFinalizing = false
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 10
            locationManager.pausesLocationUpdatesAutomatically = false
            applyBackgroundUpdatesFlag()
            locationManager.startUpdatingLocation()
            endCheckTimer?.invalidate()
            endCheckTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkEndConditions()
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension DriveTrackingEngine: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            self.handleLocations(locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            // A departure visit (arrival recorded, departure now known) means
            // we just left somewhere — a classic drive start signal.
            if visit.departureDate != .distantFuture, self.state == .idle {
                self.beginEvaluation(reason: "visit departure")
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse:
                // Upgrade prompt: Always is required for detection while closed.
                manager.requestAlwaysAuthorization()
                self.start()
            case .authorizedAlways:
                self.start()
            case .denied, .restricted:
                self.transitionToOff()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        let clError = error as? CLError
        if clError?.code == .denied {
            Task { @MainActor in
                self.transitionToOff()
            }
        } else {
            NSLog("Miles: location error: \(error.localizedDescription)")
        }
    }
}
