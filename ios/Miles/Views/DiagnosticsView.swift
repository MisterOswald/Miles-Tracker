import SwiftUI

/// Read-only view of the on-device event log — every wake, state change,
/// and drive event, timestamped. When a drive is missed, this shows whether
/// the app was ever woken at all.
struct DiagnosticsView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No diagnostics recorded yet." : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(text.isEmpty ? Theme.muted : Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear") {
                    DiagLog.shared.clear()
                    text = ""
                }
                .disabled(text.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(text.isEmpty)
            }
        }
        .onAppear {
            text = DiagLog.shared.recent()
        }
        .refreshable {
            text = DiagLog.shared.recent()
        }
    }
}
