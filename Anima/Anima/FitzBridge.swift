// FitzBridge.swift — Anima PoC
//
// Calls anima_helper.py via Process() (Swift's equivalent of subprocess).
// All persistent PDF mutations and catalog reads go through this bridge to
// fitz, keeping PDFKit as a read-only renderer.
//
// Return convention:
//   Reads return the helper's raw stdout as String? (nil on failure); the
//   caller decodes. Mutations return Bool (true on success). Keep this uniform
//   so every future read or mutation has exactly one exemplar to follow.
//
// Path resolution:
//   The Python executable is derived from the helperPath passed in each call.
//   helperPath points to tools/anima_helper.py; the project root is two levels
//   up, and the venv Python lives at .venv/bin/python3 relative to that root.
//   This means FitzBridge has no hardcoded paths of its own — everything flows
//   from the helperPath that AppDelegate sets on AnnotationManager and
//   BookmarkManager.

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

        return runPython(arguments: arguments) != nil
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
        return runPython(arguments: arguments) != nil
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
        return runPython(arguments: arguments) != nil
    }

    /// Read the complete bookmark array stored in the PDF catalog.
    ///
    /// The helper prints a JSON array on stdout. This bridge deliberately
    /// returns raw JSON rather than decoding it, so BookmarkManager remains
    /// the owner of the bookmark data model and session-local state.
    static func listBookmarks(
        helperPath: String,
        filePath: String
    ) -> String? {
        let arguments = [
            helperPath,
            "list-bookmarks",
            "--file", filePath
        ]
        return runPython(arguments: arguments)
    }

    /// Add or update a named bookmark. The helper validates the fitz-native
    /// 0-based page index and applies case-insensitive upsert semantics.
    static func setBookmark(
        helperPath: String,
        filePath: String,
        name: String,
        page: Int
    ) -> Bool {
        let arguments = [
            helperPath,
            "set-bookmark",
            "--file", filePath,
            "--name", name,
            "--page", String(page)
        ]
        return runPython(arguments: arguments) != nil
    }

    /// Delete a named bookmark. The helper matches names case-insensitively.
    static func deleteBookmark(
        helperPath: String,
        filePath: String,
        name: String
    ) -> Bool {
        let arguments = [
            helperPath,
            "delete-bookmark",
            "--file", filePath,
            "--name", name
        ]
        return runPython(arguments: arguments) != nil
    }

    /// Read the raw last-displayed page string stored in the PDF catalog.
    ///
    /// The helper prints a fitz-native 0-based page index, or -1 when no
    /// reading position has been stored yet. Like listBookmarks, this bridge
    /// returns the helper's raw output rather than decoding it, so the caller
    /// owns the integer conversion and the unset (-1) / stale-index semantics.
    static func getLastPage(
        helperPath: String,
        filePath: String
    ) -> String? {
        let arguments = [
            helperPath,
            "get-last-page",
            "--file", filePath
        ]
        return runPython(arguments: arguments)
    }

    /// Persist the last-displayed page in the PDF catalog. The page is
    /// fitz-native and 0-based; the helper validates it against the document's
    /// page range and overwrites any previously stored value.
    static func setLastPage(
        helperPath: String,
        filePath: String,
        page: Int
    ) -> Bool {
        let arguments = [
            helperPath,
            "set-last-page",
            "--file", filePath,
            "--page", String(page)
        ]
        return runPython(arguments: arguments) != nil
    }

    // MARK: - Internal: run a Python process

    /// Resolves the venv Python path from the helperPath, runs the process,
    /// and returns trimmed stdout when it exits successfully.
    ///
    /// Path derivation:
    ///   helperPath = .../projects/anima/tools/anima_helper.py
    ///                                  ^^^^^^ project root is 2 levels up
    ///   pythonPath = .../projects/anima/.venv/bin/python3
    private static func runPython(arguments: [String]) -> String? {
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
            return nil
        }

        let status = process.terminationStatus

        if status != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            Swift.print("❌ anima_helper.py failed (exit \(status)): \(stderrString)")
            return nil
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !stdoutString.isEmpty {
            Swift.print("🔧 helper returned: \(stdoutString)")
        }

        return stdoutString
    }
}
