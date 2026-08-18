import CoreLocation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: DriveTrackingEngine
    @EnvironmentObject private var sync: SyncEngine

    @State private var autoTracking = AppSettings.autoTrackingEnabled

    var body: some View {
        Form {
            Section("Automatic tracking") {
                Toggle("Detect drives automatically", isOn: $autoTracking)
                    .onChange(of: autoTracking) { _, enabled in
                        engine.setAutoTracking(enabled: enabled)
                    }
                LabeledContent("Status", value: statusText)
                if engine.state == .active {
                    Button("End current drive now") {
                        engine.endCurrentDriveNow()
                    }
                }
                if engine.authorizationStatus != .authorizedAlways {
                    PermissionBannerView()
                }
            }

            Section("Classification rules") {
                NavigationLink("Named locations") {
                    LocationsSettingsView()
                }
                NavigationLink("Work hours") {
                    WorkHoursSettingsView()
                }
            }

            Section("IRS mileage rates") {
                NavigationLink("Rates by year") {
                    RatesSettingsView()
                }
            }

            Section("Sync") {
                NavigationLink("Server & account") {
                    SyncSettingsView()
                }
                if let last = sync.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if sync.pendingCount > 0 {
                    LabeledContent("Waiting to sync", value: "\(sync.pendingCount) drives")
                }
                Button("Sync now") {
                    sync.requestSync()
                }
                .disabled(sync.status == .syncing)
            }

            Section("Troubleshooting") {
                NavigationLink("Diagnostics log") {
                    DiagnosticsView()
                }
            }

            Section {
                LabeledContent("Version", value: appVersion)
            } footer: {
                Text("Drives are recorded on-device and work fully offline. Sync is optional and additive.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear {
            autoTracking = AppSettings.autoTrackingEnabled
            sync.refreshPendingCount()
        }
    }

    private var statusText: String {
        switch engine.state {
        case .off: return "Off"
        case .idle: return "Waiting for a drive (low power)"
        case .evaluating: return "Checking movement…"
        case .active: return "Recording a drive"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        return version
    }
}

// MARK: - Work hours

struct WorkHoursSettingsView: View {
    @State private var enabled = AppSettings.workHoursRuleEnabled
    @State private var start = Self.date(fromMinutes: AppSettings.workHoursStartMinutes)
    @State private var end = Self.date(fromMinutes: AppSettings.workHoursEndMinutes)

    var body: some View {
        Form {
            Section {
                Toggle("Enable work-hours rule", isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        AppSettings.workHoursRuleEnabled = value
                    }
            } footer: {
                Text("Drives that start Monday–Friday inside this window are classified as Business automatically (named-location rules take priority).")
            }
            if enabled {
                Section {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                        .onChange(of: start) { _, value in
                            AppSettings.workHoursStartMinutes = Self.minutes(from: value)
                        }
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                        .onChange(of: end) { _, value in
                            AppSettings.workHoursEndMinutes = Self.minutes(from: value)
                        }
                }
            }
        }
        .navigationTitle("Work Hours")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60
            + Calendar.current.component(.minute, from: date)
    }
}

// MARK: - Rates

struct RatesSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RateEntry.year, order: .reverse) private var rates: [RateEntry]
    @State private var addingYear = ""
    @State private var addingRate = ""

    var body: some View {
        Form {
            Section {
                ForEach(rates) { rate in
                    RateRowView(rate: rate)
                }
            } header: {
                Text("Cents per business mile")
            } footer: {
                Text("Each drive keeps the rate of its own year, so past deductions stay correct when rates change. Note: the IRS raised the 2026 rate mid-year (72.5¢ → 76¢ on July 1) — set the 2026 value to whichever your CPA prefers.")
            }
            Section("Add a year") {
                TextField("Year (e.g. 2027)", text: $addingYear)
                    .keyboardType(.numberPad)
                TextField("Cents per mile (e.g. 76 or 72.5)", text: $addingRate)
                    .keyboardType(.decimalPad)
                Button("Add") {
                    addRate()
                }
                .disabled(Int(addingYear) == nil || Double(addingRate) == nil)
            }
        }
        .navigationTitle("IRS Rates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addRate() {
        guard let year = Int(addingYear), let cents = Double(addingRate),
              (2000...2100).contains(year), cents >= 0 else { return }
        if let existing = rates.first(where: { $0.year == year }) {
            existing.centsPerMile = cents
        } else {
            context.insert(RateEntry(year: year, centsPerMile: cents))
        }
        try? context.save()
        addingYear = ""
        addingRate = ""
    }
}

private struct RateRowView: View {
    @Environment(\.modelContext) private var context
    let rate: RateEntry
    @State private var text = ""

    var body: some View {
        LabeledContent(String(rate.year)) {
            TextField("¢/mi", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .onSubmit { commit() }
                .onChange(of: text) { _, _ in commit() }
        }
        .onAppear {
            text = rate.centsPerMile.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", rate.centsPerMile)
                : String(format: "%.1f", rate.centsPerMile)
        }
    }

    private func commit() {
        guard let cents = Double(text), cents >= 0, cents != rate.centsPerMile else { return }
        rate.centsPerMile = cents
        try? context.save()
    }
}
