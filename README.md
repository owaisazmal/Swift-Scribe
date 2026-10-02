# Swift Scribe

**A free, open-source handwritten notes app for iPad. It is a Notability / GoodNotes alternative with no subscriptions, no ads, and no tracking.**

Swift Scribe is built entirely on Apple frameworks (SwiftUI, PencilKit, PDFKit, Vision, SwiftData). Your notes stay on your device unless you turn on iCloud sync, which keeps a copy in your own private iCloud storage.

## Features

**Writing**
- Apple Pencil handwriting with palm rejection and pressure/tilt, powered by PencilKit
- Full tool palette: pen, monoline, fountain pen, pencil, marker/highlighter, crayon, watercolor, eraser, lasso (move/copy/delete), ruler, and custom colors
- Draw and hold: draw a line, circle, ellipse, rectangle, triangle or any figure with straight sides and rest the pen a moment before lifting, and it straightens. Undo gives your own stroke back; Settings › Input turns it off
- Select ink across pages (⋯ › Select Ink Across Pages): draw round ink on any page, or drag across it, then drag what you caught to move it, onto another page if you like, or duplicate or delete it. Each is one undo step
- Pinch to zoom up to 5× with crisp ink and backgrounds at every zoom level
- Pages keep their true relative size; Fit Width (⌘0) and Fit Page (⌘9) enlarge a smaller page
- Undo / redo (toolbar, tool palette, ⌘Z / ⇧⌘Z), including page operations
- Hardware keyboard: arrows, space and Page Up/Down to scroll, ⌘↑/⌘↓ for the first and last page, ⌘N for a new page, ⇧⌘P for the page navigator, and ⌘Z to undo library changes too
- Choose to draw with Apple Pencil only, finger and pencil, or follow the system setting
- Focus mode (⌃⌘F) puts the toolbar away and leaves the page and your tools
- Two notebooks in one window: choose Open Another Notebook Beside from a notebook's title menu and write in both, side by side in landscape or one above the other in portrait, with a divider you can drag. Each keeps its own undo, and the tool you choose is the tool in both

**Presenting**
- Present (⌥⌘↩) shows one whole page at a time with the chrome hidden; arrows, space or the on-screen bar turn pages
- The Pencil (or a finger, when fingers draw) becomes a laser pointer with a fading tail, in red or green; nothing it draws is saved
- With a second screen attached (a cable or AirPlay), presenting puts the page and the laser on that screen and keeps the controls on the iPad; zoom in on the iPad and the screen follows. When you stop presenting, the screen goes back to mirroring
- Presenter notes: write notes for any page (⋯ › Presenter Notes). While a second screen shows the page, the iPad keeps a panel beside it with your notes, the page that comes next, the time and how long you've been presenting. The audience only ever sees the page

**Notebooks & paper**
- Continuous vertically scrolling pages
- Fourteen paper templates in four families: writing (blank, narrow ruled, wide ruled, penmanship, checklist), grids (grid, engineering, dotted, isometric), planning (Cornell, day planner, week planner) and creative (music staff, storyboard)
- Paper colors: white, ivory, legal-pad yellow, kraft, sage, blush, gray, charcoal, and chalkboard, where the ink writes chalk-white
- Page sizes: US Letter, A4, A5, widescreen
- A paper drawer with real miniatures: add a page with any paper, or change a page's paper and color in place (undoable)
- New Notebook starters (Journal, Lecture, Sketchbook, Planner, Music, Plain) and Shuffle for a fresh cover; your Quick Note paper only changes when you ask
- Page navigator with thumbnails: jump, drag to reorder, insert, duplicate, delete, go to page
- Bookmarks: tap the small ribbon beside the page number (⌘D), name it if you like, and find it in the navigator's Outline tab alongside an imported PDF's own table of contents
- Links: place a tab on a page that opens another page, another notebook (at a page you choose) or a web address. It is named after what it opens and follows a page when it moves or a notebook when it is renamed, and a Back button brings you back

**PDFs & images**
- Import PDFs as new notebooks, or insert them into an existing one, and annotate them
- Insert photos as pages
- Pictures on a page: add from Photos, drop from another app, or paste (⌘V), then move, resize, rotate, layer or delete them
- Forty built-in stickers in a soft paper-craft style (sticky notes in six colours, an index card, a taped grid note, torn paper, a kraft tag, washi tapes, doodles, marks and pastel tags), drawn as vectors so they stay sharp at any zoom; ink goes over them, so you can write on a note
- Stickers of your own: pick a photo and its subject is lifted out with a white die-cut edge (on-device, with Vision), kept in the sticker drawer for every notebook
- Typed text boxes: type on the page, then move, resize, turn and restyle the box (size, bold, colour, alignment); typed text is searchable
- Export any notebook as a PDF from the editor or the library (vector backgrounds, stickers and typed text, PDF text stays selectable, bookmarks become the PDF's outline, links between pages and to the web keep working), then share or print
- Export pages as images: every page of a notebook, or just the one you're on, as PNGs at twice the page's size

**Audio**
- Record lectures or meetings alongside a notebook, and play them back later
- Replay a recording with your ink: what you wrote during it is faint until the sound reaches the moment you wrote it, the page turns to follow the writing, and tapping ink jumps the sound to when it was written

**Writing history**
- A This-week strip in the library: seven small sheets, inked on the days you wrote
- A writing calendar laid out like a printed diary; choose a day to see, and open, the exact pages you wrote
- No streaks, badges or reminders

**Organization & search**
- Cloth, Print (riso) and first-page notebook covers, changeable at any time
- Quick Note (⇧⌘N) for a new notebook with your default paper
- A daily journal: Today's page (⌘T) is printed with the date, "On this day" brings back the page from a month or a year ago, and the app reopens the notebook you left open
- Folders with spine colours, and folders inside folders: drag notebooks onto folders in the sidebar, reorder folders, fold a folder's own folders away. A folder shows what is in it and in the folders inside it
- Favorites, sorting (last opened, modified, created, title), duplicate, rename
- Recently Deleted with 30-day auto-purge
- iCloud sync between your iPads (Settings › iCloud, off by default): each notebook is copied whole, a notebook changed on two devices keeps both versions, and a delete never beats newer writing. **Experimental:** the sync logic is tested with a folder standing in for iCloud, but it has not yet run against real iCloud, and it needs a build with the iCloud capability (see Getting started)
- Back up the whole library into one file (Settings › Backup) and restore it on this or another iPad. Restoring adds what is missing and never replaces a notebook: one that differs from the backup comes back beside yours as a copy
- Search by title, **handwriting** (on-device OCR with Vision), typed text, and imported PDF text, with page-level results that open at the matching page

**Languages**
- English, Spanish, French and German, including the widgets, the Siri phrases and the permission prompts. The translations were machine-made for this release and have not been reviewed by native speakers; corrections are very welcome

**Widgets & shortcuts**
- Home Screen widgets: Continue Writing (your last notebook's cover and page), This Week, and Today's Page, plus Lock Screen versions
- Shortcuts and Siri: open today's journal page, start a quick note, continue writing, or open a notebook by name

## Requirements

- Xcode 16 or later (folder-synchronized groups, Swift 6 language mode)
- iPadOS 18 or later
- Runs on iPad and on Apple silicon Macs ("Designed for iPad")

## Privacy

Swift Scribe has no accounts and no analytics. iCloud sync is off unless you turn it on; with it on, your notebooks, folders and stickers are copied to the app's private container in your own iCloud storage, which Apple syncs between your devices. The writing history is never synced. The writing history behind the week strip and calendar is a small file on your device (`Library/activity.json`) listing the days you wrote and which pages. It is never shared, and Settings › Writing History turns it off or clears it.

The widgets read a small snapshot the app writes to its own shared container on the device (the last notebook's title, page and cover, and page counts for recent days). With writing history off, no days are written there.

## Getting started

```bash
git clone https://github.com/owaisazmal/Swift-Scribe.git
```

```bash
open Swift-Scribe/NotesApp.xcodeproj
```

Select an iPad simulator and run. To run on a device, choose your team for both the `NotesApp` and `ScribeWidgets` targets; they share the App Group `group.com.owais.NotesApp`, which you may need to rename to one your team owns (it's set in `Config/*.entitlements` and `Shared/WidgetSnapshot.swift`). iCloud sync needs the iCloud capability, which a free developer account can't sign: with a paid team, set the NotesApp target's `CODE_SIGN_ENTITLEMENTS` to `Config/NotesApp-iCloud.entitlements` (or add iCloud › iCloud Documents under Signing & Capabilities) and rename the container `iCloud.com.owais.NotesApp` to one your team owns. Without it the app builds and runs as before and Settings says sync is unavailable. In the simulator you can draw with the mouse; on a device, choose **⋯ → Draw With** to switch between Apple Pencil only and finger drawing.

Run the tests with ⌘U or:

```bash
xcodebuild test -project NotesApp.xcodeproj -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
```

## Architecture

```
NotesApp/
├── App/          App entry, launch (index refresh), test-only seeds and probes
├── Models/       Manifest types (NotebookManifest, NotebookPage, CoverSpec), paper types
├── Storage/      Notebook packages, tolerant manifest codec, SwiftData library index
├── Canvas/       Page stack (one PencilKit canvas per visible page), page rendering, undo proxy
├── Editor/       NotebookDocument (model, undo, autosave), editor chrome, navigator, recorder, second screen
├── Library/      Library views, covers, new-notebook sheet, library store, one-editor registry
├── Design/       Colour tokens, typography (Fraunces, Bricolage Grotesque), cover renderer
├── Services/     PDF and image export, library backup, iCloud sync, handwriting recognition
├── Settings/     Settings and acknowledgements
└── Resources/    Bundled fonts with their licences, privacy manifest, string catalogs
ScribeWidgets/    The widget extension: Continue Writing, This Week, Today's Page
Shared/           The snapshot the app writes and the widgets read
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

## Roadmap

Contributions toward any of these are very welcome:

- [ ] Try iCloud sync on two real devices (it has only run against a stand-in folder), then sync a notebook while it is open
- [ ] A ruler that spans pages (PencilKit's ruler belongs to one canvas, and each page has its own)
- [ ] Native-speaker review of the Spanish, French and German translations, and more languages
- [ ] Plural rules for languages with more than two forms (counts are written as "1 page" / "%lld pages" pairs today)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go in [GitHub Issues](https://github.com/owaisazmal/Swift-Scribe/issues).

## License

Swift Scribe is released under the [MIT License](LICENSE).
