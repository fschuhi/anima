//
//  PDFCollectionScannerTests.swift
//  AnimaTests
//
//  Unlike OpenDialogStateTests, this exercises real file-system I/O against
//  a disposable temp directory per test -- there's no way to test mtime
//  ordering without files that actually have modification dates.
//

import XCTest
@testable import Anima

final class PDFCollectionScannerTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFCollectionScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeFile(_ name: String, modified: Date) throws {
        let url = tempDirectory.appendingPathComponent(name)
        try Data().write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func testPathNotFoundWhenDirectoryMissing() {
        let missing = tempDirectory.appendingPathComponent("does-not-exist").path
        XCTAssertEqual(PDFCollectionScanner.scan(directory: missing), .pathNotFound(missing))
    }

    func testNoFilesFoundWhenDirectoryEmpty() {
        XCTAssertEqual(PDFCollectionScanner.scan(directory: tempDirectory.path), .noFilesFound(tempDirectory.path))
    }

    func testNoFilesFoundWhenOnlyNonPDFPresent() throws {
        try makeFile("notes.txt", modified: Date())
        guard case .noFilesFound = PDFCollectionScanner.scan(directory: tempDirectory.path) else {
            return XCTFail("expected .noFilesFound")
        }
    }

    func testSortsByModificationDateDescending() throws {
        let now = Date()
        try makeFile("Oldest.pdf", modified: now.addingTimeInterval(-200))
        try makeFile("Newest.pdf", modified: now)
        try makeFile("Middle.pdf", modified: now.addingTimeInterval(-100))

        guard case .success(let filenames) = PDFCollectionScanner.scan(directory: tempDirectory.path) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(filenames, ["Newest.pdf", "Middle.pdf", "Oldest.pdf"])
    }

    func testAlphabeticalTiebreakForEqualModificationDates() throws {
        let sameInstant = Date()
        try makeFile("Beta.pdf", modified: sameInstant)
        try makeFile("alpha.pdf", modified: sameInstant)
        try makeFile("Gamma.pdf", modified: sameInstant)

        guard case .success(let filenames) = PDFCollectionScanner.scan(directory: tempDirectory.path) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(filenames, ["alpha.pdf", "Beta.pdf", "Gamma.pdf"])
    }

    func testCaseInsensitivePDFExtensionMatch() throws {
        try makeFile("Uppercase.PDF", modified: Date())
        guard case .success(let filenames) = PDFCollectionScanner.scan(directory: tempDirectory.path) else {
            return XCTFail("expected .success")
        }
        XCTAssertEqual(filenames, ["Uppercase.PDF"])
    }
}
