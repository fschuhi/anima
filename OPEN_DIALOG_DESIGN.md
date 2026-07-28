# Open Dialog Design

(Note: "I" in the following paragraphs refers to the user, "you" to the AI model.)

Status: Approved design, not yet implemented. This document absorbs the `TODO.md` item "Open a PDF with `Cmd+O`".

---

## 1. Purpose & Scope

The open dialog is a keyboard-driven launcher over a curated PDF collection, not a filesystem browser. It presents a flat list of the PDFs in a configured search path, narrows the list live as the user types a substring filter, and opens the selected file in the reader.

The cheap path -- the standard `NSOpenPanel` file chooser, wired up in a handful of lines -- was considered and consciously rejected. The daily workflow is "summon a known paper by a fragment of its name", not "navigate a directory tree". A launcher over the controlled collection (see `pdf-annotations`) serves that workflow; a general file browser does not.

Out of scope for v1: multiple search paths, recursive scanning, a settings UI, and the transfer of this UX paradigm to JumpStation. See section 8.

---

## 2. Entry Point

`MainMenu.xib` already contains a File > "Open..." menu item with key equivalent `Cmd+O`, wired to the action `openDocument:` with a First Responder target (target `-1` in the xib). The item is currently grey because nothing in the responder chain implements that action.

The design therefore requires zero xib changes: `AppDelegate` implements `func openDocument(_ sender: Any?)`, the responder chain finds it, and the existing menu item lights up with its conventional name and shortcut.

Modal guard: the dialog declines to open while another modal interaction is active, following the same rule as the `pdf://` scheme handler (beep, log line, no queueing).

The action shows the dialog; the dialog returns a chosen file URL; opening the file goes through the existing hot-open path `loadDocument(url:)`, which already owns document replacement. No new document-lifecycle code.

---

## 3. Data Source & Settings

The file list is produced by a non-recursive scan of a single search path for `*.pdf` at the moment the dialog opens. No caching, no index: the collection is a personal library of controlled size, and a directory listing at dialog-open time is instantaneous at that scale.

The search path is stored in `UserDefaults` under a single key holding the path string. Default value: `~/Obsidian/Papers/Collection/PDFs`. Seeding happens through a `make` target that runs `defaults write` for the app's bundle identifier; the target documents the mechanism and makes the setting reproducible. No settings UI in v1.

Degenerate states are handled before the dialog appears, mirroring JumpStation's "no bookmarks" convention: if the search path does not exist, or exists but contains no PDFs, the reader shows an alert naming the path and the problem instead of presenting a hollow dialog.

Sort order of the full list: alphabetical by filename, case-insensitive. The filter narrows this order; it never reorders.

---

## 4. Panel Structure & Appearance

The dialog is a sibling of `JumpStationPanel`: a modal `NSPanel` run via `NSApp.runModal(for:)`, borderless card look (hidden title bar, `separatorColor` border, corner radius, `textBackgroundColor` background), an embedded table view that routes its own key events, movable by window background.

Approach A applies: the panel skeleton is duplicated from `JumpStationPanel`, not extracted into a shared base. The duplication is a conscious decision -- extraction waits until the JumpStation transfer produces a second real consumer of the filtering paradigm, so the shared shape is learned from two concrete examples rather than guessed from one.

Layout, top to bottom:

- **Filter label**: a display-only text label showing the current filter string, styled in the 9pt medium system font used by the sidebar card titles, `secondaryLabelColor`. When the filter is empty it shows a quiet placeholder (e.g. "type to filter") so the row is never a mystery gap. The label is not a focused text field; the table keeps the keyboard at all times.
- **File table**: single column, one row per matching PDF, filename without path. Row height and fonts follow the JumpStation table conventions.

The filter label exists for one load-bearing reason: it is the only place the filter string remains visible when the filter matches nothing and the table is empty. In that moment the label is the user's diagnostic -- it shows exactly what was typed, and `Backspace` visibly walks back to a matching state.

---

## 5. Filter & Selection State Machine

The dialog is modeless. There is no mode flag anywhere in the design: letters always edit the filter, arrows always move the selection. A whole class of "which mode am I in" states and bugs is structurally impossible because the only state variables are the filter string and the selection index.

**Model state:**

- `filterString: String` -- single source of truth for what the user has typed. The label renders it; the match list derives from it. It is never stored in or read back from a view.
- Selection index -- which visible row is selected, or none when the list is empty.

**Key map:**

| Key | Effect |
| --- | --- |
| Printable character | Append to `filterString`, re-filter, snap selection to first row |
| `Backspace` | Remove last character of `filterString`, re-filter, snap selection to first row |
| `Up` / `Down` | Move selection within the visible rows |
| `Enter` | Close the dialog, open the selected row via `loadDocument(url:)` |
| `Escape` (filter non-empty) | Clear `filterString`, show the full list, snap selection to first row |
| `Escape` (filter empty) | Close the dialog without opening anything |

**Filtering rule:** case-insensitive substring match of `filterString` against the filename. An empty filter matches everything.

**Selection rule (snap-to-first):** after every change to `filterString` -- append, `Backspace`, or `Escape`-clear -- the selection snaps to the first visible row. Arrowing down and then typing therefore pulls the selection back to the top; this predictability is the accepted price of the rule. Selection plus filtering together resolve the shared-prefix problem: when several filenames share a long common prefix, the user types a few characters and arrows to the wanted row instead of typing the prefix to its point of divergence.

**Empty-match state:** when no filename matches, the table shows no rows and nothing is selected. `Enter` beeps. The filter label shows the non-matching string; `Backspace` and `Escape` are the ways back. The dialog does not prevent this state -- the label makes it legible instead.

**Mouse:** clicks select rows only, as in JumpStation; only `Enter` opens. Right-click selects like left-click; no context menu in v1.

---

## 6. Match Display

Each visible row renders its filename as an `NSAttributedString` with the first occurrence of the matched substring emphasized (bold or a subtle background on the matched range; exact styling decided at implementation against Dark Mode). First occurrence only -- the mark exists so the eye can confirm the match, and one range keeps the rendering trivial. Subsequent occurrences within the same filename are not marked.

With an empty filter, rows render as plain strings with no marking.

---

## 7. Testability

The filter and selection logic is designed and tested as a plain Swift type before it is wired into the panel, in the spirit of the JumpStation note about designing the non-visual state machine separately. The type owns `filterString`, the full file list, the derived visible list, the selection index, and the key-event transitions from section 5. It knows nothing about AppKit views.

Test spec, at minimum: append and `Backspace` transitions; case-insensitive substring matching; snap-to-first after every filter change; two-stage `Escape`; `Enter` behavior with a selection, and beep-path with none; empty-match entry and recovery; first-occurrence range computation for the match display.

The panel itself then reduces to rendering this type's state and forwarding key events -- thin enough that manual testing covers it.

---

## 8. Deferred

- **Multiple search paths** and **recursive scanning**: revisit if the collection outgrows a single flat directory. The `UserDefaults` key would become an array of strings; nothing in this design blocks that.
- **Settings UI**: `defaults write` via the `make` target suffices for a single user; a preferences panel is not worth its ceremony yet.
- **JumpStation transfer**: after this dialog's UX has proven itself in daily use, transfer the paradigm to JumpStation (substring filter instead of prefix matching, page-number ordering, the modeless key map). At that point, evaluate extracting the shared filtering-panel shape from the two concrete implementations.
- **Open Recent**: the xib's stock "Open Recent" submenu is untouched by this design; whether Anima should feed it is a separate, unexamined question.
