# Swift Scribe design notes

The visual system is **Clothbound**: a library that looks like a shelf of cloth-bound notebooks, and a quiet warm desk around the page. **Print** is a second cover style borrowed from riso printing. From the other audit directions, only Drafting Table's tabular numerals come along.

## Principles

- The canvas stays quiet. Paper and ink only, and nothing moves while you write.
- Controls are bound like the notebooks. Buttons and bars are boards standing on the desk, fields and tab tracks are wells pressed into it, and the action that finishes a task is cloth. No Liquid Glass and no blur of our own. Menus, alerts, the share sheet and the tool picker stay system.
- Each control appears in one place. Undo and redo live in the tool picker and return to the top bar only while it's hidden.
- Colour never carries meaning alone. Favourites get a ribbon plus a spoken label; selection gets stitching plus a check mark.

## Colour tokens

All tokens live in `Assets.xcassets` with light, dark, and Increase Contrast variants. Use the generated symbols (`Color.paper`, `UIColor.ink`).

| Token | Light | Dark | Use |
|---|---|---|---|
| Paper | `#F1EDE4` | `#181613` | Library ground |
| Desk | `#E7E2D7` | `#121110` | Around the page in the editor |
| Surface | `#F8F6F1` | `#211F1B` | Sidebar, sheets, and the rows of Settings (which lie on Paper) |
| Ink | `#1B2230` | `#ECE6DA` | Text |
| InkSecondary | `#5A6070` | `#A8A194` | Secondary text, small-caps metadata |
| AccentColor (cobalt ink) | `#2747B8` | `#8FA8FF` | Tint, links, selection |
| Tomato | `#C9452F` | `#FF7B61` | Favourite ribbon, recording |
| OnTomato | `#FFFFFF` | `#181613` | Text on tomato. White fails on dark tomato (2.5:1). |
| Mustard | `#E8B023` | `#F0BE45` | Highlight, stitched selection |
| OnMustard | `#1B2230` | `#1B2230` | Text on mustard |
| LabelCream | `#F7F1E3` | `#E9E1CE` | Cloth cover labels (kept light in dark mode) |
| LabelInk, LabelInkSecondary | `#1B2230`, `#5A6070` | `#1B2230`, `#505665` | Text on labels |
| Hairline | Ink at 15% | Ink at 15% | Rules, page edges; 32% with Increase Contrast |
| Board | `#FAF7F0` | `#2A2722` | Buttons, bars and tab thumbs (lighter than a dark sheet, so they lift at night) |
| Well | `#5A4526` at 9% | Black at 38% | Fields and tab tracks, over any ground; 14% and 55% with Increase Contrast |
| PrimaryCloth, OnPrimaryCloth | `#2747B8`, `#F1EDE4` | `#3A5BB8`, `#ECE6DA` | The finishing button. At night it is the dark app icon's cloth, not the bright tint |
| DestructiveCloth, OnDestructiveCloth | `#C9452F`, `#FFFFFF` | `#A83E2B`, `#ECE6DA` | The stop-recording button |

Every text pair is checked by `DesignTokenTests.testEveryTextPairReachesAA` in all four appearances. The lowest ratios:

| Pair | Light | Light + HC | Dark | Dark + HC |
|---|---|---|---|---|
| InkSecondary on Desk | 4.86 | 6.62 | 7.36 | 10.97 |
| OnTomato on Tomato | 4.80 | 6.52 | 7.10 | 9.06 |
| LabelInkSecondary on LabelCream | 5.58 | 8.29 | 5.64 | 8.27 |
| Accent on Desk | 6.07 | 7.72 | 8.27 | 10.59 |

- **Cloth colours:** Oxblood `#6E2A2A`, Tomato `#C9452F`, Mustard `#D6A02A`, Moss `#3D5A40`, Jade `#2F7D6B`, Cobalt `#2F4DA0`, Navy `#1E2A45`, Slate `#56606B`, Rose `#C98A86`, Oat `#CDBF9F`. They are cover and spine content, never text backgrounds, so they live in code (`ClothColor`).
- **Riso inks:** pink `#FF48B0`, yellow `#FFE800`, teal `#00838A`, blue `#0078BF`, black `#1C1C21`, on paper stock `#F7F4EC`. They appear only on Print covers, never on controls.

## Type

- **Fraunces** (SIL OFL): library headings, empty states and cloth labels.
  - In SwiftUI, use `Font.display(_:relativeTo:)` and `Font.displayText(_:relativeTo:)`. These are `Font.custom` on the named instances `Fraunces-SemiBold` and `Fraunces-Regular`, so they scale with Dynamic Type.
  - Cloth labels are drawn with Core Text: SOFT 50, WONK 1, optical size matched to the point size.
- **Bricolage Grotesque** (SIL OFL): Print cover titles only. Condensed ExtraBold (wdth 75, wght 800) through variation axes, because there is no named condensed instance.
- **SF Pro**: all other UI. Metadata uses `.metaStyle()`: small caps, tracking and tabular digits.
- **Font files:** both are bundled unmodified from google/fonts with their OFL texts (`OFL-*.txt`). They are registered at launch with `CTFontManagerRegisterFontURLs`, because the Info.plist is generated. Neither licence declares a Reserved Font Name, and we neither instance nor rename the fonts.

## Spacing, shape, motion

- **Spacing:** a 4-point grid (`Space.x1` = 4 through `Space.x12` = 48).
- **Covers:** 3:4. The spine corners are 1.3% of the width and the fore-edge corners 3.5%.
- **Motion:**
  - 0.18 s ease-out (`Motion.standard`). The favourite ribbon drops on a spring (`Motion.ribbon`).
  - Opening a notebook zooms from its cover on iOS 18+.
  - With Reduce Motion, or on iOS 17, every one of these becomes a cross-fade.

## Controls

Every button, field and tab in the app is drawn by `Design/Controls.swift`, in three materials:

- **Board** (`.board(in:)`): Board fill, a Hairline edge, a lit top edge (white at 85%, 9% at night) and a two-layer umber shadow (`#2A2116`, 10% at 0.5 pt and 7% at 6 pt; black at night). Pressed, it sinks into the well and loses its shadow; disabled, it lies flat. Increase Contrast drops the lit edge.
- **Well** (`.well(in:)`): the Well colour with an umber inner shadow and a lit lower lip. Its edge is the Hairline, ink at 50% with Increase Contrast, and a 1.5 pt accent ring while it has focus.
- **Cloth** (`.scribe(.primary)`): PrimaryCloth with the covers' own two-way weave (a 4 pt tile, white 6% and black 7%), the cover board's bevel (white 18% over black 20%) and an umber shadow. Disabled cloth is a well with secondary text. Increase Contrast drops the weave and bevel.

The pieces:

- **Buttons.** `.scribe` is a board with Ink in the medium weight; `.scribe(.primary)` is cloth in semibold, for the one action that finishes a task (Done, Create, Save, Share); `.scribe(.destructive)` is tomato cloth, used only for the stop-recording button. Anything else that deletes is a tomato icon on a board, or an Ink word, and asks before it acts or can be undone. Shapes are 22 pt continuous rounded rectangles, so a one-line button is a capsule and a wrapped one stays a slab. `compact` draws 34 pt inside a 44 pt target. At accessibility sizes, buttons in content wrap to three lines.
- **Bars.** `BarGroup` puts a row of 44 pt icons (`.barIcon`, Ink, a small well while pressed, Tomato for a destructive role) on one board capsule; `.boardIcon` is a single icon on a round board. Toolbar items wear `.boardBackground()`, which removes the system glass on iPadOS 26 and later. Everything in a bar stops growing at the largest standard text size and shows the Large Content Viewer instead.
- **Under the bar.** When a bar has no room for a field or a set of tabs (a narrow window, a long translation, text above the Large size), they take a row of their own under it: the navigator's go-to field, the link sheet's tabs, the library's search.
- **Fields.** `ScribeSearchField` is a capsule well with a glyph, a 44 pt clear button and room for one more control (the navigator's Go arrow). Escape clears it, then leaves it. Sheet fields use `.scribeField(focused:)`, a rounded well.
- **The library bar.** A board with Sort, New and Select, then the search well (260 pt). When the bar has no room for the field (a narrow window, or a long translation beside the sidebar), it moves to a row of its own under the bar instead of into the system's overflow menu. The sidebar button is a round board like Settings beside it; it shows and hides the sidebar the way the system's did, over the shelves in portrait and beside them in landscape.
- **Tabs.** `ScribeSegmentedPicker` lays its segments out in equal widths on a well, with one board thumb that slides to the chosen one (it jumps with Reduce Motion). The chosen label is Ink semibold, the others TextSecondary medium, so it never relies on colour alone. In dark mode the thumb carries a 10% ink wash, and with Increase Contrast an InkSecondary edge. VoiceOver reads the segments as tabs.
- Boards never sit inside scrolling grids or lists, where their shadows would be drawn live.

## Covers

All three styles share the 3:4 shape, a left spine band, the tomato favourite ribbon and a meta line under the cover. From 100 pt wide (shelf, spread and previews), every cover is drawn as a closed notebook:

- **Page block.** Cream leaves (`#F7F1E3`, `#D9D1BF` in dark mode) show past the board, 2.8% of the width along the fore-edge and 1.6% of the height along the tail, with three leaf hairlines that round the corner. The board is measured inside the page block, and the ribbon hangs from the board.
- **Board.** A 1 px bevel: white at 18% along the head and spine, black at 20% along the fore-edge and tail.
- **Shadow plate.** Every cover sits on a soft contact and ambient shadow drawn once into a 9-slice plate (`CoverShadowPlate`, stronger on the night desk). Nothing is shaded live.

The styles:

- **Cloth.** The cloth colour, a faint two-way weave, a rounded spine (a three-stop shade) and a hinge groove at 11% of the board, and a cream label.
  - The label sits 17% in from the spine, 9% from the fore-edge and 17% from the top.
  - It has a double hairline border, a Fraunces title (up to three lines) and a small-caps meta line: the shelf's name, or the month the notebook was started (`SEP 2026`). Never the page count, which is printed under the cover, so adding a page never re-renders it.
- **Print.** Two riso inks on paper stock, overprinted with multiply and baked into the image, and saddle-stitched like a zine: a fold at the spine edge and two staples (`#B9B6AE`, edged `#8E8A80`) at 28% and 72% of the height.
  - Patterns come from `CoverRNG(notebook id, seed)`: a base layer (dots, stripes, rings, halftone, or a flat fill) and an overlay (disc, band, dots or stripes). Positions, spacing and angles are jittered.
  - The overlay is misregistered by at most 0.3 pt.
  - The title is uppercase Bricolage on a paper-stock knockout, so its contrast (15.4:1) never depends on the pattern.
  - Shuffle rolls a new seed in another pair of inks. Increase Contrast replaces the patterns with two solid blocks.
- **First page.** The page thumbnail sits behind a 9% cloth spine, with the hinge groove. Imported PDFs get a `PDF` tag, and they default to this style.

### Rendering and appearance

- Covers are rendered once per request, off the main thread, by `CoverRenderer`. A request is the spec, title, meta, width bucket, scale, appearance, contrast and first-page hash.
- They are cached in a bounded in-memory LRU (80 MB) and on disk in `Caches/Covers`. A cover that has to be rendered or read from disk fades in (0.15 s); a cache hit appears at once.
- There are no live blend modes or shadows in scrolling grids. The ribbon and selection are SwiftUI overlays, so they can animate.
- **Dark mode is a night desk.** Boards are dimmed about 10% so they don't glow, the page block uses its own dimmed cream, cloth labels stay light, and paper and ink never invert.
- **Increase Contrast.** No weave or shaded spine, stronger leaf lines, and a 1 pt Hairline outline, so a cover stands off the ground without its shadow.

## Library

- The library opens with an editorial Fraunces heading and a small-caps summary, then **Continue writing**: the last notebook opened, lying open.
  - Its case (the cloth, dimmed for Print and first-page covers) peeks round two facing pages: the current page on the right, the one before it on the left. Page 1 faces an *ex libris* bookplate with the title and the month it was started.
  - A ribbon in the cloth colour marks the page and carries its number. The seam is shaded, or a plain rule with Increase Contrast.
  - Opening zooms out of the right-hand page, and closing zooms back into it. Every open grows out of what was touched: a cover, the spread, or a search result's page card.
- Below that are shelves grouped by recency (Today, Yesterday, This week, Earlier this month, then by month) or by folder, each with a small-caps label and a hairline rule; folder shelves lead with their spine chip.
- **Shelves fill the width.** `ShelfMetrics.fit` picks the column count for the width (about 176 pt a cover, 136 to 232 pt), so there's no gutter in any size or orientation: on an 11-inch iPad, two covers of about 213 pt in portrait with the sidebar, four in portrait without it or in landscape with it, and six in landscape without it. Covers render from the 176 or 220 pt bucket.
- **Every row stands on a ledge:** a 5 pt Surface band with a Hairline top edge and a baked shadow beneath, 8 pt wider than the row on each side. The "pages, edited" line sits just under it, at the cover's width.
- Search results show page cards whose matches are bold on a highlighter band (never colour alone): mustard under OnMustard in dark mode, ochre `#806113` under LabelCream on light paper (5.3:1 on Surface, 5.1:1 for the text), because Apple's audit reads a pale band as faint text. The Pages row fades in.
- The sidebar shows a cloth spine chip for each folder. A folder inside another is indented one step under it, and a folder that holds folders has a chevron on its trailing edge that folds them away.
- **Locked notebooks.** The cover is blurred past reading (9% of its width) under a cream disc with an ink padlock, and its title is written beneath it, since the cover no longer says it. Behind the lock, the editor shows a padlock in a Surface circle, the notebook's name in the display face, and Unlock beside the way back.
- **Covers are real buttons.** Each has a full VoiceOver description (title, page count, last edit, favourite, folder), a hover lift, and a typed drag payload (`com.owais.swiftscribe.notebook-reference`).
- At accessibility text sizes, the grid becomes a list, led by a Continue writing row.
- **Empty states look like the library.** A new library shows a small illustrated shelf (ghost spines leaning on a cloth notebook) above "Your shelf is ready."; an empty folder says so by name and offers a new notebook there; empty Favourites shows the ribbon.

## On the page

- **Ribbons.** The page ribbon wears the notebook's cloth. Beside it hangs a slimmer bookmark ribbon: a Surface ghost with a Hairline edge until the page is bookmarked, then Mustard with an OnMustard bookmark. Bookmarked pages carry a small mustard ribbon on their navigator thumbnail.
- **Presenter view.** A 300 pt Surface panel on the trailing side with a Hairline edge: elapsed time in semibold tabular numerals with the clock beside it, then small-caps "Next" over the next page's thumbnail and "Notes" over the notes in the title 3 size, so they read at arm's length. The bar's panel button fills while it is showing.
- **Two notebooks.** The divider between panes is a Desk strip with a Hairline down its middle and a short grip. The second pane's bar leads with a cross where the first has the back chevron, and each pane keeps its own cloth ribbon, so it is always clear which notebook a page belongs to.
- **Selecting ink.** The lasso is the stitched line (mustard dashes over an ink line) and what it caught gets the same stitched box as a selected sticker. The bar at the top says what to do in a short sentence, then offers Duplicate, Delete (Tomato), Undo and a filled Done.
- **Replay.** The transport is the floating bar at the bottom: play or pause, the time in semibold tabular numerals, a scrubber, the length, and a filled Done. Ink still to come stays on the page at 16% opacity.
- **Study tape.** A strip of washi tape in Mustard, Rose, Sage or Sky with pinked ends, pale diagonal stripes and a darker lower edge, 200 by 30 points when placed. It is opaque, because its job is to hide. Lifted, it is a dashed outline in the deeper shade of its colour over a 14% wash, so the answer reads clearly and the strip can still be found.
- **Transcript.** Lines are rows with the time in small tabular numerals and the words in the body size. The line being said is semibold on a 20% Mustard wash with a Mustard edge, so it never relies on colour alone. Beside a replay it is a 300 pt Surface panel with a Hairline edge, like the presenter view.
- **Find.** The find bar is a floating bar at the top: a magnifying glass, the field, "3 of 12" in tabular numerals, up and down arrows and a filled Done. Every match on a page gets a 30% Mustard wash with a darker Mustard edge; the one being shown is a 50% wash with an Ink outline (cream on dark paper), so it is told apart by more than colour.
- **Zoom window.** A Board strip along the foot of the editor with a Hairline top edge: a row of 44 pt bar icons over the magnified paper. The area it shows is outlined on the page in the accent colour, with a small filled tab to drag it by. The last three tenths of both the outline and the strip carry an 8% accent tint: writing there moves the window on.
- **Today's events.** Plain text in the small size, one event to a line with the time first, below a journal page's printed date and against the right margin. It is a text box like any other once it is there.
- **Floating bars.** The arrange bar (top, while something on the page is selected), the way back from a link (top) and the presenter's bar (bottom) are one style: a board capsule (see Controls), 44 pt targets, never blurred, and a compact cloth Done.
- **Selection.** A selected picture, sticker, text box or link gets the stitched outline (mustard dashes over an ink line, so it shows on any paper) and one round handle at its lower corner.
- **Stickers** are drawn in code (`Sticker`), 100 units wide, in four families. They share one look, taken from the sticky notes: a soft pastel fill, a thin edge in the deeper shade of the same hue, a little light across the top and a faint layered shadow, so each reads as a piece of paper resting on the page. Nothing has a hard white border.
  - Notes and Tape: sticky notes with a folded corner in butter, pink, blue, mint, lavender and peach; a ruled index card, a grid note held by a strip of tape, a torn strip of ruled paper, a kraft tag on a string, the cream label with the cloth label's double hairline, a speech bubble, a ribbon banner, and five washi tapes with pinked ends (three striped, one dotted, one gingham).
  - Doodles: sparkles, a daisy, a leaf sprig, a cloud, a sun, a crescent moon, a rainbow, a paperclip and a pushpin.
  - Marks: star, heart, check, exclamation, question, a curved arrow, a pennant flag, a marker ring and a highlighter line.
  - Tags: IMPORTANT, TO DO, DONE and IDEA as pastel pills with a dot and tracked rounded capitals.
  - The palette is six pastels with their deeper companions (butter, rose, peach, sky, mint, lavender) plus kraft and cream. Stickers are content, like covers, and never invert in dark mode. Shadows are layered tints, not blurs, so a sticker stays vector in an exported PDF.
- **Stickers of your own** keep the die-cut look: the subject of a photo with a white edge about 2% of its long side. In the drawer they come first, after a dashed "From Photo…" tile.
- **Text boxes** are set in the system face, Regular or Bold, at Small (13), Body (17), Large (24) or Title (34), in five tints from the cloth palette: Ink, Tomato, Cobalt, Moss and Plum. On Charcoal and Chalkboard each tint switches to a lighter value. While selected a text box has two handles: the round one at its lower left scales the type, the pill on its right edge changes the width.
- **Links** are an index tab: a Mustard square with an ink arrow, then the page's name in semibold on label cream, with a white die-cut edge. A link to another notebook has a sage square with a small book, and a web link a sky-blue square with an arrow leaving the page; a link whose page or notebook was deleted has a grey square. After following one, a floating "Back to Page N" (or "Back to" the notebook it came from) sits where the arrange bar would.
- **The second screen** shows only the page on black, and the laser drawn larger so it reads from across a room. The presenter's bar on the iPad gains a small screen symbol while it is in use.
- **Focus mode** leaves one control: a 44 pt round board at the top right to come back.
- **The laser** is red `#FF3B2F` or green `#22D36B` with a white core and a glow, and a tail that fades over 0.9 s.

## Widgets

- Paper ground and Ink text in the app's light and dark values; headings in the system serif (the app's fonts aren't bundled in the extension), metadata in small caps.
- **Continue Writing** shows the cover exactly as the shelf draws it (the app renders it), the title, "Page 3 of 12" and, in the medium size, the week strip.
- **This Week** is the page count for the week over seven leaves, filled on the days written, with today's initial in heavy type. A run of days is mentioned only from two days up, and never as a streak to keep.
- **Today's Page** is a tear-off calendar leaf: weekday, a large day number, the month, and whether today has been written.
- **Quick Note** is the pencil-on-square symbol in the accent colour over its name, and the bare symbol on the Lock Screen. The Control Center buttons use the same symbol, and a calendar for Today's Page.

## App icon

The Home Screen icon is a Clothbound notebook on the desk. It's drawn in code by `Scripts/AppIcon` (Core Graphics, Core Text and ImageIO, no UIKit or AppKit), so every variant and alternate comes from one source.

- **Light.** A cobalt cloth notebook on the desk colour `#E7E2D7`.
  - The cloth has the covers' faint two-way weave, a darker rounded spine and a hinge.
  - A cream page block (`#F7F1E3`, three leaf lines) shows along the fore-edge and the tail.
  - The cream label has the double hairline and a Fraunces "S" in `#1B2230`, set with the cloth-label instance (SOFT 50, WONK 1).
  - A tomato ribbon with a cream edge hangs below the book, in its shadow.
  - The primary PNG has no alpha channel.
- **Dark.** Designed, not derived: a transparent background for the system's dark backdrop, lifted cloth (`#3A5BB8`), the label kept light (`#E9E1CE`) and the dark tomato ribbon (`#FF7B61`). No shadows.
- **Tinted.** Grayscale on transparent, in the same reading order: label brightest, cloth mid-grey, the "S" near black.
- **Alternates.** Settings › App Icon offers Cobalt (the primary icon), Tomato (mustard ribbon), Moss, Oxblood, Mustard and Print, each with its own dark and tinted art.
  - Print is riso paper stock with a pink disc overprinted on a yellow halftone, a riso-blue ribbon, and a Bricolage "S" on a knockout.
  - The alternates are listed in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, which puts them in the generated Info.plist; `AppIconTests` checks that they arrive there.
  - The tiles are 60 pt previews (`IconPreview-*`, light and dark) with the stitched selection and a check mark. They wrap onto more rows as text grows. iPadOS confirms the change itself.
- **Geometry at 1024 px.**
  - The book is laid out at 520 × 694 around (512, 470), then drawn 8% larger so it holds its own beside full-bleed icons.
  - Spine 8% of the width with a gradient, hinge at 11%. Weave period 14 px, 6 px lines.
  - Page block 22 px on the fore-edge and 14 px at the tail, so it survives the Home Screen's edge treatment at small sizes.
  - Label from 17% to 91% of the width and 22% to 62% of the height; the "S" is set at 300 px and centred on its outline.
  - Ribbon 72 × 320 px (`RibbonShape`'s 0.28 notch) at 70% of the width, hanging 110 px below the book.
  - Book shadow blur 36 px at 22%, 18 px down (light only).
- **Regenerating.** Run `swiftc -O Scripts/AppIcon/*.swift -o .build/make-icon && .build/make-icon NotesApp/Assets.xcassets docs`. It rewrites every icon set, the previews and `docs/icon-sheet.png`, a review sheet with each variant and the light icon at 152, 120, 80, 58 and 40 px. The output is deterministic and committed.
