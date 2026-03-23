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
//  Visual design:
//    The panel is styled to match CommentCardView — same background color,
//    corner radius, fonts, and color palette. A custom title label ("Add
//    comment" / "Edit comment") replaces the native window title, rendered
//    in the same muted style as the card's date/author line. A thin divider
//    separates the title from the text editor, mirroring the card layout.
//    The native traffic light buttons are hidden; Escape is the only exit.
//
//  Session geometry:
//    TODO: Save panel frame after dismissal and restore on next invocation.
//    Deferred — needs investigation into NSPanel/NSWindow frame lifecycle
//    to understand why setFrame is ignored before runModal.
//
//  Usage:
//    let newComment = CommentInputPanel.showModal(existingText: "old comment")
//    // Returns the edited text (may be empty if user cleared it)
//
//  Lifecycle:
//    showModal() creates the panel, runs it as a modal session, and tears
//    it down after Escape. The panel is not reused across invocations —
//    each call creates a fresh instance.
//

import Cocoa

class CommentInputPanel: NSPanel {

    // --- Layout constants (easily tunable) ---
    private static let defaultWidth: CGFloat = 420
    private static let defaultHeight: CGFloat = 120

    // --- Card-matched style constants (mirror CommentCardView) ---
    private static let cornerRadius: CGFloat = 5
    private static let borderWidth: CGFloat = 1.0
    private static let titleFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    private static let titleColor = NSColor.secondaryLabelColor
    private static let commentFont = NSFont.systemFont(ofSize: 11)
    private static let internalPadding: CGFloat = 6
    private static let dividerTopSpacing: CGFloat = 4
    private static let dividerBottomSpacing: CGFloat = 4

    // Leading padding for the title label — aligned with the text view's
    // effective left edge (internalPadding 6 + textContainerInset.width 2 = 8).
    private static let titleLeadingPadding: CGFloat = 8

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
        self.isMovableByWindowBackground = true
        self.level = .modalPanel
        self.isReleasedWhenClosed = false

        // Hide the native title text — we render our own title label
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        // Hide the traffic light buttons (close, minimize, zoom)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Card-matched appearance on the content view
        if let contentView = self.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = CommentInputPanel.cornerRadius
            contentView.layer?.borderColor = NSColor.separatorColor.cgColor
            contentView.layer?.borderWidth = CommentInputPanel.borderWidth
            contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }

        // Build the UI: title label + divider + text editor
        let isNewComment = existingText.isEmpty
        setupUI(titleText: isNewComment ? "Add comment" : "Edit comment",
                existingText: existingText)
    }

    // --- UI Setup ---

    private func setupUI(titleText: String, existingText: String) {
        guard let contentView = self.contentView else { return }

        // --- Title label (matches card's date/author line) ---
        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = CommentInputPanel.titleFont
        titleLabel.textColor = CommentInputPanel.titleColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // --- Divider (matches card's title/comment separator) ---
        let divider = NSBox()
        divider.boxType = .custom
        divider.borderType = .lineBorder
        divider.borderColor = NSColor.separatorColor
        divider.borderWidth = 1
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        // --- Text editor (NSTextView inside NSScrollView) ---
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = CommentInputPanel.commentFont
        textView.textColor = NSColor.labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        // Pre-populate with existing comment text
        textView.string = existingText

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // --- Layout constraints ---
        // With .fullSizeContentView, our content extends behind the
        // transparent title bar. We place the title label at the same
        // internalPadding (6pt) as the card, sitting inside the title
        // bar zone — which is fine since the title bar is invisible.
        NSLayoutConstraint.activate([
            // Title label: tight to top, left-aligned with text content
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: CommentInputPanel.internalPadding),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: CommentInputPanel.titleLeadingPadding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -CommentInputPanel.internalPadding),

            // Divider: below title
            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: CommentInputPanel.dividerTopSpacing),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Scroll view (text editor): fills remaining space
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: CommentInputPanel.dividerBottomSpacing),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: CommentInputPanel.internalPadding),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -CommentInputPanel.internalPadding),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -CommentInputPanel.internalPadding),
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
