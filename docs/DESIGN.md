# Swift Scribe design notes

The visual system is **Clothbound**: a library that looks like a shelf of cloth-bound notebooks, and a quiet warm desk around the page. **Print** is a second cover style borrowed from riso printing. From the other audit directions, only Drafting Table's tabular numerals come along.

## Principles

- The canvas stays quiet. Paper and ink only, and nothing moves while you write.
- System chrome stays system. Bars, menus and the tool picker are Liquid Glass. We tint them and never imitate them or add blur of our own.
- Each control appears in one place. Undo and redo live in the tool picker and return to the top bar only while it's hidden.
- Colour never carries meaning alone. Favourites get a ribbon plus a spoken label; selection gets stitching plus a check mark.

## Colour tokens

All tokens live in `Assets.xcassets` with light, dark, and Increase Contrast variants. Use the generated symbols (`Color.paper`, `UIColor.ink`).

| Token | Light | Dark | Use |
|---|---|---|---|
| Paper | `#F1EDE4` | `#181613` | Library ground |
| Desk | `#E7E2D7` | `#121110` | Around the page in the editor |
| Surface | `#F8F6F1` | `#211F1B` | Sidebar, sheets |
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

## Covers

All three styles share the 3:4 shape, a left spine band, the tomato favourite ribbon and a meta line under the cover.

- **Cloth.** The cloth colour, a faint two-way weave, a darker spine, and a cream label.
  - The label sits 17% in from the spine, 9% from the fore-edge and 17% from the top.
  - It has a double hairline border, a Fraunces title (up to three lines) and a small-caps meta line (folder name, or page count).
- **Print.** Two riso inks on paper stock, overprinted with multiply and baked into the image.
  - Patterns come from `CoverRNG(notebook id, seed)`: a base layer (dots, stripes, rings, halftone, or a flat fill) and an overlay (disc, band, dots or stripes). Positions, spacing and angles are jittered.
  - The overlay is misregistered by at most 0.3 pt.
  - The title is uppercase Bricolage on a paper-stock knockout, so its contrast (15.4:1) never depends on the pattern.
  - Reprint rolls a new seed. Increase Contrast replaces the patterns with two solid blocks.
- **First page.** The page thumbnail sits behind a 9% cloth spine. Imported PDFs get a `PDF` tag, and they default to this style.

### Rendering and appearance

- Covers are rendered once per request, off the main thread, by `CoverRenderer`. A request is the spec, title, meta, width bucket, scale, appearance, contrast and first-page hash.
- They are cached in a bounded in-memory LRU (80 MB) and on disk in `Caches/Covers`.
- There are no live blend modes in scrolling grids. The ribbon and selection are SwiftUI overlays, so they can animate.
- **Dark mode is a night desk.** Covers are dimmed about 10% so they don't glow, cloth labels stay light, and paper and ink never invert.

## Library

- The library opens with an editorial Fraunces heading and a small-caps summary, then a "Continue writing" spread (cover plus current page).
- Below that are shelves grouped by recency or folder, each with a small-caps label and a hairline rule.
- The sidebar shows a cloth spine chip for each folder.
- **Covers are real buttons.** Each has a full VoiceOver description (title, page count, last edit, favourite, folder), a hover lift, and a typed drag payload (`com.owais.swiftscribe.notebook-reference`).
- At accessibility text sizes, the grid becomes a list.
