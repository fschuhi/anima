User:
Hi GPT! This is a continuation of previous conversations on `anima`. Please read the guide `FIRST_PROMPT.md`. We will probably take a slightly different route than what's marked as next steps (in `GOALS.md`), so please do not yet pour a lot of effort into that.

Assistant:
Denkt nach

Hi Frank -- I have read `CRITICAL_RULES.md` first, then `FIRST_PROMPT.md`, and verified the `filesdump.txt` integrity: its header and trailer both report **26 documents**, so the project context is complete.

I understand and will follow:

-   Discuss -> Approve -> Implement, in that order.
-   No unsolicited files or code changes.
-   Complete drop-in replacements after approval, with no incidental cleanup.
-   Small, teachable steps rather than a solution dump.
-   Existing tests are the behavioral specification and must remain green.
-   Inventory first when reviewing existing artifacts.
-   The project context is self-contained; I will work from the supplied materials rather than assumed prior-session memory.

## Project orientation

Anima is a native macOS PDF reader for a deliberately narrow highlight-and-comment workflow. PDFKit handles rendering and interaction; the Python/PyMuPDF helper owns incremental PDF writes. `AnnotationManager` is the dual-write seam, while `MainViewController` owns the split-view/sidebar synchronization and emphasis behavior.

The current test baseline recorded in `GOALS.md` is **18 green tests**: 11 Python and 7 Swift.

## Current pointer, as recorded

The next planned item is a **Swift FitzBridge round-trip test**, preceded by two decisions:

1.  How the Swift test should resolve the helper and venv paths.
2.  How the test should inspect the persisted write, with the likely route being reopening the mutated PDF through PDFKit and reusing `SidebarExtractor`\-style verification.

But I will not start designing that in depth yet, since you expect a different route.

## Two sensible ways to proceed now

1.  **You name the detour directly.**
    Tell me the behavior, concern, or file you want to work on, and I will begin with a proportionate inventory and a discussion of options.

2.  **Brief re-triage discussion first.**
    We can look at the currently visible forks -- test hardening, resize/window ergonomics, color-rendering investigation, or a focused cleanup -- and decide whether the session should intentionally revise the order in `GOALS.md`.


Which route do you prefer, and what is the slightly different direction you have in mind?

User:
I'm usually an avid PDF reader who uses highlights and comments and exports them into Obsidian, with a Zettelkasten-like workflow around it. Having a good PDF reader _and_ with strong (which means specificall fast) annotation facilities is a major building block of that overall approach. Anima was supposed to be the replacement for the _old_ PDF-Xchange-Reader, running in the Windows 11 VM under Parallels; the new Editor from them sucks, because it can do too much and important keyboard shortcuts for selecting and highlighting have been nerfed. Anima would enable a fully MacOS centric workflow, as Obsidian runs under MacOS, too.

I've basically stopped reading PDFs.

Anima is not ready yet, because it misses important UI aspects, particularly like goto page, search in the document, have multiple files open (not yet included in the `TODO.md` or `GOALS.md`), and overall has a smooth UX which pulls me in, e.g. that the app remembers the sizing and position of the main window. And because the highlight colors in Anima are not the same like other apps show them (like the PDF-Xchange-Viewer, but also browsers), I'm hesitant to do _any_ highlighting. I'm in a limbo state.

After working on other projects, I therefore dipped my toes into `anima` yesterday, and I was appalled by (a) a new error, probably coming from new automatic isolation settings, and (b) me not having a clue about the overall architecture, the design, the Swift language, feeling like puppet handled by an LLM.

As a result, I'm contemplating to stop working on Anima. This would be a desaster, because there is to my knowledge nothing on the market except the old PDF-Xchange-Viewer that I _want_ to use, and _wanting_ is so important for the whole motivational arc. It _feels_ like I'm rather close and should not abandon the project, but I'm feeling like a dumb vibe coder. Yesterday I had the test: the project came back from hibernation into broad daylight, and what I felt wasn't the itch to continue, it was dread and joylessness. Other LLMs point out that I've taken a lot of decisions along the path and that I've made good progress learning Swift and even dealing with Xcode, but it simply doesn't feel that way.

How could we salvage this mess?

Assistant:
What you are describing is not primarily a Swift competence problem. It is a **product-flow and ownership problem**:

-   Anima has reached the awkward middle: it is real enough to expose the missing pieces, but not yet comfortable enough to earn daily use.
-   The code has accumulated several sophisticated subsystems -- hybrid persistence, popup suppression, sidebar scroll physics, dual-write consistency, emphasis state -- before the basic reader loop is fully habitable.
-   The current roadmap put test hardening ahead of reader habitability. That is technically defensible, but it may be wrong for the project's actual purpose: getting you back to reading PDFs.
-   The Xcode isolation error was especially damaging because it made the project feel like an opaque machine you cannot re-enter. According to the current `GOALS.md`, that particular Xcode 26.3 error was fixed with `nonisolated` on `CommentCard`, and the recorded baseline is 18 green tests. But the fact that the fix felt alien is the important signal.

And your hesitation about highlights is rational. If you do not trust that Anima's rendered highlight appearance matches what you intend, then annotations are not safe working material. The color issue is not cosmetic; it blocks use of the reader.

## The key reframing

Do **not** try to salvage Anima by becoming fluent in all of its architecture first.

That would turn the project into a Swift education program with a PDF reader attached. It is the reverse of what you need.

Instead, salvage it by making a narrowly defined version of Anima pleasant enough that you voluntarily open it for a real paper. Architecture understanding should be rebuilt only around the pieces we touch, just in time.

You are not starting from nothing. The hard annotation contract exists and is tested:

-   PDFKit renders and handles selection.
-   fitz persists annotations incrementally.
-   The UUID and coordinate contracts are explicit.
-   Highlight creation, comment editing, deletion, sidebar extraction, and Finder opening already exist.
-   The current test baseline says those core seams are green.

That is substantial. The project is not a pile of speculative scaffolding. But it needs a deliberate simplification of **what counts as success next**.

## Three routes

### 1\. Reader-first recovery -- my recommendation

Declare a temporary milestone: **"Anima Daily Reader v0.1."**

Its only criterion:

> Can Frank open a real PDF and enjoy reading, finding a page, searching, highlighting, commenting, and resuming the next day without anxiety about the result?

For that milestone, prioritize only blockers to actual use:

1.  Establish trust in highlight color rendering.
2.  Make the main window and sidebar behave civilly across launches.
3.  Add navigation that lets you return to known places quickly -- at minimum page awareness and goto page.
4.  Investigate document search, ideally by exposing native PDFKit behavior rather than building a search system.
5.  Open multiple PDFs as separate app instances first, which already works with `open -n`; defer true tabs until the reader loop proves it needs them.

Under this route, the planned FitzBridge and cross-page Swift tests are not abandoned. They are intentionally parked. They protect valuable contracts, but they do not currently get you back to reading.

**Trade-off:** We accept a small amount of known test debt while we remove the usability blockade. That is safe only if we avoid touching the established annotation-writing contract casually.

### 2\. Comprehension-first reset

Pause feature work. Do a small number of guided architecture sessions:

1.  Trace one real action end-to-end: select text -> highlight -> fitz write -> PDFKit in-memory update.
2.  Trace one comment action end-to-end.
3.  Draw a compact "who owns what" map for the eight Swift files.
4.  Identify the few concepts you need right now: AppKit lifecycle, delegates, view controllers, Auto Layout, `PDFView`, and Swift isolation.

This would restore intellectual ownership before further changes.

**Trade-off:** It may make the code feel less mysterious, but it postpones the visible improvements that would motivate you to use Anima again. I would use this as a short supporting intervention, not the main project direction.

### 3\. Controlled retirement / replacement investigation

Explicitly stop feature development for now and evaluate whether a commercial macOS reader, or a minimal alternative architecture, can meet your workflow.

This is not irrational. A tool that is too burdensome to maintain can become more expensive than the workflow friction it replaces.

**Trade-off:** Based on the project context, this seems premature. You have already passed the difficult annotation-persistence threshold, and the missing functionality is mostly reader ergonomics and navigation rather than a failed foundation. But keeping this option legitimate is useful: continuing should be a choice, not an obligation to justify past effort.

## A value-first path

I recommend route 1, with one brief route-2 session embedded at the beginning.

Not "build a polished reader." Not "finish all tests." Not "learn Swift properly."

Instead:

### Step 0 -- Reclaim the map, without changing code

We make a concise architecture inventory of the current app, organized around user actions rather than source files:

-   How a PDF reaches the window.
-   How a highlight is created and saved.
-   How comments are stored without popups.
-   How the sidebar is derived and updated.
-   Which parts are stable infrastructure versus active sources of complexity.

This should be short enough to become your re-entry map. The goal is not to understand every line of `MainViewController.swift`; it is to know where to look and what you can safely leave alone.

### Step 1 -- Resolve the trust blocker: highlight color

Do the experiment already named in `TODO.md`, before changing any color values:

-   Inspect the existing appearance stream and its blend mode.
-   Produce or inspect a controlled blend-mode-free comparison.
-   Compare PDFKit/Preview against a browser/PDFium and your reference viewer.
-   Decide whether Anima needs display-side compensation, whether the stored PDF is correct but Apple rendering differs, or whether the annotation-writing appearance stream should change.

This is the right first technical task because it answers whether Anima is safe to use for new annotations.

### Step 2 -- Make relaunching civilized

Treat window position/size and split-divider persistence as one contained ergonomics task. This is high visible value and likely low architectural risk. It addresses the basic feeling that the app is a temporary development artifact rather than your reader.

### Step 3 -- Navigation before architecture

For immediate reading utility:

-   Add page awareness.
-   Add goto page.
-   Investigate whether simple native PDFKit find can be surfaced cheaply.

I would challenge the existing implied sequence here: a status bar may be a good eventual home for these controls, but it should not automatically become a prerequisite structural project. We should first ask whether a small page indicator plus `Cmd+G` gives the needed value without building a generalized status-bar framework.

### Step 4 -- Defer real tabs consciously

"Multiple files open" is important, but it is also where the single-window assumptions, menu behavior, document ownership, sidebar state, and `AppDelegate` open policy converge. That is a separate design discussion.

The cheapest usable answer today is already present: multiple independent instances via `open -n`. It is imperfect, but it gives you parallel reading without forcing a tab architecture now. We can decide later whether this is enough or whether tabbed documents are essential to your actual workflow.

## The collaboration correction I would make

For future work, I would use a stricter rule:

> Before modifying a subsystem, I explain its local ownership and the exact action path it participates in. We do not treat it as a black box merely because it currently works.

For example, if we work on page navigation, we should not need to descend into fitz, sidebar extraction, popup behavior, or annotation UUIDs. We would locate the narrow PDFKit navigation seam, explain it, make one change, and run the relevant tests.

That is how you stop being a person who asks an LLM to manipulate an unfamiliar codebase, and become the person who owns a growing set of small, understandable decisions.

## Proposed immediate next session

I suggest we do **Step 0 only** next: a user-action-based architecture inventory and a "stable / do not touch / likely next seams" map. No code, no files, no edits, no attempt to solve the roadmap.

Then we can make a deliberate project decision:

1.  continue with the reader-first recovery path, starting with highlight color trust;
2.  revise the roadmap to put usability ahead of remaining test gaps;
3.  or pause/retire the project after a fair assessment.

Would you like to begin with that recovery inventory, or would you rather discuss first whether highlight-color trust, navigation, or the sense of code ownership is the most immediate blocker?

User:
Thank you for this constructive feedback on my ranting. This has already been a milestone in itself. I'm less willing to abandon the project now.

The "Reader-first recovery" shows it's head in the "UX Priorities" section in the `TODO.md`, except the document search. I'm totally fine with parking the test suite for a while. I worked on it yesterday, with two small tests, that's enough for now, also because anything else needs understanding first, which is lacking (or dormant; I remember having a much better grip a couple of months ago; I might put the bar too high when it comes to bringing a project out of hibernation). I will closely monitor the changes with git diff, always prepared to rollback. This stance suits my overall inclination for step-by-step work.

The "replacement investigation" is a dead end. I will have to go back to the PDF-Xchange-Reader. Other readers are too high-powered, too cluttered, to clumsy with screenshots. I don't need signing, forms, drawing, whatever. And I am under the borderline spell of a depressive episode, triggered by a sense of not being good enough. That's a bad point in time to make sweeping decisions. Thank you for flagging this route as premature.

I'm fine with Step 0 - Step 4.

Regarding your "stricter rule": Should that go anywhere in e.g. the `LLM_INSTRUCTIONS.md` (which I would prefer)? Or do you suggest using this rule only for this convo here?

When you say "proposed immediate next session", do you refer to a new session I should start? Or is it something we do here?

Assistant:
I mean **we can do Step 0 here, in this session**. I used "next session" only in the project-planning sense, not as a request for you to restart the chat.

And I agree with your calibration: two small test gaps closed yesterday is a solid stopping point for test-first hardening. Parking the remaining test items is a conscious prioritization, not abandonment of quality -- especially with `git diff` and rollback as your guardrails.

## Should the stricter rule go into `LLM_INSTRUCTIONS.md`?

**Yes, I think it belongs there**, rather than being only a promise for this conversation.

It addresses a recurring collaboration requirement, not a one-off technical detail:

> Before modifying a subsystem, explain its local ownership and the exact user-action path it participates in. Do not treat working subsystems as black boxes; identify what is in scope and what is intentionally out of scope for the current change.

### Inventory of relevant existing material

`LLM_INSTRUCTIONS.md` already has several elements that partially serve this purpose:

-   **"Step-by-step development"** in the referenced critical rules: requires digestible work and explanation of why.
-   **"How to Collaborate"**: positions the user as learning Swift and asks the model to educate rather than simply generate.
-   **"Explaining & Teaching Style"**: requires an inline explanation sufficient for the current decision, with optional pointers for deeper study.
-   **"Scope Skepticism"** and **"Architecture Skepticism"**: require challenging unnecessary complexity and avoiding infrastructure detours.
-   **"What Success Looks Like"**: explicitly says you should understand the code after work is done.

**Finding:** those rules say _that_ explanations and small steps are required, but they do not explicitly require an explanation of **the local ownership boundary and end-to-end action path before changing a subsystem**.

**Why that gap matters:** Anima has several subsystems which are individually reasonable but collectively dense. Without this explicit rule, an AI can make a locally correct change while leaving the surrounding ownership model implicit -- exactly the "puppet handled by an LLM" failure mode you want to prevent.

### Two ways to add it

1.  **Small addition to "How to Collaborate"** -- recommended
    Add a short "Local ownership before modification" subsection near the teaching/collaboration guidance. It would apply across the project without turning the instructions into a larger process framework.

    -   Pro: clear, durable, and proportionate.
    -   Con: it will not force a formal diagram or inventory every time, so we must still apply judgment proportionately.
2.  **New formal pre-change protocol**
    Add a required mini-template: user action, owning file/type, collaborators, explicit non-goals, and test boundary.

    -   Pro: very unambiguous.
    -   Con: likely too bureaucratic for small changes such as changing a layout constant or adding a test assertion. It risks creating ceremony rather than understanding.

I recommend **option 1**, with a wording that makes the depth proportional: a one-paragraph orientation for a small localized change, a fuller action-path inventory when a change crosses components.

I will not modify `LLM_INSTRUCTIONS.md` unless you explicitly approve it. If you choose option 1, I can first propose the exact wording for discussion, then -- only after your approval -- provide the complete drop-in replacement file.

## Step 0, here

We can now begin the recovery inventory here, without code or document changes. I suggest we organize it by four daily-reader actions rather than by the Swift file list:

1.  Open or resume a PDF.
2.  Read and navigate through it.
3.  Create and trust a highlight/comment.
4.  Reopen the file later and extract/use its annotations.

For each, I will identify:

-   the files and types that own the action;
-   the action's path through the app;
-   what is stable infrastructure and should be left alone;
-   the likely narrow seam for the UX work ahead.

This is specifically not a line-by-line code tour and not an attempt to explain all of `MainViewController.swift`.

Would you like to approve **option 1** for a future `LLM_INSTRUCTIONS.md` addition, and shall we begin the Step 0 user-action inventory now?

User:
Option 1, agreed. Let's put the "Local Ownership before modification" before the "Explaining & Teaching Style". Please draft the paragraph content. I'll do the editing of the `LLM_INSTRUCTIONS.md`, no drop-in replacement required.

And let's begin with the Step 0 user-action inventory! Exciting!

Assistant:
Denkt nach

## Draft paragraph for `LLM_INSTRUCTIONS.md`

Place this before `### Explaining & Teaching Style`:

markdown

```markdown
`### Local Ownership Before Modification
Before proposing or making a change to an existing subsystem, explain its local ownership in terms of the user action we are changing: which type or file owns the action, which collaborators it calls, what state or contract it relies on, and what is intentionally outside the change's scope. Scale the explanation to the change: a small localized edit may need only a short orientation; a change crossing UI, persistence, or coordination boundaries needs a concise end-to-end action path. Do not treat currently working code as a black box merely because it is not the immediate target. The goal is that I can locate the relevant seam, understand why it is safe to change, and know which surrounding systems we are deliberately leaving alone.`

```

I think this is right-sized: it creates the requested obligation without forcing a bureaucratic template for every one-line change.

* * *

# Step 0 -- User-action inventory

This is an inventory, not a change proposal. I am organizing the current system around the things you want to do as a reader, rather than around the source-file list.

## 1\. Open or resume a PDF

### What the action currently does

You can open a PDF in three ways:

1.  Finder / "Open With" Anima.
2.  A command-line argument.
3.  The development fallback at `data/input.pdf`.

Once the PDF is loaded, Anima suppresses native popup display in memory, builds the sidebar from existing comments, and lays out the PDF/sidebar pair.

### Ownership and path

Responsibility

Current owner

What it does

macOS application launch and file-open delivery

`AppDelegate.swift`

Receives Finder URLs, resolves the PDF source, creates the main controller, and assigns the initial window title.

Main app layout

`MainViewController.swift`

Creates the split view with PDF on the left and sidebar on the right.

PDF loading preparation

`MainViewController.loadPDF(document:)`

Scrubs popup state in PDFKit memory, assigns the document to `pdfView`, extracts comment cards, creates one sidebar container per PDF page, then runs layout.

PDF rendering and interaction

`AnimaPDFView.swift`

Is the `PDFView` subclass that displays the loaded document and later handles mouse/keyboard interactions.

Finder eligibility

`Info.plist`

Registers Anima as an alternate viewer for `com.adobe.pdf`.

### Important current behavior

-   A cold Finder launch is handled correctly: `application(_:open:)` stashes the URL before window setup, then `applicationDidFinishLaunching` consumes it.
-   A hot Finder open does **not** replace the existing document. It logs that Anima is single-window and points to `open -n`.
-   `MainViewController.loadPDF` does more than assign `pdfView.document`: it also establishes the sidebar's per-page structure and strips popup presentation state from PDFKit's in-memory version.

### Stable infrastructure -- do not casually touch for reader ergonomics

-   The Finder cold-launch timing logic in `AppDelegate`.
-   The distinction between disk PDF contents and PDFKit's in-memory popup-suppressed state.
-   The per-page sidebar container construction in `loadPDF`.

These are not directly involved in window persistence, page navigation, or search.

### Likely narrow seams for upcoming work

-   **Window frame persistence:** `AppDelegate.applicationDidFinishLaunching`, because it owns the `NSWindow` lifecycle and has the window outlet.
-   **Tabs / true multi-document support:** this is not narrow. It crosses `AppDelegate` hot-open behavior, document ownership in `MainViewController`, sidebar state, and likely menu/window semantics. The existing `open -n` multi-instance behavior is the useful stopgap.

### Finding vs preference

-   **Finding:** true tabs are structurally broader than the current UX items because the app has one `pdfView`, one `sidebarScrollView`, one set of emphasis state, and a hot-open policy that intentionally does not replace the current document.
-   **Preference:** defer tabs until basic single-document reading is pleasant again.

* * *

## 2\. Read and navigate a PDF

### What the action currently does

The app already provides:

-   continuous single-page scrolling;
-   PDFKit selection;
-   native trackpad scrolling;
-   zoom behavior through `autoScales`;
-   sidebar scroll synchronization;
-   card-to-highlight emphasis and highlight-to-card emphasis.

It does **not** yet expose:

-   a page indicator;
-   goto page;
-   a document search command/UI;
-   civilized startup resize and persistent window geometry.

### Ownership and path

Responsibility

Current owner

What it does

Core PDF reading view

`AnimaPDFView.swift`

Inherits PDFKit's rendering, continuous-scroll presentation, text selection, and page conversion facilities.

Split-view construction

`MainViewController.loadView()`

Creates the PDF/sidebar split, sets initial sidebar width, adds minimum widths and content hugging priorities.

Initial divider position

`MainViewController.viewDidLoad()`

Positions the divider for an initial 300-point sidebar.

Resize observation

`MainViewController.setupResizeObserver()`

Watches `pdfView` frame changes and triggers sidebar relayout.

Sidebar layout calculations

`MainViewController.updateSidebarLayout()`

Maps every PDF page and card anchor into sidebar coordinates, including collision avoidance.

Scroll synchronization

`MainViewController.pdfViewDidScroll(_:)`

Converts PDF scroll position to the sidebar's corresponding scroll position.

Keyboard input currently claimed by Anima

`AnimaPDFView.handleKeyEvent(_:)`

Handles H, P, Return, and Delete; passes unhandled events back to PDFKit/AppKit.

Fallback key monitor

`AppDelegate.swift`

Re-sends key events to `AnimaPDFView` because PDFKit internals may hold keyboard focus.

### The important distinction: PDF reader versus sidebar physics

The visible PDF reader is mostly PDFKit. The complicated code is mostly there to make the sidebar line up and scroll with that reader:

text

```text
`PDFKit renders/scales/scolls the PDF
        ->
MainViewController converts page/card positions
        ->
sidebar containers and cards are moved to visually align`

```

That means page navigation is likely a **PDFKit-facing feature**, while the sidebar needs to react correctly afterward but should not own navigation policy.

### Stable infrastructure -- do not casually touch

-   The coordinate conversion in `pdfViewDidScroll(_:)`.
-   `updateSidebarLayout()` page-position math and card collision avoidance.
-   The local-scroll routing in `PageSidebarView`.

These are exactly the kind of working-but-dense subsystem that should not become collateral damage while adding a page display or `Cmd+G`.

### Likely narrow seams for upcoming work

1.  **Window and split persistence**

    -   Main window: `AppDelegate`, because `NSWindow` frame autosaving is window-level AppKit state.
    -   Sidebar width: `MainViewController`, because the divider belongs to its `NSSplitView`.
    -   The expected effect is indirect but helpful: preserving the divider reduces surprise at launch and likely removes much of the "sidebar is the wrong width" experience.
2.  **Status/page indicator**

    -   Likely `MainViewController`, because it already owns the main reading layout and coordinates PDF state with adjacent UI.
    -   `AnimaPDFView` / `PDFView` supplies the current page state; the controller should display it.
    -   The first question is whether a small dedicated status strip is necessary, or whether the smallest useful display can be introduced without prematurely creating a general status-bar subsystem.
3.  **Goto page**

    -   Likely a small navigation method in `MainViewController` or `AnimaPDFView`, invoked by the controller's UI/command handler.
    -   The underlying movement is native PDFKit: identify the page, construct/use the proper destination, call `go(to:)`.
    -   The sidebar should follow through its existing scroll synchronization, rather than receiving a special goto-page implementation.
4.  **Search**

    -   This deserves an investigation before design.
    -   The cheap path is to expose PDFKit's document search and native selection/navigation behavior.
    -   We should first determine what keyboard behavior already comes "for free" through the responder chain and what minimal UI is needed to make it usable. We should not begin by designing a sidebar result list, regex engine, or custom search index.

### Finding vs preference

-   **Finding:** resize causes `pdfView` frame-change notifications, which call full sidebar relayout; with `autoScales`, width changes also cause PDF scaling changes. This supports the existing TODO hypothesis that resize roughness is related to ambiguous split resizing plus expensive synchronous relayout.
-   **Finding:** the mode toggles overwrite the filename because `AnimaPDFView.updateWindowTitle()` starts from `"Anima"` rather than the loaded PDF name.
-   **Preference:** solve the high-frequency reader loop first: stable window geometry, page awareness, goto page, then minimal search.

* * *

## 3\. Create and trust a highlight or comment

### What the action currently does

There are two highlight entry paths:

-   Select text and press Return/Enter.
-   Toggle persistent highlight mode with H, then release the mouse after selecting text.

Highlights are created without comments. You double-click a highlight later to add or edit a comment. Deleting targets the currently emphasized highlight.

### Ownership and path: create highlight

text

```text
`Reader selects text in PDFKit
        ->
AnimaPDFView.createHighlightFromSelection()
        ->
selection is split into lines, first page is chosen
        ->
AnnotationManager.createHighlight(...)
        ->
fitz-space quads are calculated
        ->
FitzBridge runs tools/anima_helper.py
        ->
PyMuPDF writes the PDF incrementally
        ->
AnnotationManager creates matching in-memory PDFKit annotation
        ->
AnimaPDFView asks sidebar to rebuild the affected page`

```

### Ownership and path: edit comment

text

```text
`Reader double-clicks a highlight or sidebar card
        ->
AnimaPDFView / MainViewController ensures visual emphasis
        ->
AnimaPDFView.editComment(...)
        ->
AnnotationManager.editComment(...)
        ->
CommentInputPanel presents modal text editor
        ->
FitzBridge -> anima_helper.py persists /Contents change
        ->
AnnotationManager updates PDFKit in-memory annotation
        ->
sidebar rebuilds that page's cards`

```

### Specific owners

Responsibility

Current owner

What it does

Mouse and key dispatch

`AnimaPDFView.swift`

Detects selection/highlight gestures, hit-tests highlights, handles H/Return/Delete, starts CRUD requests.

Annotation business logic

`AnnotationManager.swift`

Owns creation/edit/delete dual-write workflow, UUID lookup, in-memory annotation construction, coordinate conversion.

Cross-language persistence

`FitzBridge.swift`

Runs the venv Python helper as a subprocess.

PDF mutation

`tools/anima_helper.py`

Uses fitz/PyMuPDF to add, edit, and delete annotations with incremental save.

Comment editor UI

`CommentInputPanel.swift`

Provides the modal, multi-line comment editing panel.

Visual selection/emphasis state

`MainViewController.swift`

Changes the in-memory highlight color/opacity and card border; unifies it with the Delete target.

Sidebar data extraction

`SidebarExtractor.swift`

Turns non-empty annotation comments into `CommentCard` data.

### Stable infrastructure -- the hard-won contract

The annotation system has several explicit contracts that should be regarded as stable infrastructure while we work on reader UX:

1.  **PDFKit renders; fitz writes.**
    PDFKit is deliberately not used to save the document because its rewrite behavior damages or changes annotation details.

2.  **Dual-write during a session.**
    The helper persists to disk, then `AnnotationManager` mirrors the mutation in the in-memory PDFKit document. This avoids a reload and associated scroll drift.

3.  **Coordinate conversion happens in Swift.**
    `AnnotationManager.fitzQuad(from:pageHeight:)` converts only the y axis before passing quads to fitz. The helper receives fitz-native coordinates.

4.  **UUID is `/NM`.**
    It is how the Swift UI and Python helper identify the same annotation. `userName` is fallback only; `/T` is the author.

5.  **Comments use `/AnimaComment` in PDFKit memory.**
    This suppresses PDFKit's native yellow popup icons in normal mode. Standard `.contents` is restored only when X-Ray mode is enabled.

6.  **The PDF file remains the long-term source of truth.**
    On a later launch, PDFKit loads fitz's persisted PDF, then Anima prepares its in-memory popup-suppressed display state again.


### The highlight-color issue belongs here

Your hesitation to highlight is a justified trust concern because the current annotation path has two different questions:

-   **Persistence correctness:** the stored annotation color and opacity are pinned by Python tests and written by `anima_helper.py`.
-   **Renderer appearance:** Apple renderers show the persisted annotation more saturated than PDFium/browser/reference viewers, according to the current TODO evidence.

The code currently sets a pink color `[1.0, 0.75, 0.80]` with opacity `0.4`. The pending question is not simply "what RGB value looks nicer?" It is whether the generated annotation appearance stream -- likely including its blend mode -- produces a rendering discrepancy across PDF engines.

That makes the planned experiment a **trust investigation**, not cosmetic tuning.

### Likely narrow seam for the color investigation

-   Primary: `tools/anima_helper.py`, because it creates and updates the fitz annotation and therefore its persisted appearance stream.
-   Verification: the existing Python test fixture/output workflow and manual comparison across renderers.
-   Potentially later: `AnnotationManager.highlightColor` and `highlightOpacity`, which must remain aligned with the Python values if we change stored appearance.

Notably, this should not require changes to sidebar layout, navigation, or the general PDF opening path.

### Finding vs preference

-   **Finding:** highlight creation intentionally truncates a cross-page selection to the first page. This is recorded as a deliberate per-page design rather than a known defect.
-   **Finding:** color/opacity persistence is covered by the Python tests, but render-equivalence across Apple and non-Apple PDF engines is not currently pinned.
-   **Preference:** do the controlled appearance-stream experiment before choosing a compensation or changing the annotation defaults.

* * *

## 4\. Reopen the PDF and use its annotations downstream

### What the action currently does

On reopening a PDF:

1.  `AppDelegate` loads it as a `PDFDocument`.
2.  `MainViewController.loadPDF` moves existing standard PDF comment text into in-memory `/AnimaComment` and disconnects/removes popup annotations for normal rendering.
3.  `SidebarExtractor` scans annotations, takes non-empty comments, extracts UUID/author/date/anchor position, and creates comment cards.
4.  The sidebar aligns those cards against their corresponding PDF positions.

Outside Anima, the persisted standard PDF annotations are intended to remain compatible with your existing `pdf-annotations` extraction workflow and Obsidian notes.

### Ownership and path

Responsibility

Current owner

What it does

Persisted PDF annotation format

`tools/anima_helper.py`

Writes standard highlight annotations, `/NM`, `/Contents`, author/date/appearance data, and popup metadata.

App reopen preparation

`MainViewController.scrubCommentsForPopupSuppression(in:)`

Converts standard contents into Anima's display-only in-memory representation and removes visible popup behavior.

Sidebar model

`SidebarExtractor.swift`

Extracts comment-bearing highlights to `CommentCard` values.

Sidebar visual representation

`CommentCardView.swift`

Renders date/author/comment and emits click/double-click actions.

Compatibility verification

Python tests and the intended external `pdf-annotations` workflow

Tests validate core PDF fields and incremental-save preservation; full production extraction/bibnote verification remains a Phase 2 task.

### Stable infrastructure -- do not casually touch

-   The fact that `/Contents` must remain usable for other viewers and downstream extraction.
-   The xref-level `/NM` writing in `anima_helper.py`.
-   The clear-comment behavior: fitz ignores empty `set_info` content, so clearing relies on writing an empty `/Contents` value directly at xref level.
-   The distinction between disk representation and popup-suppressed in-memory display representation.

### Known small debt, now intentionally parked

The current roadmap identifies two remaining persistence-related test items:

-   a Swift `FitzBridge` round trip;
-   a Python test pinning comment-clear ordering when a popup does not already exist.

Those are valuable because they defend real contracts. But they do not need to block reader-first work if we leave this persistence seam alone until we deliberately return to it.

### Finding vs preference

-   **Finding:** current Python tests already cover creation, edit, clear, delete, UUID `/NM`, opacity survival, incremental-save preservation, and error cases.
-   **Finding:** the clear-comment implementation has a known fragile ordering concern, documented in `GOALS.md`; its focused regression test is still missing.
-   **Preference:** preserve this subsystem as-is during the early UX recovery steps unless the color experiment specifically requires a helper change.

* * *

# Compact re-entry map

If you only retain one map from this inventory, I suggest this one:

text

```text
`AppDelegate
  owns: launch, Finder opening, main window setup, initial PDF choice

MainViewController
  owns: PDF/sidebar split layout, sidebar rebuild/layout/scroll sync, visual emphasis

AnimaPDFView
  owns: reader input -- keys, mouse, selection, highlight hit-testing
  delegates annotation mutations to AnnotationManager

AnnotationManager
  owns: annotation CRUD contract and dual-write coordination
  calls FitzBridge, mirrors results into PDFKit memory

FitzBridge -> anima_helper.py
  owns: subprocess boundary -> durable incremental PDF writes

SidebarExtractor + CommentCardView
  own: deriving and showing comment cards from in-memory PDFKit annotations`

```

And the practical rule for reader-first work:

text

```text
`Window persistence / page navigation / search:
  stay mostly on the AppDelegate + MainViewController + PDFKit side.

Highlight trust:
  investigate the AnnotationManager + anima_helper.py appearance boundary.

Do not enter sidebar physics or annotation persistence
unless the specific user action actually requires it.`

```

## Suggested next discussion

The inventory supports the recovery sequence we discussed, but we should choose the first visible win deliberately.

The three credible first moves are:

1.  **Highlight color investigation** -- resolves the trust blocker before you annotate anything.
2.  **Window + split-view persistence** -- makes every launch less development-artifact-like.
3.  **Page indicator + goto page** -- immediately improves real-paper navigation.

My recommendation remains **highlight color investigation first**, because it determines whether you can safely return to annotation use at all. But window persistence is the smaller, more contained engineering task and might be a good confidence-restoring warm-up.

Which should become Step 1?

User:
Excellent. I feel much better prepared to tackled some interesting UX challenges! Thank you!

1.  Tabs deferred. I'm totally fine with the current `open -n` mechanism.


-   Regarding the current page number, if you suggest not adding a statusbar, let's display the info in the window's caption. We have a minor inconsistency right now that the full name is displayed at startup, but as soon as I press "H" that status is display and the file name is dropped. As a compromise, let's only display the full name at the beginning if the PDF doesn't start with `\([^)]+\)` (author + year). If there is, use that short name handle and retain it when changing state. That should leave enough space for the page number.
-   agreed on 3. goto page
-   agreed on 4. search

> produces a rendering discrepancy across PDF engine

Exactly. PDFKit is the outlier, judging from the Chrome and Brave browsers and PDF-Xchange-Viewer.

Let's start with the Highlight color investigation.

-   Attached a sample PDF, from the `pdf-annotations.pdf` project. The highlights and comments were added with PDF-Xchange-Viewer.
-   screenshots from viewing `input.pdf` in:

1.  PDF-Xchange-Viewer
2.  Edge
3.  Chrome
4.  Preview
5.  Anima

-   The fifth screenshot

Assistant:
Denkt nach

Excellent -- and the supplied reference PDF changes the color investigation in an important, clarifying way.

## First finding: this is not initially an Anima-written-appearance-stream problem

You state that the annotations in the attached `input.pdf` were created with the old PDF-XChange Viewer. The screenshots then show that **same PDF** in five readers.

So, if PDF-XChange Viewer, Edge, and Chrome render those existing highlights as pale pink, while Preview and Anima render them more saturated, then:

-   the stored annotation color is not unique to Anima;
-   Anima's Python helper did not create the appearance stream we are observing;
-   Preview and Anima are the common factor: Apple's PDF rendering stack, with Anima using PDFKit directly.

That does **not** prove the blend-mode hypothesis yet. But it does establish the first-order diagnosis:

> The immediate problem is that Apple renderers display a PDF-XChange-authored reference annotation differently from the non-Apple renderers you trust.

This is good news in one specific sense: we should not begin by altering `anima_helper.py` or its persisted default color. The reference PDF lets us investigate the rendering discrepancy without risking Anima-written annotations at all.

## Screenshot inventory

### Findings

-   The highlight hue in the non-Apple reference views is a very light, low-saturation pink.
-   The Apple views -- Preview and Anima -- are visibly stronger and pinker.
-   The mismatch occurs even though the annotation originated in PDF-XChange Viewer, not in Anima.
-   Anima and Preview are visually aligned enough that this does not look like an Anima sidebar, opacity, coordinate, or dual-write issue.

### What remains unknown

We do not yet know which PDF-level feature Apple handles differently. Plausible candidates include:

1.  **Blend mode** in an appearance stream or ExtGState, especially `/BM /Multiply`.
2.  **Use of a custom appearance stream** versus a renderer's own markup-annotation drawing path.
3.  **Opacity interpretation/compositing** in the presence of an appearance stream.
4.  Some combination of the above.

The current `TODO.md` names `/BM /Multiply` as a hypothesis. The screenshots make that hypothesis worth testing, but they do not themselves confirm it.

## Local ownership before modification

For this investigation, the ownership boundary is pleasantly narrow:

text

```text
`Reference PDF created by PDF-XChange Viewer
        ->
PDF annotation dictionary and possible appearance stream
        ->
PDF rendering engine interprets it
        ->
PDF-XChange / Edge / Chrome / Preview / PDFKit display result`

```

### In scope

-   The attached reference PDF's annotation dictionaries and appearance streams.
-   A disposable copy of that PDF for controlled experiments.
-   Rendering comparisons in the five viewers.
-   Later, possibly Anima's **in-memory display color** after the cause is known.

### Explicitly out of scope for the first experiment

-   `AnnotationManager.createHighlight(...)`
-   `tools/anima_helper.py`
-   fitz persistence behavior
-   UUIDs, comments, popup suppression, sidebar extraction, and layout
-   changing Anima's stored pink `[1.0, 0.75, 0.80]` or opacity `0.4`

That boundary matters. The first question is: _why does PDFKit show this existing PDF-XChange annotation differently?_ Not: _what pink should Anima write?_

## Proposed investigation sequence

### Step 1A -- Read-only PDF forensics

Inspect one or more known highlight annotations in the reference PDF, without changing it:

-   `/C` -- annotation color;
-   `/CA` -- opacity;
-   `/AP` -- whether it has an appearance stream;
-   the appearance stream's resources and ExtGState;
-   `/BM` -- blend mode, if present;
-   whether several highlights use the same structure.

This tells us what PDF-XChange actually stored.

**What it can answer:** whether the blend-mode hypothesis has evidence.

**What it cannot answer alone:** whether the observed Apple discrepancy is caused by that feature.

### Step 1B -- Controlled variant experiment

Make one or more copies of `input.pdf` outside the source fixture, for example under `tmp/`, and alter **only one rendering feature per copy**.

The cleanest first pair would be:

-   `control.pdf` -- byte-for-byte copy;
-   `no-multiply.pdf` -- same document except the target highlight appearance stream's `/BM /Multiply` is removed or changed to `/Normal`.

Then compare both in Preview/Anima and one non-Apple reference renderer.

Possible outcomes:

Outcome

Interpretation

The two variants look different in Chrome/Edge/PDF-XChange, but identical in Preview/Anima

Apple likely ignores or mishandles the relevant blend mode.

Preview/Anima become lighter with the no-multiply variant

The blend mode influences Apple too; we need inspect how each engine composites it.

No viewer changes meaningfully

`/BM` is not the relevant lever, or the changed object was not actually used in rendering.

Only non-Apple views change in an undesirable way

One universal stored-PDF adjustment may be impossible; Anima-only display compensation becomes the likely direction.

### Step 1C -- Decide the product-level remedy

Only after the comparison should we choose among these paths:

1.  **No Anima change:** if the actual evidence overturns the visual impression or shows an acceptable PDF-level fix.
2.  **Change what Anima writes:** only if an altered annotation construction produces faithful rendering across the readers you care about.
3.  **Anima-only display compensation:** keep the stored PDF annotations standard and correct for PDF-XChange/browser/downstream extraction, but make their _in-memory PDFKit appearance_ lighter in Anima.
4.  **Accept a renderer limitation temporarily:** if compensation would make Anima-created annotations inconsistent or difficult to reason about.

My current expectation -- explicitly an inference, not a conclusion -- is that option 3 may be the eventual practical answer. If PDFKit is the outlier, changing the stored annotation to satisfy PDFKit could make the already-correct non-Apple rendering worse. But Step 1B is what earns that conclusion.

## Small note on the other UX decisions

I have recorded these as decisions for our working discussion, without changing any project files:

-   True tabs are deferred; `open -n` is the accepted multi-document route for now.
-   The window caption will eventually carry document identity, mode state, and current-page information rather than requiring a status bar.
-   The caption should preserve a leading parenthesized author/year handle when the filename begins with one; otherwise it begins from the full filename.
-   Goto page and document search remain reader-first priorities after the color trust investigation.

We can return to the caption design later. It is a coherent small feature, but it is separate from this rendering question.

## Approval point

I recommend starting with **Step 1A only**: read-only inspection of the reference PDF's highlight annotation structure. No project source changes, no fixture edits, and no generated variant PDFs yet.

If you approve, I will propose the exact one-off terminal inspection command(s) and explain what each part prints before you run them.

User:
Ok, approach approved, let's start with Step 1A. Attached is the output of an extract utility, in an ndjson format I use in my pdf-annotations project.

Assistant:
Denkt nach

Good -- this NDJSON confirms the **high-level annotation contract** for the PDF-XChange-created reference highlights.

## What this output establishes

Across the six highlights shown:

-   **Stroke color:** `[1.0, 0.752942..., 0.796078...]`
    -   This is effectively Anima's current stored pink: `[1.0, 0.75, 0.80]`.
-   **Opacity:** `0.399993...`
    -   This is effectively Anima's current opacity: `0.4`.
-   **Annotation type:** standard PDF highlight (`[8, "Highlight"]`).
-   **Geometry:** standard highlight quad vertices.
-   **Comments and metadata:** normal `/Contents`, author/title, dates, subject, and `/NM`\-style IDs surfaced by fitz as `info["id"]`.

So the visual mismatch is especially clean:

> The reference PDF-XChange annotations use essentially the exact same high-level color and opacity values that Anima writes today. Yet PDF-XChange, Edge, and Chrome display them pale, while Preview and Anima display them saturated.

That means changing Anima's `HIGHLIGHT_COLOR` or `HIGHLIGHT_OPACITY` blindly would be a poor first response. It might make Anima look right while making its persisted annotations too faint in the non-Apple readers that currently render the reference PDF correctly.

## What this output cannot establish

Your extractor shows fitz's useful high-level annotation view, but it does **not** include the low-level PDF keys we need for Step 1A:

-   `/AP` -- annotation appearance dictionary;
-   `/AP /N` -- normal appearance stream;
-   `/Resources` and `/ExtGState` inside that stream;
-   `/BM` -- blend mode, possibly `Multiply`;
-   possibly any `/CA` opacity encoded in the appearance stream's graphics state.

That is not a defect in your extractor. Those are deliberately lower-level PDF object details, and this is exactly why we need one targeted raw-xref inspection.

## Step 1A -- inspect one annotation's raw PDF objects

Use the project venv Python so this runs under the same PyMuPDF version as Anima:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
import re
import fitz

pdf_path = "input.pdf"
target_uuid = "62ca6973-93f3-4935-88b2ca6254fa4c56"
doc = fitz.open(pdf_path)

for page in doc:    for annot in page.annots() or []:        if annot.info.get("id") != target_uuid:
            continue
        print(f"Page: {page.number}")
        print(f"Annotation xref: {annot.xref}")
        print("\n=== Annotation dictionary ===")
        print(doc.xref_object(annot.xref, compressed=False))
        for key in ("C", "CA", "BM", "AP"):
            print(f"\n/{key}: {doc.xref_get_key(annot.xref, key)}")
        ap_kind, ap_value = doc.xref_get_key(annot.xref, "AP")
        if ap_kind == "xref":
            ap_xref = int(re.match(r"(\d+)", ap_value).group(1))
            print(f"\n=== /AP dictionary (xref {ap_xref}) ===")
            print(doc.xref_object(ap_xref, compressed=False))
            normal_kind, normal_value = doc.xref_get_key(ap_xref, "N")
            if normal_kind == "xref":
                normal_xref = int(re.match(r"(\d+)", normal_value).group(1))
                print(f"\n=== /AP /N appearance stream dictionary (xref {normal_xref}) ===")
                print(doc.xref_object(normal_xref, compressed=False))
                print("\n=== /AP /N appearance stream content ===")
                print(doc.xref_stream(normal_xref).decode("latin-1"))
        doc.close()
        raise SystemExit

doc.close()
raise SystemExit(f"Could not find annotation UUID: {target_uuid}")
PY`

```

### Why this first target

`62ca6973-93f3-4935-88b2ca6254fa4c56` is the `Introduction--Definition` highlight with comment `H2`, on page 0. It is a simple single-quad highlight, so its raw structure should be easier to read than the multi-line examples.

### What to bring back

Please paste the terminal output, particularly:

1.  the annotation dictionary;
2.  the `/AP` result;
3.  the `/AP /N` appearance stream dictionary and contents, if they exist.

I will then inventory the keys rather than jumping to a fix. In particular, we will learn whether PDF-XChange supplied a custom normal appearance stream and whether it contains an ExtGState such as `/BM /Multiply`.

No source files or PDFs are changed by this command.

User:
scheme

```scheme
`Page: 0
Annotation xref: 16
=== Annotation dictionary ===
<<
  /C [ 1 .752942 .796079 ]  /F 4
  /M (D:20251021211946+02'00')
  /P 8 0 R  /T (fschuhi)
  /AP <<
    /N 40 0 R  >>
  /CA .399994
  /NM (62ca6973-93f3-4935-88b2ca6254fa4c56)
  /RC (<?xml version="1.0"?><body xmlns="http://www.w3.org/1999/xhtml" xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/" xfa:APIVersion="Acrobat:7.0.8" xfa:spec="2.0.2" style="font-size:12.0pt;text-align:left;color:#000000;font-weight:normal;font-style:normal;font-family:Arial;font-stretch:normal"><p><span style="font-family:Arial;font-size:8.0pt">H2</span></p></body>)
  /Rect [ 47.55296 232.09046 183.59346 242.80725 ]  /Subj (Highlight)
  /Popup 17 0 R  /Subtype /Highlight
  /Contents (H2)
  /QuadPoints [ 49.68 242.80725 181.46642 242.80725 49.68 232.09046
      181.46642 232.09046 ]  /CreationDate (D:20251021211943+02'00')
>>

/C: ('array', '[1 .752942 .796079]')
/CA: ('float', '.399994')
/BM: ('null', 'null')
/AP: ('dict', '<</N 40 0 R>>')`

```

Assistant:
Denkt nach

This is already a useful result.

## Step 1A inventory -- annotation dictionary

For the reference PDF-XChange highlight:

Key

Value

Function

`/Subtype /Highlight`

Standard highlight annotation

Identifies the annotation type.

`/C [1 .752942 .796079]`

Pink color

Matches Anima's current stored color almost exactly.

`/CA .399994`

Approximately 0.4 opacity

Matches Anima's current stored opacity almost exactly.

`/QuadPoints`

One four-corner quad

Defines the highlighted text geometry.

`/Rect`

Enclosing rectangle

Bounding box around the quad.

`/AP << /N 40 0 R >>`

Normal appearance stream at xref 40

This is the important low-level rendering object.

`/BM`

Absent at annotation level

The annotation itself does not declare a blend mode.

`/Contents`, `/RC`, `/Popup`

`H2` comment and related popup/rich-text metadata

Not relevant to highlight color compositing.

### Finding

The annotation-level evidence confirms the high-level color and opacity match Anima's current values, and it confirms that PDF-XChange supplies a custom normal appearance stream:

text

```text
`/AP << /N 40 0 R >>`

```

So the remaining rendering behavior is likely specified inside object **40**, not on the annotation dictionary itself.

The script stopped there because `/AP` is an inline dictionary (`'dict'`), rather than a direct xref reference. That is normal PDF structure -- `/N` inside the dictionary is the actual xref we need.

## Step 1A, continued -- inspect appearance stream xref 40

Please run this read-only command in the same directory as `input.pdf`:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
import fitz

pdf_path = "input.pdf"
appearance_xref = 40

doc = fitz.open(pdf_path)

print(f"=== Appearance stream dictionary (xref {appearance_xref}) ===")
print(doc.xref_object(appearance_xref, compressed=False))
for key in ("Resources", "BBox", "Matrix", "Group"):
    print(f"\n/{key}: {doc.xref_get_key(appearance_xref, key)}")
print("\n=== Appearance stream content ===")
print(doc.xref_stream(appearance_xref).decode("latin-1"))
doc.close()
PY`

```

## What we are looking for

The promising patterns would look approximately like this:

text

```text
`/Resources <<
  /ExtGState <<
    /GS0 <<
      /BM /Multiply
      /ca .399994
    >>
  >>
>>`

```

and then, in the stream content:

text

```text
`/GS0 gs`

```

Meaning:

-   the appearance stream defines a graphics state;
-   that graphics state requests a blend mode and/or opacity;
-   the drawing commands activate it before painting the highlight.

There are several possible structures, so do not worry if it does not look exactly like that. The key questions are:

1.  Does xref 40 have `/Resources`?
2.  Is there an `/ExtGState` dictionary?
3.  Does it contain `/BM /Multiply`, another blend mode, or none?
4.  Does the stream activate that state with a `gs` command?

Once we have that output, we can distinguish between:

-   **"PDF-XChange's appearance stream uses Multiply and Apple ignores/interprets it differently"**, and
-   **"the discrepancy comes from another detail of the appearance stream or PDFKit's highlight handling."**

Still no changes to Anima, the reference PDF, or the test fixture.

User:
Interesting.

scheme

```scheme
`=== Appearance stream dictionary (xref 40) ===
<<
  /BBox [ 47.55296 232.09046 183.59346 242.80725 ]  /Filter [ /FlateDecode ]
  /Length 24
  /Matrix [ 1 0 0 1 -47.55296 -232.09046 ]  /Subtype /Form
  /FormType 1
  /Resources <<
    /ProcSet [ /PDF ]
    /XObject <<
      /Fm0 53 0 R    >>
    /ExtGState <<
      /GS0 54 0 R    >>
  >>
>>

/Resources: ('dict', '<</ProcSet[/PDF]/XObject<</Fm0 53 0 R>>/ExtGState<</GS0 54 0 R>>>>')
/BBox: ('array', '[47.55296 232.09046 183.59346 242.80725]')
/Matrix: ('array', '[1 0 0 1 -47.55296 -232.09046]')
/Group: ('null', 'null')
=== Appearance stream content ===
/GS0 gs
/Fm0 Do`

```

Assistant:
Denkt nach

Yes -- this is the structure we were looking for. It has one extra level of indirection, but it is clean.

## What xref 40 tells us

The annotation's normal appearance stream does not paint the pink highlight directly. It does two things:

text

```text
`/GS0 gs
/Fm0 Do`

```

In PDF graphics terms:

1.  **`/GS0 gs`** activates a named extended graphics state.
2.  **`/Fm0 Do`** draws a nested form XObject.

And its resources resolve those names as:

text

```text
`/GS0 -> xref 54
/Fm0 -> xref 53`

```

So the appearance hierarchy is:

text

```text
`Highlight annotation (xref 16)
  -> /AP /N (xref 40)
       -> activate graphics state /GS0 (xref 54)
       -> draw form XObject /Fm0 (xref 53)`

```

## Why this is promising

The annotation itself has:

-   color `/C [1 .752942 .796079]`;
-   opacity `/CA .399994`;
-   no annotation-level `/BM`.

But PDF-XChange's custom appearance stream applies a graphics state _before_ drawing its actual highlight form. That state is exactly where a blend mode such as `/BM /Multiply` would normally live.

The actual painting path -- perhaps including a second graphics state -- may also be inside xref 53.

So we need to inspect **both xref 54 and xref 53** before drawing a conclusion.

## Step 1A, final read-only inspection

Run:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
import fitz

pdf_path = "input.pdf"
xrefs = [53, 54]

doc = fitz.open(pdf_path)

for xref in xrefs:    print(f"\n{'=' * 72}")
    print(f"=== Object dictionary (xref {xref}) ===")
    print(doc.xref_object(xref, compressed=False))
    for key in ("Type", "Subtype", "BM", "CA", "ca", "SMask", "Resources", "BBox", "Matrix", "Group"):
        print(f"/{key}: {doc.xref_get_key(xref, key)}")
    try:
        stream = doc.xref_stream(xref)
    except RuntimeError:
        stream = None

    if stream is not None:        print("\n=== Stream content ===")
        print(stream.decode("latin-1"))
    else:
        print("\n(No stream content -- this is a plain PDF dictionary object.)")
doc.close()
PY`

```

## What each object should answer

### xref 54 -- `GS0`

This is probably a plain `/ExtGState` dictionary. The decisive lines would be something like:

text

```text
`/Type /ExtGState
/BM /Multiply`

```

It may also contain opacity state, such as `/ca` or `/CA`.

### xref 53 -- `Fm0`

This is probably another Form XObject containing the actual path painting. Its stream may contain:

-   geometry construction commands;
-   fill or stroke operations;
-   another `gs` graphics-state activation;
-   possibly another nested resource dictionary.

## Current evidence, stated carefully

We can now say:

-   PDF-XChange has authored a custom appearance stream for the reference highlight.
-   The stream deliberately applies an extended graphics state before drawing the highlight form.
-   The annotation's color and opacity match Anima's current values.
-   Therefore, the remaining visual difference is very plausibly in PDF-XChange's appearance-stream mechanics and/or the rendering engines' interpretation of them.

We **cannot yet** say it is `/Multiply`, because xref 54 has not been inspected.

User:
scheme

```scheme
`=== Object dictionary (xref 53) ===
<<
  /BBox [ 47.55296 232.09046 183.59346 242.80725 ]  /Group <<
    /I false
    /K false
    /S /Transparency
  >>
  /Filter [ /FlateDecode ]
  /Length 24
  /Matrix [ 1 0 0 1 0 0 ]  /Subtype /Form
  /FormType 1
  /Resources <<
    /ProcSet [ /PDF ]
    /XObject <<
      /Fm0 72 0 R    >>
    /ExtGState <<
      /GS0 73 0 R    >>
  >>
>>
/Type: ('null', 'null')
/Subtype: ('name', '/Form')
/BM: ('null', 'null')
/CA: ('null', 'null')
/ca: ('null', 'null')
/SMask: ('null', 'null')
/Resources: ('dict', '<</ProcSet[/PDF]/XObject<</Fm0 72 0 R>>/ExtGState<</GS0 73 0 R>>>>')
/BBox: ('array', '[47.55296 232.09046 183.59346 242.80725]')
/Matrix: ('array', '[1 0 0 1 0 0]')
/Group: ('dict', '<</I false/K false/S/Transparency>>')
=== Stream content ===
/GS0 gs
/Fm0 Do

========================================================================
=== Object dictionary (xref 54) ===
<<
  /CA .399994
  /ca .399994
  /Type /ExtGState
>>
/Type: ('name', '/ExtGState')
/Subtype: ('null', 'null')
/BM: ('null', 'null')
/CA: ('float', '.399994')
/ca: ('float', '.399994')
/SMask: ('null', 'null')
/Resources: ('null', 'null')
/BBox: ('null', 'null')
/Matrix: ('null', 'null')
/Group: ('null', 'null')
(No stream content -- this is a plain PDF dictionary object.)`

```

Assistant:
Denkt nach

That is genuinely interesting -- and it corrects the initial `/BM /Multiply` hypothesis.

## Step 1A finding: no Multiply blend mode so far

The first graphics state, xref 54, is:

text

```text
`<<
  /CA .399994
  /ca .399994
  /Type /ExtGState
>>`

```

It sets only opacity:

-   `/CA` -- stroking alpha;
-   `/ca` -- non-stroking/fill alpha;
-   both approximately `0.4`.

There is **no `/BM` key**, so PDF-XChange is not applying `/Multiply` at this level.

That matters: the TODO hypothesis has not been confirmed. We should now regard it as a disproven candidate at the two outer levels inspected, unless the final nested graphics state contains one.

## What the appearance hierarchy now is

text

```text
`Annotation xref 16
  /C  [1 .752942 .796079]     pink
  /CA .399994                 40% annotation opacity
  /AP /N -> xref 40

xref 40: outer Form XObject
  /GS0 -> xref 54             applies 40% opacity
  /Fm0 -> xref 53             draws nested form

xref 53: transparency-group Form XObject
  /Group /S /Transparency     isolates/defines a transparency compositing group
  /GS0 -> xref 73             unknown yet
  /Fm0 -> xref 72             actual painted geometry unknown yet`

```

Both xref 40 and xref 53 contain the same small pattern:

text

```text
`/GS0 gs
/Fm0 Do`

```

So PDF-XChange has generated a layered chain of form XObjects, and xref 53 specifically declares a **transparency group**.

## Why the transparency group is now the main lead

A transparency group is not itself a blend mode. It specifies that the form's contents are composited as a grouped transparency operation rather than merely painted directly into the surrounding page graphics.

The relevant distinction is:

text

```text
`No blend mode:
  "how are colors combined?" -- likely Normal, unless a deeper state says otherwise.

Transparency group:
  "at what stage are this form's internal pieces composited with each other
   and with the page?"`

```

Different PDF engines can differ in their handling of nested transparency groups, alpha application, and markup-annotation appearance streams. This is now a more plausible source of the discrepancy than a visible `/BM /Multiply` at the levels inspected.

Also notice the potentially important duplication:

-   The annotation has `/CA .399994`.
-   The outer appearance graphics state xref 54 separately applies `/CA` and `/ca` at `.399994`.

That does **not** automatically mean opacity is applied twice. Renderers have rules about whether to render a markup annotation from its annotation properties, supplied appearance, or both. But it gives us a precise question: perhaps different engines treat the annotation opacity and appearance-stream opacity differently.

## What remains unknown

We still need xref 72 and xref 73:

-   **xref 73** should tell us whether the innermost graphics state sets the actual pink color and whether it contains a blend mode.
-   **xref 72** should show the real drawing commands: likely a filled path corresponding to the highlight shape.

At that point we can say whether PDF-XChange's visual appearance is:

1.  a straightforward pink shape at 40% alpha inside nested transparency forms;
2.  a shape with a final blend mode;
3.  something more unusual.

## Step 1A -- final nested-object inspection

Please run this final read-only command:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
import fitz

pdf_path = "input.pdf"
xrefs = [72, 73]

doc = fitz.open(pdf_path)

for xref in xrefs:    print(f"\n{'=' * 72}")
    print(f"=== Object dictionary (xref {xref}) ===")
    print(doc.xref_object(xref, compressed=False))
    for key in ("Type", "Subtype", "BM", "CA", "ca", "C", "Resources", "BBox", "Matrix", "Group"):
        print(f"/{key}: {doc.xref_get_key(xref, key)}")
    try:
        stream = doc.xref_stream(xref)
    except RuntimeError:
        stream = None

    if stream is not None:        print("\n=== Stream content ===")
        print(stream.decode("latin-1"))
    else:
        print("\n(No stream content -- this is a plain PDF dictionary object.)")
doc.close()
PY`

```

### What I expect, but have not assumed

-   xref 73 may contain an RGB color-setting equivalent and perhaps another alpha value.
-   xref 72 may be the actual form whose stream fills the highlight quad.
-   If neither object contains `/BM`, we can conclude that the sample's custom appearance uses **normal alpha compositing within nested transparency groups**, not Multiply.

Then Step 1A will be complete: we will have an actual PDF-object-level description of what the known-good PDF-XChange output contains, before making any experimental variants.

User:
scheme

```scheme
`=== Object dictionary (xref 72) ===
<<
  /BBox [ 47.55296 232.09046 183.59346 242.80725 ]  /Group <<
    /I false
    /K false
    /S /Transparency
  >>
  /Filter [ /FlateDecode ]
  /Length 92
  /Matrix [ 1 0 0 1 0 0 ]  /Subtype /Form
  /FormType 1
  /Resources <<
    /ProcSet [ /PDF ]
  >>
>>
/Type: ('null', 'null')
/Subtype: ('name', '/Form')
/BM: ('null', 'null')
/CA: ('null', 'null')
/ca: ('null', 'null')
/C: ('null', 'null')
/Resources: ('dict', '<</ProcSet[/PDF]>>')
/BBox: ('array', '[47.55296 232.09046 183.59346 242.80725]')
/Matrix: ('array', '[1 0 0 1 0 0]')
/Group: ('dict', '<</I false/K false/S/Transparency>>')
=== Stream content ===
1 0.753 0.796 rg
49.68 242.807 m
46.721 239.848 46.721 235.05 49.68 232.09 c
181.466 232.09 l
184.426 235.05 184.426 239.848 181.466 242.807 c
f


========================================================================
=== Object dictionary (xref 73) ===
<<
  /BM /Multiply
  /Type /ExtGState
>>
/Type: ('name', '/ExtGState')
/Subtype: ('null', 'null')
/BM: ('name', '/Multiply')
/CA: ('null', 'null')
/ca: ('null', 'null')
/C: ('null', 'null')
/Resources: ('null', 'null')
/BBox: ('null', 'null')
/Matrix: ('null', 'null')
/Group: ('null', 'null')
(No stream content -- this is a plain PDF dictionary object.)`

```

Assistant:
Denkt nach

Step 1A is now complete, and the original hypothesis is confirmed -- with an important qualification about **where** the blend mode lives.

## Complete appearance inventory

For the PDF-XChange-authored `H2` highlight:

text

```text
`Annotation xref 16
  /C  [1 .752942 .796079]          pink
  /CA .399994                      annotation opacity
  /AP /N -> xref 40                normal appearance

xref 40: outer appearance Form
  activates /GS0 -> xref 54        alpha .399994
  draws /Fm0 -> xref 53

xref 53: transparency-group Form
  activates /GS0 -> xref 73        /BM /Multiply
  draws /Fm0 -> xref 72

xref 72: inner transparency-group Form
  sets fill color: 1 0.753 0.796 rg
  paints the rounded highlight shape

xref 73: ExtGState
  /BM /Multiply`

```

So the effective appearance pipeline is:

text

```text
`pink filled rounded shape
  -> Multiply blend mode
  -> 40% alpha graphics state
  -> custom normal appearance stream
  -> highlight annotation with /CA .399994`

```

## What we now know

### Confirmed findings

1.  **The PDF-XChange reference highlight has `/BM /Multiply`.**
    It is not at the annotation level; it is in the nested appearance stream's graphics state, xref 73.

2.  **The reference PDF uses the same basic pink and opacity that Anima writes.**
    The high-level values are effectively identical:

    -   color: approximately `[1.0, 0.753, 0.796]`
    -   opacity: approximately `0.4`
3.  **PDF-XChange gives the highlight a custom, nested appearance stream.**
    The actual visible highlight is a rounded pink filled shape inside two Form XObjects, both marked as transparency groups.

4.  **The PDF-XChange appearance stream carries opacity in two places.**

    -   Annotation dictionary: `/CA .399994`
    -   Outer appearance graphics state, xref 54: `/CA .399994` and `/ca .399994`
5.  **The actual pink fill is only set inside the inner form.**
    The command is:

    pdf

    ```text
    `1 0.753 0.796 rg`

    ```

    followed by a rounded-path fill.


### Correction to the earlier framing

The issue is now not merely "PDFKit is an outlier in highlight rendering." More precisely:

> The readers differ in how they render a PDF-XChange custom highlight appearance that combines nested transparency groups, `/Multiply`, and opacity declared both on the annotation and in the appearance stream.

That is a much stronger basis for an experiment.

## One subtle but important point

`/Multiply` over a pure white page background should not dramatically change the pink background by itself: multiplying any color by white yields that same color.

It matters more where the highlight overlaps non-white content -- especially black text. With Multiply, black text remains black rather than being washed toward pink/gray by a simple normal alpha overlay.

Therefore, if the screenshots show a substantial difference in the pink _background_ on white areas, `/Multiply` alone may not explain it. The duplicated opacity is now an equally strong suspect:

text

```text
`annotation /CA = 0.4
appearance graphics-state alpha = 0.4`

```

A renderer that effectively applies both could yield an approximate effective alpha of:

text

```text
`0.4 * 0.4 = 0.16`

```

That would look far paler than a renderer that applies only one of the two 0.4 opacity declarations.

This is an inference from the PDF structure and screenshots, not yet a demonstrated conclusion. But it gives us a much better experiment than "remove Multiply and see."

* * *

# Step 1B -- controlled variants

We should create copies only under `tmp/`, leaving the attached/reference `input.pdf` untouched.

I see two credible approaches.

## Approach A -- one-variable-at-a-time matrix

Create four variants from a copy of `input.pdf`, all modifying only the selected highlight's appearance machinery:

Variant

Change

What it isolates

`control.pdf`

Exact copy

Baseline.

`no-multiply.pdf`

Remove `/BM /Multiply` from xref 73

Whether blend mode explains visible differences.

`annotation-alpha-only.pdf`

Remove the alpha values from appearance graphics state xref 54; retain annotation `/CA`

Whether renderers differ because one uses annotation opacity and another uses both.

`appearance-alpha-only.pdf`

Remove annotation `/CA`; retain xref 54 alpha

The converse opacity path.

This is the most informative approach. We would compare the same `H2` highlight in Preview, Anima, and one trusted non-Apple renderer.

**Pros**

-   Separates blend mode from the two alpha mechanisms.
-   Directly tests the strongest hypotheses.
-   Leaves the reference source untouched.

**Cons**

-   Four files and several viewer comparisons.
-   The experiment will be a little more hands-on.

## Approach B -- start with the opacity question

Create only:

1.  `control.pdf`
2.  `annotation-alpha-only.pdf`
3.  `appearance-alpha-only.pdf`

Then postpone `/Multiply` until the alpha behavior is clear.

**Pros**

-   Targets the likely explanation for the pale-versus-saturated _background_ difference.
-   Easier comparison set.

**Cons**

-   Leaves a known meaningful factor untested.
-   Could mean another iteration immediately afterward.

## My recommendation

**Approach A.**

It is still small and controlled, and it should settle the basic mechanics in one pass. It also avoids the familiar trial-and-error trap: rather than changing Anima's color values repeatedly, we inspect exactly how each renderer responds to each PDF feature.

## Important experimental constraint

These variants should be treated as **rendering specimens**, not valid models for what Anima should ultimately write. Removing `/CA` from an annotation or alpha from an appearance stream can make the PDF structurally unlike ordinary authoring output. That is fine: Step 1B asks how the renderers interpret each layer, not yet what the correct production PDF should be.

If you approve **Approach A**, I will propose a small one-off Python command that:

-   copies `input.pdf` into `tmp/color-rendering-experiment/`;
-   makes the four variants;
-   verifies the exact changed keys afterward;
-   does not touch Anima source, tests, or your original PDF.

Then you can view those four specimens in Preview, Anima, and preferably Chrome or PDF-XChange Viewer.

User:
Excellent, let's do that (Approach A).

Do you think it's helpful to also add a highlight to the baseline pdf which was generated by Anima? I've attached an example, based on the `input.pdf`. Note that _both_ in Anima _and_ PDF-Xchange-Viewer _all_ highlights (including the newly added one) are displayed in the same color: saturated in Anima, light pink in PDF-Xchange-Viewer.

Assistant:
Denkt nach

**Yes -- it is highly helpful, and it changes the priority of the next experiment.**

Your observation is stronger than the original PDF-XChange-only reference:

> In both Anima and PDF-XChange Viewer, all highlights -- including the one newly written by Anima -- have the same renderer-specific appearance: saturated in Anima, pale in PDF-XChange Viewer.

## What that establishes

This means the difference is **not dependent on who authored the annotation**.

We now have two annotation sources:

1.  PDF-XChange-created highlights with a complex custom appearance stream, nested transparency groups, alpha, and `/BM /Multiply`.
2.  Anima-created highlight, written by fitz.

Yet each viewer renders both sources consistently in its own style:

Renderer

PDF-XChange-authored highlight

Anima-authored highlight

PDF-XChange Viewer

Light pink

Light pink

Anima / PDFKit

Saturated pink

Saturated pink

That strongly suggests these viewers are either:

-   ignoring supplied highlight appearance streams altogether and rendering markup annotations from high-level fields such as `/C`, `/CA`, and `/QuadPoints`; or
-   normalizing both source formats into their own internal highlight drawing behavior.

Either way, the PDF-XChange custom appearance stream remains interesting forensic evidence, but it may **not** be the causal lever for the visual difference we care about.

So I recommend a small course correction:

> Before generating the four variants from Approach A, inspect the Anima-created highlight's raw structure and compare it with the PDF-XChange one.

If its `/AP` structure is much simpler, absent, or fitz-generated -- which is likely -- but the two viewers still render it identically to their respective styles, then altering the PDF-XChange `/AP` hierarchy is unlikely to fix Anima's appearance. We would avoid spending time on an experiment whose likely result is "the renderers did not care."

## Revised next step: Step 1A.5 -- compare the Anima-authored annotation

The local ownership is still the PDF format/rendering boundary:

text

```text
`PDF-XChange-created annotation structure
                 \
                  -> PDF-XChange Viewer / PDFKit rendering behavior
                 /
Anima-created annotation structure`

```

No Anima source change, fixture mutation, or variant generation yet.

### What we need to inspect

For the newly added Anima highlight:

-   `/C`
-   `/CA`
-   `/QuadPoints`
-   `/AP`
-   if present, the appearance stream's resources, alpha, transparency groups, and blend mode.

### One detail needed from you

Please give me either:

1.  the UUID of the newly Anima-created highlight; or
2.  its highlighted text, ideally distinctive enough to identify it.

Then I will give you one small read-only command targeted precisely at that annotation.

If you do not have the UUID handy, the alternative is a short listing command that prints every page-0 highlight's UUID, comment, extracted text, and `/AP` value, letting you identify it without manually inspecting xrefs.

## Likely decision point afterward

If the Anima-created highlight lacks PDF-XChange's elaborate appearance stream, but the two applications still each render it in their same renderer-specific colors, then the next investigation should shift from PDF appearance streams to **the visible high-level annotation color under each renderer's compositing behavior**.

At that point, the practical product question becomes:

> What stored pink and opacity should Anima write so that its own PDFKit display is trustworthy, while PDF-XChange/browser display remains acceptable?

That may lead to a carefully chosen **Anima-specific stored color compensation**, but we should not decide it until this comparison tells us whether appearance streams are irrelevant.

User:
The highlighted text is

> His Holiness the Dalai Lama

I've run the extract utility on the new file, here is the new highlight:

json

```json
`{"colors": {"stroke": [1.0, 0.75, 0.800000011920929], "fill": []}, "info": {"content": "added with Anima", "name": "", "title": "fschuhi", "creationDate": "D:20260713091022+00'00'", "modDate": "D:20260713091035+00'00'", "subject": "Highlight", "id": "16b93454-0ff5-42da-9ca0-dae206297342", "extractedText": "His Holiness the Dalai Lama"}, "pageNum": 0, "annotType": [8, "Highlight"], "vertices": [[64.08000183105469, 625.4876708984375], [212.8656005859375, 625.4876708984375], [64.08000183105469, 638.771728515625], [212.8656005859375, 638.771728515625]], "topLeft": [60.948814392089844, 624.6574096679688], "botRight": [215.9967803955078, 639.6019897460938], "border": {}, "lineEnds": null, "opacity": 0.4000000059604645}`

```

Assistant:
Yes -- that confirms the Anima-created highlight has the same relevant high-level properties as the PDF-XChange highlights:

-   Pink: `[1.0, 0.75, 0.80]`
-   Opacity: `0.4`
-   Standard `/Highlight` annotation
-   Standard quad geometry
-   Normal comment/author/UUID metadata

The target UUID is:

text

```text
`16b93454-0ff5-42da-9ca0-dae206297342`

```

The remaining question is whether fitz generated an `/AP` appearance stream, and if so, whether it resembles PDF-XChange's nested transparency + Multiply construction.

## Step 1A.5 -- inspect the Anima-authored annotation

Run this read-only command from the directory containing `input-with-anima-highlight.pdf`:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
import fitz

pdf_path = "input-with-anima-highlight.pdf"
target_uuid = "16b93454-0ff5-42da-9ca0-dae206297342"
doc = fitz.open(pdf_path)

for page in doc:    for annot in page.annots() or []:        if annot.info.get("id") != target_uuid:
            continue
        print(f"Page: {page.number}")
        print(f"Annotation xref: {annot.xref}")
        print("\n=== Annotation dictionary ===")
        print(doc.xref_object(annot.xref, compressed=False))
        for key in ("C", "CA", "BM", "AP"):
            print(f"\n/{key}: {doc.xref_get_key(annot.xref, key)}")
        ap_kind, ap_value = doc.xref_get_key(annot.xref, "AP")
        if ap_kind == "dict":
            print("\n=== Inline /AP dictionary ===")
            print(ap_value)
        doc.close()
        raise SystemExit

doc.close()
raise SystemExit(f"Could not find annotation UUID: {target_uuid}")
PY`

```

Please paste that output first.

### What would be most informative

There are two likely outcomes:

1.  **No `/AP` appearance stream**, or an `/AP` that is materially simpler than PDF-XChange's.
    This would strongly support your visual observation: PDFKit and PDF-XChange Viewer are applying their own renderer-specific markup appearance from `/C`, `/CA`, and `/QuadPoints`, rather than faithfully using the detailed PDF-XChange appearance stream.

2.  **Anima has a fitz-generated appearance stream too**, perhaps with a different structure.
    Then we inspect it before deciding whether the existing appearance-stream variants are worthwhile.


Either way, this comparison is now more valuable than starting the four-file variant matrix immediately.

User:
scheme

```scheme
`=== Annotation dictionary ===
<<
  /C [ 1 .75 .8 ]  /F 4
  /M (D:20260713091035+00'00')
  /P 8 0 R  /T (fschuhi)
  /AP <<
    /N 46 0 R  >>
  /BM /Multiply
  /CA .4
  /NM (16b93454-0ff5-42da-9ca0-dae206297342)
  /Rect [ 60.948816 202.39801 215.99678 217.34259 ]  /Subj (Highlight)
  /Type /Annot
  /Popup 23 0 R  /Subtype /Highlight
  /Contents (added with Anima)  /QuadPoints [ 64.08 216.51233 212.8656 216.51233 64.08 203.22827
      212.8656 203.22827 ]  /CreationDate (D:20260713091022+00'00')
>>

/C: ('array', '[1 .75 .8]')
/CA: ('float', '.4')
/BM: ('name', '/Multiply')
/AP: ('dict', '<</N 46 0 R>>')
=== Inline /AP dictionary ===
<</N 46 0 R>>`

```

Assistant:
Denkt nach

That is a valuable correction to our model.

## Comparison finding

The Anima-created highlight is **not** a bare `/C` + `/CA` + `/QuadPoints` annotation. After fitz creates and updates it, it also has:

pdf

```text
`/AP << /N 46 0 R >>
/BM /Multiply
/CA .4`

```

So both authoring paths use a custom normal appearance and Multiply, but they place the blend-mode information differently:

Feature

PDF-XChange-created highlight

Anima / fitz-created highlight

`/C` pink

Yes

Yes

`/CA` 0.4

Yes

Yes

`/AP /N`

Yes, xref 40

Yes, xref 46

`/BM /Multiply`

Nested appearance graphics state (xref 73)

Annotation dictionary itself

Nested transparency forms

Yes

Unknown until xref 46 is inspected

This resolves one earlier uncertainty: **Anima already writes `/BM /Multiply`**. That was not explicit in `anima_helper.py`, so it is apparently generated by fitz as part of `annot.update()`.

## What your visual observation now means

Since both types of highlights render:

-   pale in PDF-XChange Viewer;
-   saturated in Anima/PDFKit;

the most likely explanation is no longer simply "PDFKit ignores the PDF-XChange appearance stream."

Instead, the renderers appear to arrive at their own consistent presentation despite the two different but related PDF encodings. The meaningful shared inputs are:

text

```text
`Highlight annotation
pink /C
0.4 /CA
Multiply blend mode
normal appearance stream`

```

That still leaves two possibilities:

1.  Both engines honor the relevant PDF features, but their transparency/compositing implementations differ.
2.  Each engine normalizes markup annotations enough that the detailed appearance differences do not dominate the result.

Either way, this reinforces the product-level concern: altering just the PDF-XChange appearance stream is unlikely to solve Anima's rendering.

## One important codebase finding

The comments in `AnnotationManager.swift` and `tools/anima_helper.py` currently describe the stored appearance in terms of color and opacity, but the actual PDF contract is slightly richer:

text

```text
`fitz's annot.update() also writes /BM /Multiply and a normal appearance stream.`

```

That is not a bug or a change request yet. It is useful architecture knowledge for later, because it means `annot.update()` has renderer-visible side effects beyond the properties Anima sets directly.

## Step 1A.5, continued: inspect fitz's normal appearance

We should inspect xref 46 before deciding whether to create the four variants. This will tell us whether fitz's generated appearance is structurally simple or whether it uses a transparency-group structure close to PDF-XChange's.

Please run this read-only command:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
import fitz

pdf_path = "input-with-anima-highlight.pdf"
appearance_xref = 46

doc = fitz.open(pdf_path)

print(f"=== Appearance stream dictionary (xref {appearance_xref}) ===")
print(doc.xref_object(appearance_xref, compressed=False))
for key in ("Resources", "BBox", "Matrix", "Group"):
    print(f"\n/{key}: {doc.xref_get_key(appearance_xref, key)}")
print("\n=== Appearance stream content ===")
print(doc.xref_stream(appearance_xref).decode("latin-1"))
doc.close()
PY`

```

### What this decides

-   If xref 46 is structurally close to PDF-XChange's appearance, we can proceed with the original **Approach A** matrix using the Anima-created highlight as the specimen. That is preferable because it is the actual production output we may eventually change.
-   If it is much simpler, we will know the renderer-specific result survives a substantial appearance difference, and should narrow the experiment toward `/C`, `/CA`, and `/BM` rather than nested form mechanics.

Still read-only: no source files, no test files, and no PDFs are altered.

User:
apache

```apache
`=== Appearance stream dictionary (xref 46) ===
<<
  /BBox [ 60.948816 202.39801 215.99678 217.34259 ]  /Type /XObject  /Filter [ /FlateDecode ]  /Length 114  /Matrix [ 1 0 0 1 0 0 ]  /Subtype /Form  /Resources <<    /ExtGState <<      /H <<        /BM /Multiply        /CA .4        /ca .4      >>
    >>
  >>
>>

/Resources: ('dict', '<</ExtGState<</H<</BM/Multiply/CA .4/ca .4>>>>>>')
/BBox: ('array', '[60.948816 202.39801 215.99678 217.34259]')
/Matrix: ('array', '[1 0 0 1 0 0]')
/Group: ('null', 'null')
=== Appearance stream content ===
q
/H gs
/H gs
1 .75 .8 rg
64.08 203.22827 m
60.948816 206.35945 60.948816 213.38115 64.08 216.51233 c
212.8656 216.51233 l
215.99678 213.38115 215.99678 206.35945 212.8656 203.22827 c
f
Q`

```

Assistant:
This gives us a much clearer picture. The two producers are structurally different, but they share the rendering ingredients that matter.

## Side-by-side appearance comparison

Aspect

PDF-XChange Viewer output

Anima / fitz output

Annotation `/C`

Pink, about `[1, .753, .796]`

Pink `[1, .75, .8]`

Annotation `/CA`

About `.4`

`.4`

Annotation `/BM`

Not on annotation; nested in its appearance

`/Multiply` directly on annotation

Normal appearance

Nested forms and transparency groups

One Form XObject

Appearance alpha

Outer ExtGState has `/CA` and `/ca` `.4`

`/H` ExtGState has `/CA` and `/ca` `.4`

Appearance blend mode

Nested ExtGState `/BM /Multiply`

`/H` ExtGState `/BM /Multiply`

Appearance fill

Pink fill path

Pink fill path

Extra form transparency groups

Yes

No

The fitz appearance stream is much simpler:

pdf

```text
`q
/H gs
/H gs
1 .75 .8 rg
... rounded highlight path ...
f
Q`

```

The doubled `/H gs` invocation looks redundant, but it is not the important difference here: applying the same graphics state twice should not double the alpha. It just activates the same state twice.

## Key conclusion

Your real-world observation now has a solid structural explanation behind it:

-   Anima and PDF-XChange highlights both have a pink color, 0.4 opacity, Multiply, and a generated appearance stream.
-   Yet PDF-XChange Viewer renders both pale and Anima/PDFKit renders both saturated.
-   Therefore, **the viewer engine is the dominant factor**, not the annotation author or the complexity of one producer's appearance stream.

That does not prove which exact compositing rule differs. But it does tell us that a PDF-XChange-only appearance-stream experiment is unlikely to yield the product fix.

## Revised Approach A -- use the Anima-created highlight as the specimen

I recommend keeping the original four-variant matrix, but apply it to the existing Anima-created highlight in a copy of `input-with-anima-highlight.pdf`.

That is better than using the PDF-XChange `H2` specimen because:

-   it is Anima's actual output format;
-   it is small and easy to inspect;
-   a successful result could directly inform how `anima_helper.py` should change;
-   all other existing annotations remain present as visual controls.

The variants would be:

File

Exact mutation to Anima highlight UUID `16b93454-0ff5-42da-9ca0-dae206297342`

Purpose

`control.pdf`

None

Baseline.

`no-multiply.pdf`

Remove `/BM` from both the annotation and the `/H` appearance state.

Tests whether PDFKit's saturation is primarily connected to Multiply.

`annotation-alpha-only.pdf`

Remove `/CA` and `/ca` from the appearance-state `/H`; retain annotation `/CA .4`.

Tests annotation-level opacity alone.

`appearance-alpha-only.pdf`

Remove annotation `/CA`; retain appearance-state `/CA` and `/ca` `.4`.

Tests appearance-stream opacity alone.

Removing a key by setting it to PDF `null` is the intended PyMuPDF low-level mechanism; on your PyMuPDF generation it physically removes the key. ([pymupdf.readthedocs.io](https://pymupdf.readthedocs.io/en/latest/document.html?utm_source=openai))

### Why remove Multiply in both places?

For the Anima annotation, Multiply is duplicated:

text

```text
`annotation /BM /Multiply
appearance /Resources /ExtGState /H /BM /Multiply`

```

Removing it from just one location would leave a partial Multiply signal and make the result harder to interpret. The `no-multiply` specimen should mean precisely: same geometry, color, and alpha, but no requested blend mode anywhere on that annotation's rendering path.

### Expected decisive outcomes

What you see

What it suggests

`no-multiply.pdf` becomes light in Anima while still acceptable in PDF-XChange/Chrome

Removing Multiply may be a viable production fix.

`annotation-alpha-only.pdf` is saturated in Anima, but `appearance-alpha-only.pdf` is light

PDFKit privileges annotation `/CA` differently from appearance alpha.

`appearance-alpha-only.pdf` is saturated, but `annotation-alpha-only.pdf` is light

The converse.

All three variants remain saturated in Anima

The difference is likely PDFKit's basic markup rendering, not these explicit PDF controls. Then stored-color compensation becomes the most realistic path.

A variant is pale in Anima but too faint in PDF-XChange/Chrome

A single universal PDF encoding may not satisfy both engines; we would consider Anima display-only compensation instead.

## One methodological detail

The files should be saved as independent copies, not incremental updates, under:

text

```text
`tmp/color-rendering-experiment/`

```

That keeps the source PDF untouched and prevents an experiment from accumulating mutations onto a previous variant. Each variant begins from the same baseline.

## Approval check

You previously approved Approach A, but we have now refined its specimen and exact mutations based on the inspection. Please confirm this revised version:

> Create four disposable variants of `input-with-anima-highlight.pdf` under `tmp/color-rendering-experiment/`, applying the exact mutations listed above to only Anima's `His Holiness the Dalai Lama` highlight.

If you confirm, I will provide one one-off command that creates and verifies all four PDFs, followed by a compact viewing checklist.

User:
Great, got it. My gut feeling says that stored-color compensation is what we will have to do, but let's first see what the 4 files say. Yes, please go ahead.

Assistant:
Denkt nach

Great. This creates the four disposable specimens under `tmp/color-rendering-experiment/`, using the Anima-created `His Holiness the Dalai Lama` highlight only. It does not modify either source PDF or any project source/test file.

Run from the directory containing `input-with-anima-highlight.pdf`:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
from pathlib import Path
import shutil

import fitz

SOURCE_PDF = Path("input-with-anima-highlight.pdf")
OUTPUT_DIR = Path("tmp/color-rendering-experiment")
TARGET_UUID = "16b93454-0ff5-42da-9ca0-dae206297342"

def find_annotation(doc: fitz.Document, target_uuid: str):
    for page in doc:        for annot in page.annots() or []:            if annot.info.get("id") == target_uuid:
                return annot    raise RuntimeError(f"Could not find target annotation UUID: {target_uuid}")

def appearance_xref(doc: fitz.Document, annot: fitz.Annot) -> int:
    ap_kind, ap_value = doc.xref_get_key(annot.xref, "AP")
    if ap_kind != "dict":
        raise RuntimeError(f"Expected inline /AP dictionary, got: {(ap_kind, ap_value)}")
    # The target annotation's /AP is: <</N 46 0 R>>
    parts = ap_value.replace("<", " ").replace(">", " ").split()
    try:
        n_index = parts.index("/N")
        return int(parts[n_index + 1])    except (ValueError, IndexError) as error:
        raise RuntimeError(f"Could not resolve /AP /N from: {ap_value}") from error

def replace_appearance_stream(doc: fitz.Document, stream_xref: int, use_appearance_alpha: bool):
    original = doc.xref_stream(stream_xref).decode("latin-1")
    # fitz's original appearance is:
    #
    # q
    # /H gs
    # /H gs
    # 1 .75 .8 rg
    # ...
    # f
    #
    # For the annotation-alpha-only variant, remove both graphics-state
    # activations so that only the annotation-level /CA controls opacity.
    if use_appearance_alpha:        replacement = original
    else:
        replacement = original.replace("/H gs\n", "")
    if replacement == original and not use_appearance_alpha:        raise RuntimeError(
            "Expected to remove /H gs from the appearance stream, but found none."
        )

    doc.update_stream(stream_xref, replacement.encode("latin-1"))

def make_variant(
    destination: Path,
    *,
    remove_multiply: bool,
    keep_annotation_alpha: bool,
    keep_appearance_alpha: bool,
):
    shutil.copy2(SOURCE_PDF, destination)

    doc = fitz.open(destination)
    annot = find_annotation(doc, TARGET_UUID)
    ap_xref = appearance_xref(doc, annot)

    # Annotation-level controls.
    if remove_multiply:        doc.xref_set_key(annot.xref, "BM", "null")
    if not keep_annotation_alpha:        doc.xref_set_key(annot.xref, "CA", "null")
    # Appearance-stream controls.
    replace_appearance_stream(
        doc,
        ap_xref,
        use_appearance_alpha=keep_appearance_alpha,
    )

    # The appearance stream's /H resource may remain in the PDF even when
    # unused. That is harmless: the stream no longer activates it.
    doc.save(destination.with_suffix(".rewritten.pdf"), garbage=4, deflate=True)
    doc.close()

    destination.unlink()
    destination.with_suffix(".rewritten.pdf").rename(destination)

def inspect_variant(pdf_path: Path):
    doc = fitz.open(pdf_path)
    annot = find_annotation(doc, TARGET_UUID)
    ap_xref = appearance_xref(doc, annot)

    print(f"\n=== {pdf_path.name} ===")
    print(f"Annotation /BM: {doc.xref_get_key(annot.xref, 'BM')}")
    print(f"Annotation /CA: {doc.xref_get_key(annot.xref, 'CA')}")
    print(f"Appearance xref: {ap_xref}")
    print("Appearance stream:")
    print(doc.xref_stream(ap_xref).decode("latin-1").rstrip())
    doc.close()

if not SOURCE_PDF.exists():    raise SystemExit(f"Source PDF not found: {SOURCE_PDF.resolve()}")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

variants = [
    (
        "control.pdf",
        dict(
            remove_multiply=False,
            keep_annotation_alpha=True,
            keep_appearance_alpha=True,
        ),
    ),
    (
        "no-multiply.pdf",
        dict(
            remove_multiply=True,
            keep_annotation_alpha=True,
            keep_appearance_alpha=True,
        ),
    ),
    (
        "annotation-alpha-only.pdf",
        dict(
            remove_multiply=False,
            keep_annotation_alpha=True,
            keep_appearance_alpha=False,
        ),
    ),
    (
        "appearance-alpha-only.pdf",
        dict(
            remove_multiply=False,
            keep_annotation_alpha=False,
            keep_appearance_alpha=True,
        ),
    ),
]

for filename, options in variants:    destination = OUTPUT_DIR / filename

    if filename == "control.pdf":
        shutil.copy2(SOURCE_PDF, destination)
    else:
        make_variant(destination, **options)

for filename, _ in variants:    inspect_variant(OUTPUT_DIR / filename)

print(f"\nCreated specimens in: {OUTPUT_DIR.resolve()}")
PY`

```

## Expected verification summary

The terminal output should show:

Specimen

Annotation `/BM`

Annotation `/CA`

Appearance stream

`control.pdf`

`/Multiply`

`.4`

contains two `/H gs` lines

`no-multiply.pdf`

`null`

`.4`

still contains two `/H gs` lines

`annotation-alpha-only.pdf`

`/Multiply`

`.4`

contains no `/H gs` lines

`appearance-alpha-only.pdf`

`/Multiply`

`null`

contains two `/H gs` lines

A detail worth retaining: `no-multiply.pdf` leaves `/BM /Multiply` in the unused `/H` resource dictionary, but because the appearance stream still uses `/H gs`, this specimen as written would still activate it. I need to correct that before you run it.

Use this revised `replace_appearance_stream` function instead of the one above:

python

Alle anzeigen

```python
`def replace_appearance_stream(
    doc: fitz.Document,    stream_xref: int,    *,    use_appearance_alpha: bool,    use_multiply: bool,
):
    original = doc.xref_stream(stream_xref).decode("latin-1")
    if use_appearance_alpha and use_multiply:        replacement = original    elif use_appearance_alpha and not use_multiply:        replacement = original.replace("/H gs\n/H gs\n", "")    elif not use_appearance_alpha:        replacement = original.replace("/H gs\n", "")    else:        raise RuntimeError("Unsupported appearance variant.")
    doc.update_stream(stream_xref, replacement.encode("latin-1"))`

```

Ausführen

And change the call inside `make_variant` to:

python

```python
`replace_appearance_stream(
    doc,
    ap_xref,
    use_appearance_alpha=keep_appearance_alpha,
    use_multiply=not remove_multiply,
)`

```

Ausführen

Actually, I should not leave you with a two-part correction. **Use this complete corrected command instead**:

bash

```bash
`. .venv/bin/activate
python - <<'PY'
from pathlib import Path
import shutil

import fitz

SOURCE_PDF = Path("input-with-anima-highlight.pdf")
OUTPUT_DIR = Path("tmp/color-rendering-experiment")
TARGET_UUID = "16b93454-0ff5-42da-9ca0-dae206297342"

def find_annotation(doc: fitz.Document, target_uuid: str):
    for page in doc:        for annot in page.annots() or []:            if annot.info.get("id") == target_uuid:
                return annot    raise RuntimeError(f"Could not find target annotation UUID: {target_uuid}")

def appearance_xref(doc: fitz.Document, annot: fitz.Annot) -> int:
    ap_kind, ap_value = doc.xref_get_key(annot.xref, "AP")
    if ap_kind != "dict":
        raise RuntimeError(f"Expected inline /AP dictionary, got: {(ap_kind, ap_value)}")
    parts = ap_value.replace("<", " ").replace(">", " ").split()
    try:
        n_index = parts.index("/N")
        return int(parts[n_index + 1])    except (ValueError, IndexError) as error:
        raise RuntimeError(f"Could not resolve /AP /N from: {ap_value}") from error

def replace_appearance_stream(
    doc: fitz.Document,
    stream_xref: int,
    *,
    use_appearance_alpha: bool,
    use_multiply: bool,
):
    original = doc.xref_stream(stream_xref).decode("latin-1")
    if use_appearance_alpha and use_multiply:        replacement = original
    elif use_appearance_alpha and not use_multiply:        # Remove the /H graphics-state calls. This removes both its
        # appearance alpha and its /Multiply blend mode.
        replacement = original.replace("/H gs\n/H gs\n", "")
    elif not use_appearance_alpha:        # Remove both graphics-state calls. This leaves only annotation /CA.
        replacement = original.replace("/H gs\n", "")
    else:
        raise RuntimeError("Unsupported appearance variant.")
    if replacement == original and (not use_appearance_alpha or not use_multiply):        raise RuntimeError("Expected appearance stream mutation did not occur.")
    doc.update_stream(stream_xref, replacement.encode("latin-1"))

def make_variant(
    destination: Path,
    *,
    remove_multiply: bool,
    keep_annotation_alpha: bool,
    keep_appearance_alpha: bool,
):
    shutil.copy2(SOURCE_PDF, destination)

    doc = fitz.open(destination)
    annot = find_annotation(doc, TARGET_UUID)
    ap_xref = appearance_xref(doc, annot)

    if remove_multiply:        doc.xref_set_key(annot.xref, "BM", "null")
    if not keep_annotation_alpha:        doc.xref_set_key(annot.xref, "CA", "null")
    replace_appearance_stream(
        doc,
        ap_xref,
        use_appearance_alpha=keep_appearance_alpha,
        use_multiply=not remove_multiply,
    )

    rewritten = destination.with_suffix(".rewritten.pdf")
    doc.save(rewritten, garbage=4, deflate=True)
    doc.close()

    destination.unlink()
    rewritten.rename(destination)


def inspect_variant(pdf_path: Path):
    doc = fitz.open(pdf_path)
    annot = find_annotation(doc, TARGET_UUID)
    ap_xref = appearance_xref(doc, annot)

    print(f"\n=== {pdf_path.name} ===")
    print(f"Annotation /BM: {doc.xref_get_key(annot.xref, 'BM')}")
    print(f"Annotation /CA: {doc.xref_get_key(annot.xref, 'CA')}")
    print(f"Appearance xref: {ap_xref}")
    print("Appearance stream:")
    print(doc.xref_stream(ap_xref).decode("latin-1").rstrip())
    doc.close()

if not SOURCE_PDF.exists():    raise SystemExit(f"Source PDF not found: {SOURCE_PDF.resolve()}")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

variants = [
    (
        "control.pdf",
        dict(
            remove_multiply=False,
            keep_annotation_alpha=True,
            keep_appearance_alpha=True,
        ),
    ),
    (
        "no-multiply.pdf",
        dict(
            remove_multiply=True,
            keep_annotation_alpha=True,
            keep_appearance_alpha=True,
        ),
    ),
    (
        "annotation-alpha-only.pdf",
        dict(
            remove_multiply=False,
            keep_annotation_alpha=True,
            keep_appearance_alpha=False,
        ),
    ),
    (
        "appearance-alpha-only.pdf",
        dict(
            remove_multiply=False,
            keep_annotation_alpha=False,
            keep_appearance_alpha=True,
        ),
    ),
]

for filename, options in variants:    destination = OUTPUT_DIR / filename

    if filename == "control.pdf":
        shutil.copy2(SOURCE_PDF, destination)
    else:
        make_variant(destination, **options)

for filename, _ in variants:    inspect_variant(OUTPUT_DIR / filename)

print(f"\nCreated specimens in: {OUTPUT_DIR.resolve()}")
PY`

```

## Viewing protocol

For each PDF, compare **only** the target highlight, `"His Holiness the Dalai Lama"`, in:

1.  Anima;
2.  PDF-XChange Viewer;
3.  Chrome or Edge.

Keep zoom and page background comparable. The other highlights on the page are useful controls: they should remain unchanged in every specimen.

Record just two impressions per file:

text

```text
`<filename>
- Anima: lighter / same / darker than control
- PDF-XChange or browser: lighter / same / darker than control`

```

The critical caveat is that `no-multiply.pdf` also removes appearance alpha because fitz stores alpha and Multiply in the same `/H` graphics state. If that specimen changes, it will not isolate blend mode alone. The alpha-only variants still give us useful information, but the true no-Multiply-with-appearance-alpha case needs one additional low-level resource-dictionary mutation.

I recommend running these first as a quick signal check. If the alpha variants confirm the renderer divergence, we can decide whether that extra surgical no-Multiply variant is worth doing.

User:
Thank you for supplying the drop-in replacement. That was a good call.

Here is the output:

apache

```apache
`=== control.pdf ===
Annotation /BM: ('name', '/Multiply')
Annotation /CA: ('float', '.4')
Appearance xref: 46
Appearance stream:
q
/H gs
/H gs
1 .75 .8 rg
64.08 203.22827 m
60.948816 206.35945 60.948816 213.38115 64.08 216.51233 c
212.8656 216.51233 l
215.99678 213.38115 215.99678 206.35945 212.8656 203.22827 c
f
Q
=== no-multiply.pdf ===
Annotation /BM: ('null', 'null')
Annotation /CA: ('float', '.4')
Appearance xref: 41
Appearance stream:
q
1 .75 .8 rg
64.08 203.22827 m
60.948816 206.35945 60.948816 213.38115 64.08 216.51233 c
212.8656 216.51233 l
215.99678 213.38115 215.99678 206.35945 212.8656 203.22827 c
f
Q
=== annotation-alpha-only.pdf ===
Annotation /BM: ('name', '/Multiply')
Annotation /CA: ('float', '.4')
Appearance xref: 41
Appearance stream:
q
1 .75 .8 rg
64.08 203.22827 m
60.948816 206.35945 60.948816 213.38115 64.08 216.51233 c
212.8656 216.51233 l
215.99678 213.38115 215.99678 206.35945 212.8656 203.22827 c
f
Q
=== appearance-alpha-only.pdf ===
Annotation /BM: ('name', '/Multiply')
Annotation /CA: ('null', 'null')
Appearance xref: 41
Appearance stream:
q
/H gs
/H gs
1 .75 .8 rg
64.08 203.22827 m
60.948816 206.35945 60.948816 213.38115 64.08 216.51233 c
212.8656 216.51233 l
215.99678 213.38115 215.99678 206.35945 212.8656 203.22827 c
f
Q
Created specimens in: /Users/fschuhi/Projects/anima/tmp/color-rendering-experiment`

```

Using PDF-Xchange-Viewer:

-   control: light pink
-   appearance-alpha-only: light pink, as in the control
-   annotation-alpha-only: more saturated pink, opaque highlight (cannot see the text below it)
-   no-multiply: like annotation-alpha-only

Using Chrome: exactly the same behaviour like with the PDF-Xchange-Viewer,

-   2x light pink and visible text
-   2x more saturated pink and text invisible ("overpainted")

For Preview and Anima:

-   _all_ files show the same color, the usual saturated pink, and _all_ highlighted texts are equally visible,
-   highlights have sharp corners, whereas the other viewers show them with rounded, see screenshots

Assistant:
This is an unusually clean and decisive result. The experiment has done its job.

## Results inventory

### Non-Apple renderers -- PDF-XChange Viewer and Chrome

Variant

Result

What that means

`control.pdf`

Light pink, text visible

The appearance stream's `/H` graphics state is active: 40% alpha + Multiply.

`appearance-alpha-only.pdf`

Same as control

The appearance stream alone is sufficient for the intended rendering. Annotation `/CA` is not needed here.

`annotation-alpha-only.pdf`

Saturated and opaque; text overpainted

Removing `/H gs` removes the appearance stream's alpha and Multiply. The renderer paints the appearance stream's solid pink fill. Annotation `/CA .4` does not rescue it.

`no-multiply.pdf`

Same opaque result

This is expected from our specimen construction: removing `/H gs` removed both Multiply and appearance alpha, so it did **not** isolate blend mode.

### Apple renderers -- Preview and Anima/PDFKit

Variant

Result

All four

Same saturated pink, text visible, sharp corners

### Screenshot detail

The sharp-versus-rounded-corner difference is further evidence of the same thing:

-   PDF-XChange/Chrome render the supplied appearance-stream path, which has rounded ends.
-   Preview/Anima render a native markup-highlight shape from their own interpretation of the annotation geometry, producing square/sharp ends.

## The central finding

> **Preview/PDFKit is effectively ignoring the normal appearance stream for these highlight annotations.**

That is why Apple rendering does not react to:

-   the appearance-stream alpha;
-   the appearance-stream `/Multiply`;
-   the rounded fill path;
-   removal of annotation `/CA`, at least in this experiment.

Meanwhile, PDF-XChange Viewer and Chrome are visibly using the appearance stream as their primary rendering source.

This supports your gut feeling, but in a more specific form:

> We likely need an **Apple/PDFKit-facing annotation-color compensation** while preserving the current appearance stream for PDF-XChange and browser rendering.

The important nuance is that this does **not** mean changing the pink everywhere. The promising strategy is to deliberately let the PDF expose two compatible render paths:

text

```text
`PDF-XChange / Chrome:
  use the generated appearance stream
  -> retain current pink + 0.4 alpha + Multiply
  -> retain the pale reference appearance

Preview / Anima:
  use high-level annotation properties rather than /AP
  -> set a lighter annotation /C value
  -> obtain a pale display in Apple renderers`

```

That is not necessarily a hack. It is a pragmatic compatibility layer for two renderer families that demonstrably choose different PDF representations.

## One correction to our experiment design

The `no-multiply.pdf` specimen did **not** isolate `/Multiply`. As you can see from its stream:

pdf

```text
`q
1 .75 .8 rg
...
f
Q`

```

Removing `/H gs` removed **both**:

-   `/BM /Multiply`;
-   `/CA .4` and `/ca .4`.

So its result tells us "solid appearance-stream fill is opaque" -- which is useful -- but not whether Multiply itself changes the outcome.

That question is no longer central, because Apple ignored that whole path anyway. I would not spend another round creating a surgical blend-mode-only specimen unless we later decide that PDF-XChange/browser rendering itself needs adjustment.

## What this says about the likely production design

The current helper does this conceptually:

text

```text
`set annotation color to pink
set annotation opacity to 0.4
update annotation
  -> fitz generates pink /AP with Multiply and 0.4 alpha`

```

For compatibility compensation, the future design may need to separate two values:

Concern

Candidate source

Intended audience

**Annotation `/C`**

A deliberately lighter pink

PDFKit / Preview

**Appearance-stream fill color**

Existing `[1.0, 0.75, 0.80]`

PDF-XChange / Chrome

**Appearance-stream alpha**

Existing `0.4`

PDF-XChange / Chrome

**In-memory PDFKit annotation color**

Same lighter annotation color

Immediate Anima display, before reopening

This would preserve the trusted rendering in your existing workflow while making Anima agree visually with it.

## The next smallest experiment

Before designing a production change, we should test only the key proposition:

> If we change the annotation dictionary's `/C` to a paler pink while leaving the appearance stream untouched, do Preview and Anima become acceptably pale while PDF-XChange and Chrome remain unchanged?

There are two sensible experiment shapes.

### Option A -- one deliberately pale candidate

Create one copy where only the target annotation's `/C` is changed, for example from:

text

```text
`[1.0, 0.75, 0.80]`

```

to something visibly paler, such as:

text

```text
`[1.0, 0.90, 0.92]`

```

The appearance stream would remain completely untouched.

**Pros:** Fastest confirmation of the mechanism.
**Cons:** It may prove the mechanism but not land on the final pleasant color.

### Option B -- a small color ladder -- recommended

Create three copies that change **only** the target annotation dictionary's `/C`; retain the original `/AP`, `/CA`, `/BM`, quads, metadata, and all other annotations.

For example:

Specimen

Annotation `/C`

`apple-c-0.85-0.88.pdf`

`[1.0, 0.85, 0.88]`

`apple-c-0.90-0.92.pdf`

`[1.0, 0.90, 0.92]`

`apple-c-0.93-0.94.pdf`

`[1.0, 0.93, 0.94]`

Expected outcome:

-   **Preview/Anima:** three progressively paler highlight backgrounds.
-   **PDF-XChange/Chrome:** no visible change, because their appearance stream remains the original pink at 40% alpha and Multiply.

**Pros:** Finds a usable range in one comparison pass.
**Cons:** Three more disposable PDFs, though the mutation is now extremely simple and narrowly targeted.

I recommend **Option B**. It directly tests the actual compensation mechanism and makes the visual decision yours, rather than pretending there is one objectively correct RGB value.

One product question before we run that: should the goal in Preview/Anima be to match PDF-XChange's pale pink **as closely as practical**, or merely to be clearly lighter and pleasant enough that you trust it?

User:
How about using a color picker instead of a ladder? What are the 3 values?

I don't care so much about what Preview uses as color, so the "Annotation `/C`" concern is low prio. My expectation is that we will replace all annotation colors in the in-memory PDFKit layer with the "pale candidate" which matches the color shown in the PDF-Xchange-Viewer (or Chrome), correct?

Assistant:
Denkt nach

Yes -- your expectation is correct, with one important distinction:

text

```text
`Persisted PDF annotation:
  keep the current color and fitz-generated appearance stream unchanged
  -> PDF-XChange / Chrome continue to show their trusted light pink

In-memory PDFKit annotation:
  replace its display color with a compensated, paler color
  -> Anima shows the same light pink family while the app is open`

```

So the priority is **not** changing the on-disk annotation `/C` for every viewer. It is changing `PDFAnnotation.color` in Anima's in-memory document after load, and using the same compensated color when Anima creates a new in-memory annotation.

Because Anima never saves through PDFKit, that in-memory override does not overwrite the fitz-written PDF representation.

## Why a color picker is better than a blind ladder

Agreed. A three-file ladder would be a crude visual search. You already have:

-   a trusted target rendering in PDF-XChange Viewer or Chrome;
-   Anima's current, too-saturated rendering;
-   the exact baseline input color: `[1.0, 0.75, 0.80]`.

A picker lets us derive one evidence-based first candidate.

But there are **two kinds of color** involved:

1.  **Target displayed color** -- what you see in PDF-XChange/Chrome, sampled with the picker.
2.  **PDFKit input color** -- the paler color we assign to `PDFAnnotation.color` so that PDFKit's own rendering produces the target displayed color.

They are not necessarily the same. If PDFKit applies its own alpha/compositing behavior, directly assigning the target's visible RGB could make Anima too pale.

## The three proposed ladder values, for reference

These were normalized RGB values in Swift/PDF notation, from `0.0` to `1.0`:

Candidate

Normalized RGB

8-bit RGB

Hex

Mildly paler

`[1.0, 0.85, 0.88]`

`(255, 217, 224)`

`#FFD9E0`

Paler

`[1.0, 0.90, 0.92]`

`(255, 230, 235)`

`#FFE6EB`

Very pale

`[1.0, 0.93, 0.94]`

`(255, 237, 240)`

`#FFEDF0`

The current stored/source color is:

Existing value

Normalized RGB

8-bit RGB

Hex

Current pink

`[1.0, 0.75, 0.80]`

`(255, 191, 204)`

`#FFBFCC`

Those ladder values are now only fallback reference points. A picker-derived candidate is better.

## Proposed picker-based calibration

Use a flat interior part of the same highlight -- well away from:

-   black glyphs;
-   antialiased text edges;
-   rounded highlight ends;
-   the popup icon.

For example, the broad middle area behind `"His Holiness the Dalai Lama"` is suitable.

Record these two RGB values as 8-bit sRGB values:

text

```text
`A. Desired target:
   PDF-XChange Viewer or Chrome, on the baseline/control PDF

B. Current Anima display:
   Anima, on that same target highlight and same page background`

```

If you give me those values, I can calculate an initial compensated PDFKit input color.

### Why two measurements?

The target tells us where we want to land. The current Anima measurement tells us how PDFKit transforms the known input `[255, 191, 204]` into its displayed result. From the gap between those two, we can estimate how much paler the in-memory input must be.

It will be an empirical first estimate, not an assertion about PDF compositing theory. We then test one candidate rather than three blind variants.

## Implementation boundary once the candidate is chosen

The future implementation should affect two paths only:

1.  **Existing annotations loaded from disk**

    -   After `MainViewController.loadPDF(document:)` prepares the in-memory document, assign the compensated display color to each highlight's `annot.color`.
2.  **New highlights created during this session**

    -   `AnnotationManager.addInMemoryHighlight(...)` uses the compensated display color instead of the persisted fitz color.

The Python helper's persisted color remains `[1.0, 0.75, 0.80]`, and the matching fitz appearance stream remains untouched.

One later detail to handle deliberately: emphasis currently saves an annotation's current in-memory color and restores it afterward. That is good news -- if the normal in-memory color is compensated first, emphasis will naturally restore the compensated color rather than the saturated persisted one.

Please send the two picker readings -- target PDF-XChange/Chrome and current Anima -- and we can calculate a single candidate for the next disposable verification PDF.

User:
> So the priority is not changing the on-disk annotation /C for every viewer. It is changing PDFAnnotation.color in Anima's in-memory document after load, and using the same compensated color when Anima creates a new in-memory annotation.

Perfect, that's what I meant.

MacOS: Digital Color Meter

1.  screenshot: Chrome
2.  Screenshot: Preview

Windows 11: PowerToys Color Picker
3\. `ffe6ea` for pale pink (same for PDF-Xchange-Viewer and Edge)
4\. `ffbfcc` for more saturated pink for the "overpainted" cases (`annotation-alpha-only.pdf`, `no-multiply.pdf`)

Assistant:
Denkt nach

These measurements give us a solid first candidate -- but they also reveal one thing we should test before touching Anima code:

> We have proven that PDFKit ignores the supplied appearance stream. We have **not yet proven** that changing annotation `/C` changes PDFKit's rendered color in the expected way.

That is the last small mechanism check before an in-memory compensation implementation.

## The sampled values

### Trusted target -- Chrome / PDF-XChange / Edge

Your Windows picker reports:

text

```text
`#FFE6EA
RGB(255, 230, 234)
normalized: (1.000, 0.902, 0.918)`

```

That is the best value to treat as the target, because it comes from the renderer family you want Anima to visually match.

The macOS Digital Color Meter reading from the Chrome screenshot is:

text

```text
`(0.983, 0.905, 0.917)
approximately #FBE7EA`

```

It is close in green/blue but slightly lower in red. That is normal given that Digital Color Meter was set to **"Display native values"**, which are display-profile dependent, whereas the Windows hex picker reports an ordinary RGB hex value. We should use the Windows sRGB-style value as the code/test reference.

### Current Apple/PDFKit appearance

Your Preview reading is:

text

```text
`(0.962, 0.763, 0.797)
approximately #F5C3CB`

```

This is close to the original stored/source color:

text

```text
`#FFBFCC
RGB(255, 191, 204)
normalized: (1.000, 0.749, 0.800)`

```

And the Windows opaque specimens measured exactly `#FFBFCC`, which confirms the actual fill color in the appearance stream is the original pink.

## Proposed first in-memory compensation candidate

swift

```swift
`NSColor(
    red: 1.0,
    green: 230.0 / 255.0,
    blue: 234.0 / 255.0,
    alpha: 1.0
)`

```

Equivalent representations:

text

```text
`Hex:        #FFE6EA
8-bit RGB:  (255, 230, 234)
Swift:      (1.0, 0.902, 0.918, 1.0)`

```

This is deliberately the **target visible color**, not yet a mathematically derived inverse compensation. PDFKit's present rendering of the source color is sufficiently close to its raw color that using the desired visible value as the in-memory input is a reasonable first experiment.

## One last disposable PDF experiment

Before we modify Anima's in-memory behavior, I recommend creating exactly one specimen:

text

```text
`pdfkit-c-ffe6ea.pdf`

```

It would alter **only the target Anima-authored annotation's `/C`** from `[1 .75 .8]` to `[1 .901961 .917647]`, while preserving:

-   annotation `/CA .4`;
-   annotation `/BM /Multiply`;
-   appearance stream `/AP`;
-   appearance stream pink fill, alpha, and Multiply;
-   every other annotation.

### What it answers

Renderer

Expected result if `/C` controls its markup rendering

Preview / Anima

The target highlight becomes much paler, hopefully close to `#FFE6EA`.

Chrome / PDF-XChange

No visible change, because their rendering is using `/AP`, whose pink fill remains untouched.

If Preview and Anima **do** react as expected, we have proven the dual-representation strategy before writing app code:

text

```text
`PDFKit path: annotation /C -> pale in-memory display color
Other renderer path: /AP -> current trusted light-pink appearance`

```

If Preview/Anima do **not** react, then `PDFAnnotation.color` will not be the seam we need, and we stop before making a misleading code change.

## Local ownership for that eventual implementation

If the one-PDF check succeeds, the production change remains limited to two places:

1.  `MainViewController.scrubCommentsForPopupSuppression(in:)`

    -   It already iterates every loaded highlight annotation.
    -   It can also set `annot.color` to the PDFKit-only display color after preserving/migrating comments.
    -   This affects only the in-memory `PDFDocument`, never the file on disk.
2.  `AnnotationManager.addInMemoryHighlight(...)`

    -   It creates the session's immediate PDFKit mirror after fitz has persisted the normal annotation.
    -   It should set the same pale display color there, rather than `highlightColor`.

Everything else remains intentionally out of scope:

-   `tools/anima_helper.py` continues to write `[1.0, 0.75, 0.80]` at opacity `0.4`.
-   Existing Python tests continue to assert the persisted contract.
-   The appearance stream remains fitz-generated.
-   Sidebar, UUID, popup, and coordinate behavior remain untouched.

Would you like to approve that single `pdfkit-c-ffe6ea.pdf` confirmation specimen before we implement the in-memory override?

User:
Yes! We are getting closer!

Yes, `pdfkit-c-ffe6ea.pdf` approved.

Assistant:
Denkt nach

Run this from the directory containing `input-with-anima-highlight.pdf`. It creates exactly one disposable specimen:

text

```text
`tmp/color-rendering-experiment/pdfkit-c-ffe6ea.pdf`

```

It changes only the target Anima-created annotation's dictionary `/C` to `#FFE6EA`; its `/AP` appearance stream remains untouched.

bash

```bash
`. .venv/bin/activate
python - <<'PY'
from pathlib import Path
import shutil

import fitz

source_pdf = Path("input-with-anima-highlight.pdf")
output_pdf = Path("tmp/color-rendering-experiment/pdfkit-c-ffe6ea.pdf")
target_uuid = "16b93454-0ff5-42da-9ca0-dae206297342"
# #FFE6EA in normalized PDF RGB values.
pale_annotation_color = "[1 .901961 .917647]"

def find_annotation(doc: fitz.Document, uuid: str):
    for page in doc:        for annot in page.annots() or []:            if annot.info.get("id") == uuid:
                return annot    raise RuntimeError(f"Could not find target annotation UUID: {uuid}")

if not source_pdf.exists():    raise SystemExit(f"Source PDF not found: {source_pdf.resolve()}")
output_pdf.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source_pdf, output_pdf)

doc = fitz.open(output_pdf)
annot = find_annotation(doc, target_uuid)

original_color = doc.xref_get_key(annot.xref, "C")
original_opacity = doc.xref_get_key(annot.xref, "CA")
original_blend_mode = doc.xref_get_key(annot.xref, "BM")
original_appearance = doc.xref_get_key(annot.xref, "AP")
# Change only the annotation-level color that Preview/PDFKit appears to use.
# Do not call annot.update(): that would regenerate the appearance stream.
doc.xref_set_key(annot.xref, "C", pale_annotation_color)
rewritten_pdf = output_pdf.with_suffix(".rewritten.pdf")
doc.save(rewritten_pdf, garbage=4, deflate=True)
doc.close()

output_pdf.unlink()
rewritten_pdf.rename(output_pdf)

# Verification after reopening.
doc = fitz.open(output_pdf)
annot = find_annotation(doc, target_uuid)

print(f"Created: {output_pdf.resolve()}")
print(f"Target annotation UUID: {target_uuid}")
print()
print("Expected single change:")
print(f"  /C before: {original_color}")
print(f"  /C after:  {doc.xref_get_key(annot.xref, 'C')}")
print()
print("Expected unchanged controls:")
print(f"  /CA before: {original_opacity}")
print(f"  /CA after:  {doc.xref_get_key(annot.xref, 'CA')}")
print(f"  /BM before: {original_blend_mode}")
print(f"  /BM after:  {doc.xref_get_key(annot.xref, 'BM')}")
print(f"  /AP before: {original_appearance}")
print(f"  /AP after:  {doc.xref_get_key(annot.xref, 'AP')}")
doc.close()
PY`

```

## Check only one thing

Open `pdfkit-c-ffe6ea.pdf` in:

1.  **Anima or Preview**

    -   Does `"His Holiness the Dalai Lama"` become pale, ideally near the Chrome/PDF-XChange target?
2.  **Chrome or PDF-XChange Viewer**

    -   Does that same highlight remain unchanged from the baseline light pink?

The target highlight should be easy to distinguish: it is the only one on the page whose annotation `/C` was changed, while its appearance stream remains the original fitz-generated pink.

User:
scheme

```scheme
`Created: /Users/fschuhi/Projects/anima/tmp/color-rendering-experiment/pdfkit-c-ffe6ea.pdf
Target annotation UUID: 16b93454-0ff5-42da-9ca0-dae206297342
Expected single change:
  /C before: ('array', '[1 .75 .8]')  /C after:  ('array', '[1 .901961 .917647]')
Expected unchanged controls:
  /CA before: ('float', '.4')
  /CA after:  ('float', '.4')
  /BM before: ('name', '/Multiply')
  /BM after:  ('name', '/Multiply')
  /AP before: ('dict', '<</N 46 0 R>>')  /AP after:  ('dict', '<</N 41 0 R>>')`

```

Screenshots from viewing the `pdfkit-c-ffe6ea.pdf`:

1.  **PDF-Xchange-Viewer**. The color matches all other highlights. Note, though, that the _popup_ for the "added with Anima" color is much paler. It actually looks like PDF-Xchange-Viewer uses the saturated pink for the other popups.
2.  **Anima**. The highlight color is the pale pink. I love it.

Assistant:
Denkt nach

That is the confirmation we needed.

## Result

The dual-representation strategy works exactly as hoped:

Renderer path

What it used

Result after changing only annotation `/C`

PDF-XChange Viewer

Existing `/AP` appearance stream

Highlight remains the trusted light pink, matching the other highlights.

Anima / PDFKit

Annotation-level `/C`

Highlight becomes the pale pink you want.

So the production approach is now well-supported:

text

```text
`On disk:
  keep fitz's existing pink annotation contract unchanged
  /C = #FFBFCC
  /CA = 0.4
  fitz-generated /AP with pink + alpha + Multiply

In Anima memory only:
  set PDFAnnotation.color = #FFE6EA
  never save the PDF through PDFKit`

```

This preserves the existing cross-viewer / `pdf-annotations` contract while making Anima pleasant to use.

## About the `/AP` xref changing from 46 to 41

That is expected from the specimen script's full rewrite with `garbage=4`: PDF object numbers can be renumbered during garbage collection. The meaningful part is that `/AP /N` remains present and PDF-XChange displays the same light-pink highlight, which shows its appearance stream was preserved in substance.

## The paler PDF-XChange popup

That is a useful secondary finding:

-   PDF-XChange appears to render the **highlight** from `/AP`, which stayed unchanged and therefore remains the usual light pink.
-   Its **popup UI** appears to derive its color from annotation `/C`, which was changed to `#FFE6EA`.

For the production implementation, this is not a problem because we will **not change the on-disk `/C`**. External viewers will continue to see their current popup styling.

Within Anima, the corresponding edge case is X-Ray mode: PDFKit's native popup may inherit the in-memory pale display color. But X-Ray mode is explicitly a diagnostic/display mode, and normal Anima operation suppresses these popups. I would treat this as an accepted consequence unless it visibly harms X-Ray usefulness.

# Proposed production change -- one focused step

## Local ownership

**User action:** Open a PDF and see all highlights in the trusted pale pink; create a new highlight and see the same pale pink immediately.

**Owners:**

Owner

Narrow responsibility in this change

`AnnotationManager.swift`

Defines the PDFKit-only display pink and uses it for newly created in-memory highlights.

`MainViewController.swift`

Applies that display pink to existing highlights immediately after loading, during its existing document-preparation pass.

`tools/anima_helper.py`

Intentionally unchanged -- continues to persist the current pink for other readers.

Python tests

Intentionally unchanged -- their current color assertions continue to verify the persisted contract.

## Exact behavior change

1.  Add a new, clearly named constant to `AnnotationManager`:

    swift

    ```swift
    `static let pdfKitDisplayHighlightColor = NSColor(
        red: 1.0,
        green: 230.0 / 255.0,
        blue: 234.0 / 255.0,
        alpha: 1.0
    )`

    ```

    The existing `highlightColor` remains exactly as it is, because it documents/matches the persisted fitz color.

2.  In `MainViewController.scrubCommentsForPopupSuppression(in:)`, set every loaded highlight's `annot.color` to `AnnotationManager.pdfKitDisplayHighlightColor`.

    That function is the correct seam because it already visits every highlight at load time and prepares the document's **in-memory-only** display representation.

3.  In `AnnotationManager.addInMemoryHighlight(...)`, replace:

    swift

    ```swift
    `annot.color = AnnotationManager.highlightColor`

    ```

    with:

    swift

    ```swift
    `annot.color = AnnotationManager.pdfKitDisplayHighlightColor`

    ```

    This covers a new highlight immediately, without reloading the document.


## Explicitly unchanged

-   `HIGHLIGHT_COLOR` in `tools/anima_helper.py`
-   `AnnotationManager.highlightColor`
-   persisted opacity and `/BM /Multiply`
-   fitz appearance generation
-   existing Python tests and their expected color
-   sidebar, UUID, popup-suppression mechanics, and emphasis logic

The current emphasis code should continue to work naturally: it saves the annotation's current in-memory color before applying yellow emphasis, then restores that same pale display color afterward.

## Two implementation options

### Option 1 -- direct two-file display override -- recommended

Make only the two targeted changes above.

**Pros**

-   Minimal.
-   Matches the successful specimen precisely.
-   Keeps disk and display contracts deliberately separate.
-   Easy to review in `git diff` and easy to revert.

**Cons**

-   There is no automated Swift regression test specifically proving that loaded highlights receive the pale display override.

### Option 2 -- direct override plus a new test seam

Make the same behavior change, but extract a small helper that applies the PDFKit display appearance to a highlight and test that helper.

**Pros**

-   Pins the new compatibility rule in the Swift suite.

**Cons**

-   Requires a small refactor purely to make a currently private load-time behavior testable.
-   Slightly violates the reader-first "small visible value" focus, especially while the test suite is intentionally parked.

I recommend **Option 1 now**, followed by a manual verification checklist:

1.  Open the original baseline `input.pdf` in Anima -- existing highlights should all be pale.
2.  Create a new highlight -- it should be pale immediately.
3.  Quit and reopen -- that new highlight should remain pale in Anima.
4.  Open the PDF in PDF-XChange/Chrome -- its persisted rendering should remain their normal light pink.
5.  Toggle highlight emphasis on and off -- normal pale pink should restore afterward.

If you approve Option 1, I will provide complete drop-in replacements for **only** `AnnotationManager.swift` and `MainViewController.swift`, with no unrelated formatting or cleanup.

User:
> PDFKit's native popup may inherit the in-memory pale display color. But X-Ray mode is explicitly a diagnostic/display mode, and normal Anima operation suppresses these popups. I would treat this as an accepted consequence unless it visibly harms X-Ray usefulness.

The behaviour for X-Ray (triggered with key `P`) is the same for all highlights, regardless of pale or saturated, so we are safe there.

Let's do Option 1, agreed.

Assistant:
Implemented the approved display-only compensation design:

-   On-disk fitz/PDF-XChange color remains unchanged.
-   Loaded PDFKit highlights are recolored in memory to `#FFE6EA`.
-   Newly created in-memory highlights use the same pale display color immediately.
-   No Python helper, persistence behavior, sidebar behavior, or tests changed.

`MainViewController.swift` exceeds 500 lines and the change is one obvious line, so per the agreed exception this is marked as a partial patch. `AnnotationManager.swift` is provided as a complete drop-in replacement.

## `AnnotationManager.swift` -- drop-in replacement

swift

```swift
`//
//  AnnotationManager.swift
//  Anima
//
//  Manages annotation CRUD operations: creating highlights, editing comments,
//  and deleting highlights. Owns the dual-write pattern (fitz persist + in-memory
//  PDFAnnotation) and the coordinate conversion from PDFKit space to fitz space.
//
//  Design:
//    This is a toolbox class — it does not hold references to the PDFView,
//    the document, or any UI state. All context is passed per-call. This keeps
//    the class testable and avoids stale references if multi-document support
//    (tabs) is added later.
//
//    The caller (AnimaPDFView) is responsible for:
//      - Obtaining the current selection / annotation / page
//      - Setting isShowingDialog before/after editComment calls
//      - Notifying the sidebarDelegate after mutations
//      - Managing emphasis state
//
//  Popup suppression:
//    Comments are stored in a custom /AnimaComment dictionary key to prevent
//    PDFKit from rendering native yellow popup squares. The standard .contents
//    field is kept empty unless X-Ray mode is active. The isXRayMode parameter
//    on relevant methods controls this behavior. See README.md "Popup Suppression"
//    for the full contract.
//
import Cocoa
import Quartz
class AnnotationManager {
    // Path to the Python helper — absolute path for Xcode-launched app
    let helperPath: String
    // Default author for in-memory annotations. Must match anima_helper.py's
    // DEFAULT_AUTHOR so that cards created during a session show the same
    // author as cards loaded from disk on next launch.
    static let authorName = "fschuhi"
    // --- Highlight color/opacity constants (must match anima_helper.py) ---
    // anima_helper.py: HIGHLIGHT_COLOR = [1.0, 0.75, 0.80], HIGHLIGHT_OPACITY = 0.4
    static let highlightColor = NSColor(red: 1.0, green: 0.75, blue: 0.80, alpha: 1.0)
    static let highlightOpacity: CGFloat = 0.4
    // PDFKit renders highlight annotations more saturated than PDF-XChange
    // Viewer and Chromium-based browsers. This display-only color is applied
    // to PDFKit's in-memory annotations; fitz continues to persist
    // highlightColor so the on-disk PDF contract remains unchanged.
    static let pdfKitDisplayHighlightColor = NSColor(
        red: 1.0,
        green: 230.0 / 255.0,
        blue: 234.0 / 255.0,
        alpha: 1.0
    )

    init(helperPath: String) {        self.helperPath = helperPath    }

    // MARK: - Coordinate Conversion
    /// Convert a PDFKit-space rect (origin bottom-left) into a fitz-space quad
    /// dictionary (origin top-left), for one selection line.
    ///
    /// Coordinate contract (must match anima_helper.py's docstring):
    ///     y_fitz = page_height - y_pdfkit
    ///
    /// x is unaffected by the flip — only y inverts, because fitz measures
    /// from the top of the page and PDFKit measures from the bottom.
    ///
    /// - Parameters:
    ///   - bounds: A single selection line's bounding rect, in PDFKit space.
    ///   - pageHeight: The page's media-box height, in points.
    /// - Returns: A dictionary with x0/y0/x1/y1 keys, in fitz space, ready for
    ///   JSON serialization to anima_helper.py's --quads argument.
    static func fitzQuad(from bounds: NSRect, pageHeight: CGFloat) -> [String: Double] {
        let x0 = Double(bounds.origin.x)
        let x1 = Double(bounds.origin.x + bounds.size.width)        let y0_fitz = Double(pageHeight - (bounds.origin.y + bounds.size.height))        let y1_fitz = Double(pageHeight - bounds.origin.y)
        return ["x0": x0, "y0": y0_fitz, "x1": x1, "y1": y1_fitz]
    }

    /// Build the four QuadPoints corners for a single PDFKit-space rect.
    ///
    /// PDFKit expects QuadPoints as a flat array of NSValue-wrapped NSPoints,
    /// four points per quad (one quad per selection line). Order: bottom-left,
    /// bottom-right, top-left, top-right (the PDF spec order for QuadPoints).
    ///
    /// This is a pure geometry function — it does not filter degenerate
    /// (zero-width or zero-height) rects. That filtering is a policy decision
    /// made upstream, in `createHighlight`.
    ///
    /// - Parameter rect: A single selection line's bounding rect, in PDFKit space.
    /// - Returns: Four NSValue-wrapped NSPoints, in QuadPoints order.
    static func quadPoints(for rect: NSRect) -> [NSValue] {
        let bottomLeft  = NSPoint(x: rect.minX, y: rect.minY)
        let bottomRight = NSPoint(x: rect.maxX, y: rect.minY)
        let topLeft     = NSPoint(x: rect.minX, y: rect.maxY)
        let topRight    = NSPoint(x: rect.maxX, y: rect.maxY)
        return [            NSValue(point: bottomLeft),
            NSValue(point: bottomRight),
            NSValue(point: topLeft),
            NSValue(point: topRight),
        ]
    }

    // MARK: - Create Highlight
    /// Create a highlight from PDFKit selection line bounds.
    ///
    /// Performs the full dual-write sequence:
    ///   1. Convert PDFKit-space bounds to fitz-space quads
    ///   2. Call anima_helper.py to persist via fitz (incremental save)
    ///   3. Add a matching in-memory PDFAnnotation for immediate display
    ///
    /// - Parameters:
    ///   - document: The PDFDocument (needed for URL and page index)
    ///   - page: The PDFPage to add the highlight to
    ///   - pageIndex: The 0-based page index
    ///   - selectionBounds: Per-line bounding rects in PDFKit coordinate space
    ///   - isXRayMode: Whether popups should be visible (affects .contents handling)
    /// - Returns: The UUID of the created highlight, or nil on failure
    func createHighlight(
        document: PDFDocument,
        page: PDFPage,
        pageIndex: Int,
        selectionBounds: [NSRect],
        isXRayMode: Bool
    ) -> String? {
        let pageHeight = page.bounds(for: .mediaBox).height
        // Build quads in both coordinate systems:
        // - fitzQuads: for anima_helper.py (fitz space, origin top-left)
        // - pdfkitBounds: for in-memory PDFAnnotation (PDFKit space, origin bottom-left)
        var fitzQuads: [[String: Double]] = []        var pdfkitBounds: [NSRect] = []
        for bounds in selectionBounds {            if bounds.size.width < 1 || bounds.size.height < 1 {                continue
            }

            // PDFKit-space bounds — keep as-is for in-memory annotation
            pdfkitBounds.append(bounds)

            // Fitz-space quad — see fitzQuad(from:pageHeight:) for the y-flip contract
            fitzQuads.append(AnnotationManager.fitzQuad(from: bounds, pageHeight: pageHeight))
        }

        if fitzQuads.isEmpty {            Swift.print("⚠️  No valid quads from selection")
            return nil
        }

        // Highlights are created without a comment. To add or edit a comment
        // later, double-click the highlight (matches PDF-XChange Viewer workflow).
        let comment = ""
        let uuid = UUID().uuidString.lowercased()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: fitzQuads),
              let jsonString = String(data: jsonData, encoding: .utf8) else {            Swift.print("❌ Failed to serialize quads to JSON")
            return nil
        }

        guard let documentURL = document.documentURL else {            Swift.print("❌ Document has no URL")
            return nil
        }

        Swift.print("📝 Creating highlight: page=\(pageIndex), quads=\(fitzQuads.count) lines, uuid=\(uuid)")
        // Step 1: Persist to disk via fitz
        let success = FitzBridge.addHighlight(
            helperPath: helperPath,
            filePath: documentURL.path,
            page: pageIndex,
            uuid: uuid,
            quadsJSON: jsonString,
            comment: comment
        )

        if success {            // Step 2: Add in-memory annotation for immediate display (no reload)
            addInMemoryHighlight(
                page: page,
                bounds: pdfkitBounds,
                uuid: uuid,
                comment: comment,
                isXRayMode: isXRayMode
            )
            Swift.print("✅ Highlight created (dual-write): \(uuid)")
            return uuid        }

        return nil
    }

    // MARK: - Edit Comment
    /// Edit an annotation's comment via the modal CommentInputPanel.
    ///
    /// Shows the input panel, writes the new comment via fitz, and updates
    /// the in-memory annotation. The caller is responsible for setting
    /// isShowingDialog before this call and clearing it after.
    ///
    /// - Parameters:
    ///   - document: The PDFDocument (needed for URL)
    ///   - annotation: The highlight annotation to edit
    ///   - page: The page the annotation lives on
    ///   - isXRayMode: Whether popups should be visible
    /// - Returns: true if the comment was changed, false if unchanged or failed
    func editComment(
        document: PDFDocument,
        annotation: PDFAnnotation,
        page: PDFPage,
        isXRayMode: Bool
    ) -> Bool {
        guard let uuid = annotationUUID(annotation) else {            Swift.print("⚠️  Highlight has no UUID — cannot edit")
            return false
        }

        // Read from our custom key first, fallback to .contents
        var existingComment = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment")) as? String ?? ""
        if existingComment.isEmpty {            existingComment = annotation.contents ?? ""
        }

        Swift.print("🖱️  Editing comment: \(uuid)")
        Swift.print("   Existing comment: \(existingComment.isEmpty ? "(none)" : existingComment)")
        // Show the modal input panel. The panel always returns a string —
        // there is no "cancel". Escape saves whatever text is in the editor.
        let newComment = CommentInputPanel.showModal(existingText: existingComment)
        // If the comment didn't change, skip the fitz write and sidebar rebuild.
        if newComment == existingComment {            Swift.print("ℹ️  Comment unchanged, skipping save")
            return false
        }

        guard let documentURL = document.documentURL else { return false }
        let success = FitzBridge.editComment(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid,
            comment: newComment
        )

        if success {            // Dual-write: update the custom key.
            annotation.setValue(newComment, forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment"))
            // Sync standard contents based on active X-Ray Mode
            if isXRayMode {                annotation.contents = newComment                if !newComment.isEmpty {
                    ensurePopupExists(for: annotation, on: page)
                }
            } else {                annotation.contents = ""
                // Destroy popup if PDFKit aggressively re-spawned one
                if let popup = annotation.popup {                    page.removeAnnotation(popup)
                    annotation.popup = nil
                }
                annotation.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/Popup"))
            }

            Swift.print("✅ Comment updated on \(uuid)")
            Swift.print("   New comment: \(newComment.isEmpty ? "(removed)" : newComment)")
            return true
        }

        return false
    }

    // MARK: - Delete Highlight
    /// Delete a highlight annotation entirely.
    ///
    /// Calls anima_helper.py to remove from the PDF file, then removes the
    /// in-memory annotation from the page.
    ///
    /// - Parameters:
    ///   - document: The PDFDocument (needed for URL)
    ///   - annotation: The highlight annotation to delete
    ///   - page: The page the annotation lives on
    /// - Returns: true on success, false on failure
    func deleteHighlight(
        document: PDFDocument,
        annotation: PDFAnnotation,
        page: PDFPage
    ) -> Bool {
        guard let uuid = annotationUUID(annotation) else {            Swift.print("⚠️  Highlight has no UUID — cannot delete")
            return false
        }

        guard let documentURL = document.documentURL else { return false }
        Swift.print("🗑️  Deleting highlight: \(uuid)")
        let success = FitzBridge.deleteHighlight(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid
        )

        if success {            // Dual-write: remove the in-memory annotation from the page
            page.removeAnnotation(annotation)
            Swift.print("✅ Highlight deleted: \(uuid)")
        }

        return success    }

    // MARK: - In-Memory Annotation (Private)
    /// Create a PDFAnnotation in PDFKit's in-memory document for immediate display.
    /// The annotation matches what fitz wrote to disk. On next app launch, PDFKit
    /// will load the fitz-written version from the file.
    ///
    /// Fields set here must match what anima_helper.py writes via fitz:
    ///   - bounds, QuadPoints, color, opacity  (geometry + appearance)
    ///   - /NM                                  (UUID for identification)
    ///   - userName                             (backup UUID for hit-testing)
    ///   - /T                                   (author for sidebar cards)
    ///   - /AnimaComment                        (custom comment text key to suppress popups)
    ///
    /// IMPORTANT: /NM must be set explicitly. PDFKit maps userName to /T
    /// internally, so relying on userName alone for UUID storage causes /T
    /// (author) writes to overwrite the UUID. Setting /NM directly ensures
    /// annotationUUID() finds the UUID on its first check, independent of
    /// the userName ↔ /T mapping.
    private func addInMemoryHighlight(
        page: PDFPage,
        bounds: [NSRect],
        uuid: String,
        comment: String,
        isXRayMode: Bool
    ) {        // Calculate the overall bounding rect (union of all line rects)
        var overallBounds = bounds[0]
        for i in 1..<bounds.count {
            overallBounds = overallBounds.union(bounds[i])        }

        // Create the highlight annotation
        let annot = PDFAnnotation(
            bounds: overallBounds,
            forType: .highlight,
            withProperties: nil
        )

        // Keep the persisted fitz color unchanged, but compensate PDFKit's
        // in-memory rendering so Anima matches the trusted pale appearance.
        annot.color = AnnotationManager.pdfKitDisplayHighlightColor
        annot.setValue(AnnotationManager.highlightOpacity, forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))
        // Handle comment based on X-Ray mode
        if !comment.isEmpty {
            annot.setValue(comment, forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment"))
            annot.contents = isXRayMode ? comment : ""
        }

        // Set UUID — both via /NM (primary, used by annotationUUID) and
        // userName (backup). /NM must be set explicitly because PDFKit
        // does not populate it from userName.
        annot.setValue(uuid, forAnnotationKey: PDFAnnotationKey(rawValue: "/NM"))
        annot.userName = uuid
        // Set author — matches anima_helper.py's DEFAULT_AUTHOR.
        // Must be set AFTER userName to avoid PDFKit's internal
        // userName ↔ /T mapping from overwriting the author with the UUID.
        annot.setValue(AnnotationManager.authorName, forAnnotationKey: PDFAnnotationKey(rawValue: "/T"))
        // Build QuadPoints — one quad (4 points) per selection line.
        // See quadPoints(for:) for the corner-order contract.
        var quadPoints: [NSValue] = []        for rect in bounds {            quadPoints.append(contentsOf: AnnotationManager.quadPoints(for: rect))
        }

        // Set QuadPoints via the annotation key
        annot.setValue(quadPoints, forAnnotationKey: PDFAnnotationKey(rawValue: "/QuadPoints"))
        // Add to the page — PDFKit renders it immediately
        page.addAnnotation(annot)

        // Now that it's on the page, link the popup if necessary
        if isXRayMode && !comment.isEmpty {
            ensurePopupExists(for: annot, on: page)
        }

        Swift.print("🔧 In-memory annotation added: \(uuid) (\(bounds.count) quads, bounds=\(overallBounds))")
    }

    // MARK: - Popup Helpers
    /// Manually rebuilds a PDFAnnotationPopup and links it to the highlight.
    /// Because we aggressively destroy popups on load to prevent them from rendering,
    /// setting `.contents` later isn't enough; PDFKit requires the actual object to exist.
    func ensurePopupExists(for annot: PDFAnnotation, on page: PDFPage) {        if annot.popup == nil {            // Provide a sensible default size/location. PDFKit handles the yellow icon
            // placement automatically, but this dictates where the actual text box opens if clicked.
            let popupBounds = NSRect(x: annot.bounds.maxX, y: annot.bounds.maxY, width: 200, height: 150)
            let popup = PDFAnnotation(bounds: popupBounds, forType: .popup, withProperties: nil)
            annot.popup = popup            page.addAnnotation(popup)
        }
    }

    // MARK: - UUID Helper
    /// Get the UUID (NM field) of an annotation.
    func annotationUUID(_ annot: PDFAnnotation) -> String? {
        // Try the standard PDFKit way first
        if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String {            return nm        }

        // PDFKit might not expose /NM directly. Try the annotation's name property.
        let name = annot.userName        if let name = name, !name.isEmpty {
            return name        }

        return nil
    }
}`

```

## `MainViewController.swift`

⚠️ **PARTIAL PATCH - NOT A DROP-IN REPLACEMENT**

`MainViewController.swift` is over 500 lines; this is the single approved, localized addition within `scrubCommentsForPopupSuppression(in:)`.

Locate this block:

swift

```swift
`if annot.type == "Highlight" {
    // 1. Migrate the text`

```

Replace it with:

swift

```swift
`if annot.type == "Highlight" {
    // PDFKit ignores the fitz-generated appearance stream and renders
    // highlights more saturated than PDF-XChange Viewer and Chromium-based
    // browsers. This affects in-memory display only; Anima never saves
    // through PDFKit, so the persisted PDF annotation remains unchanged.
    annot.color = AnnotationManager.pdfKitDisplayHighlightColor
    // 1. Migrate the text`

```

## Verification checklist

1.  Build and run in Xcode with the original `data/input.pdf`.
2.  Confirm existing highlights are pale pink.
3.  Create a new highlight -- it should immediately appear pale pink.
4.  Click a highlight to emphasize it, then click again to clear emphasis -- it should restore to pale pink.
5.  Quit and reopen the PDF in Anima -- new and existing highlights should remain pale pink.
6.  Open the same file in PDF-XChange Viewer or Chrome -- persisted highlights should retain their usual appearance.
7.  Run the existing suites before committing:
    -   `make test`
    -   Xcode: Cmd+U

User:
Verification checklist: everything ok!

Wow, that was quite a ride. How does you context look like? I burned quite some points on `poe.com` for this session, but it was certainly worth it. I'm fine with wrapping up the session here, which means focusing on the artefacts:

-   Let's think about where to capture the lessons learned. `README.md`? Or maybe better a dedicated `HIGHLIGHTS_IN_PDF.md` which would go into a new `doc/` folder; I would note it (with `#`) in the `manifest.lst`.
-   Some striked-through items need to go to the `HISTORY.md` (attached), please tell me what to insert and where (i.e. make a PARTIAL PATCH).
-   In `TODO.md`, I'm going to mark the whole "Highlight colors too saturated" point marked strike-through, ok?
-   For the `GOALS.md`, please draft a new "Current Session Pointer" section.

Assistant:
Denkt nach

My context is still coherent. We have a complete causal chain, not merely a successful color tweak:

1.  PDF-XChange/Chrome and Apple PDFKit render the same highlight annotation differently.
2.  The reference and fitz-generated highlights both use the same core pink, `0.4` opacity, `/Multiply`, and an appearance stream.
3.  PDF-XChange/Chrome visibly honor the appearance stream -- including its rounded geometry and alpha.
4.  Preview/PDFKit effectively renders its own highlight representation from annotation-level properties -- sharp corners, unchanged by the appearance-stream variants.
5.  Changing only annotation `/C` to `#FFE6EA` left PDF-XChange appearance unchanged but made Anima/Preview display the pale color.
6.  Therefore Anima now keeps the persisted fitz representation unchanged and applies `#FFE6EA` only to the in-memory PDFKit representation.

That is a strong, experimentally justified compatibility decision. The token cost was worthwhile.

# Documentation inventory and recommendation

## `README.md`

**Current role:** canonical architecture, contracts, operational behavior, and technical gotchas.

**Best fit for:** the settled production rule:

text

```text
`Persisted annotation representation != PDFKit in-memory display representation.`

```

This belongs in `README.md` because it is a durable architecture contract future work must not accidentally undo.

## `HISTORY.md`

**Current role:** completed work record.

**Best fit for:** what was achieved this session -- the rendering investigation and the resulting PDFKit-only display compensation.

## `TODO.md`

**Current role:** forward-looking work, with completed items struck through until transferred to `HISTORY.md`.

**Best fit for:** striking through the saturated-color investigation item now that it is resolved.

## A new `docs/HIGHLIGHTS_IN_PDF.md`

**Potential role:** preserve the complete forensic experiment: object xrefs, `/AP` hierarchy, nested Form XObjects, `/BM /Multiply`, the four specimens, and the renderer matrix.

**My recommendation: do not create it now.** It would be a documentation layer with one occupant, and it would duplicate the durable conclusion that belongs in `README.md`. The detailed terminal evidence is valuable, but it is historical investigation material rather than an ongoing subsystem guide.

If we later support multiple colors, revise annotation generation, or encounter another renderer-specific issue, then a dedicated `docs/PDF_RENDERING_COMPATIBILITY.md` could earn its place. At that point it would be a living compatibility note rather than an archive of one investigation.

So I recommend:

-   concise durable contract in `README.md`;
-   accomplishment and key evidence in `HISTORY.md`;
-   no new folder or manifest entry.

That is the smallest documentation set that preserves what future-us needs.

* * *

# `TODO.md`

Yes -- strike through the whole "Highlight colors too saturated" item. This is complete, not merely investigated.

⚠️ **PARTIAL PATCH - NOT A DROP-IN REPLACEMENT**

Replace the existing bullet beginning:

markdown

```markdown
`- **Highlight colors too saturated (Apple renderers).**`

```

with this one-line completed item:

markdown

```markdown
`- ~~**Highlight colors too saturated (Apple renderers).** Resolved 2026-07-13: PDF-XChange/Chromium render fitz's appearance stream, while PDFKit renders highlight annotations from their high-level properties and appeared more saturated. Persisted fitz color/opacity remain unchanged; Anima applies a PDFKit-only in-memory display color (`#FFE6EA`) to loaded and newly created highlights. Verified in Anima, PDF-XChange Viewer, Chrome, Preview, and X-Ray mode.~~`

```

This makes the resolution understandable while it remains temporarily in the forward-looking file. At the end of the session, it should move into `HISTORY.md` and disappear from `TODO.md`.

* * *

# `HISTORY.md`

I recommend a new top-level section directly **after `## Highlight Workflow`** and before `## Sidebar (Comment Cards)`.

⚠️ **PARTIAL PATCH - NOT A DROP-IN REPLACEMENT**

Insert:

markdown

```markdown
`## Highlight Rendering Compatibility
- Resolved Apple PDFKit highlight saturation mismatch (2026-07-13). PDF-XChange Viewer and Chromium-based renderers honor fitz's generated normal appearance stream, while Preview/PDFKit render markup highlights from high-level annotation properties and showed the same stored pink more saturated. Controlled PDF variants confirmed that changing only annotation `/C` leaves PDF-XChange/Chrome appearance unchanged while changing Anima/Preview display.
- Added PDFKit-only in-memory display compensation: persisted fitz annotations retain the existing pink `[1.0, 0.75, 0.80]`, opacity `0.4`, and fitz-generated appearance stream; Anima uses pale `#FFE6EA` for loaded and newly created in-memory PDFKit highlights. This preserves the existing on-disk and downstream annotation contract while matching the trusted PDF-XChange/Chrome visual appearance in Anima.
- Verified existing highlights, newly created highlights, post-emphasis restoration, reopen behavior, PDF-XChange/Chrome rendering, and X-Ray mode.`

```

I would **not** add the low-level xref object chain to `HISTORY.md`. It is useful evidence, but too detailed for the completed-work record. The entries above preserve the result, causal distinction, and reason not to "simplify" the two-color arrangement later.

* * *

# `README.md`

I recommend inserting a concise new subsection under `## Technical Notes`, immediately **before `### Appearance Stream Caveat`**.

That location is appropriate because the current caveat already discusses fitz appearance-stream regeneration. The new note explains why Anima intentionally has a persisted color and a different in-memory display color.

⚠️ **PARTIAL PATCH - NOT A DROP-IN REPLACEMENT**

Insert:

markdown

```markdown
`### Highlight Rendering Compatibility
PDF-XChange Viewer and Chromium-based PDF renderers honor fitz's generated highlight appearance stream, while Apple PDFKit renders markup highlights from their high-level annotation properties and displays the same stored pink more saturated. Anima therefore deliberately maintains two representations:

- **Persisted PDF representation:** `anima_helper.py` writes the established pink `[1.0, 0.75, 0.80]` at opacity `0.4`; fitz generates the corresponding appearance stream. This remains the compatibility contract for PDF-XChange Viewer, browsers, and the downstream `pdf-annotations` workflow.
- **In-memory PDFKit display representation:** after loading, Anima changes highlight `PDFAnnotation.color` to pale `#FFE6EA`; newly created in-memory annotations use the same display color immediately. Anima never saves through PDFKit, so this display-only override does not modify the PDF file.
Do not collapse these values into one shared constant without re-running the cross-renderer comparison. The distinction is intentional renderer compatibility, not a persistence mismatch.`

```

This is the one location where I think the explicit "do not collapse" warning earns its space. Someone seeing two colors later may reasonably think it is duplication, when it is actually a tested compatibility contract.

* * *

# `GOALS.md` -- draft Current Session Pointer

Replace the entire current `## 📍 Current Session Pointer` content -- from its first bold `**Where we are:**` through the sentence immediately before `## 🎯 Strategic vision` -- with:

markdown

```markdown
`**Where we are:** Reader-first recovery is underway. The Apple/PDFKit highlight-color trust blocker is closed (2026-07-13): fitz continues to persist the established annotation representation for PDF-XChange/Chromium compatibility, while Anima applies a pale `#FFE6EA` color only to PDFKit's in-memory highlights. Verified for existing and newly created highlights, reopen, emphasis restoration, external rendering, and X-Ray mode. The remaining test gaps are consciously parked; the recorded baseline remains 18 green tests (11 Python + 7 Swift).
**What's next (in order):**
1. Civilize launch and resizing: main-window frame persistence plus split-divider persistence/holding behavior. See `TODO.md` -> UX Priorities.
2. Reader navigation: retain a sensible document handle in the window caption, add current-page display there, then add goto page.
3. Investigate the smallest useful native PDFKit document-search interaction before designing custom search UI.
4. Return to the parked Swift/Python test gaps after the core reader loop feels pleasant enough for daily use.
Tabs remain deferred; separate `open -n` instances are the accepted multi-document workflow for now.`

```

## Why I reordered it this way

This formally records the decision you made during the session:

-   test hardening is not rejected;
-   it is temporarily subordinated to making Anima a reader you want to open;
-   tabs are not a current blocker because `open -n` is sufficient for the present workflow;
-   navigation has a deliberately small first shape, rather than immediately becoming a status-bar or tab architecture project.

* * *

## Suggested wrap-up order

1.  Update `README.md` with the durable compatibility contract.
2.  Strike the completed `TODO.md` item.
3.  Insert the `HISTORY.md` section.
4.  Replace the `GOALS.md` Current Session Pointer.
5.  Review `git diff`.
6.  Commit the code and documentation together.
7.  Before the commit, run:
    -   `make test`
    -   Xcode Cmd+U

You already verified the manual behavior. The test run is now the final regression confirmation before this excellent recovery milestone becomes a clean rollback point.

User:
Agreed with not having the doc.

Regarding the `HISTORY.md`, per the protocol of how to migrate stuff to the file, we shouldn't refer to the highlighting yet. That's to be done in the _next_ session, when we turn to the item we just marked as strike-through.

What we need to do is to move the _old_ ticked-off items:

pgsql

```pgsql
`- ~~Coordinate conversion: y-flip math for known page heights and points.~~
- ~~QuadPoints construction: verify PDFKit-space quad geometry.~~`

```

Could you please provide a PARTIAL PATCH and tell me where to put it in the `HISTORY.md`?

Assistant:
Denkt nach

You are right -- the new highlight-color work should remain only as a struck-through item in `TODO.md` for now. It moves to `HISTORY.md` next session, when we deliberately process that completed item.

For the two old testing items, there is **no `HISTORY.md` insertion needed**: they have already been migrated there.

## Finding

In `HISTORY.md`, under:

markdown

```markdown
`## Testing
### Swift (Swift Testing) -- 7 tests passing`

```

these entries already record the completed TODO items:

markdown

```markdown
`- `testFitzQuadYFlip` -- pins the PDFKit→fitz y-flip contract (known  page/rect, round-trip identity, non-standard page height, x unaffected)
  (2026-07-11)
- `testQuadPointsConstruction` -- pins QuadPoints corner order and count  (single rect, multi-rect flattening, degenerate zero-width/height rects)
  (2026-07-11)`

```

They correspond directly to:

markdown

```markdown
`- ~~Coordinate conversion: y-flip math for known page heights and points.~~
- ~~QuadPoints construction: verify PDFKit-space quad geometry.~~`

```

So adding them again would duplicate the historical record.

## `TODO.md`

⚠️ **PARTIAL PATCH - NOT A DROP-IN REPLACEMENT**

Under `## Testing` -> `### Swift -- remaining`, delete these two lines:

markdown

```markdown
`- ~~Coordinate conversion: y-flip math for known page heights and points.~~
- ~~QuadPoints construction: verify PDFKit-space quad geometry.~~`

```

Then that section should begin:

markdown

```markdown
`### Swift -- remaining
- Integration: FitzBridge round-trip against test PDF (requires venv).
- Cross-page selection: pin the page-scoped behavior -- only first-page lines produce quads, second-page lines are dropped (intended: highlights are per-page; continuation via `link` comment convention).`

```

No `HISTORY.md` change is required for those two items.

User:
What do you think is better:

1.  strike-through a ticked-off item in `TODO.md`, _do not_ add it to `HISTORY.md`
2.  ..., _and do_ add it to `HISTORY.md`

And what do our artefacts tell us how to do it?

Assistant:
Denkt nach

**Option 2 is the intended protocol:**

1.  Strike through the completed item in `TODO.md` while it remains there during the active session.
2.  At session wrap-up, add its completed-work record to `HISTORY.md`.
3.  Then remove the struck-through item from `TODO.md`.

## What the project artifacts say

### `TODO.md`

Its charter explicitly says:

> "Completed items are struck through ... until they move to `HISTORY.md` ... at session end."

That establishes the temporary state: strikethrough is not the final archive; it is the in-session marker.

### `HISTORY.md`

Its opening says:

> "`TODO.md` stays forward-looking. Completed `TODO.md` items move here."

That establishes the final state: once recorded historically, the task should no longer remain in `TODO.md`.

### `LLM_INSTRUCTIONS.md`

Its whole-session workflow says to:

-   update `TODO.md`;
-   "move tasks from `GOALS.md` and `TODO.md` to `HISTORY.md`."

So all three artifacts agree: **option 2**.

## Why I previously said no `HISTORY.md` patch was needed

Not because option 1 is the protocol. Rather, those exact two test items have **already been added to `HISTORY.md`**:

markdown

```markdown
`- `testFitzQuadYFlip` ...
- `testQuadPointsConstruction` ...`

```

So their historical migration was apparently completed earlier, but the final cleanup step -- removing the now-duplicated struck-through entries from `TODO.md` -- was missed.

The correct action for those two old items is therefore:

-   **Do not add them again** to `HISTORY.md`, because that would create duplicate historical entries.
-   **Remove them now** from `TODO.md`, because their migration is already complete.

For today's highlight-color item, we follow the normal process:

-   now: strike it through in `TODO.md`;
-   next session, when we intentionally process it: write the `HISTORY.md` entry;
-   then: remove it from `TODO.md`.

User:
Hmm, there is a problem with that approach. The original idea to have the strike-through is that `TODO.md` is always shared in the initial `filesdump.txt`, whereas the `HISTORY.md` is not. I'd like a new session to know what we did in the last session, so the strike-through items need to be retained in the `TODO.md`.

Assistant:
Denkt nach

You are right. My proposed cleanup would defeat the reason the filesdump includes `TODO.md` but excludes `HISTORY.md`.

A fresh session needs to see not just what remains open, but also the **immediately preceding completed work** -- especially when that work establishes a new contract, like the PDFKit-only color compensation. `GOALS.md` gives the strategic summary, but it is too compact to preserve all recently completed task-level context.

## Revised protocol

The better workflow for this project is:

1.  **During the session:** complete an item and strike it through in `TODO.md`.
2.  **At the session's end:** leave that struck-through item in `TODO.md`.
3.  **During a later session:** once the completed item has served as handover context and is no longer needed in the normal filesdump, migrate it to `HISTORY.md`.
4.  **Only then:** remove it from `TODO.md`.

So the answer is a modified **option 2**:

-   Yes, completed work ultimately belongs in `HISTORY.md`.
-   But no, it should **not** necessarily be moved there at the same session's end.
-   The strike-through is a deliberate, temporary rolling handover record.

That matches your actual need better than the literal wording currently in the files.

## What the artifacts currently say

There is a genuine mismatch between stated process and intended workflow:

-   `TODO.md` says completed entries remain struck through "until they move to `HISTORY.md` ... at session end."
-   `HISTORY.md` says completed TODO items move there.
-   `LLM_INSTRUCTIONS.md` says to move tasks from `TODO.md` to `HISTORY.md` at session end.

Those statements prescribe immediate migration.

But the actual dump structure and your stated purpose prescribe **delayed migration**: retain struck-through work in `TODO.md` for the next session's context.

I think the artifacts should be corrected, eventually, to say something like:

> Completed items are struck through and retained through at least the next session as a compact handover record. Move them to `HISTORY.md` and remove them from `TODO.md` once they are no longer useful in the standard session context.

That is a process-documentation change, so I would discuss and get explicit approval before drafting edits to `TODO.md` and `LLM_INSTRUCTIONS.md`.

## Consequence for the two old test items

The two completed Swift test items should **remain struck through in `TODO.md` now**, even though their accomplishments are already recorded in `HISTORY.md`.

They still tell a fresh session:

-   the coordinate and QuadPoints test gap was just closed;
-   the remaining testing scope starts after those two items;
-   the current tests-first push stopped deliberately after those wins.

The same applies to today's color item: strike it through in `TODO.md`, retain it there for the next session, and do not add it to `HISTORY.md` yet.

My earlier recommendation to remove the two old items was therefore wrong for the filesdump-as-handover workflow.

User:
I'd like to push back a bit on your final verdict. Here is what I'm going to do:

-   Update `HISTORY.md` with the info gleaned from the topics which are marked strike-through. These would have been the two tests, and (differing from the protocol) I've already had that in the `HISTORY.md`. In a default case I would have to add the info.
-   Remove the strike-through items (the 2 tests)
-   Update the highlighting topic in the `TODO.md` with relevant information and use strike-through to mark it as done.

At the end of the next session, the strike-through highlight topic will be reflected in the `HISTORY.md` and removed from the `TODO.md`.

For `HISTORY.md` I suggest this preamble:

applescript

```applescript
`# History
- All notable accomplishments in the project, organized by feature area.
- This file serves as the historical record -- `TODO.md` stays forward-looking.
- At the end of a session, items from `TODO.md` that are marked strike-through (i.e. done items from the _previous_ sessions) are moved here.
- New entries carry a date; entries before 2026-07-11 predate that convention.`

```

Please draft

1.  a new "Charter" paragraph for `TODO.md`.
2.  a new "Workflow for the Whole Session (CRITICAL)" for \`LLM\_INSTRUCTIONS.md\`\`

Assistant:
Denkt nach

Your revised workflow is better than my prior conclusion. It preserves both purposes cleanly:

-   `TODO.md` carries the immediate handover context from the just-finished session.
-   `HISTORY.md` is the durable archive, updated one session later.
-   A fresh filesdump shows what was recently completed without requiring `HISTORY.md`.
-   Tasks do not linger indefinitely because the following session performs the migration.

Your proposed `HISTORY.md` preamble expresses that well.

## 1\. Draft replacement Charter paragraph for `TODO.md`

Replace the existing Charter paragraph below the title with:

markdown

```markdown
`**Charter:** Forward-looking only -- concrete, startable work: tasks specified well enough that next-session-me can begin within ten minutes, plus investigation items, test specs, and scratchpad ideas awaiting promotion or deletion. Items are unordered within their theme sections; open questions are marked _Needs investigation_ in the bullet. Completed items are struck through (~~like this~~) and retained as a compact handover record for the next session, because `TODO.md` is included in the standard filesdump while `HISTORY.md` normally is not. At the end of a session, move the struck-through items that were already present at the start of that session into `HISTORY.md`, then remove them from `TODO.md`. Strategic direction, ordering, and milestones live in `GOALS.md` -- anything that needs a strategy discussion before it is actionable goes there. Architecture, contract, and settled decisions live in `README.md`.`

```

The important phrase is "already present at the start of that session." It avoids accidentally archiving work completed in the same session, before it has served its purpose as the next session's handover context.

## 2\. Draft replacement for `LLM_INSTRUCTIONS.md` -> `## Workflow for the Whole Session (CRITICAL)`

Replace the current numbered list in that section with:

markdown

```markdown
`1. **Start from the current handover.** Check `GOALS.md` and `TODO.md` -- especially the _Current Session Pointer_ in `GOALS.md` and any struck-through items in `TODO.md`. The struck-through items record what the previous session completed and may establish contracts or decisions relevant to the work now beginning. Do not skip ahead without an explicit decision.
2. **Advance the project step by step.** Follow the Discuss -> Approve -> Implement workflow from `CRITICAL_RULES.md`. Keep work proportionate, explain local ownership before modifying an existing subsystem, and do not treat parked work as implicitly abandoned.
3. **Close the previous session's handover items.** At the end of the session, move to `HISTORY.md` the struck-through `TODO.md` items that were already present when this session began, then remove those items from `TODO.md`. Do not move items completed during the current session yet; leave them struck through in `TODO.md` so they appear in the next session's standard filesdump.
4. **Record the current session's handover.** Strike through newly completed `TODO.md` items and add enough outcome or contract detail for the next session to understand what changed. Update the _Current Session Pointer_ in `GOALS.md` to state where the project now is and what comes next. Update `README.md` when the session establishes or changes a durable architecture, technical, or behavioral contract. Touch up other project documentation when necessary.`

```

This makes the one-session delay explicit, and it distinguishes three different documentation jobs:

-   `TODO.md` -- current work plus immediate prior-session handover;
-   `HISTORY.md` -- durable completed-work archive;
-   `GOALS.md` -- current strategic position and next action.

User:
GPT, what is your true assessment of the protocol? Please push back if you feel you need to. I can e.g. see why it is better to have _both_ the info of a done topic in the `TODO.md` (marked with strike-through), _and_ add something right away to `HISTORY.md`. Reason: The know-how is still fresh with regard to how the TODO was ticked-off. This knowledge is not really available anymore when dealing with the postponed moving of the TODO to the HISTORY. This is also better because we know the _date_ of the work done, see the preamble of `HISTORY.md`.

Assistant:
Denkt nach

My true assessment: **your hybrid protocol is better**.

I would revise my last draft accordingly:

1.  When an item is completed, **immediately add the historical entry to `HISTORY.md`** while the evidence, reasoning, exact scope, and date are fresh.
2.  Also leave a **concise struck-through handover entry in `TODO.md`** through the next session, because `TODO.md` is in the standard filesdump and `HISTORY.md` normally is not.
3.  At the end of the next session, remove that now-stale struck-through `TODO.md` item. It was already archived at the time of completion, so this is cleanup only.

That gives each artifact a distinct role without asking either to do a job at the wrong time:

File

Role

`TODO.md`

Current actionable work plus one-session rolling handover context.

`HISTORY.md`

Accurate, durable record written when the work is fresh.

`GOALS.md`

Compact strategic state and next priorities.

`README.md`

Durable architectural contracts and operational guidance.

## Why I would push back against delayed `HISTORY.md` migration

Your concern is exactly right. If the historical write happens a session later:

-   the date may be reconstructed imperfectly;
-   the key causal insight may be lost;
-   a future model may summarize only the task title rather than why the solution was chosen;
-   the next session may choose a different priority and never get around to the migration;
-   the process relies on someone remembering that a struck-through line is not yet historically recorded.

This highlight-color work is a particularly clear example. The immediately useful historical record is not merely:

> "Fixed highlight colors."

It is:

> "Confirmed a renderer split experimentally; retained fitz's persisted representation; applied an in-memory PDFKit-only display override; verified it across specific renderers."

That is fresh now. It would be weaker if reconstructed later from a one-line struck-through TODO bullet.

## The main risk of the hybrid protocol

The cost is duplication. A completed item exists temporarily in both:

-   `HISTORY.md` as the full durable record;
-   `TODO.md` as the short-term handover marker.

But I think this duplication is **intentional and bounded**:

-   It lasts only until the end of the next session.
-   The two entries serve different readers.
-   The `TODO.md` version should be brief and handover-oriented.
-   The `HISTORY.md` version should be complete enough to preserve the accomplishment and reasoning.

That is not wasteful duplication; it is a cache of recently completed context in the one file every fresh session sees.

## Recommended protocol

I would state it as:

text

```text
`On completion, write the durable historical record immediately.
Retain a concise struck-through TODO entry through the next session.
At the end of that next session, remove the already-archived TODO entry.`

```

One additional guardrail:

> Do not use the struck-through TODO line as the sole source for the later historical entry. The historical entry is written in the session that completed the work.

That resolves the freshness problem completely.

## Revised `TODO.md` charter

I would prefer this over my previous draft:

markdown

```markdown
`**Charter:** Forward-looking only -- concrete, startable work: tasks specified well enough that next-session-me can begin within ten minutes, plus investigation items, test specs, and scratchpad ideas awaiting promotion or deletion. Items are unordered within their theme sections; open questions are marked _Needs investigation_ in the bullet. When an item is completed, record its durable outcome in `HISTORY.md` during the same session while the evidence and rationale are fresh, then strike it through in `TODO.md` with a concise handover note. Retain struck-through items through the next session because `TODO.md` is included in the standard filesdump while `HISTORY.md` normally is not; at the end of that next session, remove the already-archived items from `TODO.md`. Strategic direction, ordering, and milestones live in `GOALS.md` -- anything that needs a strategy discussion before it is actionable goes there. Architecture, contract, and settled decisions live in `README.md`.`

```

## Revised whole-session workflow for `LLM_INSTRUCTIONS.md`

markdown

```markdown
`1. **Start from the current handover.** Check `GOALS.md` and `TODO.md` -- especially the _Current Session Pointer_ in `GOALS.md` and any struck-through items in `TODO.md`. The struck-through items summarize what the previous session completed and may establish contracts or decisions relevant to the work now beginning. Do not skip ahead without an explicit decision.
2. **Advance the project step by step.** Follow the Discuss -> Approve -> Implement workflow from `CRITICAL_RULES.md`. Keep work proportionate, explain local ownership before modifying an existing subsystem, and do not treat parked work as implicitly abandoned.
3. **Record completed work while it is fresh.** During the current session, add a dated entry to `HISTORY.md` for each completed item that merits a durable record. Strike through the corresponding `TODO.md` item and add a concise outcome or handover note. Update `README.md` when the session establishes or changes a durable architecture, technical, or behavioral contract.
4. **Expire the previous handover.** At the end of the session, remove struck-through `TODO.md` items that were already present when the session began, provided their durable record is already in `HISTORY.md`. Leave items completed during the current session struck through in `TODO.md` so they appear in the next session's standard filesdump.
5. **Update project position.** Update the _Current Session Pointer_ in `GOALS.md` to state where the project now is and what comes next. Touch up other project documentation when necessary.`

```

I think this is the best version because it keeps the historical record accurate, gives a new session the immediate context it needs, and has a simple cleanup rule that does not depend on reconstructing old work later.

User:
Do we need to touch the `README.md` in this session?

Assistant:
**Yes, I recommend updating `README.md` in this session.**

This session established a durable architectural contract, not merely a UX preference:

-   fitz's persisted annotation representation remains the compatibility contract for PDF-XChange, Chrome/Edge, and downstream extraction;
-   PDFKit renders the same annotation differently;
-   Anima deliberately applies a different color only to PDFKit's **in-memory** annotations;
-   the app must not save that adjusted PDFKit representation back to disk.

That is precisely the kind of knowledge `README.md` is intended to retain. Without it, a future cleanup could see `highlightColor` and `pdfKitDisplayHighlightColor`, decide they are redundant, and "simplify" away the compatibility fix.

The durable note should be concise. The full experiment details belong in `HISTORY.md`, not `README.md`.

I would add the `### Highlight Rendering Compatibility` section proposed earlier under `## Technical Notes`, immediately before `### Appearance Stream Caveat`. Its key warning -- do not collapse the two colors into one -- is justified by the experimental evidence we gathered today.

User:
Ah, sorry, I forgot that we had already added it, thanks.

Well, GPT, this concludes this session! It was a pleasure working with you! A lot of good "flow", true collaboration (you as senior dev, me as tester / user / product manager). What also made a difference was your inventory at the beginning of this session. All in all, I am in a _much_ better mood than at the beginning of this session -- thank you, GPT!

Assistant:
Thank you, Frank. This was an excellent session -- not just because we resolved a real blocker, but because we restored a workable relationship with the project.

We now have:

-   a reader-first recovery direction;
-   a clear, user-action-based architecture map;
-   an explicit local-ownership collaboration rule ready for `LLM_INSTRUCTIONS.md`;
-   a tested explanation for the renderer discrepancy;
-   a minimal compatibility solution that preserves the on-disk PDF contract while giving Anima the pale highlight appearance you want;
-   verification across Anima, Preview, Chrome, PDF-XChange Viewer, reopening, emphasis restoration, new highlights, and X-Ray mode;
-   a clearer documentation/handover protocol.

Most importantly, Anima has moved from "opaque project I dread reopening" toward "reader I can trust to get closer to daily use." That is a substantial recovery milestone.

For the final local wrap-up, the remaining mechanical steps are the documentation edits you have planned, `git diff`, the already-passing verification state, and then a commit with a message along the lines of:

text

```text
`Compensate PDFKit highlight rendering in memory`

```

Thank you for the rigorous testing, the good pushback, and the product judgment throughout. It was a pleasure collaborating with you.
