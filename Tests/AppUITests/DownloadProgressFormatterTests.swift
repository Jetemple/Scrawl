@testable import AppUI
import XCTest

final class DownloadProgressFormatterTests: XCTestCase {
    private let mib = Int64(1024 * 1024)

    // MARK: - megabytes precision bands

    func testMegabytesUsesTwoDecimalsBelowTen() {
        XCTAssertEqual(DownloadProgressFormatter.megabytes(mib / 2), "0.50")
        XCTAssertEqual(DownloadProgressFormatter.megabytes(mib), "1.00")
    }

    func testMegabytesUsesOneDecimalInTens() {
        XCTAssertEqual(DownloadProgressFormatter.megabytes(25 * mib), "25.0")
    }

    func testMegabytesDropsDecimalsAtHundredAndAbove() {
        XCTAssertEqual(DownloadProgressFormatter.megabytes(412 * mib), "412")
    }

    // MARK: - rowLabel

    func testRowLabelWithKnownTotalShowsPercentAndSizes() {
        XCTAssertEqual(
            DownloadProgressFormatter.rowLabel(receivedBytes: 412 * mib, totalBytes: 1621 * mib),
            "25% (412/1621 MB)"
        )
    }

    func testRowLabelWithUnknownTotalShowsReceivedOnly() {
        XCTAssertEqual(
            DownloadProgressFormatter.rowLabel(receivedBytes: 412 * mib, totalBytes: nil),
            "412 MB"
        )
        XCTAssertEqual(
            DownloadProgressFormatter.rowLabel(receivedBytes: 412 * mib, totalBytes: 0),
            "412 MB"
        )
    }

    /// A received count larger than the total (rounding/racey servers) clamps at 100% rather
    /// than reporting an impossible percentage.
    func testRowLabelClampsPercentToHundred() {
        XCTAssertEqual(
            DownloadProgressFormatter.rowLabel(receivedBytes: 2000 * mib, totalBytes: 1621 * mib),
            "100% (2000/1621 MB)"
        )
    }

    // MARK: - statusText

    func testStatusTextWithKnownTotal() {
        XCTAssertEqual(
            DownloadProgressFormatter.statusText(
                modelDisplayName: "Whisper large-v3",
                receivedBytes: 412 * mib,
                totalBytes: 1621 * mib
            ),
            "Downloading Whisper large-v3: 25% (412/1621 MB)"
        )
    }

    func testStatusTextWithUnknownTotal() {
        XCTAssertEqual(
            DownloadProgressFormatter.statusText(
                modelDisplayName: "Whisper large-v3",
                receivedBytes: 412 * mib,
                totalBytes: nil
            ),
            "Downloading Whisper large-v3: 412 MB"
        )
    }
}
