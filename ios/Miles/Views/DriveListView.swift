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
            summaryCard

            if drives.isEmpty {
                emptyState
            } else {
                ForEach(groupedByDay, id: \.day) { group in
                    Section {
                        ForEach(group.drives) { drive in
                            driveRow(drive, in: group.drives)
                        }
                    } header: {
                        HStack {
                            Text(Formatters.dayHeader(group.day))
                            Spacer()
                            Text(Formatters.miles(group.drives.reduce(0) { $0 + $1.distanceMiles }))
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.muted)
                        .textCase(nil)
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Drives")
        .navigationDestination(for: UUID.self) { id in
            if let drive = drives.first(where: { $0.id == id }) {
                DriveDetailView(drive: drive)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                syncButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingManualAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                }
                .accessibilityLabel("Add drive manually")
            }
        }
        .sheet(isPresented: $showingManualAdd) {
            NavigationStack {
                DriveEditView(drive: nil)
            }
        }
    }

    // MARK: - Rows

    private func driveRow(_ drive: Drive, in dayDrives: [Drive]) -> some View {
        ZStack {
            NavigationLink(value: drive.id) { EmptyView() }.opacity(0)
            DriveRowView(drive: drive)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                classify(drive, as: .business)
            } label: {
                Label("Business", systemImage: "briefcase.fill")
            }
            .tint(Theme.business)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                classify(drive, as: .personal)
            } label: {
                Label("Personal", systemImage: "person.fill")
            }
            .tint(Theme.personal)
        }
        .contextMenu {
            contextMenuItems(for: drive, in: dayDrives)
        }
    }

    // MARK: - Summary card

    private var monthSummary: (name: String, deduction: Double, miles: Double, toClassify: Int) {
        let calendar = Calendar.current
        let now = Date()
        let monthDrives = drives.filter {
            calendar.isDate($0.startedAt, equalTo: now, toGranularity: .month)
        }
        return (
            now.formatted(.dateTime.month(.wide)),
            monthDrives.reduce(0) { $0 + $1.deductionDollars },
            monthDrives.reduce(0) { $0 + $1.distanceMiles },
            monthDrives.filter { $0.category == .unclassified }.count
        )
    }

    private var summaryCard: some View {
        let summary = monthSummary
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(summary.name) deduction")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text(Formatters.money(summary.deduction))
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(Formatters.miles(summary.miles)) tracked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                if summary.toClassify > 0 {
                    Text("\(summary.toClassify) to classify")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: Capsule())
                } else {
                    Text("All classified")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(18)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
    }

    // MARK: - Status / empty

    @ViewBuilder
    private var statusSection: some View {
        if engine.authorizationStatus != .authorizedAlways || !engine.motionAvailable {
            card {
                PermissionBannerView()
            }
        }
        if engine.state == .active {
            card {
                HStack(spacing: 12) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(Theme.business)
                        .symbolEffect(.pulse)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drive in progress")
                            .font(.subheadline.weight(.bold))
                        if let started = engine.currentDriveStartedAt {
                            Text("Started \(Formatters.time(started)) · \(engine.currentDrivePointCount) GPS points")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        if case .error(let message) = sync.status {
            card {
                Label(message, systemImage: "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(Theme.unclassified)
            }
        }
    }

    private var emptyState: some View {
        card {
            VStack(spacing: 12) {
                Image(systemName: "car.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 64, height: 64)
                    .background(Theme.accentSoft, in: Circle())
                Text("No drives yet")
                    .font(.headline.weight(.bold))
                Text("Drives are detected automatically when you start moving. Grant \u{201C}Always\u{201D} location access and go for a drive — or add one manually with the + button.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.04), radius: 8, y: 3)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }

    private var syncButton: some View {
        Button {
            sync.requestSync()
        } label: {
            Group {
                if sync.status == .syncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 34, height: 34)
            .background(Theme.card, in: Circle())
            .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.06), radius: 6, y: 2)
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

    private func previousDrive(of drive: Drive, in dayDrives: [Drive]) -> Drive? {
        guard let index = dayDrives.firstIndex(where: { $0.id == drive.id }),
              index + 1 < dayDrives.count else { return nil }
        return dayDrives[index + 1]
    }

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
            categoryChip
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Formatters.time(drive.startedAt)) – \(Formatters.time(drive.endedAt))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)
                Text(routeDescription)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.miles(drive.distanceMiles))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Theme.text)
                if drive.category == .business {
                    Text(Formatters.money(drive.deductionDollars))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.business)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.04), radius: 8, y: 3)
    }

    private var routeDescription: String {
        let start = drive.startAddress.isEmpty ? "Unknown" : drive.startAddress
        let end = drive.endAddress.isEmpty ? "Unknown" : drive.endAddress
        return "\(start) → \(end)"
    }

    private var categoryChip: some View {
        Text(chipLetter)
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(Theme.color(for: drive.category))
            .frame(width: 40, height: 40)
            .background(
                Theme.softColor(for: drive.category),
                in: RoundedRectangle(cornerRadius: 13)
            )
    }

    private var chipLetter: String {
        switch drive.category {
        case .business: return "B"
        case .personal: return "P"
        case .unclassified: return "?"
        }
    }
}
