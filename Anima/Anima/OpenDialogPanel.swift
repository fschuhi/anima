//
//  OpenDialogPanel.swift
//  Anima
//
//  Modal keyboard launcher over the curated PDF collection (Cmd+O).
//  Specified in docs/OPEN_DIALOG_DESIGN.md sections 4-6. Panel skeleton is
//  a deliberate duplication of JumpStationPanel's (design doc section 4,
//  Approach A) -- extraction waits until the JumpStation transfer produces
//  a second real consumer.
//
//  All filter/selection logic lives in OpenDialogState and
//  OpenDialogKeyTranslator; this file only renders that state and forwards
//  events, per section 7's "thin enough that manual testing covers it."
//

import Cocoa

/// NSTableView variant that keeps this panel's keyboard and right-click
/// behavior local to the modal panel instead of leaking it to the PDF view.
/// Mirrors JumpStationPanel's BookmarkTableView.
private final class FilenameTableView: NSTableView {

    var onKeyEvent: ((NSEvent) -> Bool)?
    var onRightClickRow: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// Right-click selects like left-click; no context menu in v1
    /// (design doc section 5).
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

final class OpenDialogPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Layout Constants

    private static let defaultWidth: CGFloat = 440
    private static let defaultHeight: CGFloat = 320
    private static let cornerRadius: CGFloat = 5
    private static let borderWidth: CGFloat = 1
    private static let internalPadding: CGFloat = 6
    private static let filterLabelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    private static let rowFont = NSFont.systemFont(ofSize: 11)  // matches CommentCardView's commentLabel
    private static let rowHeight: CGFloat = 16
    private static let filterPlaceholder = "type to filter"

    // MARK: - State

    /// Single source of truth for filter string and selection. Every key
    /// event replaces this via OpenDialogState.applying; mouse clicks go
    /// through OpenDialogState.selecting(_:in:) instead, in
    /// tableViewSelectionDidChange(_:) -- the one place this panel touches
    /// `state` outside the reducer.
    private var state: OpenDialogState

    private let onOpen: (String) -> Void

    private let filterLabel = NSTextField(labelWithString: "")
    private let tableView = FilenameTableView()
    private let scrollView = NSScrollView()

    // MARK: - Public API

    /// Presents a modal open dialog over `filenames`. Callers should check
    /// for an empty collection beforehand and show the reader-level
    /// path/empty-collection alert instead (design doc section 3) -- this
    /// panel assumes a non-empty list, mirroring JumpStationPanel's own
    /// contract for bookmarks.
    static func showModal(
        filenames: [String],
        onOpen: @escaping (String) -> Void
    ) {
        let panel = OpenDialogPanel(filenames: filenames, onOpen: onOpen)

        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
    }

    // MARK: - Initialization

    private init(filenames: [String], onOpen: @escaping (String) -> Void) {
        self.state = .initial(fullFilenames: filenames)
        self.onOpen = onOpen

        let styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]

        super.init(
            contentRect: OpenDialogPanel.centeredRect(),
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
        refresh()

        initialFirstResponder = tableView
    }

    // MARK: - Appearance and Layout

    private func setupAppearance() {
        guard let contentView = contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = OpenDialogPanel.cornerRadius
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor
        contentView.layer?.borderWidth = OpenDialogPanel.borderWidth
        contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    private func setupTable() {
        let filenameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filename"))
        filenameColumn.width = 400
        filenameColumn.minWidth = 200

        tableView.addTableColumn(filenameColumn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.rowHeight = OpenDialogPanel.rowHeight
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

        tableView.onRightClickRow = { [weak self] row in
            self?.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        guard let contentView = contentView else { return }

        filterLabel.font = OpenDialogPanel.filterLabelFont
        filterLabel.textColor = NSColor.secondaryLabelColor
        filterLabel.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .custom
        divider.borderType = .lineBorder
        divider.borderColor = NSColor.separatorColor
        divider.borderWidth = 1
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(filterLabel)
        contentView.addSubview(divider)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            filterLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: OpenDialogPanel.internalPadding
            ),
            filterLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: OpenDialogPanel.internalPadding + 2
            ),
            filterLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -OpenDialogPanel.internalPadding
            ),

            divider.topAnchor.constraint(equalTo: filterLabel.bottomAnchor, constant: 4),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: OpenDialogPanel.internalPadding
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -OpenDialogPanel.internalPadding
            ),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -OpenDialogPanel.internalPadding
            ),
        ])
    }

    // MARK: - Table Data Source

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.visibleFilenames.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn = tableColumn else { return nil }

        let filename = state.visibleFilenames[row]
        let cell = reusableCell(for: tableView, identifier: tableColumn.identifier)

        cell.textField?.attributedStringValue = OpenDialogPanel.attributedFilename(
            filename,
            filterString: state.filterString
        )

        return cell
    }

    private func reusableCell(
        for tableView: NSTableView,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSTableCellView {
        if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byClipping
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

    /// Sizes the single column to fit the widest currently-visible filename,
    /// so rows render on one line and overflow becomes a genuine horizontal
    /// scrollbar instead of wrapping. Recomputed on every refresh(), since
    /// the widest entry changes as the filter narrows the visible list.
    private func updateColumnWidth() {
        guard let column = tableView.tableColumns.first else { return }

        let widths = state.visibleFilenames.map {
            ($0 as NSString).size(withAttributes: [.font: OpenDialogPanel.rowFont]).width
        }
        let contentWidth = (widths.max() ?? 0) + 12  // matches the cell's 6pt leading/trailing insets

        column.width = max(contentWidth, OpenDialogPanel.defaultWidth - (2 * OpenDialogPanel.internalPadding))
    }

    /// Section 6: the first case-insensitive occurrence of `filterString` in
    /// `filename` rendered bold; first occurrence only. An empty filter
    /// renders the filename as a plain string with no marking. Converts
    /// OpenDialogState's String.Index range to the NSRange an
    /// NSAttributedString needs.
    private static func attributedFilename(_ filename: String, filterString: String) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: filename.utf16.count)

        // NSTextField ignores its own lineBreakMode once attributedStringValue
        // is assigned directly -- the attributed string's own paragraph style
        // takes over, and NSParagraphStyle's default wraps by word. Setting
        // .byClipping here is what actually stops rows from wrapping; it
        // doesn't truncate with an ellipsis either, since updateColumnWidth()
        // sizes the column to fit the full text and a horizontal scrollbar
        // handles anything wider than the panel itself.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let result = NSMutableAttributedString(string: filename)
        result.addAttributes(
            [
                .foregroundColor: NSColor.labelColor,
                .font: OpenDialogPanel.rowFont,
                .paragraphStyle: paragraphStyle,
            ],
            range: fullRange
        )

        guard let matchRange = OpenDialogState.firstMatchRange(of: filterString, in: filename) else {
            return result
        }

        result.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: OpenDialogPanel.rowFont.pointSize),
            range: NSRange(matchRange, in: filename)
        )
        return result
    }

    // MARK: - Rendering

    private func refresh() {
        filterLabel.stringValue = state.filterString.isEmpty
            ? OpenDialogPanel.filterPlaceholder
            : state.filterString

        updateColumnWidth()
        tableView.reloadData()

        if let index = state.selectionIndex {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
    }

    // MARK: - Keyboard Handling

    private func handleTableKeyEvent(_ event: NSEvent) -> Bool {
        guard let key = OpenDialogKeyTranslator.translate(event) else {
            return false
        }

        switch OpenDialogState.applying(key, to: state) {
        case .updated(let next):
            state = next
            refresh()

        case .open(let filename):
            closeModal()
            onOpen(filename)

        case .close:
            closeModal()

        case .beep:
            NSSound.beep()
        }

        return true
    }

    // MARK: - Mouse Selection

    /// Mouse clicks select rows only (design doc section 5); Enter is the
    /// only way to open. A click is not one of OpenDialogKey's six cases,
    /// so it bypasses OpenDialogState.applying and goes through
    /// OpenDialogState.selecting(_:in:) instead.
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        state = OpenDialogState.selecting(selectedRow >= 0 ? selectedRow : nil, in: state)
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
