//
//  OpenDialogState.swift
//  Anima
//
//  Filter and selection state for the Cmd+O open dialog.
//  Specified in docs/OPEN_DIALOG_DESIGN.md, sections 5-7; this file
//  implements the key map from section 5 as a pure reducer, and section 6's
//  match-range computation for the panel's display layer.
//
//  Deliberately knows nothing about NSPanel, NSTableView, or file-system
//  scanning. It holds whatever filename list it is handed and filters
//  within that list's existing order -- it neither sorts nor re-sorts. The
//  caller (the panel) owns presenting outcomes: opening a file, closing the
//  dialog, or beeping.
//

import Foundation

/// The six inputs the open dialog responds to, per the key map in
/// OPEN_DIALOG_DESIGN.md section 5. Modeless throughout: there is no mode
/// flag anywhere in this file, only the transitions below.
nonisolated enum OpenDialogKey: Equatable {
    case character(Character)
    case backspace
    case up
    case down
    case enter
    case escape
}

/// What the panel should do after a key is applied. Two of the six keys
/// (Enter, Escape-when-empty) fall outside pure state -- they ask the host
/// to open a file or close the dialog -- so the reducer returns an outcome
/// rather than always returning a new state.
nonisolated enum OpenDialogOutcome: Equatable {
    case updated(OpenDialogState)
    case open(String)   // filename of the row to load
    case close
    case beep           // Enter with no selection (empty-match state)
}

nonisolated struct OpenDialogState: Equatable {

    /// The full collection, in whatever order the caller supplied it.
    /// Never reordered here -- section 3 assigns sorting to the directory
    /// scan, and section 5 says filtering "narrows this order; it never
    /// reorders."
    let fullFilenames: [String]

    /// Single source of truth for what the user has typed. Never stored in
    /// or read back from a view.
    private(set) var filterString: String

    /// Index into `visibleFilenames`, not `fullFilenames` -- its meaning is
    /// only stable within one filter state, which is exactly what
    /// snap-to-first (see `applying`) exists to keep sound across changes.
    /// nil exactly when `visibleFilenames` is empty.
    private(set) var selectionIndex: Int?

    /// The dialog's state when it first opens: full list, empty filter,
    /// first row selected unless the collection is empty.
    static func initial(fullFilenames: [String]) -> OpenDialogState {
        OpenDialogState(
            fullFilenames: fullFilenames,
            filterString: "",
            selectionIndex: fullFilenames.isEmpty ? nil : 0
        )
    }

    /// Case-insensitive substring filter, computed fresh on every access
    /// rather than cached. At personal-library scale (section 3: no index,
    /// no caching needed) this is cheap, and it removes any possibility of
    /// a stale cache diverging from `filterString`.
    var visibleFilenames: [String] {
        guard !filterString.isEmpty else { return fullFilenames }
        return fullFilenames.filter {
            $0.range(of: filterString, options: .caseInsensitive) != nil
        }
    }

    var selectedFilename: String? {
        guard let index = selectionIndex, visibleFilenames.indices.contains(index) else {
            return nil
        }
        return visibleFilenames[index]
    }

    /// The single reducer for all six keys in section 5's table.
    static func applying(_ key: OpenDialogKey, to state: OpenDialogState) -> OpenDialogOutcome {
        switch key {
        case .character(let char):
            return .updated(snappedToFirst(of: state, filterString: state.filterString + String(char)))

        case .backspace:
            return .updated(snappedToFirst(of: state, filterString: String(state.filterString.dropLast())))

        case .up:
            return .updated(movingSelection(of: state, by: -1))

        case .down:
            return .updated(movingSelection(of: state, by: 1))

        case .enter:
            if let filename = state.selectedFilename {
                return .open(filename)
            }
            return .beep

        case .escape:
            if state.filterString.isEmpty {
                return .close
            }
            return .updated(snappedToFirst(of: state, filterString: ""))
        }
    }

    /// Shared by the character, backspace, and non-empty-escape cases: every
    /// change to `filterString` snaps the selection to the first visible row
    /// (section 5, "Selection rule").
    private static func snappedToFirst(of state: OpenDialogState, filterString: String) -> OpenDialogState {
        var next = OpenDialogState(
            fullFilenames: state.fullFilenames,
            filterString: filterString,
            selectionIndex: nil
        )
        next.selectionIndex = next.visibleFilenames.isEmpty ? nil : 0
        return next
    }

    /// Up/Down move within the visible rows, clamped at both ends -- no
    /// wraparound. A no-op (returns state unchanged) when the visible list
    /// is empty, since there is nothing to move a selection across.
    private static func movingSelection(of state: OpenDialogState, by delta: Int) -> OpenDialogState {
        let visibleCount = state.visibleFilenames.count
        guard visibleCount > 0, let current = state.selectionIndex else {
            return state
        }
        let clamped = min(max(current + delta, 0), visibleCount - 1)
        var next = state
        next.selectionIndex = clamped
        return next
    }

    /// Section 6: the range of the first case-insensitive occurrence of
    /// `filterString` within `filename`, for the panel to render as
    /// emphasized text. nil when the filter is empty (rows render as plain
    /// strings) or when there is no match.
    static func firstMatchRange(of filterString: String, in filename: String) -> Range<String.Index>? {
        guard !filterString.isEmpty else { return nil }
        return filename.range(of: filterString, options: .caseInsensitive)
    }

    /// Sets the selection directly to a specific visible-row index, or nil
    /// to clear it. For mouse clicks, which are not one of OpenDialogKey's
    /// six cases and therefore never go through `applying`.
    static func selecting(_ index: Int?, in state: OpenDialogState) -> OpenDialogState {
        var next = state
        next.selectionIndex = index
        return next
    }
}
