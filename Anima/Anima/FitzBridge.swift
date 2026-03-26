// FitzBridge.swift — Anima PoC
//
// Calls anima_helper.py via Process() (Swift's equivalent of subprocess).
// All annotation writing goes through this bridge to fitz, keeping PDFKit
// as a read-only renderer.
//
// Path resolution:
//   The Python executable is derived from the helperPath passed in each call.
//   helperPath points to tools/anima_helper.py; the project root is two levels
//   up, and the venv Python lives at .venv/bin/python3 relative to that root.
//   This means FitzBridge has no hardcoded paths of its own — everything flows
//   from the helperPath that AppDelegate sets on AnnotationManager.

import Foundation

struct FitzBridge {

    /// Create a highlight annotation via anima_helper.py.
    ///
    /// - Parameters:
    ///   - helperPath: Path to anima_helper.py (absolute)
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

    // MARK: - Internal: run a Python process

    /// Resolves the venv Python path from the helperPath and runs the process.
    ///
    /// Path derivation:
    ///   helperPath = .../projects/anima/tools/anima_helper.py
    ///                                  ^^^^^^ project root is 2 levels up
    ///   pythonPath = .../projects/anima/.venv/bin/python3
    private static func runPython(arguments: [String]) -> Bool {
        let process = Process()

        // Derive the venv Python path from the helper script location.
        // helperPath is the first element of arguments.
        let helperURL = URL(fileURLWithPath: arguments[0])
        let projectRoot = helperURL
            .deletingLastPathComponent()   // .../tools/
            .deletingLastPathComponent()   // .../anima/
        let pythonPath = projectRoot
            .appendingPathComponent(".venv/bin/python3")
            .path

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
