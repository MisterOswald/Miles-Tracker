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
        List {
            if !routeCoordinates.isEmpty {
                Section {
                    routeMap
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Classification") {
                Picker("Category", selection: categoryBinding) {
                    ForEach(DriveCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.segmented)

                if drive.category == .business {
                    LabeledContent("Deduction") {
                        Text(Formatters.money(drive.deductionDollars))
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Rate", value: Formatters.rate(drive.rateCentsPerMile))
                }

                TextField(
                    "Purpose (e.g. client meeting)",
                    text: purposeBinding,
                    axis: .vertical
                )
            }

            Section("Trip") {
                LabeledContent("Distance", value: Formatters.miles(drive.distanceMiles))
                LabeledContent("Duration", value: Formatters.duration(drive.duration))
                LabeledContent("Started") {
                    Text("\(drive.startedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                LabeledContent("Ended") {
                    Text("\(drive.endedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                LabeledContent("From", value: drive.startAddress.isEmpty ? "Unknown" : drive.startAddress)
                LabeledContent("To", value: drive.endAddress.isEmpty ? "Unknown" : drive.endAddress)
                if drive.source != .auto {
                    LabeledContent("Source", value: drive.source == .manual ? "Added manually" : "Merged")
                }
            }

            Section {
                Button("Edit drive") {
                    showingEdit = true
                }
                Button("Delete drive", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
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

    private var routeMap: some View {
        Map {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            if let first = routeCoordinates.first {
                Marker("Start", systemImage: "flag.fill", coordinate: first)
                    .tint(.green)
            }
            if let last = routeCoordinates.last {
                Marker("End", systemImage: "flag.checkered", coordinate: last)
                    .tint(.red)
            }
        }
        .mapStyle(.standard)
    }

    private var categoryBinding: Binding<DriveCategory> {
        Binding(
            get: { drive.category },
            set: { newValue in
                drive.category = newValue
                drive.touch()
                saveAndSync()
            }
        )
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
