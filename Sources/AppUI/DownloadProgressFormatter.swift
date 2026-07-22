import Foundation

/// Pure formatting for model-download progress text — the menu-bar status line and the
/// inline Models-page row label. Side-effect-free so the byte-count → human-readable rules
/// (MB precision bands, percent rounding, unknown-total fallback) are unit-testable without
/// driving a live download.
enum DownloadProgressFormatter {
    /// Menu-bar status line, e.g. "Downloading Whisper large-v3: 25% (412/1621 MB)".
    static func statusText(modelDisplayName: String, receivedBytes: Int64, totalBytes: Int64?) -> String {
        let receivedMB = megabytes(receivedBytes)
        guard let totalBytes, totalBytes > 0 else {
            return "Downloading \(modelDisplayName): \(receivedMB) MB"
        }
        return "Downloading \(modelDisplayName): \(percentAndSize(receivedBytes: receivedBytes, totalBytes: totalBytes))"
    }

    /// Compact progress string shown inline in the Models page row, e.g. "25% (412/1621 MB)".
    static func rowLabel(receivedBytes: Int64, totalBytes: Int64?) -> String {
        guard let totalBytes, totalBytes > 0 else {
            return "\(megabytes(receivedBytes)) MB"
        }
        return percentAndSize(receivedBytes: receivedBytes, totalBytes: totalBytes)
    }

    private static func percentAndSize(receivedBytes: Int64, totalBytes: Int64) -> String {
        let ratio = max(0, min(1, Double(receivedBytes) / Double(totalBytes)))
        let percent = Int((ratio * 100).rounded())
        return "\(percent)% (\(megabytes(receivedBytes))/\(megabytes(totalBytes)) MB)"
    }

    static func megabytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 100 {
            return String(format: "%.0f", mb)
        }
        if mb >= 10 {
            return String(format: "%.1f", mb)
        }
        return String(format: "%.2f", mb)
    }
}
