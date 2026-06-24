import Foundation

/// Pure decision logic for importing a user-supplied ("bring your own") model file.
/// Turns a picked file name into the on-disk model id and destination file name, or
/// an error explaining why the file can't be imported. The actual validation and copy
/// live in `LocalModelManager`; keeping the naming/collision decision pure makes it
/// easy to test exhaustively.
enum CustomModelImport {
    struct Plan: Equatable {
        /// Stem used as the model's id everywhere in the app (e.g. "ggml-my-finetune").
        let modelID: String
        /// File name written into the models directory ("<modelID>.bin").
        let destinationFileName: String
    }

    enum ImportError: LocalizedError, Equatable {
        case notAModelFile
        case unreadableName
        case alreadyInstalled(modelID: String)

        var errorDescription: String? {
            switch self {
            case .notAModelFile:
                "This doesn't look like a Whisper model. Scrawl expects a whisper.cpp ggml .bin file."
            case .unreadableName:
                "That file doesn't have a usable name. Rename it to something like my-model.bin and try again."
            case let .alreadyInstalled(modelID):
                "A model named \"\(modelID)\" is already installed. Delete it first, or rename your file."
            }
        }
    }

    static func plan(forSourceFileName sourceFileName: String, existingModelIDs: [String]) -> Result<Plan, ImportError> {
        let modelID = sanitizedModelID(fromFileName: sourceFileName)
        guard !modelID.isEmpty else {
            return .failure(.unreadableName)
        }
        guard !existingModelIDs.contains(modelID) else {
            return .failure(.alreadyInstalled(modelID: modelID))
        }
        return .success(Plan(modelID: modelID, destinationFileName: "\(modelID).bin"))
    }

    /// Derives a safe model id from a picked file name: takes the last path component
    /// (so a full path can't escape the models directory), drops a trailing `.bin`,
    /// replaces anything outside `[A-Za-z0-9-_.]` with "-", collapses repeats, and trims
    /// stray separators. Returns "" when nothing usable remains.
    static func sanitizedModelID(fromFileName fileName: String) -> String {
        var name = (fileName as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".bin") {
            name = String(name.dropLast(4))
        }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let mapped = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let collapsed = mapped.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }
}
