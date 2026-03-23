# Anima — Sidebar Design Document

**Status:** Phases 1–4 Implemented (Phase 4 session geometry deferred)
**Date:** 2026-03-23
**Context:** This document captures design decisions for Anima's annotation
sidebar. It is intended as a reference for future LLM conversations and for
Frank's own planning.

---

## Overview

The sidebar is a fixed-width panel on the right side of the Anima window that
displays **comment cards** — one card per annotation that has a non-empty
comment. It never overlaps the PDF content. The sidebar is always visible;
there is no toggle to hide it.

The sidebar replaces the NSAlert-based comment dialog as the primary way to
view and (eventually) edit comments. It is the single biggest feature that
makes Anima a viable replacement for PDF-XChange Viewer.

---

## Terminology

| Term              | Meaning                                                    |
|-------------------|------------------------------------------------------------ |
| **Sidebar** | The right-side panel containing all cards                  |
| **Card** | A single comment entry in the sidebar                      |
| **Page-sidebar** | The vertical zone within the sidebar that corresponds to   |
|                   | one PDF page. Its top/bottom align with the page's         |
|                   | top/bottom in the scroll view.                             |
| **Anchor** | The vertical center of gravity of a highlight's quads      |
|                   | (in page coordinates). Determines where a card "wants"     |
|                   | to be positioned.                                          |
| **Command comment** | A comment whose text is a pipeline instruction ("link",  |
|                   | "H1", "H2", etc.) rather than a human-readable note.       |
| **Emphasis** | The visual indication shown when a highlight is clicked    |
|                   | (from either PDF or sidebar): the highlight turns light    |
|                   | yellow, and the card (if any) gets an accent border.       |

---

## Layout Model

### Sidebar Structure

The sidebar is a continuous vertical scroll view, subdivided into
**page-sidebars**. Each page-sidebar corresponds to one PDF page and is
vertically aligned with that page in the PDF scroll view.

```
┌─────────────────────────────┬──────────────┐
│                             │ Page 1       │
│         PDF Page 1          │  ┌────────┐  │
│                             │  │ Card A │  │
│                             │  └────────┘  │
│                             │  ┌────────┐  │
│                             │  │ Card B │  │
│                             │  └────────┘  │
├─────────────────────────────┼──────────────┤
│                             │ Page 2       │
│         PDF Page 2          │  ┌────────┐  │
│                             │  │ Card C │  │
│                             │  └────────┘  │
│                             │              │
│                             │              │
├─────────────────────────────┼──────────────┤
│         PDF Page 3          │ Page 3       │
│                             │  (no cards)  │
│                             │              │
└─────────────────────────────┴──────────────┘
```

- The PDF is always in **continuous scroll** mode. No single-page, no
  fit-to-screen, no facing pages.
- Multiple page-sidebars are visible simultaneously as the user scrolls.
- The sidebar scrolls in lockstep with the PDF — they share the same
  vertical scroll position.

### Card Positioning: Anchor-Based Layout with Collision Avoidance

Each card has an **anchor**: the vertical midpoint of its highlight's
bounding box (the union of all quads for that highlight), expressed in page
coordinates. The layout algorithm positions each card as close to its anchor
as possible, subject to:

1. Cards must not overlap.
2. Cards must stay within their page-sidebar boundaries.
3. Cards are processed top-to-bottom (greedy algorithm): sort by anchor Y,
   then place each card as close to its anchor as the previous card's
   bottom edge allows.

**Ordering tiebreaker:** When two highlights have similar anchor Y values
(e.g., two highlights starting on the same text line), the highlight whose
vertical center of gravity is higher comes first. For highlights with
identical centers of gravity, use horizontal position (left-to-right) as
a secondary sort key.

Note: fitz's annotation order within a page is insertion order, not spatial
order. The layout algorithm must sort explicitly by anchor position.

### Card Sizing

- **Width:** Always equals the sidebar width. No horizontal resizing.
  No manual repositioning. Cards and PDF never overlap.
- **Height:** Determined automatically by the app to fit the comment text
  at the current sidebar width, subject to:
  - **Minimum height:** Title bar (if shown) + 1 row of comment text,
    or just 1 row of comment text if title bars are off.
  - **Maximum height:** No hard maximum, but constrained by available space
    in the page-sidebar. When content exceeds the available height, the
    card gets an internal vertical scrollbar.
- Width changes (from window resizing) cascade into height changes (text
  rewraps → card height changes → layout reflows).

### Page-Sidebar Overflow

A page-sidebar has a fixed height (equal to the PDF page height). If the
total height of all cards exceeds this, the page-sidebar gets its own
vertical scrollbar. Some page-sidebars may have scrollbars while others
do not — this is per-page.

### When Layout Reflows

Card positions are **stable during scrolling** — they are pinned to page
coordinates. Layout recomputes only when:

- The window or sidebar is resized (width change → text rewrap → height change)
- A comment is added, edited, or deleted (card appears, changes height,
  or disappears)
- Title bar visibility is toggled (changes card heights)

Layout does **not** recompute on every scroll frame.

---

## Card Content and Appearance

### Card Structure

```
┌──────────────────────────────┐
│ 2026-03-14  fschuhi          │  ← Title bar (optional, toggleable)
├──────────────────────────────┤
│ This is the comment text.    │  ← Comment body (plain Unicode, LF)
│ It can be multiple lines.    │
└──────────────────────────────┘
```

- **Title bar** (optional): Shows the annotation date and author.
  Whether title bars are shown is a per-document setting (each tab
  can have a different setting). Initial implementation may use a
  global toggle; the architecture should make per-document trivial.
- **Comment body**: Plain Unicode text. Standard line ending is Unix LF.
  No rich text, no Markdown rendering, no images.
- **No status bar** on cards.

### Command Comments (Pipeline Instructions)

Comments whose text is a pipeline instruction for `pdf-annotations`
("link", and "H1", "H2", ... "H9") are displayed in **light gray** text.
This applies to all command comments uniformly — they are metadata for
the extraction pipeline, not for reading comprehension.

Rationale: After entering these commands, they do not enhance
intelligibility during reading. The eye picks up headers from the PDF
directly, and "link" continuations are visible because of continuous
scroll mode.

Command comments are still editable and behave identically to regular
cards in all other respects.

### Empty Comments

- An annotation with an empty comment (`""`) or a missing `/Contents`
  field produces **no card**. No indicators, no collapsed cards, no
  ghost entries.
- When the user removes a comment (clears the text), the card disappears.
- `""` and missing `/Contents` are treated identically.
- The sidebar is purely comment-focused.
- **fitz quirk:** `annot.set_info()` silently ignores empty strings for
  the "content" field. Clearing a comment requires writing an empty PDF
  string `"()"` directly via `doc.xref_set_key(annot.xref, "Contents", "()")`.
  This was discovered by the `test_clear_comment` test and fixed in
  `anima_helper.py` (2026-03-22).

---

## Interaction

### Bidirectional Emphasis (Implemented)

Emphasis works in both directions — from sidebar to PDF and from PDF to
sidebar — using the same shared logic in MainViewController.

**Card → Highlight (click card in sidebar):**
Clicking a sidebar card emphasizes the corresponding highlight in the
PDF: the highlight changes to light yellow (#FFFFE0) at higher opacity
(0.7), and the card itself gets a 2pt accent-colored border.

**Highlight → Card (click highlight in PDF):**
Clicking a highlight in the PDF emphasizes it (same visual change) and
activates the corresponding card in the sidebar (if one exists). Highlights
without comments (no card) still get the visual emphasis — this is useful
for identifying which highlight will be affected by the Delete key.

**Shared behavior for both directions:**

- Clicking the same card/highlight again clears the emphasis (toggle).
- Only one card/highlight pair can be emphasized at a time.
- Emphasis is unified with `selectedAnnotation` — the Delete key always
  targets the visually emphasized highlight.
- When an annotation is mutated (comment edited, highlight deleted),
  emphasis is preserved through the sidebar rebuild so the user sees
  the result of their edit.

**Double-click behavior:**
Double-clicking a highlight ensures emphasis is ON (no toggle) before
opening the comment dialog. This guarantees the user always sees which
highlight they're editing. After saving, emphasis persists — the user
sees the newly created/updated card with its accent border, confirming
the edit took effect.

The `toggle` parameter on `highlightWasClicked(uuid:onPageIndex:toggle:)`
distinguishes single-click (toggle: true) from double-click (toggle: false).

### Scroll Card Into View (Planned)

When emphasis is applied to a card via highlight-click, and the card is
not fully visible (in a page-sidebar with overflow), the sidebar should
scroll to show the card. If the page-sidebar has no scrollbar (content
fits), no scrolling is needed — the card is by definition visible.

### Leader Lines (Decided Against)

Leader lines (thin lines connecting a card to its highlight) were
considered and rejected. The card-click emphasis approach is simpler,
less visually cluttered, and achieves the same goal of connecting
card ↔ highlight for the user. The anchor-based layout already keeps
cards close to their highlights, so a connecting line adds complexity
without proportional benefit.

### Comment Editing — Input Form (Phase 4 Redesign)

**Decision (2026-03-22):** In-sidebar editing was considered and deferred
indefinitely. The complexity of making cards editable in-place (temporary
placeholder cards, dynamic height changes during editing, keyboard handling)
does not justify the benefit over a well-designed modal input form.

The current NSAlert-based dialog will be replaced by a **custom input
form** — a modal NSPanel styled to match the card aesthetic.

**Input Form Specification:**

- **Type:** Custom `NSPanel`, modal, borderless (no traffic light buttons).
  The only way to dismiss is Escape.
- **Visual style:** Matches CommentCardView — same background color,
  corner radius, font. Title area shows "Add comment" or "Edit comment"
  in the same muted style as the card's date/author line. Creates visual
  continuity between input and result.
- **Text input:** Editable `NSTextView` (not NSTextField) for multi-line
  support with word wrapping. Comments are often longer than they appear
  in the test PDFs — wrapping across 2-3 lines is common.
- **Escape to save and close:** Always saves the current text. There is
  no "cancel" — Escape always means "save what's there." This aligns
  with Anima's "always immediate autosave" philosophy and with Frank's
  Excel workflow (Escape to exit cell editing).
- **Enter for newlines:** Enter inserts a line break. No special key
  handling for commit — Escape is the only exit.
- **Empty comment confirmation:** If the user presses Escape with empty
  text and the highlight previously had a comment, show a brief
  confirmation ("Remove comment from this highlight?") before clearing.
  This guards against accidental deletion.
- **Initial position:** Centered on screen, with default dimensions
  providing room for approximately 3 lines of text. Width and height
  are defined as easily configurable constants.
- **Resizable and draggable:** The user can drag the form to a new
  position and resize it (wider or taller). The form is not limited
  to its initial dimensions.
- **Session memory:** After any move or resize, the new frame is saved
  in memory. The next time the form opens (for any annotation), it
  appears at the last-used position and size. This persists for the
  session only (resets on app launch).

**Invocation:** Double-click a highlight in the PDF (same as today).
The emphasis is applied first (toggle: false), then the input form
appears. After saving, emphasis persists and the sidebar shows the
updated card.

When the input form is implemented, `askForComment()` and its NSAlert
become dead code and should be removed.

---

## Live Sidebar Updates (Phase 3 — Implemented)

The sidebar stays in sync with annotation mutations during a session.
When the user creates a highlight, edits a comment, or deletes a
highlight, the sidebar updates immediately.

### Architecture

AnimaPDFView notifies MainViewController via the `SidebarUpdateDelegate`
protocol. The delegate receives only the affected page index. On
notification, MainViewController:

1. Remembers the current emphasis state (UUID + page index)
2. Clears card-side emphasis (the card view is about to be torn down)
3. Tears down all card views for the affected page
4. Re-extracts cards via `SidebarExtractor.extractCards(from:at:)`
5. Rebuilds card views with click handlers
6. Re-runs the layout algorithm
7. Re-applies card-side emphasis if the annotation is still emphasized

This "rebuild the whole page" approach is deliberately simple — no
surgical card insertion or removal, no diffing. Pages typically have
a handful of annotations, so the performance cost is negligible. The
benefit is a single code path for all mutation types.

The emphasis-preservation in steps 1/2/7 ensures that the double-click
editing flow works smoothly: the user edits a comment, the sidebar
rebuilds, and the newly created/updated card appears with its accent
border still active.

### Mutation Points

Three places in AnimaPDFView trigger the delegate:

1. **Comment edited** (`handleDoubleClickOnHighlight`) — after the
   in-memory annotation's `.contents` is updated
2. **Highlight deleted** (`deleteSelectedHighlight`) — after the
   annotation is removed from the page
3. **Highlight created** (`createHighlightFromSelection`) — after the
   in-memory annotation is added. Currently a no-op (highlights start
   without comments), but wired for future-proofing.

---

## Resizing Behavior

- The sidebar width is adjustable via a **draggable divider** (standard
  `NSSplitView` behavior).
- **Minimum widths** are enforced for both the PDF view and the sidebar.
- Resizing the sidebar (or the window, or going fullscreen) causes all
  cards to reflow: text rewraps at the new width, card heights adjust,
  and the layout algorithm repositions cards.
- Cards have no independent size controls — the user controls width
  (via the divider) and the app determines heights.

---

## Implementation Pipeline

Each phase is self-contained and useful on its own. Later phases build
on earlier ones. A phase can be split into sub-steps during implementation.

### Phase 0: Split View Foundation (DONE)

- Replace the current single `AnimaPDFView` layout with an `NSSplitView`
  containing the PDF view (left) and a sidebar scroll view (right).
- Draggable divider with minimum widths.
- Sidebar is empty (just a colored background to verify geometry).
- Verify: resizing works, PDF rendering is unaffected, all existing
  keyboard/mouse handling still works.

### Phase 1: Read-Only Cards (DONE)

- Scan the document's annotations on load; build card data for every
  highlight with a non-empty comment.
- Render cards in page-sidebars aligned to their PDF pages.
- Implement anchor-based layout with collision avoidance.
- Card auto-sizing (height fits content, internal scroll on overflow).
- Page-sidebar scrollbars when cards exceed page height.
- Command comments ("link", "H1", "H2") rendered in light gray.
- Title bar toggle (global initially, per-document later).
- Sidebar scrolls in lockstep with PDF.

### Phase 2: Bidirectional Navigation (DONE)

- [x] Click card → emphasize highlight (color/opacity change) + card
      gets active border. Toggle on re-click.
- [x] Click highlight → emphasize highlight + activate card (if any).
      Toggle on re-click. Unified with selectedAnnotation for Delete.
- [x] Double-click highlight → ensure emphasis (no toggle) + open
      comment dialog. Emphasis survives sidebar rebuild after edit.
- [x] Scroll card into view when emphasis applied via highlight-click
      and card is not fully visible.

### Phase 3: Live Updates (DONE)

- SidebarUpdateDelegate protocol: AnimaPDFView → MainViewController.
- Per-page re-extraction via SidebarExtractor.extractCards(from:at:).
- Sidebar rebuilds affected page on comment add/edit/delete.
- Emphasis preserved through rebuilds (UUID remembered, card re-activated).

### Phase 4: Input Form (DONE — session geometry deferred)

- [x] Custom NSPanel styled to match card aesthetic (CommentInputPanel.swift).
- [x] Modal, Escape to save, Enter for newlines.
- [x] Resizable, draggable (isMovableByWindowBackground + native title bar).
- [x] Traffic light buttons hidden; Escape is the only exit.
- [x] Custom title label ("Add comment" / "Edit comment") in card style.
- [x] `askForComment()` / NSAlert removed.
- [ ] Session-remembered geometry (deferred — needs NSPanel frame lifecycle
      investigation; static var approach failed to restore position).
- [ ] Empty-comment confirmation before clearing.

---

## Known Gotchas

### PDFKit userName ↔ /T ↔ /NM Mapping

PDFKit internally maps the `userName` property to the `/T` (Title/Author)
PDF field. This means:

- Setting `annot.userName = uuid` writes the UUID into `/T`.
- Subsequently setting `/T` to the author name overwrites `userName`.
- `annotationUUID()` must check `/NM` first, not `userName`.

The fix (implemented): set `/NM` explicitly via `setValue(_:forAnnotationKey:)`
for UUID storage, and set `/T` explicitly for the author. Keep `userName`
as a backup but never rely on it as the primary UUID source.

This was caught empirically (the sidebar showed UUIDs instead of author
names, and `anima_helper.py` received "fschuhi" as the UUID). A round-trip
unit test (`testInMemoryAnnotationRoundTrip`) now guards against
regressions.

### PDFKit annot.bounds vs Raw PDF /Rect

PDFKit's `annot.bounds.midY` does **not** match the raw PDF `/Rect` midY
value. PDFKit appears to transform the coordinates, effectively returning
`pageHeight - rawMidY`. The `sidebar_basic_expected.json` and
`sidebar_page_extract_expected.json` fixtures contain the PDFKit-reported
values. When creating new test fixtures, always use the values printed by
the `💡 Extracted Anchor Y` diagnostic lines on first test run.

### fitz set_info() Ignores Empty Strings

`annot.set_info(info)` with `info["content"] = ""` is silently ignored by
fitz — the old content value survives both in memory and after save. To
clear a comment, use `doc.xref_set_key(annot.xref, "Contents", "()")` to
write an empty PDF string directly at the xref level. This is implemented
in `anima_helper.py`'s `cmd_edit_comment` and verified by
`test_clear_comment` in the Python test suite.

---

## Open Questions

- **Card visual style:** Border? Shadow? Background tint? Rounded corners?
  Needs visual experimentation. Start simple (thin border, white
  background) and refine.
- **Font and text size:** Match the system font? Fixed size or
  user-adjustable? Start with system defaults.
- **Per-document title bar toggle:** Storage mechanism — where does this
  preference live? In-memory only (resets on close)? Or persisted
  somewhere?
- **Emphasis color tuning:** Light yellow (#FFFFE0) at 0.7 opacity works
  but may need adjustment for different PDF backgrounds or dark mode.

---

## Non-Goals

The sidebar deliberately does **not** support:

- Hiding/showing the sidebar (it is always visible)
- Horizontal card resizing or manual card positioning
- Cards overlapping the PDF
- Rich text or Markdown rendering in cards
- Cards for highlights without comments (no indicators)
- Thumbnail or minimap views
- Filtering or searching within the sidebar
- Leader lines (decided against — see Interaction section)
- In-sidebar editing (decided against — see Comment Editing section)
