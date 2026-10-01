# Swift Scribe

**A free, open-source handwritten notes app for iPad — a Notability / GoodNotes alternative with no subscriptions, no ads, and no tracking.**

Swift Scribe is built entirely on Apple frameworks (SwiftUI, PencilKit, PDFKit, Vision, SwiftData). Your notes stay on your device.

## Features

**Writing**
- Apple Pencil handwriting with palm rejection and pressure/tilt, powered by PencilKit
- Full tool palette: pen, monoline, fountain pen, pencil, marker/highlighter, crayon, watercolor, eraser, lasso (move/copy/delete), ruler, and custom colors
- Pinch to zoom up to 5× with crisp ink and backgrounds at every zoom level
- Pages keep their true relative size; Fit Width (⌘0) and Fit Page (⌘9) enlarge a smaller page
- Undo / redo (toolbar, tool palette, ⌘Z / ⇧⌘Z), including page operations
- Hardware keyboard: arrows, space and Page Up/Down to scroll, ⌘↑/⌘↓ for the first and last page, ⌘N for a new page, ⇧⌘P for the page navigator, and ⌘Z to undo library changes too
- Choose to draw with Apple Pencil only, finger and pencil, or follow the system setting

**Notebooks & paper**
- Continuous vertically scrolling pages
- Fourteen paper templates in four families: writing (blank, narrow ruled, wide ruled, penmanship, checklist), grids (grid, engineering, dotted, isometric), planning (Cornell, day planner, week planner) and creative (music staff, storyboard)
- Paper colors: white, ivory, legal-pad yellow, kraft, sage, blush, gray, charcoal, and chalkboard, where the ink writes chalk-white
- Page sizes: US Letter, A4, A5, widescreen
- A paper drawer with real miniatures: add a page with any paper, or change a page's paper and color in place (undoable)
- New Notebook starters (Journal, Lecture, Sketchbook, Planner, Music, Plain) and Shuffle for a fresh cover; your Quick Note paper only changes when you ask
- Page navigator with thumbnails: jump, drag to reorder, insert, duplicate, delete, go to page

**PDFs & images**
- Import PDFs as new notebooks, or insert them into an existing one, and annotate them
- Insert photos as pages
- Export any notebook as a PDF from the editor or the library (vector backgrounds, PDF text stays selectable), then share or print

**Audio**
- Record lectures or meetings alongside a notebook, and play them back later

**Writing history**
- A This-week strip in the library: seven small sheets, inked on the days you wrote
- A writing calendar laid out like a printed diary; choose a day to see, and open, the exact pages you wrote
- No streaks, badges or reminders

**Organization & search**
- Cloth, Print (riso) and first-page notebook covers, changeable at any time
- Quick Note (⇧⌘N) for a new notebook with your default paper
- A daily journal: Today's page (⌘T) is printed with the date, "On this day" brings back the page from a month or a year ago, and the app reopens the notebook you left open
- Folders with spine colours, drag notebooks onto folders in the sidebar, reorder folders
- Favorites, sorting (last opened, modified, created, title), duplicate, rename
- Recently Deleted with 30-day auto-purge
- Search by title, **handwriting** (on-device OCR with Vision), and imported PDF text, with page-level results that open at the matching page

## Requirements

- Xcode 16 or later (folder-synchronized groups, Swift 6 language mode)
- iPadOS 18 or later
- Runs on iPad and on Apple silicon Macs ("Designed for iPad")

## Privacy

Swift Scribe has no accounts and no analytics. The writing history behind the week strip and calendar is a small file on your device (`Library/activity.json`) listing the days you wrote and which pages. It is never shared, and Settings › Writing History turns it off or clears it.

## Getting started

```bash
git clone https://github.com/owaisazmal/Swift-Scribe.git
```

```bash
open Swift-Scribe/NotesApp.xcodeproj
```

Select an iPad simulator and run. In the simulator you can draw with the mouse; on a device, choose **⋯ → Draw With** to switch between Apple Pencil only and finger drawing.

Run the tests with ⌘U or:

```bash
xcodebuild test -project NotesApp.xcodeproj -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
```

## Architecture

```
NotesApp/
├── App/          App entry, launch (migration, index refresh), test-only seeds and probes
├── Models/       Manifest types (NotebookManifest, NotebookPage, CoverSpec), paper types
├── Storage/      Notebook packages, tolerant manifest codec, v1 migration, SwiftData library index
├── Canvas/       Page stack (one PencilKit canvas per visible page), page rendering, undo proxy
├── Editor/       NotebookDocument (model, undo, autosave), editor chrome, navigator, recorder
├── Library/      Library views, covers, new-notebook sheet, library store, one-editor registry
├── Design/       Colour tokens, typography (Fraunces, Bricolage Grotesque), cover renderer
├── Services/     PDF export, handwriting recognition
├── Settings/     Settings and acknowledgements
└── Resources/    Bundled fonts with their licences, privacy manifest
```

Key design decisions (details and measurements in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); visual system in [docs/DESIGN.md](docs/DESIGN.md)):

- **One package per notebook.**
  - Each notebook is `Library/<id>.scribe/`: a `manifest.json`, one ink file per page in page-local points, plus assets, thumbnails and recognised text.
  - Saves write only changed pages, each atomically, and the manifest last, all off the main thread.
  - Files that can't be read are set aside as `.corrupt` and never overwritten.
- **One canvas per visible page.**
  - Pages sit in a UIKit scroll view, and only the pages on screen ±1 have a `PKCanvasView`, so work follows the page you're writing on, not the size of the notebook.
  - Zoom is re-applied to each canvas after a pinch, so ink stays sharp from a whole page up to 5×.
- **One undo history.** Strokes and page operations register against the document, not against views, so undo survives canvases being recycled.
- **One document per notebook.** Every window shares it, and closing waits for recordings, imports and the last save. If saving fails, the editor says so instead of closing.
- **The index is a cache.** SwiftData indexes the library for fast sorting and search, and can always be rebuilt from the manifests.
- **Old notebooks move across safely.** Notebooks from earlier versions are migrated on first launch, and the originals are kept in `Backups/v1`.

## Roadmap

Contributions toward any of these are very welcome:

- [ ] iCloud sync across devices
- [ ] Typed text boxes and sticky notes on pages
- [ ] Insert images/stickers as movable objects (not just full pages)
- [ ] Audio playback synced to strokes (Notability-style replay)
- [ ] Shape recognition (draw-and-hold to snap lines, circles, rectangles)
- [ ] Split view: two notebooks side by side
- [ ] Presentation / laser pointer mode
- [ ] Outline / bookmarks, page links
- [ ] Nested folders
- [ ] Export as images, backup / restore of the whole library
- [ ] Lasso and ruler across pages (both work within a page today)
- [ ] Localization

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go in [GitHub Issues](https://github.com/owaisazmal/Swift-Scribe/issues).

## License

Swift Scribe is released under the [MIT License](LICENSE).
