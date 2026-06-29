import Foundation

struct PreferencesModelRow: Equatable, Sendable {
    let id: String
    let displayName: String
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let isPreparing: Bool
    let isCancelled: Bool
    /// Non-nil only while this row's model is being downloaded, e.g. "25% (412/1621 MB)".
    let downloadProgressText: String?

    init(
        id: String,
        displayName: String,
        isInstalled: Bool,
        isSelected: Bool,
        isDownloading: Bool,
        isPreparing: Bool = false,
        isCancelled: Bool,
        downloadProgressText: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.isInstalled = isInstalled
        self.isSelected = isSelected
        self.isDownloading = isDownloading
        self.isPreparing = isPreparing
        self.isCancelled = isCancelled
        self.downloadProgressText = downloadProgressText
    }

    var canDownload: Bool {
        !isInstalled && !isDownloading && !isPreparing
    }

    var canSelect: Bool {
        isInstalled && !isSelected && !isDownloading && !isPreparing
    }

    var statusText: String {
        if isPreparing { return "Preparing" }
        if isDownloading { return "Downloading" }
        // Installed/selected truth wins over a stale cancelled flag: a model that is
        // actually on disk is never "cancelled", even if a cancel raced its install.
        if isSelected { return "Selected" }
        if isInstalled { return "Installed" }
        if isCancelled { return "Download cancelled" }
        return "Available"
    }

    var actionTitle: String {
        if isPreparing { return "Preparing" }
        if isDownloading { return "Downloading" }
        if isSelected { return "Selected" }
        if isInstalled { return "Use" }
        return "Download"
    }
}

enum PreferencesModelState {
    static func rows(
        models: [any ManagedModel],
        selectedModelID: String,
        downloadingModelID: String?,
        cancelledModelID: String? = nil,
        downloadProgressText: String? = nil
    ) -> [PreferencesModelRow] {
        models.map { model in
            let isDownloading = model.id == downloadingModelID
            let isCancelled = model.id == cancelledModelID
            let isInstalled: Bool
            let isPreparing: Bool
            let rowProgressText: String?

            switch model.installState {
            case .notInstalled:
                isInstalled = false
                isPreparing = false
                rowProgressText = isDownloading ? downloadProgressText : nil
            case let .preparing(progress):
                isInstalled = false
                isPreparing = true
                rowProgressText = progress?.displayText
            case .installed:
                isInstalled = true
                isPreparing = false
                rowProgressText = isDownloading ? downloadProgressText : nil
            }

            return PreferencesModelRow(
                id: model.id,
                displayName: model.displayName,
                isInstalled: isInstalled,
                isSelected: model.id == selectedModelID,
                isDownloading: isDownloading,
                isPreparing: isPreparing,
                isCancelled: !isInstalled && isCancelled,
                downloadProgressText: rowProgressText
            )
        }
    }

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

        var rows: [PreferencesModelRow] = []
        rows.append(contentsOf: downloadableModels.map { model in
            let installedModelID = installedIDs.contains(model.id) ? model.id : installedIDByFamily[canonicalFamily(model.id)]
            let rowModelID = installedModelID ?? model.id
            let isInstalled = installedModelID != nil
            // An installed model is never "cancelled" — a cancel that races a finishing
            // download must not leave the row showing "Download cancelled" next to "Use".
            let isCancelled = !isInstalled && (rowModelID == cancelledModelID || model.id == cancelledModelID)
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
        })

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
        if modelID == ModelCatalog.parakeetModelID {
            return "Parakeet v3"
        }
        return modelID.replacingOccurrences(of: "ggml-", with: "")
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
