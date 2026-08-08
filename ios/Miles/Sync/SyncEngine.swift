import Foundation
import SwiftData

/// Offline-first sync. Drives edited locally are flagged `needsSync` (the
/// outbound queue); each sync pushes them and pulls server changes since the
/// last cursor. Conflicts are last-write-wins by `updatedAt`, and because the
/// server only accepts pushes newer than its own copy, classification edits
/// made on the web win over stale device state.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSyncAt: Date? = AppSettings.lastSyncAt
    @Published private(set) var pendingCount = 0

    private var syncTask: Task<Void, Never>?

    private init() {}

    /// Fire-and-forget sync trigger; coalesces overlapping requests.
    func requestSync() {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.sync()
            self?.syncTask = nil
        }
    }

    func refreshPendingCount() {
        let context = Persistence.container.mainContext
        let descriptor = FetchDescriptor<Drive>(
            predicate: #Predicate { $0.needsSync == true }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    func sync() async {
        guard APIClient.shared.isConfigured else {
            refreshPendingCount()
            return
        }
        status = .syncing
        let context = Persistence.container.mainContext

        do {
            let dirtyDescriptor = FetchDescriptor<Drive>(
                predicate: #Predicate { $0.needsSync == true }
            )
            let dirty = try context.fetch(dirtyDescriptor)
            let pushed = dirty.map { drive -> (Drive, Date) in (drive, drive.updatedAt) }

            let response = try await APIClient.shared.sync(
                cursor: AppSettings.syncCursor,
                drives: dirty.map(Self.toDTO)
            )

            // Only clear the dirty flag if the drive wasn't edited again
            // while the request was in flight.
            for (drive, updatedAtWhenPushed) in pushed
            where drive.updatedAt == updatedAtWhenPushed {
                drive.needsSync = false
            }

            try Self.apply(serverDrives: response.drives, context: context)
            try context.save()

            AppSettings.syncCursor = APIClient.isoFormatter.string(from: response.serverTime)
            AppSettings.lastSyncAt = Date()
            lastSyncAt = AppSettings.lastSyncAt
            status = .idle
        } catch let error as APIError {
            status = .error(error.errorDescription ?? "Sync failed")
        } catch {
            status = .error("Sync failed: \(error.localizedDescription)")
        }
        refreshPendingCount()
    }

    // MARK: - Merge logic

    private static func apply(serverDrives: [DriveDTO], context: ModelContext) throws {
        guard !serverDrives.isEmpty else { return }
        let ids = serverDrives.map(\.id)
        let descriptor = FetchDescriptor<Drive>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        let locals = try context.fetch(descriptor)
        var byID: [UUID: Drive] = [:]
        for drive in locals { byID[drive.id] = drive }

        for dto in serverDrives {
            if let local = byID[dto.id] {
                // Last-write-wins; the server copy wins ties so web edits
                // (the designated source of truth for classification) stick.
                if local.needsSync && local.updatedAt > dto.updatedAt {
                    continue
                }
                update(local, from: dto)
            } else if dto.deletedAt == nil {
                context.insert(makeDrive(from: dto))
            }
        }
    }

    private static func update(_ drive: Drive, from dto: DriveDTO) {
        drive.startedAt = dto.startedAt
        drive.endedAt = dto.endedAt
        drive.distanceMiles = dto.distanceMiles
        drive.startLatitude = dto.startLat
        drive.startLongitude = dto.startLng
        drive.endLatitude = dto.endLat
        drive.endLongitude = dto.endLng
        drive.startAddress = dto.startAddress
        drive.endAddress = dto.endAddress
        drive.categoryRaw = dto.category
        drive.purposeNote = dto.purposeNote
        drive.rateCentsPerMile = dto.rateCentsPerMile
        drive.encodedPolyline = dto.polyline
        drive.sourceRaw = dto.source
        drive.updatedAt = dto.updatedAt
        drive.deletedAt = dto.deletedAt
        drive.needsSync = false
    }

    private static func makeDrive(from dto: DriveDTO) -> Drive {
        Drive(
            id: dto.id,
            startedAt: dto.startedAt,
            endedAt: dto.endedAt,
            distanceMiles: dto.distanceMiles,
            startLatitude: dto.startLat,
            startLongitude: dto.startLng,
            endLatitude: dto.endLat,
            endLongitude: dto.endLng,
            startAddress: dto.startAddress,
            endAddress: dto.endAddress,
            category: DriveCategory(rawValue: dto.category) ?? .unclassified,
            purposeNote: dto.purposeNote,
            rateCentsPerMile: dto.rateCentsPerMile,
            encodedPolyline: dto.polyline,
            source: DriveSource(rawValue: dto.source) ?? .auto,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt,
            needsSync: false
        )
    }

    static func toDTO(_ drive: Drive) -> DriveDTO {
        DriveDTO(
            id: drive.id,
            startedAt: drive.startedAt,
            endedAt: drive.endedAt,
            distanceMiles: drive.distanceMiles,
            startLat: drive.startLatitude,
            startLng: drive.startLongitude,
            endLat: drive.endLatitude,
            endLng: drive.endLongitude,
            startAddress: drive.startAddress,
            endAddress: drive.endAddress,
            category: drive.categoryRaw,
            purposeNote: drive.purposeNote,
            rateCentsPerMile: drive.rateCentsPerMile,
            polyline: drive.encodedPolyline,
            source: drive.sourceRaw,
            updatedAt: drive.updatedAt,
            deletedAt: drive.deletedAt
        )
    }
}
