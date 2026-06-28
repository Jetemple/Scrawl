@testable import AppUI
import Foundation
import XCTest

final class CustomModelImportTests: XCTestCase {
    func testPlanStripsBinExtensionAndKeepsName() {
        let result = CustomModelImport.plan(forSourceFileName: "ggml-my-finetune.bin", existingModelIDs: [])
        guard case let .success(plan) = result else { return XCTFail("expected success") }
        XCTAssertEqual(plan.modelID, "ggml-my-finetune")
        XCTAssertEqual(plan.destinationFileName, "ggml-my-finetune.bin")
    }

    func testPlanUsesLastPathComponentOnly() {
        // A full path must not let a model escape the models directory.
        let result = CustomModelImport.plan(forSourceFileName: "/Users/me/Downloads/distil-large-v3.bin", existingModelIDs: [])
        guard case let .success(plan) = result else { return XCTFail("expected success") }
        XCTAssertEqual(plan.modelID, "distil-large-v3")
        XCTAssertEqual(plan.destinationFileName, "distil-large-v3.bin")
    }

    func testPlanSanitizesUnsafeCharacters() {
        let result = CustomModelImport.plan(forSourceFileName: "My Model (v2).bin", existingModelIDs: [])
        guard case let .success(plan) = result else { return XCTFail("expected success") }
        XCTAssertEqual(plan.modelID, "My-Model-v2")
        XCTAssertEqual(plan.destinationFileName, "My-Model-v2.bin")
    }

    func testPlanRejectsCollisionWithExistingModel() {
        let result = CustomModelImport.plan(
            forSourceFileName: "ggml-small.en.bin",
            existingModelIDs: ["ggml-small.en", "ggml-tiny.en"]
        )
        XCTAssertEqual(result, .failure(.alreadyInstalled(modelID: "ggml-small.en")))
    }

    func testPlanRejectsNameThatSanitizesToEmpty() {
        let result = CustomModelImport.plan(forSourceFileName: ".bin", existingModelIDs: [])
        XCTAssertEqual(result, .failure(.unreadableName))
    }

    func testPlanRejectsAllSymbolName() {
        let result = CustomModelImport.plan(forSourceFileName: "@@@.bin", existingModelIDs: [])
        XCTAssertEqual(result, .failure(.unreadableName))
    }

    func testPlanAcceptsModelWithoutBinExtension() {
        let result = CustomModelImport.plan(forSourceFileName: "ggml-base", existingModelIDs: [])
        guard case let .success(plan) = result else { return XCTFail("expected success") }
        XCTAssertEqual(plan.modelID, "ggml-base")
        XCTAssertEqual(plan.destinationFileName, "ggml-base.bin")
    }
}
