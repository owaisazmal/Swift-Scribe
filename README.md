# Swift Scribe

[![CI](https://github.com/owaisazmal/Swift-Scribe/actions/workflows/ci.yml/badge.svg)](https://github.com/owaisazmal/Swift-Scribe/actions/workflows/ci.yml)

**A free, open-source handwritten notes app for iPad. It is a Notability / GoodNotes alternative with no subscriptions, no ads, and no tracking.**

Swift Scribe is built entirely on Apple frameworks (SwiftUI, PencilKit, PDFKit, Vision, SwiftData). Your notes stay on your device unless you turn on iCloud sync, which keeps a copy in your own private iCloud storage.

## Features

**Writing**
- Apple Pencil handwriting with palm rejection and pressure/tilt, powered by PencilKit
- A tool tray of our own at the foot of the page: up to eight pens, each with its kind (pen, fineliner, fountain pen, pencil, highlighter, crayon, watercolour), colour and width, an eraser for whole strokes or part of one, a lasso (move/copy/delete), and the shortcuts you choose to keep beside them (Picture, Text Box, Sticker, Link, Study Tape, Ruler, Zoom Window)
- Draw and hold: draw a line, circle, ellipse, rectangle, triangle or any figure with straight sides and rest the pen a moment before lifting, and it straightens. Undo gives your own stroke back; Settings › Input turns it off
- Pencil gestures: scribble back and forth over ink with a pen to erase it (one undo brings it back), and draw a loop round ink and hold still to select it. Settings › Apple Pencil turns each off, and chooses what the Pencil's double-tap and squeeze do: the system's setting, the eraser, Undo, Select Ink, showing or hiding the tools, or the zoom window. **Needs a check on a device:** double-tap and squeeze can't be tried in the simulator, and the scribble and loop have only been recognised from drawn test strokes
- Select ink across pages (⋯ › Select Ink Across Pages): draw round ink on any page, or drag across it, then drag what you caught to move it, onto another page if you like, or duplicate or delete it. Each is one undo step
- Handwriting to text: with ink selected, Turn into Text reads it on the device and shows the words to correct, copy, or type onto the page in the handwriting's place. One undo brings the handwriting back
- Translate handwriting: in that same sheet, Translate turns the words into another language with Apple's translator, which works on the iPad once iPadOS has downloaded the language. Show Original brings the words back as they were read. **Needs a check on a device:** the simulator has no translator, so the translation itself has only run through a stand-in
- Zoom window (⋯ › Zoom Window): a magnified strip along the bottom for writing small and neat. What you write in the strip lands on the page inside a blue outline; when your writing reaches the tinted band on the right and the pen rests, the window moves along the line, and at the end of the line it drops to the start of the next. Drag the outline's tab to place it, and use the strip's buttons to step back and forward, start a new line, bring it to the page you are looking at, or zoom in and out
- Whiteboards (+ › Whiteboard, or the Whiteboard starter in New Notebook): a page with no edges, for brainstorming and diagrams. Write, drop pictures, stickers, text and links anywhere, move about with two fingers (or one, when only the Pencil draws) and pinch out to a seventh of full size to see a whole wall of it. The Whiteboard button in the bar holds Show Everything, which fits all that is on the board, Actual Size, which goes back to 1×, the pages and a guide; nothing stands over the board. Among a notebook's pages a board is a card showing what is on it; tap the card to open it, and turn to another page from the ribbon. Thumbnails, exports, search, flashcards, the time-lapse and presenting use the part of the board that has something on it. Dotted, squared, ruled or blank, in any paper colour. A board is 40,000 points across (about 14 metres), opened in the middle, so there is no edge to reach in practice
- Pinch to zoom up to 5× with crisp ink and backgrounds at every zoom level
- Pages keep their true relative size; Fit Width (⌘0) and Fit Page (⌘9) enlarge a smaller page
- Undo / redo (toolbar, ⌘Z / ⇧⌘Z), including page operations
- Hardware keyboard: arrows, space and Page Up/Down to scroll, ⌘↑/⌘↓ for the first and last page, ⌘N for a new page, ⇧⌘P for the page navigator, ⌘F to find in the notebook, and ⌘Z to undo library changes too
- Choose to draw with Apple Pencil only, finger and pencil, or follow the system setting
- Focus mode (⌃⌘F) puts the toolbar away and leaves the page and your tools
- Pens you set up once: tap a pen to write with it, tap it again to change its kind, colour or width, and the empty label at the end adds another. Its kind is picked from a little pen roll, and the same options move it along the tray or remove it; touch and hold opens them in one go. The tray is one slim board and the page keeps the whole width of the window; the pencil button in the bar puts it away
- Notebook tabs: choose Open Another Notebook in a Tab from a notebook's title menu and a tab bar appears, with a plus for more. Each tab keeps its notebook open, undo history and all, while you look at another; ⇧⌘] and ⇧⌘[ step along the bar and ⌘W closes a tab. Your tabs are still there after a visit to the library and the next time the app opens
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
- Select a PDF's own text (⋯ › Select PDF Text): drag across the words, tap a word, or take the whole page, then copy it (⌘C) or highlight it in yellow, green, pink or blue. A highlight is ink, so the eraser takes it off and one undo removes it
- A highlighter that snaps: draw the highlighter roughly along a line of a PDF's text and it is laid straight over that line, as tall as the line and no wider than the letters you passed over. Undo gives your own stroke back; Settings › Apple Pencil turns it off
- Insert photos as pages
- Scan documents (+ › Scan Documents in a notebook, or the library's New menu for a notebook of its own): the camera finds the paper, straightens and crops it, and each sheet becomes a page you can write on. What is printed on a scan or a photo page is read on the device, so search finds it
- Pictures on a page: add from Photos, drop from another app, or paste (⌘V), then move, resize, rotate, layer or delete them
- Forty built-in stickers in a soft paper-craft style (sticky notes in six colours, an index card, a taped grid note, torn paper, a kraft tag, washi tapes, doodles, marks and pastel tags), drawn as vectors so they stay sharp at any zoom; ink goes over them, so you can write on a note
- Stickers of your own: pick a photo and its subject is lifted out with a white die-cut edge (on-device, with Vision), kept in the sticker drawer for every notebook
- Study tape (+ › Study Tape): a strip of washi tape in four colours that covers what is under it, ink included. Tap it to lift it and tap again to put it back, with a finger or the Pencil; touch and hold to move, stretch or turn it. Lifting is for looking and is never saved, so every strip is back in place the next time you open the notebook. While presenting, lifting a strip reveals the answer on the second screen too
- Typed text boxes: type on the page, then move, resize, turn and restyle the box (size, bold, colour, alignment); typed text is searchable
- Today's events (+ › Today's Events): the day's events from your calendar, printed on the page as a text box you can move, restyle or delete
- Export any notebook as a PDF from the editor or the library (vector backgrounds, stickers and typed text, PDF text stays selectable, bookmarks become the PDF's outline, links between pages and to the web keep working), then share or print
- Export pages as images: every page of a notebook, or just the one you're on, as PNGs at twice the page's size
- Export a page as a time-lapse video: the page being written, every stroke in the order and at the pace you made it with the waits taken out, sped up to fit twenty seconds at most. It plays in the export sheet and shares like any video

**Studying**
- Flashcards: every notebook can hold a deck (⋯ › Flashcards). Select study tape and choose Make Flashcard, and the card's question is that part of the page with the tape on and its answer the same part with the tape lifted. Select handwriting and Make Flashcard clips it onto a card as it looks on its paper. Or write a card yourself
- Spaced repetition: after turning a card over you say Again, Good or Easy, and it comes back later the better you knew it (tomorrow, then in three days, then in about a week, and so on up to a year). A card you forgot comes round again in the same sitting
- The library's Flashcards card says how many are due across your notebooks and opens them in one sitting. Cards in a locked notebook stay out of it. Cards live in the notebook's own package, so a duplicate, a backup and iCloud sync carry them
- Study guide (⋯ › Study Guide): the main points of a page, a whole notebook or a recording's transcript, and practice questions with their answers, written by Apple Intelligence on the iPad itself. Add the summary to the page as a text box, or save the questions as flashcards. On an iPad without Apple Intelligence the sheet says so and nothing else happens. **Needs a check on a device:** Apple's model has written summaries and questions in the simulator from short typed notes, but not yet on an iPad from real handwriting or a long notebook

**Audio**
- Record lectures or meetings alongside a notebook, and play them back later
- Replay a recording with your ink: what you wrote during it is faint until the sound reaches the moment you wrote it, the page turns to follow the writing, and tapping ink jumps the sound to when it was written
- Transcripts: have a recording written down (Recordings › the speech bubble › Transcribe). It is done on the iPad, never on a server; if the iPad can't transcribe a language on the device, the app says so and sends nothing. Read it line by line, copy it, and tap a line to hear it with the ink you wrote as it was said. During a replay the transcript sits beside the page with the line being said marked. **Needs a check on a device:** the simulator has no on-device recogniser, so the recogniser itself has only run through a stand-in

**Writing history**
- A This-week strip in the library: seven small sheets, inked on the days you wrote
- A writing calendar laid out like a printed diary; choose a day to see, and open, the exact pages you wrote
- No streaks, badges or reminders

**Organization & search**
- Cloth, Print (riso) and first-page notebook covers, changeable at any time
- Quick Note (⇧⌘N) for a new notebook with your default paper
- A daily journal: Today's page (⌘T) is printed with the date, "On this day" brings back the page from a month or a year ago, and the app reopens the notebook you left open. With Settings › Daily Journal › Print Today's Events on, each new day's page starts with that day's events from your calendar
- Locked notebooks: touch and hold a notebook and choose Lock, and it asks for Face ID, Touch ID or the iPad's passcode every time it is opened. Its cover is blurred under a padlock, what is written in it is left out of search, Spotlight, the widgets and On This Day, and it is covered again whenever the app leaves the screen. A lock keeps a notebook closed in the app; it does not encrypt its files
- Folders with spine colours, and folders inside folders: drag notebooks onto folders in the sidebar, reorder folders, fold a folder's own folders away. A folder shows what is in it and in the folders inside it
- Tags and smart shelves: tag a notebook (its title menu, or touch and hold it in the library and choose Tags) or a single page (⋯ › Tag Page), and the tag gets a shelf in the sidebar with the notebooks that carry it and, under them, the tagged pages, which open at that page. A smart shelf is a saved filter: everything tagged with any, or all, of the tags you choose. Rename a tag, or take it off everything, from the sidebar; search finds notebooks by their tags too. A backup carries your smart shelves; iCloud sync carries the tags inside each notebook but not the smart shelves
- Favorites, sorting (last opened, modified, created, title), duplicate, rename
- Recently Deleted with 30-day auto-purge
- iCloud sync between your iPads (Settings › iCloud, off by default): each notebook is copied whole, a notebook changed on two devices keeps both versions, and a delete never beats newer writing. **Experimental:** the sync logic is tested with a folder standing in for iCloud, but it has not yet run against real iCloud, and it needs a build with the iCloud capability (see Getting started)
- Back up the whole library into one file (Settings › Backup) and restore it on this or another iPad. Restoring adds what is missing and never replaces a notebook: one that differs from the backup comes back beside yours as a copy
- Search by title, **handwriting** (on-device OCR with Vision), typed text, imported PDF text, the print on scans and photo pages, and what was said in transcribed recordings, with page-level results that open at the matching page
- Find in a notebook (⌘F, or ⋯ › Find in Notebook): every place the words appear, in handwriting, typed text, PDF text and scans, is marked on the page, and the arrows (or ⌘G and ⇧⌘G) step from one to the next
- Spotlight: notebooks can be found from the Home Screen by their title or by the words in them (Settings › Search turns it off). The index is kept by iPadOS on the iPad

**Languages**
- English, Spanish, French and German, including the widgets, the Siri phrases and the permission prompts. The translations were machine-made for this release and have not been reviewed by native speakers; corrections are very welcome

**Widgets & shortcuts**
- Home Screen widgets: Continue Writing (your last notebook's cover and page), This Week, Today's Page and Quick Note, plus Lock Screen versions
- Control Center buttons for Quick Note and Today's Page, which can also go on the Action button
- Shortcuts and Siri: open today's journal page, start a quick note, continue writing, or open a notebook by name

## Requirements

- Xcode 16 or later (folder-synchronized groups, Swift 6 language mode)
- iPadOS 18 or later
- Runs on iPad and on Apple silicon Macs ("Designed for iPad")

## Privacy

Swift Scribe has no accounts and no analytics. Handwriting and speech are recognised on the device: a recording is only transcribed when you ask, and only if the iPad can do it without sending it anywhere. Translation uses Apple's translator on the iPad. Study guides are written by Apple's language model on the iPad, from the words already read from your pages, and are never sent anywhere; without that model there is no study guide. Your calendar is read only when you ask for today's events, or when you have turned on printing them in the journal, and the events go nowhere but onto the page. The camera is used only while you scan. iCloud sync is off unless you turn it on; with it on, your notebooks, folders and stickers are copied to the app's private container in your own iCloud storage, which Apple syncs between your devices. The writing history is never synced. The writing history behind the week strip and calendar is a small file on your device (`Library/activity.json`) listing the days you wrote and which pages. It is never shared, and Settings › Writing History turns it off or clears it.

The widgets read a small snapshot the app writes to its own shared container on the device (the last notebook's title, page and cover, and page counts for recent days). With writing history off, no days are written there. A locked notebook is never in that snapshot, nor in Spotlight's index, which iPadOS keeps on the device and which Settings › Search switches off.

A locked notebook is closed to anyone using the app without Face ID, Touch ID or the passcode. Its files are not encrypted beyond what iPadOS does for every app, and a backup or an iCloud copy holds it like any other notebook.

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
├── Services/     PDF, image and video export, library backup, iCloud sync, handwriting and speech recognition,
│                 scanning, translation, the calendar, notebook locks, Spotlight
├── Settings/     Settings and acknowledgements
└── Resources/    Bundled fonts with their licences, privacy manifest, string catalogs
ScribeWidgets/    The widget extension: Continue Writing, This Week, Today's Page, Quick Note, and the Control Center buttons
Shared/           The snapshot the app writes and the widgets read, and what a Control Center button hands the app
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
- [ ] Try transcription on a real iPad, with real speech and a long recording (the simulator can't recognise speech on the device)
- [ ] Try on a real iPad what the simulator can only stand in for: scanning with the camera, Face ID on a locked notebook, translation, the calendar's permission prompt, the Control Center buttons, and the zoom window with a Pencil
- [ ] Try the study guide on an iPad with Apple Intelligence: how good its summaries and questions are from real handwriting, and how long a long notebook takes
- [ ] Try the Pencil gestures with a real Pencil: double-tap and squeeze (which now switch the tray's tools with no system picker), and how readily a scribble or a loop is recognised in real handwriting
- [ ] Try whiteboards on a real iPad with a Pencil: writing at 5× and far from the middle of the board, panning and pinching while the tools are showing, and how a board with a lot of ink on it feels. Also still to run on a board at all: the time-lapse export, finding handwritten words, and presenting to a second screen
- [ ] Try tabs, PDF text and the tool tray on a real iPad: writing with each kind of pen, the eraser's two kinds, selecting text and the snapping highlighter with a Pencil, PDFs with columns or scanned pages, the tab shortcuts on a hardware keyboard, and a long session with many tabs open
- [ ] A ruler that spans pages (PencilKit's ruler belongs to one canvas, and each page has its own)
- [ ] Native-speaker review of the Spanish, French and German translations, and more languages

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go in [GitHub Issues](https://github.com/owaisazmal/Swift-Scribe/issues).

## License

Swift Scribe is released under the [MIT License](LICENSE).
