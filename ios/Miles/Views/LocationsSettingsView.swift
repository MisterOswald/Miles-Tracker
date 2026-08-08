import CoreLocation
import SwiftData
import SwiftUI

/// Named auto-classify places ("Home", "Warehouse"). A drive starting or
/// ending inside a place's radius is tagged with its category automatically.
struct LocationsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NamedLocation.name) private var locations: [NamedLocation]
    @State private var showingAdd = false

    var body: some View {
        List {
            if locations.isEmpty {
                Section {
                    Text("No named locations yet. Add places like \u{201C}Home\u{201D} or \u{201C}Warehouse\u{201D} and drives to or from them classify themselves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(locations) { location in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(location.name)
                            .font(.body.weight(.medium))
                        Text(subtitle(for: location))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(locations[index])
                    }
                    try? context.save()
                }
            }
        }
        .navigationTitle("Named Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                LocationEditView()
            }
        }
    }

    private func subtitle(for location: NamedLocation) -> String {
        let rule = location.autoCategory.map { "auto-tags \($0.displayName)" }
            ?? "label only"
        return "\(Int(location.radiusMeters)) m radius · \(rule)"
    }
}

struct LocationEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var radius = 150.0
    @State private var autoCategory: DriveCategory? = nil
    @State private var resolvedCoordinate: CLLocationCoordinate2D?
    @State private var resolvedLabel: String?
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Place") {
                TextField("Name (e.g. Warehouse)", text: $name)
            }
            Section("Where") {
                TextField("Address", text: $address)
                    .textContentType(.fullStreetAddress)
                Button {
                    Task { await geocodeAddress() }
                } label: {
                    if working {
                        ProgressView()
                    } else {
                        Text("Look up address")
                    }
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || working)
                Button("Use current location") {
                    useCurrentLocation()
                }
                if let resolvedLabel {
                    Label(resolvedLabel, systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Section("Radius") {
                Slider(value: $radius, in: 50...1000, step: 25) {
                    Text("Radius")
                }
                Text("\(Int(radius)) meters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Auto-classify drives as", selection: $autoCategory) {
                    Text("Don't auto-classify").tag(DriveCategory?.none)
                    Text("Business").tag(DriveCategory?.some(.business))
                    Text("Personal").tag(DriveCategory?.some(.personal))
                }
            } footer: {
                Text("Applied when a detected drive starts or ends inside this radius.")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                        || resolvedCoordinate == nil
                    )
            }
        }
    }

    private func geocodeAddress() async {
        working = true
        errorMessage = nil
        defer { working = false }
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            guard let location = placemarks.first?.location else {
                errorMessage = "Couldn't find that address."
                return
            }
            resolvedCoordinate = location.coordinate
            resolvedLabel = String(
                format: "Found: %.4f, %.4f",
                location.coordinate.latitude, location.coordinate.longitude
            )
        } catch {
            errorMessage = "Address lookup failed — check your connection."
        }
    }

    private func useCurrentLocation() {
        errorMessage = nil
        if let location = CLLocationManager().location {
            resolvedCoordinate = location.coordinate
            resolvedLabel = "Using current location"
        } else {
            errorMessage = "Current location isn't available yet — try again in a moment."
        }
    }

    private func save() {
        guard let coordinate = resolvedCoordinate else { return }
        let location = NamedLocation(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            autoCategory: autoCategory
        )
        context.insert(location)
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
