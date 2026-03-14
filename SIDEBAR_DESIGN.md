# Anima — Sidebar Design Document

**Status:** Design draft (no implementation yet)
**Date:** 2026-03-14
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
|-------------------|------------------------------------------------------------|
| **Sidebar**       | The right-side panel containing all cards                  |
| **Card**          | A single comment entry in the sidebar                      |
| **Page-sidebar**  | The vertical zone within the sidebar that corresponds to   |
|                   | one PDF page. Its top/bottom align with the page's         |
|                   | top/bottom in the scroll view.                             |
| **Anchor**        | The vertical center of gravity of a highlight's quads      |
|                   | (in page coordinates). Determines where a card "wants"     |
|                   | to be positioned.                                          |
| **Command comment** | A comment whose text is a pipeline instruction ("link",  |
|                   | "H1", "H2", etc.) rather than a human-readable note.       |

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
("link", "H1", "H2", etc.) are displayed in **light gray** text. This
applies to all command comments uniformly — they are metadata for the
extraction pipeline, not for reading comprehension.

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

---

## Interaction

### Bidirectional Navigation

- **Click a card** → the corresponding highlight in the PDF is visually
  indicated (e.g., briefly emphasized or connected by a leader line).
  If the highlight is off-screen, the PDF scrolls to show it.
- **Click a highlight** → the corresponding card in the sidebar is
  visually indicated. If the card is off-screen (in a page-sidebar
  with overflow), scroll to show it.

### Leader Lines

Leader lines (thin lines connecting a card to its highlight) are shown
**only when a card has focus** — i.e., when the user clicks on a card or
on a highlight. No always-on leader lines; they would be visually
distracting with many annotations.

### Comment Editing — Phased Approach

**Phase 1 (initial implementation):**

Double-click a highlight → the existing `askForComment()` NSAlert dialog
appears. The sidebar displays cards as **read-only**. This phase delivers
the full layout engine, scroll synchronization, and visual alignment —
which is the hard part.

**Phase 2 (later):**

Double-click a highlight → the corresponding card in the sidebar becomes
**editable in-place**. The NSAlert dialog is removed.

Phase 2 editing rules:
- Double-click a highlight → card gets focus and becomes editable.
  If the highlight has no comment, a temporary empty card appears.
- Double-click a card → card becomes editable.
- **Enter** inserts a newline (multi-line comments are normal).
- **Escape** saves and exits editing. There is no "cancel" — Escape
  always means "save what's there."
- If the user presses Escape with empty text, the card disappears
  (no empty cards rule).
- Editing persists via the existing dual-write pattern (fitz to disk,
  in-memory update for display).

When Phase 2 is complete, `askForComment()` becomes dead code and should
be removed.

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

### Phase 0: Split View Foundation

- Replace the current single `AnimaPDFView` layout with an `NSSplitView`
  containing the PDF view (left) and a sidebar scroll view (right).
- Draggable divider with minimum widths.
- Sidebar is empty (just a colored background to verify geometry).
- Verify: resizing works, PDF rendering is unaffected, all existing
  keyboard/mouse handling still works.

### Phase 1: Read-Only Cards

- Scan the document's annotations on load; build card data for every
  highlight with a non-empty comment.
- Render cards in page-sidebars aligned to their PDF pages.
- Implement anchor-based layout with collision avoidance.
- Card auto-sizing (height fits content, internal scroll on overflow).
- Page-sidebar scrollbars when cards exceed page height.
- Command comments ("link", "H1", "H2") rendered in light gray.
- Title bar toggle (global initially, per-document later).
- Sidebar scrolls in lockstep with PDF.

### Phase 2: Bidirectional Navigation

- Click card → indicate/scroll to highlight.
- Click highlight → indicate/scroll to card.
- Leader line shown on focused card only.

### Phase 3: Live Updates

- When a highlight is created (ENTER or mouseUp in highlight mode),
  the sidebar adds a card in real time (if comment is non-empty — which
  currently it never is, since highlights are created without comments).
- When a comment is added/edited via `askForComment()`, the sidebar
  updates the card (or creates/removes it).
- When a highlight is deleted, the sidebar removes the card.
- Layout reflows after each change.

### Phase 4: In-Place Editing

- Double-click highlight or card → card becomes editable.
- Enter = newline, Escape = save and exit.
- Empty text on Escape = card removed.
- Temporary empty card for highlights without comments.
- Remove `askForComment()` and the NSAlert dialog.

---

## Open Questions

- **Command comment detection:** How to identify command comments? Exact
  string match ("link", "H1", "H2", "H3", etc.)? Or a prefix/pattern?
  Need the complete list of recognized commands from `pdf-annotations`.
- **Leader line style:** Thin straight line? Curved? Color? Needs visual
  experimentation during implementation.
- **Card visual style:** Border? Shadow? Background tint? Rounded corners?
  Needs visual experimentation. Start simple (thin border, white
  background) and refine.
- **Font and text size:** Match the system font? Fixed size or
  user-adjustable? Start with system defaults.
- **Per-document title bar toggle:** Storage mechanism — where does this
  preference live? In-memory only (resets on close)? Or persisted
  somewhere?

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
