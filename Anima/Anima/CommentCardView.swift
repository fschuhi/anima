//
//  CommentCardView.swift
//  Anima
//
//  A visual representation of a single comment card in the sidebar.
//
//  Interaction:
//    Clicking a card triggers the onClicked closure, which MainViewController
//    uses to emphasize the corresponding highlight in the PDF.
//    Double-clicking triggers onDoubleClicked, used to open the edit dialog.
//    The card itself does not manage emphasis state -- MainViewController calls
//    setActive() and setInactive() to control the visual indication.
//
//  Comment search:
//    MainViewController marks cards whose comment text matches the active
//    comment-search query. All matches receive a thin pale-green border; the
//    current F3 result receives a thicker pale-green border. These visual
//    states are separate from normal annotation emphasis, although search
//    takes visual precedence defensively. Entering either find mode clears
//    annotation emphasis at the coordination layer.
//

import Cocoa

class CommentCardView: NSView {

    let card: CommentCard

    /// Called when the user single-clicks this card.
    var onClicked: ((CommentCard) -> Void)?

    /// Called when the user double-clicks this card.
    var onDoubleClicked: ((CommentCard) -> Void)?

    // UI Elements
    private let titleLabel: NSTextField
    private let divider: NSBox
    private let commentLabel: NSTextField

    // Top-left origin makes layout math easier
    override var isFlipped: Bool { return true }

    // --- Border appearance ---
    private static let activeBorderColor = NSColor.controlAccentColor
    private static let activeBorderWidth: CGFloat = 2.0
    private static let searchMatchBorderColor = NSColor(
        red: 0.70,
        green: 0.90,
        blue: 0.70,
        alpha: 1.0
    )
    private static let searchMatchBorderWidth: CGFloat = 1.0
    private static let currentSearchHitBorderWidth: CGFloat = 3.0
    private static let normalBorderColor = NSColor.separatorColor
    private static let normalBorderWidth: CGFloat = 1.0

    // These states are controlled by MainViewController. They are kept
    // independent because a card can be a search match without being the
    // current F3 result, and annotation emphasis has separate semantics.
    private var isAnnotationActive = false
    private var isSearchMatch = false
    private var isCurrentSearchHit = false

    init(card: CommentCard) {
        self.card = card

        // 1. Initialize UI Elements
        self.titleLabel = NSTextField(labelWithString: "\(card.dateString)  \(card.author)")
        self.titleLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        self.titleLabel.textColor = NSColor.secondaryLabelColor
        self.titleLabel.lineBreakMode = .byTruncatingTail

        self.divider = NSBox()
        self.divider.boxType = .custom
        self.divider.borderType = .lineBorder
        self.divider.borderColor = NSColor.separatorColor
        self.divider.borderWidth = 1

        self.commentLabel = NSTextField(wrappingLabelWithString: card.text)
        self.commentLabel.font = NSFont.systemFont(ofSize: 11)

        // 2. Command Comment Styling
        let text = card.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHeaderCommand = text.hasPrefix("H") && text.count == 2 && text.last!.isNumber
        if text == "link" || isHeaderCommand {
            self.commentLabel.textColor = NSColor.tertiaryLabelColor
        } else {
            self.commentLabel.textColor = NSColor.labelColor
        }

        super.init(frame: .zero)

        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        self.wantsLayer = true
        self.layer?.cornerRadius = 5
        self.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        updateBorderAppearance()

        self.addSubview(titleLabel)
        self.addSubview(divider)
        self.addSubview(commentLabel)
    }

    private func setupLayout() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        commentLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Title Label: Pinned top, left, right with 6px padding
            titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),

            // Divider: 4px below title
            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            divider.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Comment Label: 4px below divider, 6px padding sides and bottom
            commentLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            commentLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            commentLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
            commentLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -6)
        ])
    }

    // MARK: - Visual State

    /// Recomputes the border from the card's independent display states.
    ///
    /// Search states deliberately take precedence. The coordinator clears
    /// annotation emphasis before beginning a search, but this ordering keeps
    /// the card visually correct if state changes briefly overlap.
    private func updateBorderAppearance() {
        if isCurrentSearchHit {
            self.layer?.borderColor = CommentCardView.searchMatchBorderColor.cgColor
            self.layer?.borderWidth = CommentCardView.currentSearchHitBorderWidth
        } else if isSearchMatch {
            self.layer?.borderColor = CommentCardView.searchMatchBorderColor.cgColor
            self.layer?.borderWidth = CommentCardView.searchMatchBorderWidth
        } else if isAnnotationActive {
            self.layer?.borderColor = CommentCardView.activeBorderColor.cgColor
            self.layer?.borderWidth = CommentCardView.activeBorderWidth
        } else {
            self.layer?.borderColor = CommentCardView.normalBorderColor.cgColor
            self.layer?.borderWidth = CommentCardView.normalBorderWidth
        }
    }

    // MARK: - Annotation Emphasis

    /// Visually indicate that this card's highlight is currently emphasized.
    func setActive() {
        isAnnotationActive = true
        updateBorderAppearance()
    }

    /// Restore the card's annotation-emphasis state to inactive.
    func setInactive() {
        isAnnotationActive = false
        updateBorderAppearance()
    }

    // MARK: - Comment Search

    /// Marks or unmarks this card as matching the active comment-search query.
    /// Matching cards use a thin pale-green border unless they are the current
    /// F3 result, which uses the thicker pale-green border.
    func setSearchMatch(_ isMatch: Bool) {
        isSearchMatch = isMatch

        if !isMatch {
            isCurrentSearchHit = false
        }

        updateBorderAppearance()
    }

    /// Marks or unmarks this card as the current F3 comment-search result.
    /// A current hit is necessarily also a match.
    func setCurrentSearchHit(_ isCurrentHit: Bool) {
        isCurrentSearchHit = isCurrentHit

        if isCurrentHit {
            isSearchMatch = true
        }

        updateBorderAppearance()
    }

    // MARK: - Click Handling

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClicked?(card)
        } else if event.clickCount == 1 {
            onClicked?(card)
        }
    }
}
