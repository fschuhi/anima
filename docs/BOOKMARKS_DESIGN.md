# Bookmarks (Jumpstation) -- Design & Prep

Status: In progress. Persistence, session state, automated coverage, and `Cmd+B` bookmark creation are implemented; navigation and deletion remain.
Date: 2026-07-15
Reference material: `docs/JumpStation.bas`, `docs/UserFormSelector.frm` (Excel/VBA, UX inspiration only).

This document records the bookmark design, implementation progress, settled persistence contract, API and UI surface, keybindings, and remaining value-first sequence. It is a working handover document rather than an exhaustive spec: the next session should be able to begin bookmark navigation without re-deriving earlier decisions.

## Scope and non-goals

In scope:

- Named, full-page bookmarks: a bookmark associates a user-supplied name with a whole page (no sub-page anchor).
- Add a bookmark for the current page (`Cmd+B`) through a prototype `NSAlert`. Implemented.
- Open a keyboard-first "jumpstation" selector (`Cmd+J`) to filter, pick, and jump. Next.
- Delete the selected bookmark from the jumpstation (`Cmd+D`), with confirmation. Next.
- Unique names, case-insensitive: re-adding an existing name prompts to re-point it to the current page or keep the old association. Implemented for `Cmd+B`.
- Persistence inside the PDF, surviving reopen, without disturbing the document's existing outline. Implemented.

Non-goals (explicitly out of scope):

- The ephemeral jump-back stack from the VBA reference. We dropped it -- only the selector ("jumpstation") is in scope. No origin-push, no "jump back" key.
- Sub-page or coordinate-level anchors. A bookmark is always a whole page.
- The final visual selector. The first cut uses an `NSAlert` for naming and a minimal picker; the polished panel is a later step (see Sequencing).
- Multi-user / untrusted-input concerns. Single-user project; no sanitization beyond what fitz needs.

Note on the reference: `JumpStation.bas` / `UserFormSelector.frm` inspire the *navigation and selection* UX -- a modal, keyboard-first, type-to-filter picker with a two-stage Escape. They do **not** cover adding, removing, or renaming (their targets are hard-coded in code). The management half is new to Anima, and it is where most of the decisions below live.

## Implementation status

Completed:

- `/AnimaBookmarks` JSON persistence in the PDF catalog, using incremental fitz saves without modifying the native PDF outline.
- Helper commands: `list-bookmarks`, `set-bookmark`, and `delete-bookmark`.
- Pytest coverage for empty listing, case-insensitive upsert, case-insensitive deletion, missing deletion, invalid 0-based pages, and native-TOC preservation.
- `FitzBridge` read/mutation calls and `BookmarkManager`, which owns the session-local `[Bookmark]` list and reloads it after every successful mutation.
- Swift integration coverage for the real `BookmarkManager -> FitzBridge -> helper -> PDF catalog -> reload` path.
- `Cmd+B` bookmark creation: native naming alert, 1-based page wording in the reader UI, case-insensitive duplicate detection, and a `Re-point` / `Keep Existing` decision.

Remaining:

- `Cmd+J` bookmark navigation.
- `Cmd+D` bookmark deletion from the navigation picker.
- Replacement of the initial picker with the polished keyboard-first `JumpStationPanel`.

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

Implemented helper commands follow the existing argparse / exit-code / stdout conventions:

- `list-bookmarks --file F` -- prints the JSON array on stdout, or `[]` if the key is absent. `BookmarkManager` calls it on document load and after each successful mutation.
- `set-bookmark --file F --name NAME --page N` -- case-insensitive upsert, then incremental-save. It is a pure data operation: it does not prompt. `N` is a fitz-native 0-based page index.
- `delete-bookmark --file F --name NAME` -- removes by case-insensitive name; exits non-zero if the name is absent, mirroring `delete-highlight`'s handling of a nonexistent target.

The helper owns persistence semantics, including case-insensitive matching and the updated stored ordering after an upsert. Swift owns all user interaction and duplicate-name decisions.

Pytest coverage is the helper specification: empty listing, round-trip/upsert, deletion, delete-nonexistent, invalid page, and the guard that an existing native PDF TOC remains intact.

## Swift side and local ownership

The feature remains additive: it does not alter the dual-write highlight path, sidebar, search, popup suppression, or emphasis. Those systems are intentionally outside bookmark work.

Implemented pieces:

- **`BookmarkManager`** -- a toolbox-style class in the mold of `AnnotationManager`. It holds no view or document references, receives a PDF file path per operation, owns the in-memory `[Bookmark]` list, and delegates persistence to `FitzBridge`. A bookmark is a navigation aid, not an annotation, so it remains separate from `AnnotationManager`.
- **`FitzBridge`** -- provides `listBookmarks`, `setBookmark`, and `deleteBookmark`. It returns raw list JSON to `BookmarkManager`, which owns decoding and session-local model state.
- **`AppDelegate`** -- creates and injects `BookmarkManager` alongside `AnnotationManager`, then loads bookmarks once for each opened PDF before reader setup.
- **`AnimaPDFView`** -- owns `Cmd+B` keyboard dispatch and the temporary native `NSAlert` interaction. It determines the current PDFKit page index, presents the page as 1-based in the alert, detects duplicate names against `BookmarkManager.bookmarks`, and delegates confirmed persistence to the manager.

Implemented add path:

- **Add (`Cmd+B`)** -- `AnimaPDFView` identifies the current page, shows a naming `NSAlert`, checks `BookmarkManager`'s in-memory list case-insensitively, and either persists the new bookmark or presents `Re-point` / `Keep Existing` for a duplicate. A confirmed add or re-point calls `BookmarkManager.setBookmark`, which persists through the helper and reloads the catalog-backed in-memory list.

Remaining paths:

- **Open / jump (`Cmd+J`)** -- will present a minimal picker populated from the in-memory list; `Enter` will jump through `PDFView.go(to:)`, reusing the same navigation mechanism as bare `G`.
- **Delete (`Cmd+D`, inside the picker)** -- will confirm, call `BookmarkManager.deleteBookmark`, refresh the picker from the updated in-memory list, and remain scoped to bookmark navigation.

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

Completed:

1. **Persistence + helper.** Implemented `list-bookmarks`, `set-bookmark`, and `delete-bookmark` in `anima_helper.py`, with pytest coverage including the native-TOC preservation guard.
2. **Swift persistence boundary.** Implemented `FitzBridge` bookmark operations, `BookmarkManager`, load-time hydration, and a real Swift integration test against the helper and disposable PDF fixtures.
3. **End-to-end bookmark creation.** Implemented `Cmd+B`, prototype naming alert, duplicate-name `Re-point` / `Keep Existing` decision, and in-session state refresh after persistence.

Next:

4. **Minimal navigation and deletion.** Implement `Cmd+J` with a minimal picker, `Enter` to navigate to the selected bookmark, and `Cmd+D` inside that picker to delete with confirmation. This is the next point at which the bookmark feature becomes usable for its central main-text <-> endnotes round trip.
5. **Polished selector.** Replace the minimal picker with the keyboard-first `JumpStationPanel` and the `UserFormSelector` type-to-filter experience.

Parked later, separately: the reader-keybinding migration discussion and a custom replacement for the `Cmd+B` naming `NSAlert`.

## Remaining decisions

Settled:

- **Page index base.** `/AnimaBookmarks` stores fitz-native 0-based page indices. Swift keeps those values internally; reader-facing UI displays `page + 1`.
- **`BookmarkManager` construction and wiring.** `AppDelegate` creates it alongside `AnnotationManager` and injects it into `AnimaPDFView`.

Still parked for a separate keybinding-migration discussion:

- **X-Ray source key.** The current code uses bare `P`; the earlier migration note mentioned `R`. Confirm the intended source key before proposing a `Cmd`-modified replacement.
- **`Cmd+H` versus system Hide.** Do not shadow the conventional macOS Hide shortcut for auto-annotate without an explicit decision.

## References

- `docs/JumpStation.bas`, `docs/UserFormSelector.frm` -- VBA UX inspiration (selection/navigation only).
- `AnnotationManager` -- toolbox-class precedent (no view/doc refs, per-call context).
- `CommentInputPanel` -- keyboard-first modal `NSPanel` precedent.
- `SidebarExtractor` -- load-time JSON-over-subprocess extraction precedent.
- `/AnimaComment` -- private custom-key precedent that `/AnimaBookmarks` follows.
- Bare `G` goto-page -- `PDFView.go(to:)` navigation the jump will reuse.
