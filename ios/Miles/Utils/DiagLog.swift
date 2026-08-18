import Foundation

/// Persistent on-device event log (Settings → Diagnostics log) so missed
/// drives can be diagnosed from facts instead of guesses. Records wakes,
/// state transitions, and drive lifecycle events with timestamps.
final class DiagLog {
    static let shared = DiagLog()

    private let queue = DispatchQueue(label: "com.miles.diaglog")
    private let fileURL: URL
    private let maxBytes = 120_000

    private init() {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        fileURL = dir.appendingPathComponent("diagnostics.log")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    func log(_ message: String) {
        NSLog("Miles: %@", message)
        let line = "\(Self.timeFormatter.string(from: Date())) | \(message)\n"
        queue.async { [fileURL, maxBytes] in
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
            // Keep the file bounded; drop the oldest two-thirds when full.
            if let size = (try? FileManager.default.attributesOfItem(
                atPath: fileURL.path))?[.size] as? Int,
                size > maxBytes,
                let data = try? Data(contentsOf: fileURL) {
                let tail = data.suffix(maxBytes / 3)
                try? tail.write(to: fileURL, options: .atomic)
            }
        }
    }

    func recent() -> String {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
    }

    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
