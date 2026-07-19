# JUMPSTACK_DESIGN.md -- Far-Jump History (`Cmd+E` / `Cmd+R`)

Status: agreed design, ready for implementation. Settled 2026-07-19.

This document is the specification for `TARGET_ARCHITECTURE.md` Phase C step 10. It is self-contained: an implementation session needs this file plus the project's filesdump, and nothing from the conversation in which the design was settled.

It supersedes `TARGET_ARCHITECTURE.md` §6.5, which is reduced to a pointer at this file. Where the two disagree, this document wins.

**Why a separate document.** `TARGET_ARCHITECTURE.md` carries one thread: retiring the Windows/Parallels route and making the `pdf://` flow macOS-native. The JumpStack suspends that thread rather than continuing it -- it serves six far-jump sources, five of which predate `pdf://` entirely. Keeping it here means a future reader looking for navigation behavior does not have to search a resolver-contract document to find it.

---

## 1. What the feature is

A far jump is a defined non-local reader transition: goto page, find in PDF, find in comments, `F3` in either search mode, jump to bookmark, and a same-document `pdf://` page link. All six already execute through the shared seam in `AnimaPDFView` established by Phase C step 9.

The JumpStack records where those jumps departed from and arrived at, so the reader can walk back and forward along them:

- **`Cmd+E`** -- back: return to the previous recorded position.
- **`Cmd+R`** -- forward: advance to the next recorded position.

The use case that shaped the design is search with multiple hits: jump between found positions in both directions to get a feel for where they sit in the document, with ordinary scrolling free to happen in between.

In-memory only. Cleared on document change, so both keys are within-document by construction; last-page restore remains the cross-document return path. Persistence in private PDF metadata was considered and deferred (`TARGET_ARCHITECTURE.md` §9 ledger).

---

## 2. Model

Two pieces of state, owned by `AnimaPDFView` alongside the seam:

- **`entries`** -- a list of 0-based page indices, oldest first. Not bounded: the earlier cap of five was bookkeeping for the abandoned persistence design, and each entry is one `Int`.
- **`pointer`** -- an index into `entries` identifying the entry the reader currently occupies. Undefined while `entries` is empty.

**Invariant:** `entries[pointer]` is the page the reader arrived at through the most recent recorded event. The reader may have scrolled away from it since; ordinary scrolling is never recorded, and the divergence is handled where it matters (see §3, far jump, and trace 3).

**Notation used throughout this document:** `[5, 40, 50*]` is a three-entry stack whose pointer is on the entry `50`. Page numbers in traces are written as the reader sees them; the implementation stores 0-based indices.

---

## 3. Operations

### Far jump

Given a target page `T`, and `O` = the page the reader is on **right now**, read from the reader rather than from `entries[pointer]`:

1. Drop every entry above `pointer` (the forward history is invalidated by a new jump).
2. Push `O`, unless `entries` is non-empty and its last entry already equals `O`.
3. Push `T`, unless `entries` is non-empty and its last entry already equals `T`.
4. Set `pointer` to the last index of `entries`.

Then perform the jump.

Two pushes, one rule applied twice. Because step 1 runs first, the entry under the pointer is always the last entry by the time steps 2 and 3 run, so the decline rule needs no notion of the pointer at all: **decline if equal to the last entry.**

Note what the double push costs and buys. In the steady state `O` equals the last entry -- the reader is standing where the previous jump left it -- so step 2 declines and the pointer advances by exactly one. `O` and the last entry diverge precisely when the reader scrolled away after arriving, which is precisely when that position deserves its own stop. Meanwhile pushing `T` is what makes the most recent jump target reachable by `Cmd+R`; recording origins alone would leave it permanently out of reach.

### Back -- `Cmd+E`

1. If `entries` is empty, or `pointer` is 0: beep, do nothing else.
2. Decrement `pointer`.
3. Go to `entries[pointer]`.

### Forward -- `Cmd+R`

1. If `entries` is empty, or `pointer` is the last index: beep, do nothing else.
2. Increment `pointer`.
3. Go to `entries[pointer]`.

**Back and forward never modify `entries`.** They move the pointer and navigate; nothing is pushed, dropped, or refreshed.

**Both are move-then-jump**, in that order and identically. This is load-bearing -- see §5.

**Neither goes through the seam.** They call the same PDFKit page primitive the seam ultimately calls, directly. Routing them through `farJump(to:)` would make every return record itself as a new jump.

### Document change

`entries` is emptied and `pointer` returns to its undefined state. Consequently a stored entry can never address a page outside the current document, and no range validation is needed at navigation time.

---

## 4. Traces

These are the specification for the unit tests. Each covers at least one rule no other trace covers; the coverage note says which.

### Trace 1 -- canonical chain from empty

*Covers: seeding an empty stack, the double push, the origin decline in the steady state.*

```
start                       []            reader on 5
goto 40   push 5, push 40   [5, 40*]      reader on 40
find 50   decline 40, push 50   [5, 40, 50*]   reader on 50
F3 -> 60  decline 50, push 60   [5, 40, 50, 60*]   reader on 60
```

### Trace 2 -- walk to both ends

*Covers: move-then-jump in both directions, both beeps, and the fact that the most recent jump target (60) is reachable going forward.*

```
from      [5, 40, 50, 60*]   reader on 60
Cmd+E     [5, 40, 50*, 60]   reader on 50
Cmd+E     [5, 40*, 50, 60]   reader on 40
Cmd+E     [5*, 40, 50, 60]   reader on 5
Cmd+E     beep, unchanged    reader on 5
Cmd+R     [5, 40*, 50, 60]   reader on 40
Cmd+R     [5, 40, 50*, 60]   reader on 50
Cmd+R     [5, 40, 50, 60*]   reader on 60
Cmd+R     beep, unchanged    reader on 60
```

### Trace 3 -- scroll, then far-jump

*Covers: the origin being read from the reader rather than the pointer, and the extra stop this produces.*

```
from      [5, 40, 50*]   reader scrolls from 50 to 55
F3 -> 60  push 55 (differs from last entry 50), push 60
          [5, 40, 50, 55, 60*]   reader on 60
```

Walking back now stops at both 55 (where reading actually happened) and 50 (the find target).

### Trace 4 -- far jump whose target is the current page

*Covers: both pushes declining, and page-local movement collapsing to a single stop.*

```
from      [5, 40, 50*]   reader on 50
F3 -> 50  decline 50 (origin), decline 50 (target)
          [5, 40, 50*]   unchanged, reader on 50
Cmd+E     [5, 40*, 50]   reader on 40
```

Several hits on one page are one stop, not several. This is the intended behavior, not a tolerated artifact.

### Trace 5 -- back, then a new far jump

*Covers: dropping the forward history. This rule fires in no other trace.*

```
from      [5, 40, 50, 60*]   reader on 60
Cmd+E     [5, 40, 50*, 60]   reader on 50
Cmd+E     [5, 40*, 50, 60]   reader on 40
goto 90   drop above pointer -> [5, 40]
          decline 40 (origin), push 90
          [5, 40, 90*]   reader on 90
Cmd+E     [5, 40*, 90]   reader on 40
Cmd+E     [5*, 40, 90]   reader on 5
Cmd+E     beep
```

50 and 60 are gone: a new jump from a rewound position invalidates the branch that was ahead of it.

Composing with trace 3: had the reader scrolled from 40 to 42 before `goto 90`, the origin push would not have declined, giving `[5, 40, 42, 90*]`. Same rule, no special case.

### Trace 6 -- document change

Not a trace. Loading a different PDF empties `entries` and returns `pointer` to undefined; `Cmd+E` and `Cmd+R` beep until the first far jump in the new document.

---

## 5. Properties, and one rejected convention

**Move-then-jump is required in both directions.** The alternative convention -- peek at the pointer, jump, then decrement -- leaves the pointer one behind the reader. After two back-presses in trace 2 the pointer would sit on 5 while the reader is on 40, so the first `Cmd+R` moves the pointer to 40 and navigates to the page the reader is already standing on. The press consumes an input and produces no motion, which reads as a broken feature. This convention was traced, found wanting, and rejected.

**Recording origins alone does not support forward.** With only origins pushed, the most recent jump target never enters the stack and `Cmd+R` has nothing to reach. The `T` push in §3 step 3 exists for this and only this.

**The decline rule is a page comparison, not a pointer comparison** -- see §3. Implementations should not reintroduce pointer arithmetic here.

**Ordinary scrolling records nothing.** It changes where a later far jump departs from (trace 3), which is the whole of its influence.

---

## 6. Integration

### 6.1 The seam needs the target page

Phase C step 9 left `recordPreJumpPosition()` taking no argument, since a stub needs none. §3 step 3 requires the destination, so the hook gains the target page index and each of the three overloads derives it from the argument it already holds:

| Overload | Source of the page |
|---|---|
| `farJump(to page: PDFPage)` | `document.index(for: page)` |
| `farJump(to selection: PDFSelection)` | `selection.pages.first`, then `document.index(for:)` |
| `farJump(to destination: PDFDestination)` | `destination.page`, then `document.index(for:)` |

All three sources are already used elsewhere in the codebase: `AnimaPDFView.pageIndex(for:in:)` takes `selection.pages.first` (with a comment on why a selection is treated generically), and `MainViewController.navigateToCommentSearchResult` constructs its `PDFDestination(page:at:)`.

Two of the three are optional-shaped, because `selection.pages` may be empty and `destination.page` may be nil. When no page can be derived, **perform the jump and record nothing at all** -- neither the origin nor the target.

Both halves of that matter. The jump proceeds because the user asked to navigate and the history rides along as a convenience; a `Cmd+G` that silently did nothing because an internal bookkeeping step came up empty would read as a broken reader. And the record is all-or-nothing because a partial one -- pushing the origin, skipping the target -- would break the §2 invariant: `entries[pointer]` would claim the reader is at the origin while the reader has in fact moved to the target. Every later `Cmd+E` and `Cmd+R` reasons from that invariant, so one corrupted entry misleads the feature for the rest of the document's session. Skipping the record entirely leaves the stack merely incomplete, which costs one missing stop and nothing more.

This resolves an earlier open question -- whether the seam needed the destination -- in the affirmative, by the requirements of the model rather than by preference. `TARGET_ARCHITECTURE.md` §9 anticipated it: page granularity is what the ledger reserved.

### 6.2 What stays outside the seam

Unchanged from step 9, and still correct here: `restore(toPageIndex:)` and the document install path in `AppDelegate` (`TARGET_ARCHITECTURE.md` §6.3 step 5) do not far-jump. Loading a document positions the reader; it does not navigate within it, and the stack is empty at that moment anyway. The dead `reloadDocument()` keeps its own direct call pending its separate deletion item in `TODO.md`.

### 6.3 Clearing on document change

The chain already exists: `AppDelegate.loadDocument(url:)` -> `MainViewController.clearOutgoingDocumentState()` -> `AnimaPDFView.clearSearchAndSelection()`, which is documented as clearing all transient reader state tied to the current document. The JumpStack is exactly that, and its clearing belongs on that path.

### 6.4 Key bindings

| Key | keyCode | Action |
|---|---|---|
| `Cmd+E` | 14 | back |
| `Cmd+R` | 15 | forward |

Dispatched in `AnimaPDFView.handleKeyEvent(_:)`, guarded against Shift, Control, and Option like its siblings.

`Cmd+J` was the original candidate for back and is **not** available: it belongs to the JumpStation bookmark panel. `Cmd+E` and `Cmd+R` are adjacent under the left hand, which suits the back/forward pairing.

Both are claimed by stock items in `MainMenu.xib`, and neither should reach the menu:

- `Cmd+E` is `Use Selection for Find`, selector `performFindPanelAction:`. `Cmd+F` and `Cmd+G` in the same menu carry that same selector and already fall through to Anima's own find dialog and goto-page, so the selector is demonstrably unhandled in Anima's responder chain.
- `Cmd+R` is `Revert to Saved`, selector `revertDocumentToSaved:`. That is an NSDocument action, and Anima has no document architecture.

Both fall-throughs are cheap to confirm once wired, and the implementing session should confirm rather than assume.

---

## 7. Acceptance

Replacing `TARGET_ARCHITECTURE.md` step 11 items (b) through (d), whose `Cmd+R`-as-back wording predates this design. Item 11(a) concerned step 9 and was verified on 2026-07-19.

- (a) All six far-jump sources still navigate as before.
- (b) Traces 1 to 5 reproduce in the reader.
- (c) `Cmd+E` at the bottom of the stack and `Cmd+R` at the top both beep, and neither crashes nor moves the reader.
- (d) `Cmd+E` and `Cmd+R` on an empty stack -- fresh launch, before any far jump -- both beep. Note that this overrides the earlier acceptance wording, which specified a silent no-op.
- (e) After switching documents via a `pdf://` link or Finder open, both keys beep: the stack was cleared.
- (f) `Cmd+J` still opens JumpStation, and `Cmd+E` / `Cmd+R` are not intercepted by the menu.

---

## 8. Open questions

Not decided in the design session, and not to be decided silently during implementation:

- **Interaction with an active search.** `Esc` currently clears PDF-text search, then comment search, then annotation emphasis, in that order. Whether `Cmd+E` or `Cmd+R` should clear an active find, leave it standing, or leave it standing but stop advancing it, was never discussed. Leaving it untouched is the smallest behavior and the likely default, but it is a product decision.
- **Persistence.** Deferred, recorded in `TARGET_ARCHITECTURE.md` §9. Nothing in this design forecloses it: entries are page indices, which is the granularity persistence would want.

---

## 9. Left to the implementing session

- **Undefined pointer representation.** `-1` as a sentinel, or `Int?` with `nil`. One line either way; the difference is whether the empty case is enforced by convention or by the compiler.
- **Where the type lives.** A small value type with `entries`, `pointer`, and the three operations is testable without a `PDFView` or a fixture PDF, which is what makes §4 directly transcribable into unit tests. Whether it is a nested type in `AnimaPDFView` or its own file, and whether its tests join `AnnotationGeometryTests.swift` or get their own file, is a local judgement.
- **How much gets wired in one sitting.** The natural break is: the type plus its tests first, with no reader wiring at all, so nothing can regress; then the seam, the two keys, and the clearing; then manual acceptance.

---

## 10. Consequential edits elsewhere

To be made when this design is implemented, not before:

- `TARGET_ARCHITECTURE.md` -- §6.5 reduced to a pointer at this file; step 11 acceptance corrected per §7 above.
- `TODO.md` -- the JumpStack entry still describes the cap of five and `Cmd+R` as the return key.
- `GOALS.md` -- the Current Session Pointer still sends the next session at step 10 as originally specced.
- `README.md` -- the Navigate section gains `Cmd+E` and `Cmd+R`; `AnimaPDFView.swift`'s header comment gains them too.
