import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Live address suggestions backed by MKLocalSearchCompleter (MapKit — free,
/// no API key).
@MainActor
final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 3 {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func bias(around coordinate: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 40_000,
            longitudinalMeters: 40_000
        )
    }

    func clear() {
        results = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in
            self.results = items
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter, didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.results = []
        }
    }
}

/// Manual add (drive == nil) and edit (drive != nil) form with address
/// autocomplete and route/distance calculation via Apple Maps directions.
struct DriveEditView: View {
    private enum Field: Hashable {
        case start
        case end
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncEngine

    let drive: Drive?

    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var distanceText: String
    @State private var startAddress: String
    @State private var endAddress: String
    @State private var category: DriveCategory
    @State private var purposeNote: String
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var endCoordinate: CLLocationCoordinate2D?
    /// Set when a route was calculated; overwrites the drive's polyline on save.
    @State private var routePolyline: String?
    @State private var routing = false
    @State private var routeInfo: String?
    @State private var validationError: String?

    @StateObject private var startCompleter = AddressCompleter()
    @StateObject private var endCompleter = AddressCompleter()
    @FocusState private var focusedField: Field?

    init(drive: Drive?) {
        self.drive = drive
        let defaultStart = Calendar.current.date(
            byAdding: .minute, value: -30, to: Date()
        ) ?? Date()
        _startedAt = State(initialValue: drive?.startedAt ?? defaultStart)
        _endedAt = State(initialValue: drive?.endedAt ?? Date())
        _distanceText = State(
            initialValue: drive.map { String(format: "%.1f", $0.distanceMiles) } ?? ""
        )
        _startAddress = State(initialValue: drive?.startAddress ?? "")
        _endAddress = State(initialValue: drive?.endAddress ?? "")
        _category = State(initialValue: drive?.category ?? .unclassified)
        _purposeNote = State(initialValue: drive?.purposeNote ?? "")
        if let drive, let lat = drive.startLatitude, let lng = drive.startLongitude {
            _startCoordinate = State(
                initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lng)
            )
        }
        if let drive, let lat = drive.endLatitude, let lng = drive.endLongitude {
            _endCoordinate = State(
                initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lng)
            )
        }
    }

    var body: some View {
        Form {
            Section("When") {
                DatePicker("Started", selection: $startedAt)
                DatePicker("Ended", selection: $endedAt)
            }

            Section {
                addressRows(
                    placeholder: "Start address",
                    text: $startAddress,
                    field: .start,
                    completer: startCompleter
                )
                addressRows(
                    placeholder: "End address",
                    text: $endAddress,
                    field: .end,
                    completer: endCompleter
                )
            } header: {
                Text("Where")
            } footer: {
                Text("Pick from the suggestions so the drive gets exact map coordinates.")
            }

            Section {
                Button {
                    Task { await calculateRoute() }
                } label: {
                    HStack {
                        if routing {
                            ProgressView()
                            Text("Calculating…")
                                .padding(.leading, 8)
                        } else {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text("Calculate route & distance")
                        }
                    }
                }
                .disabled(startCoordinate == nil || endCoordinate == nil || routing)
                if let routeInfo {
                    Text(routeInfo)
                        .font(.caption)
                        .foregroundStyle(Theme.business)
                }
            } footer: {
                Text("Uses Apple Maps driving directions to fill in the mileage and draw the route on the drive's map. You can still adjust the distance by hand afterwards.")
            }

            Section("Distance") {
                TextField("Miles", text: $distanceText)
                    .keyboardType(.decimalPad)
            }

            Section("Classification") {
                Picker("Category", selection: $category) {
                    ForEach(DriveCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                TextField("Purpose (optional)", text: $purposeNote, axis: .vertical)
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(drive == nil ? "Add Drive" : "Edit Drive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            // Bias suggestions toward where the drive happened (or where the
            // phone is now) so "a street name" matches before identical street names
            // in other states.
            let bias = endCoordinate
                ?? startCoordinate
                ?? CLLocationManager().location?.coordinate
            if let bias {
                startCompleter.bias(around: bias)
                endCompleter.bias(around: bias)
            }
        }
    }

    // MARK: - Address autocomplete

    @ViewBuilder
    private func addressRows(
        placeholder: String,
        text: Binding<String>,
        field: Field,
        completer: AddressCompleter
    ) -> some View {
        TextField(placeholder, text: text)
            .textContentType(.fullStreetAddress)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .onChange(of: text.wrappedValue) { _, newValue in
                if focusedField == field {
                    completer.update(query: newValue)
                }
            }

        if focusedField == field {
            ForEach(completer.results.prefix(5), id: \.self) { completion in
                Button {
                    select(completion, for: field)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(completion.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private func select(_ completion: MKLocalSearchCompletion, for field: Field) {
        Task {
            do {
                let response = try await MKLocalSearch(
                    request: MKLocalSearch.Request(completion: completion)
                ).start()
                guard let item = response.mapItems.first else { return }
                let address = Self.displayAddress(completion)
                switch field {
                case .start:
                    startAddress = address
                    startCoordinate = item.placemark.coordinate
                case .end:
                    endAddress = address
                    endCoordinate = item.placemark.coordinate
                }
                routeInfo = nil
                focusedField = nil
                startCompleter.clear()
                endCompleter.clear()
            } catch {
                validationError = "Couldn't look up that address — check your connection."
            }
        }
    }

    private static func displayAddress(_ completion: MKLocalSearchCompletion) -> String {
        let subtitle = completion.subtitle
            .replacingOccurrences(of: ", United States", with: "")
        // Keep it short: street + city.
        let city = subtitle.components(separatedBy: ", ").first ?? ""
        return city.isEmpty ? completion.title : "\(completion.title), \(city)"
    }

    // MARK: - Route calculation

    private func calculateRoute() async {
        guard let start = startCoordinate, let end = endCoordinate else { return }
        routing = true
        routeInfo = nil
        defer { routing = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                validationError = "No driving route found between those addresses."
                return
            }
            let miles = route.distance / Geo.metersPerMile
            distanceText = String(format: "%.1f", miles)
            routePolyline = Self.encode(route.polyline)
            validationError = nil
            routeInfo = String(
                format: "Route found: %.1f miles · distance and map updated.", miles
            )
        } catch {
            validationError = "Route lookup failed — check your connection."
        }
    }

    private static func encode(_ polyline: MKPolyline) -> String {
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: polyline.pointCount
        )
        polyline.getCoordinates(
            &coords, range: NSRange(location: 0, length: polyline.pointCount)
        )
        return Polyline.encode(coordinates: coords)
    }

    // MARK: - Save

    private func save() {
        guard let miles = Double(distanceText.replacingOccurrences(of: ",", with: ".")),
              miles >= 0 else {
            validationError = "Enter the distance in miles (e.g. 12.4)."
            return
        }
        guard endedAt > startedAt else {
            validationError = "The end time must be after the start time."
            return
        }

        if let drive {
            drive.startedAt = startedAt
            drive.endedAt = endedAt
            drive.distanceMiles = miles
            drive.startAddress = startAddress
            drive.endAddress = endAddress
            drive.category = category
            drive.purposeNote = purposeNote
            if let coordinate = startCoordinate {
                drive.startLatitude = coordinate.latitude
                drive.startLongitude = coordinate.longitude
            }
            if let coordinate = endCoordinate {
                drive.endLatitude = coordinate.latitude
                drive.endLongitude = coordinate.longitude
            }
            if let routePolyline {
                drive.encodedPolyline = routePolyline
            }
            drive.touch()
        } else {
            let year = Calendar.current.component(.year, from: startedAt)
            let record = Drive(
                startedAt: startedAt,
                endedAt: endedAt,
                distanceMiles: miles,
                startLatitude: startCoordinate?.latitude,
                startLongitude: startCoordinate?.longitude,
                endLatitude: endCoordinate?.latitude,
                endLongitude: endCoordinate?.longitude,
                startAddress: startAddress,
                endAddress: endAddress,
                category: category,
                purposeNote: purposeNote,
                rateCentsPerMile: RateStore.rate(forYear: year, context: context),
                encodedPolyline: routePolyline ?? "",
                source: .manual
            )
            context.insert(record)
        }

        do {
            try context.save()
            sync.refreshPendingCount()
            sync.requestSync()
            dismiss()
        } catch {
            validationError = "Couldn't save the drive: \(error.localizedDescription)"
        }
    }
}
