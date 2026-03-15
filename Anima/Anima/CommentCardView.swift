//
//  CommentCardView.swift
//  Anima
//
//  Created by Frank Schuhardt on 15.03.26.
//


//
//  CommentCardView.swift
//  Anima
//
//  A visual representation of a single comment card in the sidebar.
//

import Cocoa

class CommentCardView: NSView {

    let card: CommentCard

    // UI Elements
    private let titleLabel: NSTextField
    private let divider: NSBox
    private let commentLabel: NSTextField

    // Top-left origin makes layout math easier
    override var isFlipped: Bool { return true }

    init(card: CommentCard) {
        self.card = card

        // 1. Initialize UI Elements
        // NSTextField(labelWithString:) automatically makes it read-only, borderless, and transparent
        self.titleLabel = NSTextField(labelWithString: "\(card.dateString)  \(card.author)")
        self.titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        self.titleLabel.textColor = NSColor.secondaryLabelColor
        self.titleLabel.lineBreakMode = .byTruncatingTail

        self.divider = NSBox()
        self.divider.boxType = .custom
        self.divider.borderType = .lineBorder
        self.divider.borderColor = NSColor.separatorColor
        self.divider.borderWidth = 1

        // NSTextField(wrappingLabelWithString:) automatically configures multi-line wrapping
        self.commentLabel = NSTextField(wrappingLabelWithString: card.text)
        self.commentLabel.font = NSFont.systemFont(ofSize: 12)

        // 2. Command Comment Styling
        // If it's a pipeline instruction ("link", "H1", etc.), make it light gray.
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
        // Use semantic colors so it looks perfect in both Light and Dark mode
        self.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        self.layer?.cornerRadius = 6
        self.layer?.borderColor = NSColor.separatorColor.cgColor
        self.layer?.borderWidth = 1

        self.addSubview(titleLabel)
        self.addSubview(divider)
        self.addSubview(commentLabel)
    }

    private func setupLayout() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        commentLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Title Label: Pinned to top, left, right with 8px padding
            titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),

            // Divider: 4px below title, spans full width, 1px tall
            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            divider.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Comment Label: 6px below divider, 8px padding sides and bottom
            commentLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            commentLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            commentLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            commentLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8)
        ])
    }
}
