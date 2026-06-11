import Foundation

/// Removes orphaned Scrawl temp files left in a directory (e.g. from a crash or force-quit).
/// Only flat files whose `lastPathComponent` begins with one of the given prefixes are deleted.
/// Subdirectories are never entered and symlinks are never followed.
/// Per-file errors are silently ignored so a single undeletable file never blocks the rest.
public enum TempFileSweeper {
    public static let defaultPrefixes: [String] = [
        "scrawl-audio-",
        "scrawl-transcript-",
        "scrawl-whisper-",
        "scrawl-download-"
    ]

    /// Remove matching files from `directory`. Never recurses. Never throws.
    public static func sweep(
        directory: URL,
        prefixes: [String] = defaultPrefixes
    ) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        ) else {
            return
        }

        for item in contents {
            // Only delete regular files — skip directories and symlinks
            guard let resourceValues = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  resourceValues.isSymbolicLink != true,
                  resourceValues.isRegularFile == true
            else {
                continue
            }

            let name = item.lastPathComponent
            guard prefixes.contains(where: { name.hasPrefix($0) }) else {
                continue
            }

            try? fm.removeItem(at: item)
        }
    }
}
