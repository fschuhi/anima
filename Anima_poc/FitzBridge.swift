// FitzBridge.swift — Anima PoC
//
// Calls anima_helper.py via Process() (Swift's equivalent of subprocess).
// All annotation writing goes through this bridge to fitz, keeping PDFKit
// as a read-only renderer.
//
// The Python executable is resolved from .venv/bin/python3 relative to the
// current working directory. Run ./anima from the project folder.

import Foundation

struct FitzBridge {

    /// Create a highlight annotation via anima_helper.py.
    ///
    /// - Parameters:
    ///   - helperPath: Path to anima_helper.py (relative or absolute)
    ///   - filePath: Path to the PDF file
    ///   - page: Page number (0-indexed)
    ///   - uuid: UUID for the annotation
    ///   - quadsJSON: JSON string of quad coordinates (fitz space)
    ///   - comment: Optional comment text
    /// - Returns: true on success, false on failure
    static func addHighlight(
        helperPath: String,
        filePath: String,
        page: Int,
        uuid: String,
        quadsJSON: String,
        comment: String = ""
    ) -> Bool {
        var arguments = [
            helperPath,
            "add-highlight",
            "--file", filePath,
            "--page", String(page),
            "--uuid", uuid,
            "--quads", quadsJSON
        ]

        if !comment.isEmpty {
            arguments.append(contentsOf: ["--comment", comment])
        }

        return runPython(arguments: arguments)
    }

    /// Edit the comment on an existing highlight.
    static func editComment(
        helperPath: String,
        filePath: String,
        uuid: String,
        comment: String
    ) -> Bool {
        let arguments = [
            helperPath,
            "edit-comment",
            "--file", filePath,
            "--uuid", uuid,
            "--comment", comment
        ]
        return runPython(arguments: arguments)
    }

    /// Delete a highlight entirely.
    static func deleteHighlight(
        helperPath: String,
        filePath: String,
        uuid: String
    ) -> Bool {
        let arguments = [
            helperPath,
            "delete-highlight",
            "--file", filePath,
            "--uuid", uuid
        ]
        return runPython(arguments: arguments)
    }

    // --- Internal: run a Python process ---

    private static func runPython(arguments: [String]) -> Bool {
        let process = Process()

        // Use the venv Python so fitz/PyMuPDF is available.
        // Process() needs an absolute path for executableURL.
        let cwd = FileManager.default.currentDirectoryPath
        let pythonPath = "\(cwd)/.venv/bin/python3"

        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = arguments

        // Capture stdout and stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Swift.print("❌ Failed to launch Python process: \(error)")
            Swift.print("   Expected Python at: \(pythonPath)")
            return false
        }

        let status = process.terminationStatus

        if status != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            Swift.print("❌ anima_helper.py failed (exit \(status)): \(stderrString)")
            return false
        }

        // Print stdout (the UUID) for debugging
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let stdoutString = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stdoutString.isEmpty {
            Swift.print("🔧 helper returned: \(stdoutString)")
        }

        return true
    }
}
