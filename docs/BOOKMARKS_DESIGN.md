# Bookmarks (Jumpstation) -- Design & Prep

Status: Draft, prep for the next session. Not yet implemented.
Date: 2026-07-15
Reference material: `docs/JumpStation.bas`, `docs/UserFormSelector.frm` (Excel/VBA, UX inspiration only).

This document prepares the "Bookmarks with jump stack" item from `TODO.md`. It records the decisions we settled during prep, the verified persistence mechanism, the API and UI surface, the keybindings, and a value-first implementation sequence. It is deliberately a prep doc, not an exhaustive spec: it should let the next session start building without re-deriving the decisions, and it names the open questions to confirm before coding.

## Scope and non-goals

In scope:

- Named, full-page bookmarks: a bookmark associates a user-supplied name with a whole page (no sub-page anchor).
- Add a bookmark for the current page (`Cmd+B`), name entered via a prototype `NSAlert`.
- Open a keyboard-first "jumpstation" selector (`Cmd+J`) to filter, pick, and jump.
- Delete the selected bookmark from the jumpstation (`Cmd+D`), with confirmation.
- Unique names, case-insensitive: re-adding an existing name prompts to re-point it to the current page or keep the old association.
- Persistence inside the PDF, surviving reopen, without disturbing the document's existing outline.

Non-goals (explicitly out of scope):

- The ephemeral jump-back stack from the VBA reference. We dropped it -- only the selector ("jumpstation") is in scope. No origin-push, no "jump back" key.
- Sub-page or coordinate-level anchors. A bookmark is always a whole page.
- The final visual selector. The first cut uses an `NSAlert` for naming and a minimal picker; the polished panel is a later step (see Sequencing).
- Multi-user / untrusted-input concerns. Single-user project; no sanitization beyond what fitz needs.

Note on the reference: `JumpStation.bas` / `UserFormSelector.frm` inspire the *navigation and selection* UX -- a modal, keyboard-first, type-to-filter picker with a two-stage Escape. They do **not** cover adding, removing, or renaming (their targets are hard-coded in code). The management half is new to Anima, and it is where most of the decisions below live.

## Persistence (settled and verified)

Bookmarks are stored as a JSON array in a private key in the PDF's document catalog (`/Root`), named `/AnimaBookmarks` to match the existing `/AnimaComment` convention.

Data shape:

```json
[
  {"name": "Endnotes Start", "page": 141},
  {"name": "Important Figure", "page": 36}
]
```

`page` is the fitz-native 0-based page index in this example (the storage base is the one open storage detail to confirm -- see Open Questions). Names preserve the user's display casing; uniqueness is enforced case-insensitively.

Write and read (verified on PyMuPDF 1.26.7 and 1.28.0):

```python
# write (upsert the whole list, then incremental-save to the same file)
doc = fitz.open(path)
doc.xref_set_key(doc.pdf_catalog(), "AnimaBookmarks",
                 fitz.get_pdf_str(json.dumps(bookmarks)))
doc.save(path, incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)

# read
doc = fitz.open(path)
kind, val = doc.xref_get_key(doc.pdf_catalog(), "AnimaBookmarks")
bookmarks = json.loads(val) if kind == "string" else []
```

Why this and not the alternatives:

- **Not the native PDF outline (`/Outlines`).** A PDF has exactly one outline, usually owned by the document's own table of contents; writing bookmarks there would clobber or entangle it. Confirmed: the catalog key leaves an existing outline (`get_toc()`) fully intact.
- **Not `/Info`.** Freshly created and minimal PDFs may have no `/Info` dictionary at all (verified: a fitz-built PDF reported `/Info -> null`), so that route needs an extra "create it first" step. The catalog always exists.
- **Not `set_metadata()`.** The guarded metadata API rejects unknown keys outright -- `ValueError: bad dict key(s): {...}` -- so the custom key must be written at the xref level, exactly as Anima already writes `/NM` and `/Contents`.
- **No PyMuPDF upgrade needed.** The approach works on the current `~=1.26` pin (tested on 1.26.7); `xref_set_key`, `xref_get_key`, `pdf_catalog`, and `get_pdf_str` are all long-standing.

Two corrections relative to the original prep snippet: custom keys go through `xref_set_key`, not `set_metadata`; and incremental save appends to the *opened* file, so it is one path in and out (no `file.pdf -> file_with_marks.pdf` rename), consistent with how `anima_helper.py` already saves.

## Helper API surface (Python)

Reading and writing the catalog key both go through the Python side: PDFKit cannot write the PDF, and it will not surface an arbitrary catalog key on read either. So the helper gains three subcommands, following the existing argparse / exit-code / stdout conventions and mirroring how `SidebarExtractor` already emits JSON that Swift consumes:

- `list-bookmarks --file F` -- prints the JSON array on stdout (empty array if the key is absent). Called once on document load.
- `set-bookmark --file F --name NAME --page N` -- upsert by case-insensitive name (last write wins), then incremental-save. Pure data operation: it does not prompt.
- `delete-bookmark --file F --name NAME` -- remove by case-insensitive name; non-zero exit if the name is absent, mirroring `delete-highlight`'s handling of a nonexistent target.

Ownership of the duplicate-name interaction stays in Swift, not the helper (see below): the helper's `set-bookmark` is a dumb upsert, and the UI decides whether to call it.

Tests are the spec (Rule 5): each subcommand gets pytest coverage -- round-trip a bookmark, upsert an existing name, delete, delete-nonexistent, and a "leaves an existing TOC intact" guard -- before the subcommand is considered done.

## Swift side and local ownership

The feature is additive: it does not touch the dual-write highlight path, the sidebar, or search. Those are deliberately left alone. The new pieces:

- **`BookmarkManager`** (new) -- a toolbox class in the mold of `AnnotationManager`: holds no view or document references, receives context per call, owns the in-memory bookmark list, and calls `FitzBridge` for list/set/delete. Keeping bookmarks out of `AnnotationManager` respects separation of concerns -- a bookmark is a navigation aid, not an annotation.
- **`FitzBridge`** (extend) -- gains `listBookmarks`, `setBookmark`, `deleteBookmark`, each a subprocess call in the same shape as the existing `addHighlight`.
- **`JumpStationPanel`** (new) -- the keyboard-first selector `NSPanel`, modeled on `CommentInputPanel` (modal, styled, Escape-driven). Owns the type-to-filter list and its key handling, lifted from `UserFormSelector`.

Action paths:

- **Add (`Cmd+B`)** -- handled in `AnimaPDFView.keyDown`, alongside the existing `H`/`P`/`G` handling. It reads the current page, shows the naming `NSAlert`, checks the entered name against `BookmarkManager`'s in-memory list (case-insensitive); if it already exists, a second `NSAlert` asks whether to re-point it to the current page or keep the old one; on confirmation it calls `FitzBridge.setBookmark` and updates the in-memory list.
- **Open / jump (`Cmd+J`)** -- presents `JumpStationPanel` populated from the in-memory list; `Enter` jumps to the selected page via `PDFView.go(to:)`, reusing the same navigation path as bare `G`.
- **Delete (`Cmd+D`, inside the panel)** -- confirms via `NSAlert`, then calls `FitzBridge.deleteBookmark`, updates the in-memory list, and refreshes the panel.
- **Read on load** -- when a document opens (the `application(_:open:)` / `MainViewController` load path), call `FitzBridge.listBookmarks` once and populate `BookmarkManager`, the same way `SidebarExtractor` runs at load time.

The in-memory list is the single source of truth during a session (dual-write pattern): every mutation updates both the PDF (via the helper) and the in-memory list, and we never reload the document.

## Keybindings

Settled for the jumpstation (all `Cmd`-modified, to stay clear of the Karabiner Capslock layer where bare letters like `Capslock+J` are remapped to cursor motion):

- `Cmd+J` -- open the jumpstation.
- `Cmd+B` -- add a bookmark for the current page.
- `Cmd+D` -- delete the selected bookmark (inside the panel), with confirmation.
- `Esc` -- exit the jumpstation. Two-stage, per the VBA reference: if a filter string is typed, the first `Esc` clears it; a second `Esc` closes the panel.
- Up / Down -- move the selection.
- Typing (letters, space) -- incremental case-insensitive substring filter; the selection jumps to the first match (`UserFormSelector.FindMatch` behavior).
- `Enter` -- jump to the selected bookmark's page.

Why `Cmd+D` and not `Del`/`Backspace`: inside the panel, `Backspace` must stay bound to editing the filter string, so it cannot also mean "delete bookmark." Outside the panel, `Backspace`/`Del` continue to delete the emphasized highlight in the PDF view -- unchanged.

Comment / future migration (not part of this feature; recorded here at your request): for consistency with the new `Cmd`-modified bindings and to avoid the Karabiner Capslock layer, consider migrating the existing bare reader-mode toggles to `Cmd`-modified equivalents -- persistent-highlight / auto-annotate `H -> Cmd+H`, and the X-Ray toggle `-> Cmd+R`. Two things to resolve before doing so:

- The X-Ray toggle is currently bound to `P` in `AnimaPDFView.keyDown` (`toggleXRayMode()`), not `R`. Confirm the intended source key -- the prep note mentioned `R`, the code says `P`.
- `Cmd+H` is, by macOS convention, the system "Hide application" shortcut. Rebinding it to auto-annotate would shadow that standard behavior; that is possible but unusual, so it should be a conscious choice rather than a surprise. (`Cmd+G` is already reserved for a future Find Next, so bare `G` is staying.)

## Interaction with existing state machines

The jumpstation is a modal panel in the `CommentInputPanel` mold: while open it captures its own keys, so its `Esc` handling is local (the two-stage clear-then-close above) and does not alter the PDF view's existing Esc precedence (PDF-text search -> comment search -> annotation emphasis). Opening the jumpstation is mutually exclusive with search and emphasis, the same way the comment editor is.

## Sequencing (value-first)

Cheapest visible value first; skipping a step should be a conscious choice, not a default.

1. **Persistence + helper.** `list-bookmarks`, `set-bookmark`, `delete-bookmark` in `anima_helper.py`, with pytest coverage (including the "TOC intact" guard). Fully testable with no UI. This is the foundation.
2. **End-to-end minimal UI.** `BookmarkManager` + `FitzBridge` wiring + read-on-load + `Cmd+B` add (with the dedup prompt) + `Cmd+J` open a *minimal* picker (even a plain list) + `Enter` to jump + `Cmd+D` delete with confirm. This is the first point the feature is usable day to day.
3. **Polished selector.** Replace the minimal picker with the keyboard-first `JumpStationPanel` and the `UserFormSelector` type-to-filter experience.

Parked (later, separate): the keybinding migration comment above; the "later visual element" that replaces the `NSAlert` naming prototype.

## Open questions to confirm before coding

- **Page index base.** Store fitz-native 0-based in `/AnimaBookmarks` (proposed, matches the helper's "fitz-native only" convention; the UI converts to 1-based for display and the goto dialog), or store 1-based? One-line decision.
- **X-Ray source key.** `P` (current code) vs `R` (prep note), for the eventual `Cmd+R` migration.
- **`Cmd+H` vs system Hide.** Whether to shadow the standard macOS Hide shortcut for auto-annotate, or pick a different modifier.
- **Where `BookmarkManager` is created and wired** -- presumably `AppDelegate`, alongside `AnnotationManager`.

## References

- `docs/JumpStation.bas`, `docs/UserFormSelector.frm` -- VBA UX inspiration (selection/navigation only).
- `AnnotationManager` -- toolbox-class precedent (no view/doc refs, per-call context).
- `CommentInputPanel` -- keyboard-first modal `NSPanel` precedent.
- `SidebarExtractor` -- load-time JSON-over-subprocess extraction precedent.
- `/AnimaComment` -- private custom-key precedent that `/AnimaBookmarks` follows.
- Bare `G` goto-page -- `PDFView.go(to:)` navigation the jump will reuse.
