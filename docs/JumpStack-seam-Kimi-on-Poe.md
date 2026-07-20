> [!note] User:
> Hi Kimi! This is a continuation of previous conversations on `anima`. Please read the guide `FIRST_PROMPT.md`.

Assistant:
Denkt nach

**Filesdump integrity check:** Header states 27 documents, trailer is present and repeats 27. The dump is complete, and I'm working from it as the sole source of truth.

## Step 3 -- Understanding acknowledged

-   `CRITICAL_RULES.md` was read first and wins over everything else.
-   Workflow is Discuss -> Approve -> Implement: no files before your explicit yes, drop-in replacements only, diffs contain exactly the agreed change and nothing else.
-   Step-by-step over one-shot dumps; learning over speed; inventory before cutting; tests are the spec (`make test`, Xcode Cmd+U stay green, and a failure after my change is my bug).
-   Your confusion is technical information, not a mood to manage. Pushback runs both directions.
-   Session bookkeeping per `LLM_INSTRUCTIONS.md`: `HISTORY.md` entries during the session, struck `TODO.md` items retained for the next dump, `GOALS.md` pointer updated at the end, `README.md` touched when a durable contract changes.
-   Standalone session: everything I rely on is in this dump, nothing from memory.

## Where we are, and what's next

Phase B landed on 2026-07-18, and it's worth a sentence of recognition: clicking a `pdf://HASH?page=N` link in Obsidian now resolves through the frozen CLI contract and lands on the exact page in Anima -- the Windows Parallels round trip is functionally dead for opening PDFs, which was the whole point of Phase 3.

**Next action** per the Current Session Pointer: `TARGET_ARCHITECTURE.md` Phase C step 9 -- the shared far-jump seam from §6.4. Step 10 (JumpStack) builds on it afterwards.

## Local ownership map -- what the seam touches

Six far-jump sources, five execution sites (each F3 shares its find's site):

Source

Discovery owner

Current final transition

`Cmd+G` goto page

`AnimaPDFView.showGotoPageDialog`

`go(to: PDFPage)`

`Cmd+F` + `F3` (PDF text)

`AnimaPDFView` find state

`go(to: PDFSelection)` in `showFindResult`

`Cmd+Shift+F` + `F3` (comments)

`MainViewController` comment-search state

`pdfView.go(to: PDFDestination)` in `navigateToCommentSearchResult`

JumpStation `Enter`

`JumpStationPanel` selection, `AnimaPDFView.jumpToBookmark` validation

`go(to: PDFPage)`

pdf:// same-document `page`

`AppDelegate.handleSchemeURL`

`pdfView.go(to: PDFPage)`, marked as the future seam site

Deliberately outside the seam: `restore(toPageIndex:)` (last-page restore _and_ the pdf:// different-document open -- §6.3 step 5 has no pre-jump position to record), ordinary scrolling and sidebar sync, and the dead `reloadDocument()` (separate deletion TODO).

## Two approaches

**A -- `farJump(to:)` overloads on `AnimaPDFView` (my recommendation).** Three one-line overloads mirroring PDFKit's own `go(to:)` idiom (`PDFPage`, `PDFDestination`, `PDFSelection`), plus a header comment stating the contract: every far jump executes here, step 10 records the pre-jump position here, `restore` and scrolling bypass deliberately. Reroute the five sites. Pros: smallest possible honest seam, no new type or injection wiring, and the TODO explicitly warns against a premature NavigationManager. Cons: `AnimaPDFView` gains one more section, and step 10's stack state would live on the view as a small property.

**B -- Dedicated `FarJumpExecutor` type.** Same seam, but as its own class injected like the managers, giving the JumpStack a natural home in step 10. Pros: cleaner separation if the seam grows. Cons: three forwarding one-liners don't yet earn a type plus wiring across `AnimaPDFView`, `MainViewController`, and `AppDelegate` -- and extraction later is cheap precisely because the call sites will already name the seam.

One design note for either approach: `go(to: PDFSelection)` has selection-specific scroll behavior we should not flatten into a point destination, so I'd keep three entry points rather than funnel everything through one destination-based core.

## Proposed steps

1.  Agree on approach and naming (now).
2.  `AnimaPDFView.swift`: add the seam, reroute its three internal sites. One drop-in replacement.
3.  `MainViewController.swift` + `AppDelegate.swift`: reroute the two external sites, update the now-stale marker comments.
4.  Verify: build, Cmd+U, `make test`, then manual acceptance 11(a) -- all six far-jump paths behave identically, restore still bypasses the seam. (No navigation unit tests exist; precedent says manual for UI navigation.)
5.  Session bookkeeping: `HISTORY.md`, strike the TODO item, `GOALS.md` pointer, mark step 9 in `TARGET_ARCHITECTURE.md`, brief `README.md` note.

**One conscious fork before you decide:** step 9 alone changes no visible behavior -- its value is making step 10 safe. We _could_ fold 9+10 into one session, but I'd keep the plan's separation: acceptance 11(a) isolates rerouting regressions before any stack logic exists.

Questions for you: Approach A or B? `farJump(to:)` as the name, or do you prefer something else? And does the boundary map match how you see it?

> [!note] User:
> I like your approach, but I'd like to get your feedback on an alternative way to approach it.
>
> The idea would be to add one narrow method to AnimaPDFView, for example conceptually:
>
> -   accept a PDFDestination
> -   capture the current page in the future JumpStack step
> -   call the underlying go(to:)
>
> Each current owner continues to find and validate its own target, but sends the final destination through this method. Page-based jumps become a PDFDestination at the page's existing visible origin or a standard page destination; PDF-text hits and comment hits can retain their annotation/selection-oriented locations.

Assistant:
Denkt nach

Good instinct -- and on reflection I think it's better than my overloads, for a reason that's already sitting in your codebase.

## Why your version wins

**`PDFDestination` is PDFKit's universal currency for "a location in a document."** All six far-jump sources reduce to it without loss: a page jump is "top of page N," a find hit is "this rect on page N," a comment hit is "this annotation's midpoint." One narrow method, one signature, one capture point for step 10 -- the seam becomes trivially explainable in a single sentence: _every far jump ends as `farJump(to: PDFDestination)`_.

**The idiom already exists in the project.** `navigateToCommentSearchResult` in `MainViewController` already constructs a `PDFDestination(page:at:)` from the annotation's midpoint and calls `pdfView.go(to: destination)`. Your proposal generalizes an idiom one owner already speaks, rather than adding a new one. Under your approach that call site becomes a literal one-line change: `go` -> `farJump`. That elegance is evidence the abstraction is honest.

**Overloads would own conversions; owners should.** Each owner knows best _where_ its jump should land. The seam's job is only to be the single execution point -- the place step 10 captures the pre-jump page before calling `go(to:)`.

## The one real risk: find/F3 scroll behavior

This is where I want to be precise, because it's the only call site with a potential _visible_ difference:

-   `go(to: PDFSelection)` lets PDFKit decide the scroll -- roughly "reveal the selection's bounds," which for a same-page F3 advance can mean barely scrolling at all.
-   `go(to: PDFDestination)` scrolls the destination point to the top of the viewport in continuous mode.

Converting find hits to destinations (e.g., top-left of `selection.bounds(for: page)`) therefore likely changes the feel of F3 chains: each hit gets pinned near the top instead of minimally revealed. Honestly, that might be an _improvement_ -- consistent landing position, reading continues downward -- but it's a behavior change in a step chartered to be behavior-preserving, and PDFKit's exact selection-scroll policy is underdocumented, so I won't promise equivalence.

**Proposal:** convert find like everything else, then do an explicit before/after manual check of an F3 chain as part of acceptance 11(a). If you dislike the new feel, the escape hatch is a hybrid: keep one additional selection-typed entry `farJump(toSelection:)` for that one site. The seam stays narrow; PDFKit reality gets admitted. I'd rather decide this from observed behavior than from guesswork.

## One refinement: don't triplicate the page geometry

Literal reading of your approach puts the "top of page" incantation (`page.bounds(for: displayBox)`, take `(minX, maxY)`) at three call sites -- goto, bookmark, pdf://. Same one-liner three times is a smell, and `displayBox` is easy to get subtly wrong. I'd put a tiny factory next to the seam instead, conceptually:

swift

```swift
`extension PDFDestination {
    // Landing point matching go(to: page)'s top-of-page behavior.
    convenience init(topOfPage page: PDFPage, displayBox: PDFDisplayBox) { ... }
}`

```

Call sites stay uniform -- `farJump(to: PDFDestination(topOfPage: page, displayBox: displayBox))` -- the seam keeps its single signature, and the geometry lives in exactly one place. Find and comment conversions are each unique, so they stay inline at their owners, as you proposed.

Two small mechanics, both already de-risked by the existing comment-search code: a fresh `PDFDestination(page:at:)` has unspecified zoom, so `go(to:)` preserves the current zoom (no zoom-reset surprise -- comment search relies on this today); and for step 10, the capture order inside the seam is `currentPageIndex()` _before_ `go(to:)` -- your "capture, then call the underlying go(to:)" framing, exactly.

## What stays the same

`restore(toPageIndex:)` keeps calling `go(to: page)` directly -- last-page restore and pdf:// different-document opens bypass the seam deliberately, with its existing comment updated to name the seam. No NavigationManager. Same three files touched: `AnimaPDFView.swift` (seam + factory + goto/find/bookmark sites), `MainViewController.swift` (one line), `AppDelegate.swift` (pdf:// site + comment). `highlightedSelections` remains the sole find visual -- nothing else depended on `go(to: PDFSelection)`.

## Decisions before I touch anything

1.  Adopt the single `farJump(to: PDFDestination)` seam with the top-of-page factory helper?
2.  Find/F3: convert to destinations now, with the before/after scroll check in acceptance and the hybrid overload as escape hatch?
3.  Keep the name `farJump(to:)`?

If yes to all three, my step 2 is the drop-in replacement of `AnimaPDFView.swift`, and we proceed as planned from there.
