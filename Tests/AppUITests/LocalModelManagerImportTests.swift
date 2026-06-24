@testable import AppUI
import Foundation
import XCTest

final class LocalModelManagerImportTests: XCTestCase {
    private var root: URL!
    private var modelsDir: URL!
    private var sourceDir: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("byom-import-tests-\(UUID().uuidString)")
        modelsDir = root.appendingPathComponent("models")
        sourceDir = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSourceFile(_ name: String, validModel: Bool = true) throws -> URL {
        let url = sourceDir.appendingPathComponent(name)
        // Real ggml magic is little-endian on disk: 0x6C 0x6D 0x67 0x67.
        let bytes: [UInt8] = validModel ? [0x6C, 0x6D, 0x67, 0x67, 0xAA, 0xBB] : [0x00, 0x01, 0x02, 0x03]
        try Data(bytes).write(to: url)
        return url
    }

    func testImportsValidModelAndExposesItAsInstalled() throws {
        let manager = LocalModelManager(modelsDirectoryURL: modelsDir)
        let source = try makeSourceFile("ggml-my-model.bin")

        let id = try manager.importModel(from: source)

        XCTAssertEqual(id, "ggml-my-model")
        XCTAssertTrue(manager.installedModelIDs().contains("ggml-my-model"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.modelURL(id: "ggml-my-model").path))
    }

    func testRejectsNonModelFileAndImportsNothing() throws {
        let manager = LocalModelManager(modelsDirectoryURL: modelsDir)
        let source = try makeSourceFile("not-a-model.bin", validModel: false)

        XCTAssertThrowsError(try manager.importModel(from: source)) { error in
            XCTAssertEqual(error as? CustomModelImport.ImportError, .notAModelFile)
        }
        XCTAssertTrue(manager.installedModelIDs().isEmpty)
    }

    func testRejectsDuplicateImport() throws {
        let manager = LocalModelManager(modelsDirectoryURL: modelsDir)
        _ = try manager.importModel(from: makeSourceFile("ggml-dup.bin"))

        XCTAssertThrowsError(try manager.importModel(from: makeSourceFile("ggml-dup.bin"))) { error in
            XCTAssertEqual(error as? CustomModelImport.ImportError, .alreadyInstalled(modelID: "ggml-dup"))
        }
    }

    func testModelsFolderURLMatchesConfiguredDirectory() {
        let manager = LocalModelManager(modelsDirectoryURL: modelsDir)
        XCTAssertEqual(manager.modelsFolderURL, modelsDir)
    }
}
