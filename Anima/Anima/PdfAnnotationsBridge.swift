// PdfAnnotationsBridge.swift — Anima
//
// Anima's dependency on the neighbouring pdf-annotations project.
//
// THE CONTRACT IS THE CLI (TARGET_ARCHITECTURE.md §3), NOT THE CODE.
// Anima never imports pdf_annot. It runs the resolver as a subprocess inside
// pdf-annotations' own venv and consumes stdout/stderr. Any change to that
// contract is made and verified in pdf-annotations first; Anima adapts second.
//
// Invocation (§3.1):
//   <pdfAnnotationsRoot>/.venv/bin/python3 -m pdf_annot.resolve <HASH>
//   with the process working directory set to <pdfAnnotationsRoot>, so that
//   load_env finds pdf_annot.toml by default-filename-in-CWD resolution.
//
// Outcome (§3.2, §3.3):
//   exit 0   -> stdout holds the fully qualified PDF path, one line.
//   exit != 0 -> stderr holds deliberate human-readable prose (never a
//               traceback). That text is shown verbatim in Anima's alert, so
//               this bridge passes it through unmodified.
//
// Not a sibling of FitzBridge:
//   FitzBridge calls Anima's own backend — same repo, same venv — and a
//   failure there is a developer failure, logged with Swift.print. This bridge
//   consumes another project's declared interface, where a failure (unknown
//   hash, duplicate pdf_id) is a normal, user-facing outcome of everyday
//   library hygiene. Hence the two-case return type instead of String?.
//
// Path resolution:
//   No hardcoded paths. pdfAnnotationsRoot is passed in per call by
//   AppDelegate, which owns it as a constant — the same philosophy that keeps
//   FitzBridge free of paths of its own.

import Foundation

struct PdfAnnotationsBridge {

    /// The two outcomes of a resolution attempt, mirroring the CLI contract.
    ///
    /// `failed` carries prose intended for the user's eyes: either the
    /// resolver's stderr verbatim, or — when the subprocess never produced any
    /// — a sentence composed here. Callers may show it without editing.
    enum ResolveOutcome {
        case resolved(path: String)
        case failed(message: String)
    }

    /// Resolve a `pdf://` hash to a fully qualified PDF path.
    ///
    /// - Parameters:
    ///   - hash: The crc32_az7 string as it appeared in the URL host. Passed
    ///     through as-is: matching is case-insensitive and the resolver
    ///     normalizes before comparison (§3.1), which matters because
    ///     URLComponents lowercases the host on the way in.
    ///   - pdfAnnotationsRoot: Absolute path to the pdf-annotations project.
    ///     Used both to locate the venv interpreter and as the process working
    ///     directory.
    /// - Returns: `.resolved` with the path, or `.failed` with displayable prose.
    static func resolve(
        hash: String,
        pdfAnnotationsRoot: String
    ) -> ResolveOutcome {
        let rootURL = URL(fileURLWithPath: pdfAnnotationsRoot)
        let pythonURL = rootURL.appendingPathComponent(".venv/bin/python3")

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-m", "pdf_annot.resolve", hash]

        // §3.1: CWD must be the project root so load_env finds pdf_annot.toml.
        process.currentDirectoryURL = rootURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            // The venv or the project itself is missing/moved. This is a
            // configuration failure on Anima's side, not a resolver message,
            // so we compose the prose ourselves.
            Swift.print("❌ Failed to launch the pdf-annotations resolver: \(error)")
            Swift.print("   Expected Python at: \(pythonURL.path)")
            return .failed(
                message: """
                    Anima could not start the pdf-annotations resolver.

                    Expected the project's Python interpreter at:
                    \(pythonURL.path)
                    """
            )
        }

        // Read the pipes BEFORE waiting for exit. FitzBridge.runPython does the
        // reverse (waitUntilExit, then read), which deadlocks if a child ever
        // fills a pipe buffer while we wait for it to die — a latent bug noted
        // in TODO.md under "FitzBridge redesign". Not replicated here.
        //
        // Sequential reads are safe at this size: the resolver writes one path
        // on stdout, or a few lines on stderr, both far below the ~64 KB pipe
        // buffer. Reading stdout to EOF cannot block long enough for stderr to
        // back up. The fully general fix — draining both pipes concurrently —
        // is unnecessary ceremony for output this small.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let stdoutText = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Trimming only strips leading/trailing whitespace, so the multi-line
        // duplicate-id message (§3.3) keeps its internal line breaks.
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            Swift.print("↩️ resolver failed (exit \(process.terminationStatus)): \(stderrText)")

            // A nonzero exit with silent stderr violates §3.3, but an empty
            // alert would be worse than an inelegant one.
            let message = stderrText.isEmpty
                ? "The pdf-annotations resolver failed without reporting a reason (exit code \(process.terminationStatus))."
                : stderrText
            return .failed(message: message)
        }

        // Exit 0 with no path is likewise off-contract; treat it as a failure
        // rather than handing an empty path to the opening flow.
        guard !stdoutText.isEmpty else {
            Swift.print("↩️ resolver exited 0 but printed no path")
            return .failed(
                message: "The pdf-annotations resolver reported success but returned no file path."
            )
        }

        Swift.print("🔗 resolved \(hash) -> \(stdoutText)")
        return .resolved(path: stdoutText)
    }
}
