> [!note] User:
> Hi GPT! This is a continuation of previous conversations on `anima`. Please read the guide `FIRST_PROMPT.md`.

Assistant:
Denkt nach

Hi Frank -- I have read `FIRST_PROMPT.md` and followed its order:

-   Read `CRITICAL_RULES.md` first.
-   Verified `filesdump.txt` integrity: its header says **27 documents** and its `END OF FILESDUMP` trailer also says **27 documents**, so it is complete.
-   Reviewed the manifest, current project position, architecture, code owners, tests, and `Makefile`.

I understand the collaboration contract: **Discuss -> Approve -> Implement**, no unsolicited files, incremental work, complete drop-in replacements only after approval, and tests remain the specification. I will work solely from the supplied project materials.

## Current project position

The next action is `TARGET_ARCHITECTURE.md` Phase C, step 9:

> Introduce a small shared far-jump seam before building the in-memory JumpStack.

The existing target discovery is already in sensible local owners:

-   `AnimaPDFView` owns goto-page, PDF-text find/F3, and bookmark jump target discovery.
-   `MainViewController` owns comment-search result discovery and annotation-centered destinations.
-   `AppDelegate` owns `pdf://` parsing, resolution, same-document detection, and validation.

But the final transition is currently scattered across direct `pdfView.go(to:)` calls. The goal is not a `NavigationManager` or a broader redesign. It is one deliberately small execution seam that all six far-jump sources call:

1.  Goto page
2.  PDF-text find
3.  PDF-text `F3`
4.  Comment find
5.  Comment-search `F3`
6.  Bookmark jump
7.  Same-document `pdf://...?page=N`

The apparent count is seven call paths, but the design describes six _sources_: PDF find and its `F3` continuation are one source family, as are comment find and its `F3` continuation.

## Two approaches

### Approach A -- Small public far-jump API on `AnimaPDFView` -- recommended

Add one narrow method to `AnimaPDFView`, for example conceptually:

-   accept a `PDFDestination`
-   capture the current page in the future JumpStack step
-   call the underlying `go(to:)`

Each current owner continues to find and validate its own target, but sends the final destination through this method. Page-based jumps become a `PDFDestination` at the page's existing visible origin or a standard page destination; PDF-text hits and comment hits can retain their annotation/selection-oriented locations.

**Why this fits the current code:**

-   `AnimaPDFView` already owns PDFKit event handling and several navigation actions.
-   `MainViewController` and `AppDelegate` already hold `pdfView`, so no new coordinator needs wiring.
-   Step 10 can add "record current page before execution" in one place without moving target-discovery logic.
-   It matches the explicit `TODO.md` instruction: no `NavigationManager` unless independent responsibility grows.

**Trade-off:** We need to choose a consistent conversion for the current page-only jumps versus selection/destination jumps. That is straightforward, but we should preserve current visible behavior rather than casually replacing `go(to: selection)` with a less precise page jump.

### Approach B -- A target enum shared by the existing owners

Introduce a small `FarJumpTarget` type with cases such as page, destination, and selection, then have one `executeFarJump(_:)` method in `AnimaPDFView`.

**Advantage:** It makes every kind of target explicit and preserves the exact existing PDFKit navigation primitives cleanly.

**Trade-off:** This is more structural machinery for a seam whose immediate job is only to centralize one action. Right now it would have one executor and only a handful of call sites. That is close to the "structural layer whose real population is one" smell described in `LLM_INSTRUCTIONS.md`.

## Recommended first step

I recommend **Approach A**, but with a careful detail: the shared seam should support the existing PDFKit destination semantics without changing what users see. We would first inventory every current direct `go(to:)` call and decide the narrowest API shape that can preserve them. Then, in a separate approved implementation step, reroute those calls and run the existing Python suite plus Xcode tests.

Would you like to proceed with **Approach A**, or do you prefer the more explicit target-enum version in Approach B?

> [!note] User:
> I like Approach A better. But isn't there another way to achieve this? How about having `farJump(to:)` overloads on `AnimaPDFView`. Three one-line overloads mirroring PDFKit's own `go(to:)` idiom (`PDFPage`, `PDFDestination`, `PDFSelection`), plus a header comment stating the contract: every far jump executes here, step 10 records the pre-jump position here, restore and scrolling bypass deliberately. Reroute the five sites (or six, or seven if you treat the two `F3` as distinct).

Assistant:
Yes -- that is better than my initial version of Approach A.

The overloads preserve PDFKit's native vocabulary instead of forcing all callers through a lowest-common-denominator `PDFDestination`. That matters because the three current forms mean slightly different things:

Target form

Current use

Why it should stay distinct

`PDFPage`

goto-page, bookmark jump, same-document `pdf://` page link

Navigate to the page as a whole.

`PDFSelection`

PDF-text find and subsequent `F3`

Keeps the hit itself visible and highlighted.

`PDFDestination`

comment find and subsequent `F3`

Centers the annotation-linked location without creating annotation emphasis.

So the seam can be deliberately tiny, on `AnimaPDFView`:

swift

```swift
`// Far-jump contract:
// Every defined non-local reader jump executes here. Step 10 will record the
// pre-jump page here before delegating to PDFKit. Last-page restoration and
// ordinary scrolling deliberately bypass this seam.
func farJump(to page: PDFPage) {    go(to: page)
}

func farJump(to destination: PDFDestination) {    go(to: destination)
}

func farJump(to selection: PDFSelection) {    go(to: selection)
}`

```

That gives us exactly the future JumpStack insertion point, while leaving target discovery where it belongs today.

## Precise inventory of the reroute

**Finding:** There are currently **six direct `go(to:)` calls** in the included code, but one is last-page restoration and is intentionally excluded.

The resulting work is **five call sites**, corresponding to the six source categories in the architecture:

1.  `AnimaPDFView.showGotoPageDialog()` -> `farJump(to: page)`
2.  `AnimaPDFView.jumpToBookmark(_:)` -> `farJump(to: page)`
3.  `AnimaPDFView.showFindResult(at:)` -> `farJump(to: selection)`
    -   Both initial find and `F3` already converge on this one method.
4.  `MainViewController.navigateToCommentSearchResult(...)` -> `pdfView.farJump(to: destination)`
    -   Both initial comment find and `F3` already converge here.
5.  `AppDelegate.handleSchemeURL(_:)` same-document page path -> `mainViewController.pdfView.farJump(to: page)`

And deliberately unchanged:

6.  `AnimaPDFView.restore(toPageIndex:)` -> direct `go(to: page)`

So your terminology is right in all three senses:

-   **Five physical reroute sites**
-   **Six far-jump sources** when PDF find and comment find each count as a source family that includes `F3`
-   **Seven user actions/entry paths** if initial PDF find, PDF-find `F3`, initial comment find, comment-find `F3`, goto, bookmark, and same-document `pdf://` link are all counted separately

The five-site framing is most useful for this refactoring, because it tells us exactly how small the diff should be.

## Testing scope for step 9

This is a behavior-preserving refactor. The existing Swift tests do not directly cover all five UI navigation paths, so automated regression protection here is limited. I would keep the code change minimal, run:

bash

```bash
`make test`

```

then run the existing Xcode test suite with **Cmd+U**, followed by the Phase C step 11(a) manual acceptance check:

-   goto page
-   PDF find and `F3`
-   comment find and `F3`
-   bookmark jump
-   same-document `pdf://...?page=N`

We should **not** add JumpStack tests yet: until step 10, the new methods merely delegate to PDFKit, and a test of that delegation would pin implementation mechanics rather than a new behavioral contract.

If you approve this exact small seam and five-site reroute, I will provide complete drop-in replacements for only:

-   `Anima/Anima/AnimaPDFView.swift`
-   `Anima/Anima/MainViewController.swift`
-   `Anima/Anima/AppDelegate.swift`

No new files, no unrelated cleanup, and no documentation changes until the behavior is actually established.
