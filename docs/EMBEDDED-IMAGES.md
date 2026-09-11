# Embedded EPUB, KEPUB, and MOBI images

Panels+ supports images embedded in reflowable `.epub`, `.kepub`, and `.mobi`
books. Kobo sync normally names KEPUB books `.kepub.epub`, which Panels+
recognizes through its EPUB suffix; a directly named `.kepub` is also accepted
when KOReader opens it in its rolling reader.
Long-press an image: Panels+ extracts that bitmap, finds its panels, and opens
the usual panel reader. At the first or last panel it turns reader pages and
looks for the previous or next image with a usable panel layout.

This is deliberately different from CBZ/CBR/PDF. Those formats expose a
fixed document page, while EPUB/KEPUB/MOBI are laid out again whenever font,
margins, orientation, or line spacing change.

## Embedded-image detector

This is **Embedded detection**, one of Panels+' two source backends. Native
detection handles fixed-layout CBZ/CBR/PDF pages; Embedded detection handles a
decoded image extracted from a reflowable book. Both use the same Quick/Smart/
Deep modes and the same shared Deep component collector; only the source image
and coordinate space differ. See [Detection](DETECTION.md#two-source-backends-native-and-embedded).

The **Detector** button cycles through **Quick**, **Smart**, and **Deep**.
It is separate from the normal document detector, so changing it does not
alter the CBZ/CBR/PDF setting.

`Quick` uses the standard low-resolution gutter map. `Deep` copies the
extracted bitmap into a K2PDFOpt source context, then runs the shared native
Leptonica component collector once for the whole image. `Smart` follows the
same policy as CBZ/CBR/PDF: Quick first, then Deep only if Quick rejects the
image.

Quick uses the same uniform sampling and panel segmentation as CBZ/CBR/PDF.
The source differs necessarily: fixed-layout files supply a rendered document
page, while EPUB/KEPUB/MOBI supply the decoded image itself. The embedded map only
applies a shared sampling cap to exceptionally tall images, so it does not
turn a large reflow image into an unbounded allocation.

For an embedded image the native detector's coordinates are image-space, not
reflow-page-space, so its returned rectangles can be cropped directly from the
retained bitmap. This is the key adaptation: a reflow page cannot be sent to
the fixed-document renderer, but its extracted image can be sent to the same
K2PDFOpt/Leptonica routine.

Deep makes one grayscale K2PDFOpt copy of the extracted image (none when the
image is already greyscale), performs one connected-component pass, and is
guarded by the same free-memory threshold as fixed-layout native detection. If
direct K2PDFOpt/Leptonica access is unavailable or finds no panel, the former
image-space Outline pass is used as a fallback; it is not the primary Deep
implementation.

On an image-to-image boundary, Panels+ keeps only the already-rendered current
crop on screen. It immediately releases the old full source bitmap, its lazy
crop closures, and any stale queued page search before scanning later reflow
pages. This prevents one large EPUB/KEPUB/MOBI image from staying resident throughout
an arbitrarily long search. Intermediate reader-page turns also cancel
KOReader's one-shot hardware page animation. Once the destination image and
its first (or last) panel are ready, Panels+ arms one normal page-change
animation immediately before replacing the viewer. Consequently, supported
devices animate directly from the current panel to the destination panel
exactly once. The same boundary animation is also supplied for fixed-layout
PDF, CBZ, and CBR documents, whose KOReader reader path does not normally emit
the page-animation event used by reflowable documents.

On animation-capable devices, **More config...** contains **Page turn
animations** and **Sync page animations with KOReader**. Synchronization is on
by default: Panels+ follows KOReader's global **Page turn animations** setting,
and changes made in either menu update it. Turn synchronization off to keep a
separate Panels+ animation preference.

## Smooth navigation

Native page-turn animation is incompatible with Smooth navigation, so Panels+
temporarily suppresses it while Smooth is selected. The saved on/off preference
is not changed and becomes effective again when navigation returns to Classic.

For fixed-layout documents, smooth navigation renders the union of the old and
new panel rectangles from the document page, places that result on a temporary
canvas, then pans the camera across it. The key operation is effectively:

```lua
document:drawPagePart(page, union_of_panel_rectangles, 0)
```

An embedded image has no `page`/`drawPagePart()` coordinate pair. Passing its
image-space rectangles to that API would crop unrelated text-page content, or
fail. Embedded images instead render the union directly from their retained
decoded bitmap, then use the same camera-pan logic as fixed-layout panels.

The **Nav. Smooth** control is enabled for panels on the same embedded image.
Its preference is separate from fixed-layout documents, and a source-union cap
falls back to an instant panel switch before making a large temporary bitmap.

Smooth animation **between images** is a separate, more expensive problem:
the images may be on different reflow pages, have unrelated sizes, and require
a page turn plus an asynchronous search before the next image is known. The
camera-pan scope therefore remains limited to panels of the same image.
Image-to-image boundaries use the single native KOReader page animation
described above when the device and reader setting support it, or the classic
instant handoff otherwise.

## What remains available

- Manga/Comic reading order. The viewer re-detects and reorders the same image.
- Strict, loose, margin, and no-crop modes. The viewer rebuilds from the
  retained source bitmap when a crop needs new pixels.
- Tap/swipe configuration, progress bar, screenshots, zoom, and rotation.
- Forward/backward image flow: after a boundary, Panels+ moves through text
  pages until it finds another embedded image whose panel layout is accepted.

## Practical roadmap

1. Add image fixtures for manga, comics, dark pages, SVG/raster edge cases,
   and small inline images to tune Outline further.
2. Consider a richer image-space outline detector for layouts the current
   higher-resolution border pass cannot separate.

These alternatives are intentionally scoped to extracted EPUB/KEPUB/MOBI images.
They do not change the fixed-page algorithms or add work to CBZ/CBR/PDF reads.
