//
//  JumpStationPanel.swift
//  Anima
//
//  A modal bookmark-navigation panel.
//
//  Current scope:
//    - Displays named page bookmarks in a two-column NSTableView.
//    - Mouse clicks select rows only; only Enter performs navigation.
//    - Up/Down moves selection; Escape closes the panel.
//    - Cmd+D confirms and deletes the selected bookmark.
//
//  Deliberately deferred:
//    The future JumpStation extension will add a display-only prefix panel,
//    case-insensitive prefix matching, Backspace behavior, and two-stage
//    Escape. That stateful keyboard behavior will be designed and tested
//    separately rather than being prebuilt here.
//

import Cocoa

/// NSTableView variant that keeps JumpStation's keyboard and right-click
/// behavior local to the modal panel instead of leaking it to the PDF view.
private final class BookmarkTableView: NSTableView {

    var onKeyEvent: ((NSEvent) -> Bool)?
    var onRightClickRow: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }

    /// Standard table behavior selects with a left click. Explicitly selecting
    /// on right click gives all mouse clicks the same "selection only" meaning.
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        if clickedRow >= 0 {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            onRightClickRow?(clickedRow)
        }

        super.rightMouseDown(with: event)
    }
}

final class JumpStationPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Layout Constants

    private static let defaultWidth: CGFloat = 440
    private static let defaultHeight: CGFloat = 320
    private static let cornerRadius: CGFloat = 5
    private static let borderWidth: CGFloat = 1
    private static let internalPadding: CGFloat = 6
    private static let titleFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    private static let rowHeight: CGFloat = 26

    // MARK: - State

    private var bookmarks: [Bookmark]

    /// Called after the panel has closed because the user pressed Enter.
    private let onJump: (Bookmark) -> Void

    /// Called after deletion is confirmed. The closure owns persistence and
    /// returns the manager's refreshed list on success, or nil on failure.
    private let onDelete: (Bookmark) -> [Bookmark]?

    private let tableView = BookmarkTableView()
    private let scrollView = NSScrollView()

    // MARK: - Public API

    /// Presents a modal JumpStation panel.
    ///
    /// Callers should check for an empty bookmark list before invoking this
    /// method and show the reader-level "No bookmarks" alert instead.
    static func showModal(
        bookmarks: [Bookmark],
        onJump: @escaping (Bookmark) -> Void,
        onDelete: @escaping (Bookmark) -> [Bookmark]?
    ) {
        let panel = JumpStationPanel(
            bookmarks: bookmarks,
            onJump: onJump,
            onDelete: onDelete
        )

        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
    }

    // MARK: - Initialization

    private init(
        bookmarks: [Bookmark],
        onJump: @escaping (Bookmark) -> Void,
        onDelete: @escaping (Bookmark) -> [Bookmark]?
    ) {
        self.bookmarks = bookmarks
        self.onJump = onJump
        self.onDelete = onDelete

        let styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]

        super.init(
            contentRect: JumpStationPanel.centeredRect(),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        level = .modalPanel

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        setupAppearance()
        setupTable()
        setupLayout()

        initialFirstResponder = tableView
    }

    // MARK: - Appearance and Layout

    private func setupAppearance() {
        guard let contentView = contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = JumpStationPanel.cornerRadius
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor
        contentView.layer?.borderWidth = JumpStationPanel.borderWidth
        contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    private func setupTable() {
        let bookmarkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bookmark"))
        bookmarkColumn.width = 340
        bookmarkColumn.minWidth = 200
        bookmarkColumn.resizingMask = .autoresizingMask

        let pageColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        pageColumn.width = 70
        pageColumn.minWidth = 55
        pageColumn.maxWidth = 90
        pageColumn.resizingMask = .autoresizingMask

        tableView.addTableColumn(bookmarkColumn)
        tableView.addTableColumn(pageColumn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.rowHeight = JumpStationPanel.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.focusRingType = .none

        tableView.onKeyEvent = { [weak self] event in
            self?.handleTableKeyEvent(event) ?? false
        }

        tableView.onRightClickRow = { [weak self] _ in
            self?.tableView.window?.makeFirstResponder(self?.tableView)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        guard let contentView = contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Bookmarks")
        titleLabel.font = JumpStationPanel.titleFont
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .custom
        divider.borderType = .lineBorder
        divider.borderColor = NSColor.separatorColor
        divider.borderWidth = 1
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(divider)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: JumpStationPanel.internalPadding
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: JumpStationPanel.internalPadding + 2
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -JumpStationPanel.internalPadding
            ),

            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: JumpStationPanel.internalPadding
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -JumpStationPanel.internalPadding
            ),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -JumpStationPanel.internalPadding
            ),
        ])
    }

    // MARK: - Table Data Source

    func numberOfRows(in tableView: NSTableView) -> Int {
        bookmarks.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn = tableColumn else { return nil }

        let bookmark = bookmarks[row]
        let identifier = tableColumn.identifier

        let cell = reusableCell(
            for: tableView,
            identifier: identifier,
            textAlignment: identifier.rawValue == "page" ? .right : .left
        )

        if identifier.rawValue == "bookmark" {
            cell.textField?.stringValue = bookmark.name
            cell.textField?.textColor = NSColor.labelColor
        } else {
            cell.textField?.stringValue = String(bookmark.page + 1)
            cell.textField?.textColor = NSColor.secondaryLabelColor
        }

        return cell
    }

    private func reusableCell(
        for tableView: NSTableView,
        identifier: NSUserInterfaceItemIdentifier,
        textAlignment: NSTextAlignment
    ) -> NSTableCellView {
        if let cell = tableView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? NSTableCellView {
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.alignment = textAlignment
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    // MARK: - Keyboard Handling

    private func handleTableKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+D deletes the selected bookmark. Backspace and Delete remain
        // intentionally unused here; the future prefix-input behavior needs
        // Backspace for editing the typed prefix.
        if event.keyCode == 2,
           modifiers.contains(.command),
           !modifiers.contains(.shift),
           !modifiers.contains(.control),
           !modifiers.contains(.option) {
            requestDeletionOfSelectedBookmark()
            return true
        }

        // Enter / numeric keypad Enter performs the only jump action.
        if event.keyCode == 36 || event.keyCode == 76 {
            jumpToSelectedBookmark()
            return true
        }

        // Escape always closes at this first implementation stage. The later
        // prefix-input extension will make Escape clear a non-empty prefix
        // before a second Escape closes the panel.
        if event.keyCode == 53 {
            closeModal()
            return true
        }

        // Explicitly define useful behavior from the no-selection state.
        if event.keyCode == 125 {
            moveSelectionDown()
            return true
        }

        if event.keyCode == 126 {
            moveSelectionUp()
            return true
        }

        return false
    }

    private func moveSelectionDown() {
        guard !bookmarks.isEmpty else {
            NSSound.beep()
            return
        }

        let currentRow = tableView.selectedRow
        let nextRow = currentRow < 0
            ? 0
            : min(currentRow + 1, bookmarks.count - 1)

        selectRow(nextRow)
    }

    private func moveSelectionUp() {
        guard !bookmarks.isEmpty else {
            NSSound.beep()
            return
        }

        let currentRow = tableView.selectedRow
        let previousRow = currentRow < 0
            ? bookmarks.count - 1
            : max(currentRow - 1, 0)

        selectRow(previousRow)
    }

    private func selectRow(_ row: Int) {
        tableView.selectRowIndexes(
            IndexSet(integer: row),
            byExtendingSelection: false
        )
        tableView.scrollRowToVisible(row)
    }

    // MARK: - Jump and Delete

    private func jumpToSelectedBookmark() {
        guard let bookmark = selectedBookmark else {
            NSSound.beep()
            return
        }

        closeModal()
        onJump(bookmark)
    }

    private func requestDeletionOfSelectedBookmark() {
        guard let bookmark = selectedBookmark else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Bookmark?"
        alert.informativeText = "Delete \"\(bookmark.name)\" from page \(bookmark.page + 1)?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        guard let updatedBookmarks = onDelete(bookmark) else {
            NSSound.beep()
            return
        }

        bookmarks = updatedBookmarks
        tableView.reloadData()
        tableView.deselectAll(nil)

        // The opening path prevents an empty panel. If the user deletes
        // the final bookmark while already in JumpStation, close cleanly.
        if bookmarks.isEmpty {
            closeModal()
        }
    }

    private var selectedBookmark: Bookmark? {
        let selectedRow = tableView.selectedRow

        guard bookmarks.indices.contains(selectedRow) else {
            return nil
        }

        return bookmarks[selectedRow]
    }

    private func closeModal() {
        NSApp.stopModal()
    }

    // MARK: - Geometry

    private static func centeredRect() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        return NSRect(
            x: screenFrame.midX - (defaultWidth / 2),
            y: screenFrame.midY - (defaultHeight / 2),
            width: defaultWidth,
            height: defaultHeight
        )
    }
}
