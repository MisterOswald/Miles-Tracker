import MapKit
import SwiftData
import SwiftUI

struct DriveDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncEngine

    let drive: Drive

    @State private var showingEdit = false
    @State private var confirmingDelete = false

    private var routeCoordinates: [CLLocationCoordinate2D] {
        let decoded = Polyline.decode(drive.encodedPolyline)
        if decoded.count >= 2 { return decoded }
        if let sLat = drive.startLatitude, let sLng = drive.startLongitude,
           let eLat = drive.endLatitude, let eLng = drive.endLongitude {
            return [
                CLLocationCoordinate2D(latitude: sLat, longitude: sLng),
                CLLocationCoordinate2D(latitude: eLat, longitude: eLng),
            ]
        }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !routeCoordinates.isEmpty {
                    routeMap
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.06), radius: 9, y: 3)
                }

                statTiles
                classifyControl

                timelineCard
                purposeCard

                HStack(spacing: 10) {
                    Button {
                        showingEdit = true
                    } label: {
                        Text("Edit drive")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.accent, in: Capsule())
                    }
                    Button {
                        confirmingDelete = true
                    } label: {
                        Text("Delete")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.card, in: Capsule())
                            .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.05), radius: 7, y: 3)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(drive.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                DriveEditView(drive: drive)
            }
        }
        .confirmationDialog(
            "Delete this drive?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                drive.deletedAt = Date()
                drive.touch()
                saveAndSync()
                dismiss()
            }
        }
    }

    // MARK: - Pieces

    private var routeMap: some View {
        Map {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Theme.accent, lineWidth: 4)
            }
            if let first = routeCoordinates.first {
                Marker("Start", systemImage: "flag.fill", coordinate: first)
                    .tint(Theme.business)
            }
            if let last = routeCoordinates.last {
                Marker("End", systemImage: "flag.checkered", coordinate: last)
                    .tint(Theme.danger)
            }
        }
        .mapStyle(.standard)
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile(
                value: String(format: "%.1f", drive.distanceMiles),
                label: "miles",
                background: Theme.card,
                foreground: Color.primary
            )
            statTile(
                value: "\(max(1, Int((drive.duration / 60).rounded())))",
                label: "minutes",
                background: Theme.card,
                foreground: Color.primary
            )
            statTile(
                value: drive.category == .business
                    ? Formatters.money(drive.deductionDollars)
                    : "—",
                label: drive.category == .business
                    ? "deduction"
                    : "if business: " + Formatters.money(drive.distanceMiles * drive.rateCentsPerMile / 100.0),
                background: drive.category == .business ? Theme.businessSoft : Theme.card,
                foreground: drive.category == .business ? Theme.business : Color.primary
            )
        }
    }

    private func statTile(value: String, label: String, background: Color, foreground: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foreground == Color.primary ? Theme.muted : foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.04), radius: 8, y: 3)
    }

    private var classifyControl: some View {
        HStack(spacing: 0) {
            classifyOption(.unclassified, label: "Unclassified", fill: Color(red: 0.55, green: 0.55, blue: 0.65))
            classifyOption(.business, label: "Business", fill: Theme.business)
            classifyOption(.personal, label: "Personal", fill: Theme.personal)
        }
        .padding(6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.04), radius: 8, y: 3)
    }

    private func classifyOption(_ category: DriveCategory, label: String, fill: Color) -> some View {
        let isOn = drive.category == category
        return Button {
            guard drive.category != category else { return }
            drive.category = category
            drive.touch()
            saveAndSync()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isOn ? .heavy : .semibold))
                .foregroundStyle(isOn ? .white : Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isOn ? fill : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var timelineCard: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
                    .frame(width: 11, height: 11)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.93, blue: 0.96))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 11, height: 11)
                    .padding(.bottom, 5)
            }
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.time(drive.startedAt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                    Text(drive.startAddress.isEmpty ? "Unknown start" : drive.startAddress)
                        .font(.subheadline.weight(.bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.time(drive.endedAt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                    Text(drive.endAddress.isEmpty ? "Unknown end" : drive.endAddress)
                        .font(.subheadline.weight(.bold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.04), radius: 8, y: 3)
    }

    private var purposeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Purpose")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
            TextField(
                "e.g. Client meeting",
                text: purposeBinding,
                axis: .vertical
            )
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.14, green: 0.14, blue: 0.24).opacity(0.04), radius: 8, y: 3)
    }

    private var purposeBinding: Binding<String> {
        Binding(
            get: { drive.purposeNote },
            set: { newValue in
                guard newValue != drive.purposeNote else { return }
                drive.purposeNote = newValue
                drive.touch()
                try? context.save()
                sync.refreshPendingCount()
            }
        )
    }

    private func saveAndSync() {
        do {
            try context.save()
            sync.refreshPendingCount()
            sync.requestSync()
        } catch {
            NSLog("Miles: save failed: \(error)")
        }
    }
}
