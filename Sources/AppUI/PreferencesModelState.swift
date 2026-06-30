import Foundation

struct PreferencesModelRow: Equatable, Sendable {
    let id: String
    let displayName: String
    let descriptionText: String
    let isInstalled: Bool
    let isSelected: Bool
    let isDefault: Bool
    let isDownloading: Bool
    let isPreparing: Bool
    let isCancelled: Bool
    /// Non-nil only while this row's model is being downloaded, e.g. "25% (412/1621 MB)".
    let downloadProgressText: String?

    init(
        id: String,
        displayName: String,
        descriptionText: String = "",
        isInstalled: Bool,
        isSelected: Bool,
        isDefault: Bool = false,
        isDownloading: Bool,
        isPreparing: Bool = false,
        isCancelled: Bool,
        downloadProgressText: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.descriptionText = descriptionText
        self.isInstalled = isInstalled
        self.isSelected = isSelected
        self.isDefault = isDefault
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
        if id == ModelCatalog.parakeetModelID {
            if isPreparing { return Self.parakeetPreparingStateText(from: downloadProgressText) }
            if isInstalled { return isDefault ? "Recommended" : "Installed" }
            return "Removed"
        }
        if isDownloading { return downloadProgressText ?? "Downloading" }
        // Installed/selected truth wins over a stale cancelled flag: a model that is
        // actually on disk is never "cancelled", even if a cancel raced its install.
        if isInstalled { return "Installed" }
        if isCancelled { return "Download cancelled" }
        return "Not installed"
    }

    var actionTitle: String {
        if isPreparing { return "Preparing" }
        if isDownloading { return "Downloading" }
        if isSelected { return "Selected" }
        if isInstalled { return "Use" }
        return "Download"
    }

    private static func parakeetPreparingStateText(from progressText: String?) -> String {
        guard
            let progressText,
            let range = progressText.range(of: #"\d+%"#, options: .regularExpression)
        else {
            return "Preparing"
        }
        return "Preparing \(progressText[range])"
    }
}

enum PreferencesModelState {
    static func rows(
        models: [any ManagedModel],
        selectedModelID: String,
        defaultModelID: String? = nil,
        downloadingModelID: String?,
        cancelledModelID: String? = nil,
        downloadProgressText: String? = nil
    ) -> [PreferencesModelRow] {
        let defaultModelID = defaultModelID ?? selectedModelID
        return models.map { model in
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
                displayName: displayName(forModelID: model.id),
                descriptionText: description(forModelID: model.id),
                isInstalled: isInstalled,
                isSelected: model.id == selectedModelID,
                isDefault: model.id == defaultModelID,
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
        defaultModelID: String? = nil,
        downloadingModelID: String?,
        cancelledModelID: String? = nil,
        downloadProgressText: String? = nil
    ) -> [PreferencesModelRow] {
        let defaultModelID = defaultModelID ?? selectedModelID
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
                displayName: displayName(forModelID: rowModelID),
                descriptionText: description(forModelID: rowModelID),
                isInstalled: isInstalled,
                isSelected: rowModelID == selectedModelID || model.id == selectedModelID,
                isDefault: rowModelID == defaultModelID || model.id == defaultModelID,
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
                    displayName: displayName(forModelID: modelID),
                    descriptionText: description(forModelID: modelID),
                    isInstalled: true,
                    isSelected: modelID == selectedModelID,
                    isDefault: modelID == defaultModelID,
                    isDownloading: isDownloading,
                    isCancelled: false,
                    downloadProgressText: isDownloading ? downloadProgressText : nil
                )
            }

        rows.append(contentsOf: customRows)
        return rows
    }

    static func displayName(forModelID modelID: String) -> String {
        let normalized = modelID.hasSuffix(".bin") ? String(modelID.dropLast(4)) : modelID
        switch normalized {
        case ModelCatalog.parakeetModelID:
            return LocalModelManager.parakeetDisplayName
        case "ggml-tiny.en":
            return "Tiny (English)"
        case "ggml-small.en":
            return "Small (English)"
        case "ggml-medium":
            return "Medium"
        case "ggml-large-v3-turbo":
            return "Large v3 Turbo"
        default:
            if normalized.hasPrefix("ggml-") {
                return String(normalized.dropFirst(5))
            }
            return normalized
        }
    }

    static func selectedModelStatusText(forModelID modelID: String) -> String {
        "Selected model: \(displayName(forModelID: modelID))"
    }

    static func displayName(forInstalledModelID modelID: String) -> String {
        displayName(forModelID: modelID)
    }

    static func description(forModelID modelID: String) -> String {
        switch canonicalFamily(modelID) {
        case canonicalFamily(ModelCatalog.parakeetModelID):
            return "Fastest on-device"
        case "tiny.en":
            return "Smallest English"
        case "small.en":
            return "Fast English"
        case "medium":
            return "Multilingual"
        case "large-v3-turbo":
            return "Most accurate"
        default:
            return "Custom Whisper model"
        }
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
