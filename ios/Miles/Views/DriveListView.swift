import SwiftData
import SwiftUI

struct DriveListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var engine: DriveTrackingEngine
    @EnvironmentObject private var sync: SyncEngine

    @Query(
        filter: #Predicate<Drive> { $0.deletedAt == nil },
        sort: \Drive.startedAt,
        order: .reverse
    ) private var drives: [Drive]

    @State private var showingManualAdd = false

    private var groupedByDay: [(day: Date, drives: [Drive])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: drives) {
            calendar.startOfDay(for: $0.startedAt)
        }
        return groups.keys.sorted(by: >).map { (day: $0, drives: groups[$0]!) }
    }

    var body: some View {
        List {
            statusSection

            if drives.isEmpty {
                emptyState
            } else {
                ForEach(groupedByDay, id: \.day) { group in
                    Section {
                        ForEach(group.drives) { drive in
                            NavigationLink(value: drive.id) {
                                DriveRowView(drive: drive)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    classify(drive, as: .business)
                                } label: {
                                    Label("Business", systemImage: "briefcase.fill")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    classify(drive, as: .personal)
                                } label: {
                                    Label("Personal", systemImage: "person.fill")
                                }
                                .tint(.purple)
                            }
                            .contextMenu {
                                contextMenuItems(for: drive, in: group.drives)
                            }
                        }
                    } header: {
                        HStack {
                            Text(Formatters.dayHeader(group.day))
                            Spacer()
                            Text(Formatters.miles(group.drives.reduce(0) { $0 + $1.distanceMiles }))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Drives")
        .navigationDestination(for: UUID.self) { id in
            if let drive = drives.first(where: { $0.id == id }) {
                DriveDetailView(drive: drive)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingManualAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add drive manually")
            }
            ToolbarItem(placement: .topBarLeading) {
                syncButton
            }
        }
        .sheet(isPresented: $showingManualAdd) {
            NavigationStack {
                DriveEditView(drive: nil)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        if engine.authorizationStatus != .authorizedAlways || !engine.motionAvailable {
            Section {
                PermissionBannerView()
            }
        }
        if engine.state == .active {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drive in progress")
                            .font(.subheadline.weight(.semibold))
                        if let started = engine.currentDriveStartedAt {
                            Text("Started \(Formatters.time(started)) · \(engine.currentDrivePointCount) GPS points")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if case .error(let message) = sync.status {
            Section {
                Label(message, systemImage: "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "car.2.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No drives yet")
                    .font(.headline)
                Text("Drives are detected automatically when you start moving. Keep the app installed, grant \u{201C}Always\u{201D} location access, and go for a drive — or add one manually with the + button.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var syncButton: some View {
        Button {
            sync.requestSync()
        } label: {
            if sync.status == .syncing {
                ProgressView()
            } else if sync.pendingCount > 0 {
                Label("\(sync.pendingCount)", systemImage: "arrow.triangle.2.circlepath")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .accessibilityLabel("Sync now")
    }

    // MARK: - Actions

    @ViewBuilder
    private func contextMenuItems(for drive: Drive, in dayDrives: [Drive]) -> some View {
        Button {
            classify(drive, as: .business)
        } label: {
            Label("Mark Business", systemImage: "briefcase")
        }
        Button {
            classify(drive, as: .personal)
        } label: {
            Label("Mark Personal", systemImage: "person")
        }
        if let previous = previousDrive(of: drive, in: dayDrives) {
            Button {
                merge(previous: previous, next: drive)
            } label: {
                Label("Merge with previous drive", systemImage: "arrow.triangle.merge")
            }
        }
        Button(role: .destructive) {
            delete(drive)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func classify(_ drive: Drive, as category: DriveCategory) {
        drive.category = category
        drive.touch()
        save()
    }

    private func delete(_ drive: Drive) {
        drive.deletedAt = Date()
        drive.touch()
        save()
    }

    /// The chronologically-previous drive in the same day group (the list is
    /// newest-first, so it's the next element).
    private func previousDrive(of drive: Drive, in dayDrives: [Drive]) -> Drive? {
        guard let index = dayDrives.firstIndex(where: { $0.id == drive.id }),
              index + 1 < dayDrives.count else { return nil }
        return dayDrives[index + 1]
    }

    /// Merges two drives split by a short stop (GPS gaps happen) into one.
    private func merge(previous: Drive, next: Drive) {
        let coords = Polyline.decode(previous.encodedPolyline)
            + Polyline.decode(next.encodedPolyline)
        let category: DriveCategory = {
            if previous.category == next.category { return previous.category }
            if previous.category == .unclassified { return next.category }
            if next.category == .unclassified { return previous.category }
            return .unclassified
        }()
        let note = [previous.purposeNote, next.purposeNote]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")

        let merged = Drive(
            startedAt: previous.startedAt,
            endedAt: next.endedAt,
            distanceMiles: ((previous.distanceMiles + next.distanceMiles) * 10).rounded() / 10,
            startLatitude: previous.startLatitude,
            startLongitude: previous.startLongitude,
            endLatitude: next.endLatitude,
            endLongitude: next.endLongitude,
            startAddress: previous.startAddress,
            endAddress: next.endAddress,
            category: category,
            purposeNote: note,
            rateCentsPerMile: max(previous.rateCentsPerMile, next.rateCentsPerMile),
            encodedPolyline: Polyline.encode(coordinates: coords),
            source: .merged
        )
        context.insert(merged)
        previous.deletedAt = Date()
        previous.touch()
        next.deletedAt = Date()
        next.touch()
        save()
    }

    private func save() {
        do {
            try context.save()
            sync.refreshPendingCount()
            sync.requestSync()
        } catch {
            NSLog("Miles: save failed: \(error)")
        }
    }
}

struct DriveRowView: View {
    let drive: Drive

    var body: some View {
        HStack(spacing: 12) {
            categoryIndicator
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Formatters.time(drive.startedAt)) – \(Formatters.time(drive.endedAt))")
                    .font(.subheadline.weight(.medium))
                Text(routeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.miles(drive.distanceMiles))
                    .font(.subheadline.weight(.semibold))
                if drive.category == .business {
                    Text(Formatters.money(drive.deductionDollars))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var routeDescription: String {
        let start = drive.startAddress.isEmpty ? "Unknown" : drive.startAddress
        let end = drive.endAddress.isEmpty ? "Unknown" : drive.endAddress
        return "\(start) → \(end)"
    }

    private var categoryIndicator: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private var color: Color {
        switch drive.category {
        case .business: return .green
        case .personal: return .purple
        case .unclassified: return .orange
        }
    }
}
