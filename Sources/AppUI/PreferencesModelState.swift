import Foundation

struct PreferencesModelRow: Equatable, Sendable {
    let id: String
    let displayName: String
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let isCancelled: Bool
    /// Non-nil only while this row's model is being downloaded, e.g. "25% (412/1621 MB)".
    let downloadProgressText: String?

    var canDownload: Bool {
        !isInstalled && !isDownloading
    }

    var canSelect: Bool {
        isInstalled && !isSelected && !isDownloading
    }

    var statusText: String {
        if isDownloading { return "Downloading" }
        if isCancelled { return "Download cancelled" }
        if isSelected { return "Selected" }
        if isInstalled { return "Installed" }
        return "Available"
    }

    var actionTitle: String {
        if isDownloading { return "Downloading" }
        if isSelected { return "Selected" }
        if isInstalled { return "Use" }
        return "Download"
    }
}

enum PreferencesModelState {
    static func rows(
        downloadableModels: [DownloadableModel],
        installedModelIDs: [String],
        selectedModelID: String,
        downloadingModelID: String?,
        cancelledModelID: String? = nil,
        downloadProgressText: String? = nil
    ) -> [PreferencesModelRow] {
        let installedIDs = Set(installedModelIDs)
        let installedIDByFamily = installedModelIDs
            .sorted()
            .reduce(into: [String: String]()) { result, modelID in
                let family = canonicalFamily(modelID)
                if result[family] == nil {
                    result[family] = modelID
                }
            }
        let downloadableIDs = Set(downloadableModels.map(\.id))
        let downloadableFamilies = Set(downloadableModels.map { canonicalFamily($0.id) })

        var rows = downloadableModels.map { model in
            let installedModelID = installedIDs.contains(model.id) ? model.id : installedIDByFamily[canonicalFamily(model.id)]
            let rowModelID = installedModelID ?? model.id
            let isInstalled = installedModelID != nil
            let isCancelled = (rowModelID == cancelledModelID || model.id == cancelledModelID)
            let isDownloading = rowModelID == downloadingModelID || model.id == downloadingModelID
            return PreferencesModelRow(
                id: rowModelID,
                displayName: model.displayName,
                isInstalled: isInstalled,
                isSelected: rowModelID == selectedModelID || model.id == selectedModelID,
                isDownloading: isDownloading,
                isCancelled: isCancelled,
                downloadProgressText: isDownloading ? downloadProgressText : nil
            )
        }

        let customRows = installedModelIDs
            .filter { !downloadableIDs.contains($0) && !downloadableFamilies.contains(canonicalFamily($0)) }
            .sorted()
            .map { modelID in
                let isDownloading = modelID == downloadingModelID
                return PreferencesModelRow(
                    id: modelID,
                    displayName: displayName(forInstalledModelID: modelID),
                    isInstalled: true,
                    isSelected: modelID == selectedModelID,
                    isDownloading: isDownloading,
                    isCancelled: false,
                    downloadProgressText: isDownloading ? downloadProgressText : nil
                )
            }

        rows.append(contentsOf: customRows)
        return rows
    }

    static func displayName(forInstalledModelID modelID: String) -> String {
        modelID.replacingOccurrences(of: "ggml-", with: "")
    }

    /// Strips the `ggml-` prefix and `.bin` extension so that files stored with
    /// or without those decorations compare equal.  The `.en` suffix is intentionally
    /// preserved: `ggml-medium.en` and `ggml-medium` are distinct model families.
    static func canonicalFamily(_ raw: String) -> String {
        var value = raw.lowercased()
        if value.hasSuffix(".bin") {
            value = String(value.dropLast(4))
        }
        if value.hasPrefix("ggml-") {
            value = String(value.dropFirst(5))
        }
        return value
    }
}
