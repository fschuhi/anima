//
//  PDFCollectionScanner.swift
//  Anima
//
//  Scans the configured PDF collection directory for the open dialog.
//  Specified in docs/OPEN_DIALOG_DESIGN.md section 3.
//
//  Deliberately does no caching or indexing -- section 3 calls a fresh scan
//  "instantaneous at scale" for a personal library, so there is nothing to
//  keep in sync. Returns filenames only, never full paths: the open dialog
//  (OpenDialogState) works with filenames throughout, and the caller
//  reconstructs a URL from the known search directory plus a chosen
//  filename, since the scan is non-recursive and filenames within one flat
//  directory are therefore unique.
//

import Foundation

/// Outcomes of a scan. The two failure cases are section 3's degenerate
/// states, each handled by the caller with an alert before the dialog is
/// ever shown.
nonisolated enum PDFCollectionScanResult: Equatable {
    case success([String])
    case pathNotFound(String)
    case noFilesFound(String)
}

enum PDFCollectionScanner {

    /// Sorted by modification date descending -- Anima updates a PDF's
    /// `pdf_mtime` on every open, so the file most recently worked with
    /// floats to the top -- with alphabetical, case-insensitive order as
    /// the tiebreak for files sharing an exact modification timestamp.
    static func scan(directory path: String) -> PDFCollectionScanResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .pathNotFound(path)
        }

        let directoryURL = URL(fileURLWithPath: path)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .noFilesFound(path)
        }

        let pdfEntries = entries.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfEntries.isEmpty else {
            return .noFilesFound(path)
        }

        let withDates: [(filename: String, mtime: Date)] = pdfEntries.map { url in
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url.lastPathComponent, mtime)
        }

        let sorted = withDates.sorted { lhs, rhs in
            if lhs.mtime != rhs.mtime {
                return lhs.mtime > rhs.mtime
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }

        return .success(sorted.map { $0.filename })
    }
}
