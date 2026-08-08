import SwiftData
import SwiftUI

/// Manual add (drive == nil) and edit (drive != nil) form. GPS misses happen;
/// this keeps the log complete.
struct DriveEditView: View {
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
    @State private var validationError: String?

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
    }

    var body: some View {
        Form {
            Section("When") {
                DatePicker("Started", selection: $startedAt)
                DatePicker("Ended", selection: $endedAt)
            }
            Section("Where") {
                TextField("Start address", text: $startAddress)
                    .textContentType(.fullStreetAddress)
                TextField("End address", text: $endAddress)
                    .textContentType(.fullStreetAddress)
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
    }

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
            drive.touch()
        } else {
            let year = Calendar.current.component(.year, from: startedAt)
            let record = Drive(
                startedAt: startedAt,
                endedAt: endedAt,
                distanceMiles: miles,
                startAddress: startAddress,
                endAddress: endAddress,
                category: category,
                purposeNote: purposeNote,
                rateCentsPerMile: RateStore.rate(forYear: year, context: context),
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
