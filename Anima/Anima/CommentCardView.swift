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
//    The card itself does not manage emphasis state — MainViewController calls
//    setActive() and setInactive() to control the visual indication.
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

    // --- Active state appearance ---
    private static let activeBorderColor = NSColor.controlAccentColor
    private static let activeBorderWidth: CGFloat = 2.0
    private static let normalBorderColor = NSColor.separatorColor
    private static let normalBorderWidth: CGFloat = 1.0

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
        self.layer?.borderColor = CommentCardView.normalBorderColor.cgColor
        self.layer?.borderWidth = CommentCardView.normalBorderWidth

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

    // --- Active state (controlled by MainViewController) ---

    /// Visually indicate that this card's highlight is currently emphasized.
    func setActive() {
        self.layer?.borderColor = CommentCardView.activeBorderColor.cgColor
        self.layer?.borderWidth = CommentCardView.activeBorderWidth
    }

    /// Restore the card to its normal visual state.
    func setInactive() {
        self.layer?.borderColor = CommentCardView.normalBorderColor.cgColor
        self.layer?.borderWidth = CommentCardView.normalBorderWidth
    }

    // --- Click handling ---

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClicked?(card)
        } else if event.clickCount == 1 {
            onClicked?(card)
        }
    }
}
