//
//  CommentInputPanel.swift
//  Anima
//
//  Created by Frank Schuhardt on 23.03.26.
//


//
//  CommentInputPanel.swift
//  Anima
//
//  A modal input panel for adding/editing highlight comments. Replaces the
//  NSAlert-based askForComment() dialog with a proper multi-line text editor.
//
//  Design philosophy (modal-by-conviction):
//    This panel is deliberately modal. Editing a comment is a focused act:
//    the user's attention is on one highlight and its annotation text.
//    Modality enforces this focus at the UI level. There is no cancel —
//    Escape always saves the current text ("always autosave" philosophy).
//    Enter inserts newlines (comments are often multi-line).
//
//  Usage:
//    let newComment = CommentInputPanel.showModal(existingText: "old comment")
//    // Returns the edited text (may be empty if user cleared it)
//
//  Lifecycle:
//    showModal() creates the panel, runs it as a modal session, and tears
//    it down after Escape. The panel is not reused across invocations —
//    each call creates a fresh instance. Session-remembered geometry
//    (Step 4) will use a static property to persist the frame.
//

import Cocoa

class CommentInputPanel: NSPanel {

    // --- Layout constants (easily tunable) ---
    private static let defaultWidth: CGFloat = 420
    private static let defaultHeight: CGFloat = 120

    // The text view where the user types
    private var textView: NSTextView!

    // --- Public API ---

    /// Shows a modal comment input panel and returns the text when dismissed.
    /// The user dismisses with Escape, which always saves the current text.
    /// Enter inserts newlines (standard NSTextView behavior).
    ///
    /// - Parameter existingText: Pre-populated text for editing (empty for new comments)
    /// - Returns: The text content at the time of dismissal
    static func showModal(existingText: String = "") -> String {
        let panel = CommentInputPanel(existingText: existingText)
        NSApp.runModal(for: panel)
        let result = panel.textView.string
        panel.orderOut(nil)
        return result
    }

    // --- Initialization ---

    private init(existingText: String) {
        // Calculate initial frame centered on screen
        let contentRect = CommentInputPanel.centeredRect()

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Panel configuration
        self.title = existingText.isEmpty ? "Add comment" : "Edit comment"
        self.isMovableByWindowBackground = true
        self.level = .modalPanel
        self.isReleasedWhenClosed = false

        // Build the text editor
        setupTextView(existingText: existingText)
    }

    // --- Text View Setup ---

    private func setupTextView(existingText: String) {
        guard let contentView = self.contentView else { return }

        // NSTextView needs to live inside an NSScrollView for proper
        // scroll behavior when text exceeds the visible area.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        // Pre-populate with existing comment text
        textView.string = existingText

        scrollView.documentView = textView

        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // Place cursor at end of existing text
        let endPos = existingText.count
        textView.setSelectedRange(NSRange(location: endPos, length: 0))

        // Ensure the text view gets focus when the panel appears
        self.initialFirstResponder = textView
    }

    // --- Keyboard Handling ---

    // Override keyDown at the panel level to intercept Escape before it
    // propagates. NSTextView would otherwise consume Escape for its own
    // purposes (e.g., cancelling a completion).
    override func keyDown(with event: NSEvent) {
        // Escape key (keyCode 53)
        if event.keyCode == 53 {
            NSApp.stopModal()
            return
        }
        super.keyDown(with: event)
    }

    // Also handle via cancelOperation (the Cocoa-standard Escape handler).
    // Belt and suspenders — some code paths send cancelOperation: instead
    // of a raw keyDown for Escape.
    override func cancelOperation(_ sender: Any?) {
        NSApp.stopModal()
    }

    // --- Geometry Helpers ---

    /// Returns a rect centered on the main screen with the default panel dimensions.
    private static func centeredRect() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = screenFrame.midX - (defaultWidth / 2)
        let y = screenFrame.midY - (defaultHeight / 2)
        return NSRect(x: x, y: y, width: defaultWidth, height: defaultHeight)
    }
}
