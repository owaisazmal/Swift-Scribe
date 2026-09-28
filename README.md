# Swift Scribe

**A free, open-source handwritten notes app for iPad and iPhone — a Notability / GoodNotes alternative with no subscriptions, no ads, and no tracking.**

Swift Scribe is built entirely on Apple frameworks (SwiftUI, PencilKit, PDFKit, Vision, SwiftData). Your notes stay on your device.

## Features

**Writing**
- Apple Pencil handwriting with palm rejection and pressure/tilt, powered by PencilKit
- Full tool palette: pen, monoline, fountain pen, pencil, marker/highlighter, crayon, watercolor, eraser, lasso (move/copy/delete), ruler, and custom colors
- Pinch to zoom up to 5× with crisp ink and backgrounds at every zoom level
- Undo / redo (toolbar, tool palette, ⌘Z / ⇧⌘Z)
- Choose to draw with Apple Pencil only, finger and pencil, or follow the system setting

**Notebooks & paper**
- Continuous vertically scrolling pages
- Paper templates: blank, narrow ruled, wide ruled, grid, dotted, Cornell, music staff
- Paper colors: white, ivory, legal-pad yellow, gray, charcoal
- Page sizes: US Letter, A4, A5, widescreen
- Page navigator with thumbnails: jump, drag to reorder, insert, duplicate, delete
- Change template or paper color per page

**PDFs & images**
- Import PDFs as new notebooks, or insert them into an existing one, and annotate them
- Insert photos as pages
- Export any notebook as a PDF (vector backgrounds, PDF text stays selectable)

**Audio**
- Record lectures or meetings alongside a notebook, and play them back later

**Organization & search**
- Folders with colors, drag notebooks onto folders in the sidebar
- Favorites, sorting (modified, created, title), duplicate, rename
- Recently Deleted with 30-day auto-purge
- Search by title, **handwriting** (on-device OCR with Vision), and imported PDF text

## Requirements

- Xcode 16 or later (project uses folder-synchronized groups)
- iOS / iPadOS 17.4 or later
- Runs on iPad, iPhone, and Apple silicon Macs ("Designed for iPad")

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
├── App/          App entry point and SwiftData container
├── Models/       Notebook, Folder (SwiftData) and PageSpec / paper types
├── Storage/      On-disk layout for drawings, imported PDFs, images, audio, thumbnails
├── Canvas/       Page layout math, paper/PDF rendering, the PencilKit canvas controller
├── Editor/       Notebook editor UI, page navigator, audio recorder
├── Library/      Sidebar, notebook grid, new-notebook sheet, library actions
├── Services/     PDF import/export and handwriting search indexing
└── Settings/     Settings screen
```

Key design decisions:

- **One canvas per notebook.** Each notebook is a single `PKCanvasView` whose strokes live in a shared coordinate space. Pages are stacked vertically at a fixed width of 800 units (`NotebookLayout`). This gives native zooming, scrolling, and undo for free.
- **Backgrounds live under the ink.** Paper templates and PDF pages are drawn into `CATiledLayer`-backed views inserted beneath the canvas content, so they re-render sharply as you zoom. PDFs are drawn with Core Graphics (`CGPDFPage`), which is safe on the tiled layer's background threads.
- **Page operations move strokes.** Inserting, deleting, reordering, or duplicating pages goes through `PageRemapper`, which assigns strokes to pages and translates them to their new position. This is covered by unit tests.
- **Metadata in SwiftData, content in files.** `Notebook` stores title, folder, page specs, etc. Ink (`drawing.pkdrawing`), imported PDFs/images, recordings, and thumbnails live in `Application Support/Notebooks/<id>/`.

## Roadmap

Contributions toward any of these are very welcome:

- [ ] iCloud sync across devices
- [ ] Typed text boxes and sticky notes on pages
- [ ] Insert images/stickers as movable objects (not just full pages)
- [ ] Audio playback synced to strokes (Notability-style replay)
- [ ] Undo for page operations (insert/delete/reorder currently reset the undo stack)
- [ ] Shape recognition (draw-and-hold to snap lines, circles, rectangles)
- [ ] Split view: two notebooks side by side
- [ ] Presentation / laser pointer mode
- [ ] Outline / bookmarks, page links
- [ ] Notebook covers and nested folders
- [ ] Export as images, backup / restore of the whole library
- [ ] Localization

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go in [GitHub Issues](https://github.com/owaisazmal/Swift-Scribe/issues).

## License

Swift Scribe is released under the [MIT License](LICENSE).
