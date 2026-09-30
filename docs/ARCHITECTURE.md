# Swift Scribe architecture

## Editor: one canvas per page, in a UIKit page stack

We chose this in Phase 2 (M1) after timing three designs against the same fixtures.

### The three designs

- **A: a PKCanvasView per page.** Each canvas lives in a zooming UIScrollView page stack. Only the visible pages ±1 have a canvas, and the canvas is re-scaled after each pinch.
- **B: PDFView with a PKCanvasView overlay per page.** Templates are drawn as PDF pages.
- **C: the v1 single canvas, fixed.** It keeps one canvas but removes the per-stroke copy, moves saves off the main thread and stores ink per page.

### Measurements

Each design was built in its own worktree against a shared harness. The timings were then re-run one design at a time on a quiet machine.

- **Environment:** iPad Pro 11-inch (M5) simulator, iOS 27.0, Debug build. Apple M4 Mac mini, load average 6–9.
- **Method:** XCTest in-process timing (medians), plus UI tests with real simulator touches.
- **Fixtures:** "heavy" is 100 Letter pages × 500 strokes. "Dense" has a 1,000-stroke page 0. "pdf300" is a generated 300-page PDF.

| Measure (simulator) | A: per-page canvases | B: PDFKit overlays | C: fixed single canvas |
|---|---|---|---|
| Main thread at stroke end, 1,000-stroke page, 100-page notebook | **0.12 ms** | 0.13 ms | 0.03 ms |
| Same, 10-page notebook (flatness) | 0.13 ms | 0.11 ms | 0.01 ms |
| Autosave, main-thread part (heavy) | **0.13 ms** | 0.15 ms | 4.5 ms |
| Insert page at start (heavy) | **3.1 ms** | 14.7 ms | 114 ms |
| Move page 0→50 (heavy) | **4.0 ms** | 19.5 ms | 107 ms |
| Delete page (heavy) | **0.6 ms** | 0.6 ms | 104 ms |
| Open heavy: longest synchronous block | 15 ms | 18 ms | 9 ms |
| Open heavy: to first ink | **49 ms** | 75 ms | 629 ms |
| Open pdf300: to first ink | 10 ms | 34 ms | 12 ms |
| Peak footprint scrolling heavy / at 5× | 356 / 411 MB | 283 / 210 MB | 531 / 473 MB |
| Peak footprint scrolling pdf300 / at 5× | 398 / 444 MB | 348 / 371 MB | 519 / 480 MB |
| Ink at 1×, 2.5×, 5× and after a pinch | re-rendered sharp | sharp only with a counter-scaled canvas hack | re-rendered sharp |
| Undo across pages (real touches), page-op undo | pass | pass (needs a canvas undo proxy) | pass (bridges PencilKit's native entries) |
| Finger scrolls / Pencil draws / finger draws with "any input" | pass | pass | pass |
| Zoom range, landscape | 0.54× (whole page) to 5× | 0.50× to 5× | 0.55× to 5× |

Notes on the measurements:

- **Hitches.** On the simulator, `XCTOSSignpostMetric.scrollingAndDecelerationMetric` reports only the swipe's duration (about 2.56 s for every design), and `XCTHitchMetric` records nothing. Hitch figures need a device. For v2 there is a debug frame-pacing probe as a simulator proxy (see below).
- **Memory.** The simulator's `phys_footprint` does not include GPU memory. B's lower footprint comes from PDFKit tiling well, not from ink.

### Decision

**A.** It is the only design that meets every main-thread target:

- page operations under 5 ms;
- first ink under 100 ms;
- autosave work on the main thread under 2 ms.

It also keeps full control of layout, zoom and the desk.

- **C was rejected.** Every page operation and first render is O(notebook), and the single canvas exposes every stroke of the notebook to accessibility, which can stall VoiceOver.
- **B was rejected.** It has to reach into PDFKit's private scroll view, and PDFKit only transform-scales overlays, so sharp ink needs a counter-scaling workaround that re-renders only after the zoom settles. Its pinch can overshoot the maximum zoom, and its page operations take 15–20 ms.

A's one weakness is simulator footprint at 5×. We addressed it with the measures below and need to confirm it on a device.

## How the editor works

- **`PageStackController`** is a UIScrollView of page slots laid out in page points (`PageStackLayout`).
  - Slot views exist only for the visible pages ±1, so page operations cost O(visible pages), not O(notebook).
  - Each slot has a paper-coloured view with a hairline edge.
  - Its background is drawn as 256-point `CATiledLayer` chunks, created only within half a viewport of the screen. One tiled view per page grew to about 900 MB at 5× in the spike.
- **Canvases.** Each visible page ±1 has a `PageCanvasView` (a PKCanvasView).
  - Its drawing is in page-local points.
  - Its frame is a viewport-sized window onto the page, so PencilKit only backs what can be seen, even at 5×.
  - At most three canvases are pooled for reuse.
- **Zoom.**
  - During a pinch, the content view is magnified.
  - When the pinch ends, the zoom is *baked*: the layout is rebuilt at the new scale, and each canvas's `zoomScale` is set so PencilKit re-renders the ink sharply.
  - Pages keep their true relative size: 1× fits the widest page to the window, so an A5 page between Letter pages is smaller. Fit Width (⌘0) and Fit Page (⌘9) fit the current page instead, which enlarges a smaller page.
  - The minimum zoom shows a whole page, and the maximum is 5×.
- **Input.** The scroll view's pan and pinch accept direct touches only, so the Pencil never scrolls. With "Pencil and finger", scrolling takes two fingers.
- **Ink stays on its page.** Each page slot clips its canvas, and every renderer (thumbnails, covers, OCR, export) draws only the page rectangle. Ink that runs past the edge is kept in the drawing but never shown. Nothing is masked at stroke end: doing that copied every stroke on the page per stroke, and clipped lasso-moved ink for good.
- **Ink in memory.** Pages with a live canvas are pinned, so the ink a stroke replaces is always there for its undo. Prefetches for pages near the viewport are cancelled when the viewport moves on; a load a canvas is waiting for never is. Ink files are read and decoded off the package actor, in parallel, at the requesting task's priority.
- **Undo.**
  - `NotebookDocument` owns one `UndoManager`, and every stroke and page operation registers against the document, never against a view. Undo therefore survives canvas recycling.
  - Canvases return a `CanvasUndoProxy` as their undo manager. PencilKit wraps each stroke's registration in its own group and calls private grouping API. The proxy absorbs that, and forwards undo and redo (from the tool picker, ⌘Z or gestures) to the document's stack.
  - Filtering those registrations out on the shared stack instead leaves an empty undo step per stroke, and deferring the group crashes.
- **Tool picker.** A hidden first-responder anchor keeps one system `PKToolPicker` visible for every page (`stateAutosaveName` is set). New and reused canvases take the picker's current tool. Undo and redo leave the top bar while the picker is showing.
- **Stroke end.** The main thread does four things only:
  1. copies the page's drawing into the document;
  2. bumps the page's version;
  3. registers undo;
  4. schedules a save.

  The notebook's modification date is applied at save time, so a stroke never touches the observed manifest.

## One document per notebook

- `DocumentRegistry` hands out one `NotebookDocument` per notebook across windows. An open still in progress is shared, so two windows opening the same notebook at once get the same document.
- Library changes (favourite, trash, folder, rename, cover) go through the open document. A change written to a closed notebook's files while a document is being opened is applied to that document too, so its first save can't revert it.
- In the editor, ⌘N adds a page. The library's ⌘N and the library itself are disabled and hidden from VoiceOver while the editor covers them.

## Saving and closing

- Saves are debounced (1.2 s), but a pending save always starts within 5 s of the first unsaved edit, and turning pages never postpones one. Pending and retry saves hold their document, so a change made as the editor closes (a recording stopping, an import landing) is still written.
- Closing stops any recording, waits for imports, then saves. If saving keeps failing, the editor stays open and asks: try again, keep editing, or close anyway. Closing anyway keeps the document alive in the registry and retrying in the background; reopening the notebook picks up the same document.
- Saves only update the library index when something the library shows changed (title, pages, cover, favourite, trash, folder). Ink-only saves don't; closing indexes everything. The index record is only written, and SwiftData only saved, when a field actually differs.

## Storage v2

Each notebook is a package at `Application Support/Library/<uuid>.scribe/`:

```
manifest.json          schemaVersion, title, cover, defaults, pages, recordings, library state
manifest.prev.json     the previous manifest, the fallback if the latest can't be read
ink/<pageID>.pkdrawing page-local ink, one file per page
assets/                imported PDFs, photos, audio
thumbs/                page thumbnails keyed by ink hash and page appearance
text/<pageID>.txt      recognised handwriting and PDF text, stamped with the ink hash it came from
```

### Writing

- `NotebookPackage` is an actor that does all file IO.
- A save writes only the dirty pages, each atomically, and writes the manifest last.
- A failed save keeps the pages dirty and retries with backoff (1 s, doubling, capped at 60 s), and shows a non-blocking notice.
- When the app goes to the background, pending writes finish under `beginBackgroundTask`.

### Reading and recovery

- **Tolerant decoding.** Unknown keys, unknown enum values and malformed fields never fail a manifest. Their raw JSON is written back unless the app changed them. Pages this build can't read are kept in place, and a newer schema opens read-only.
- **Quarantine.** A file that fails to decode is renamed to `.corrupt` and never overwritten. PencilKit returns an empty drawing for data without its `wrd\xf0` header instead of failing, so that case counts as damage too.
- **Crash between ink and manifest writes.** Ink files newer than the manifest are recovered as pages, and a stale hash is corrected.
- **Newer schemas.** The schema version is read first. A newer manifest opens read-only even if its page list has a shape this build can't read, and is never quarantined or rebuilt. The library hides changes for read-only notebooks.
- **Nested fields.** Unreadable values inside the cover, defaults, library state and recordings are written back as they were unless the app changed them, like top-level ones.

### Garbage collection and deletes

- On close, after a successful save, files no page or asset reference uses are removed. An asset is kept if its name appears anywhere in the manifest, including fields this build can't read.
- Nothing but stale thumbnails is removed while a damaged manifest is set aside, or after a manifest was rebuilt from ink, since the damaged copy may be all that lists those files.
- Background jobs (OCR text, thumbnails) never recreate a deleted package.
- Deleting permanently renames the package into `Deleting/` and removes it in the background; leftovers are swept at launch.

### Library index

- SwiftData holds the library index (`LibraryIndexSchemaV1`): records, folders, search text and cover fields.
- It is rebuilt from the manifests and `folders.json` whenever they are newer.
- An index that can't be opened is set aside and rebuilt; there is no `fatalError` at launch.

### v1 migration

`V1Migrator` is explicit, idempotent and resumable:

1. It reads a *copy* of the v1 SwiftData store.
2. It builds each notebook in `<id>.migrating`: ink is split into pages with v1's layout maths and converted to page-local points (scaled by page width / 800), and assets are copied.
3. It writes the manifest, then renames the folder into place.
4. When every notebook has succeeded, it moves the v1 files to `Backups/v1/` unchanged.

Migration tests run against `NotesAppTests/Fixtures/v1-library.json`, a library written by the real v1 code before it was removed. Migrated notebooks get first-page covers, as their v1 cards showed the first page, folders keep v1's A to Z order and a distinct cloth each, and their handwriting is recognised page by page in the background after launch.

Folders keep a distinct cloth each; v1 purple becomes Plum. The migrator and its tests stay until at least the first stable public release.

A rerun skips finished notebooks, including ones the user has deleted since (the log in `Library/migration-v1.json` remembers them), and restarts half-written ones. If the v1 database exists but can't be read, nothing is migrated or archived and the next launch tries again. Failures are shown in an alert at launch and in Settings.

## Background work and caches

- **Off the main thread:**
  - thumbnails (`PageThumbnailer`, cached in `thumbs/`);
  - covers (`CoverRenderer` and `CoverCache`: an 80 MB memory LRU plus `Caches/Covers`, kept under 150 MB). Renders stop when their cell scrolls away, disk hits are decoded before they reach the main thread, and the New Notebook preview never touches either cache;
  - PDF export (`NotebookExporter`): streamed to disk a page at a time, with progress; cancelling or dismissing the sheet stops it;
  - handwriting OCR (`HandwritingIndexer`, per page by ink hash). Rendering and Vision run off the indexer actor so an edit's cancel gets through, and a page already being read is never read twice;
  - library search: debounced, matched by a SwiftData predicate on a background context, then each matching notebook's per-page text is read for page-level results (`PageSearch`) that open the editor at that page. Results refresh whenever the index is saved;
  - PDF parsing on import.
- **Tile culling.** Paper templates draw only the rules that reach the context's clip (`TemplateRules`), so a 512 px tile at 5× strokes its own few lines, not the page's; planner labels are cached Core Text lines. Diagonal rules are laid in short pieces on a fixed grid, because Core Graphics rasterises a long diagonal slightly differently depending on where the clip starts. `PaperParityTests` holds the original papers pixel-identical and every template equal in tiles, thumbnails and export.
- **Bounded caches:**
  - PDF documents: an LRU of 6;
  - page images: an LRU of 12;
  - thumbnails: an LRU of 120;
  - paper miniatures for the paper drawer and New Notebook: an LRU of 64;
  - loaded ink: 24 clean pages. Unsaved pages are never evicted.
- **Signposts** (`OSSignposter`, subsystem `com.owais.NotesApp`):
  - "Open to first ink", "Save", "Thumbnail", "OCR page", "Export", "Cover render", "Launch".

## v1 and v2, before and after

Same run for both columns.

- **Environment:** "Scribe Bench" iPad Pro 11-inch (M5) simulator, iOS 27.0, Debug build in Swift 6 language mode, on an Apple M4 Mac mini at load average 3–4.
- **Method:** XCTest in-process timings (`NotesAppTests/PerformanceBaselineTests`, run with `SCRIBE_PERF=1`), medians unless noted. The v1 column was measured on the v1 code before it was removed in M6; the suite now runs the v2 cases only.
- **Fixtures:** heavy is 100 Letter pages × 500 strokes with a 1,000-stroke first page for v2's stroke-end cases; typical is 20 × 400.

None of these are device numbers. Pencil latency and hitches need the device checklist.

| Measure | v1 | v2 | Target |
|---|---|---|---|
| Main thread at stroke end (heavy) | 6.0 ms (copies the whole notebook's drawing out of the single canvas) | 0.12 ms; 0.12 ms for a stroke crossing the page edge; 0.12 ms in a 10-page notebook | ≤ 0.5 ms, flat |
| Autosave, main thread (heavy) | 124 ms (serialise and write the whole notebook on the main thread); typical 31 ms | 0.48 ms per save (snapshot 0.008 ms); 1.8 ms median, 2.8 ms max when the save also updates the library index | ≤ 2 ms |
| Insert a page at the start (heavy) | 332 ms (re-maps every stroke); typical 25 ms | 1.2 ms including relayout, undoable | ≤ 5 ms |
| Move page 0→50 / delete / undo (heavy) | not measured in v1 | 0.96 / 0.45 / 0.97 ms | ≤ 5 ms |
| Open heavy: longest main-thread block | 125 ms (load and lay out, all synchronous), plus 35 ms first render | 5.8 ms | ≤ 30 ms |
| Open heavy: to first ink | ≈ 160 ms | 71 ms | ≤ 100 ms |
| Open a 300-page PDF: longest block / first ink | 14 ms (synchronous) | 5.5 ms / 28 ms | |
| Export 20 pages | 1.13 s on the main thread | 1.11 s off the main thread; longest main-thread gap 2.5 ms (the probe's resolution) | never blocks |
| OCR 3 pages | 2.6 s | 3.0 s in the background; unchanged re-run 0.3 ms | |
| Library of 500, in-app scroll at 2,400 pt/s, 6 s | not measured | 0 long frames of 360, both passes | no hitches |
| 300-page PDF, in-app scroll at 2,400 pt/s, 6 s | not measured | 0 long frames of 360, both passes | no hitches |
| Peak footprint (test process, excludes GPU) | opening heavy: 528 MB | scrolling heavy: 516 MB (baseline 365), at 5×: 520 MB; scrolling the PDF: 486 MB, at 5×: 510 MB | bounded |

"Long frame" means a frame over 1.5× the display interval, counted by the debug frame-pacing probe (`-framePacing`). Swipes driven by XCUITest add two or three long frames each from its own snapshots, so the in-app scroll is the figure to compare.

## Swift 6

All three targets build in the Swift 6 language mode with no warnings. Two things matter at runtime:

- `CATiledLayer` calls `draw(_:)` on background threads, so both tiled views mark it `nonisolated`.
- `CanvasUndoProxy` keeps its notification tokens `nonisolated(unsafe)`: they're only read again in `deinit`, when nothing else can reach them.

## Colour and accessibility

- `inkSecondary` is for decoration, large text, borders and icons only. Small labels and metadata use `textSecondary`, which keeps 7:1 on paper, desk and surface in light, dark and Increase Contrast, so anti-aliased small text still clears Apple's audit (`DesignTokenTests`).
- `AccessibilityAuditUITests` runs Apple's full audit over the empty and seeded library, search results, Recently Deleted, New Notebook, Settings, Change Cover (sheets at both ends of their scroll), the editor, the paper drawer (only its top at the large text size, where the audit misreads rows it scrolls back into view), the page navigator and Recordings, in light, dark and both with Increase Contrast (`-increaseContrast` sets the trait override), then Dynamic Type, clipping and contrast again at a large text size. A few issues are logged rather than failed: text on the system glass bars, PencilKit's tool picker handle, text behind a sheet that VoiceOver skips, unnamed contrast issues on a sheet scrolled so text sits under its glass bar, and Dynamic Type on the last row and footer of the Settings Form, which the audit flags whatever they contain (both scale fully at the largest size).
- Layouts that change with text size use `AnyLayout`, not `ViewThatFits`: the audit can't follow text across `ViewThatFits`'s two copies and reports it as partly unscaled.
- No text uses `caption2`: the audit reports it as partly unscaled, so the smallest style is `caption`.
- A button holding both text and a light image (a paper miniature, a light cloth) is read as low-contrast text, so captions sit outside their button, as a cover's meta line does, and paper colour chips are filled with their own colour.

## Known limits

- Undo keeps whole-page drawings, up to 200 steps. Memory therefore grows with the number of distinct pages edited in a session, not just with the 24-page ink cache. The fix is a stroke budget that drops the oldest steps; it should be sized from a device memory trace.
- Each library record carries its search text, so the shelf's query loads it. Moving search text into its own entity is a schema change worth making before release.
- Lasso and ruler are page-scoped in the first release: each page is its own canvas, so neither can span two pages, and ink past a page edge is hidden. v1's single canvas allowed both. Cross-page lasso is a future feature, to be built as a selection layer over the per-page canvases, not by returning to one canvas.
- ⌘F is claimed by a first-responder view in the library (the toolbar search swallows it otherwise). In the iPadOS 27 simulator under XCUITest, ⌘F never reaches the app at all while ⌘G on the same view does, so it needs a check on a device.
- Every figure above is from the simulator. The device checklist covers Pencil latency, hitches (Instruments), memory at 5× with the heavy fixture, palm rejection, and Pencil double-tap and squeeze.

