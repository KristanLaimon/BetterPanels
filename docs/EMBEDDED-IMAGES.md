# Embedded EPUB and MOBI images

Panels+ supports images embedded in reflowable `.epub` and `.mobi` books.
Long-press an image: Panels+ extracts that bitmap, finds its panels, and opens
the usual panel reader. At the first or last panel it turns reader pages and
looks for the previous or next image with a usable panel layout.

This is deliberately different from CBZ/CBR/PDF. Those formats expose a
fixed document page, while EPUB/MOBI are laid out again whenever font,
margins, orientation, or line spacing change.

## Why `Detector` is disabled

The **Quick** detector is available implicitly: it runs on the extracted image
bitmap and is what opens the embedded-image panel viewer.

The disabled **Detector** button normally cycles through Quick, Smart, and
Deep. Smart and Deep are not merely different bitmap-processing settings:
their fallback is KOReader's native panel detector. That detector needs all of
the following:

1. A fixed document page number and native page dimensions.
2. A K2PDFOpt rendering context for that page.
3. Rectangles in the same page coordinate system that `drawPagePart()` uses.

An EPUB/MOBI hold supplies Panels+ with the decoded image only. It does not
supply a stable rectangle for that image in the reflowed document. Its
position can change after any typography setting changes, and the native
K2PDFOpt path is not available for CREngine reflow pages. Calling the native
detector anyway would either return no panels or return rectangles that cannot
be used to crop the extracted bitmap safely.

So this is possible in a broader sense, but it would be a **new image-space
outline detector**, not KOReader's existing Deep detector. It could inspect
the extracted bitmap directly, much like Quick does, and provide a second
algorithm for difficult layouts. That is a reasonable future feature, but it
needs its own implementation, tuning, memory limits, and image fixtures; it
cannot safely be enabled by reusing the current native detector.

## Why `Nav. Smooth` is disabled

For fixed-layout documents, smooth navigation renders the union of the old and
new panel rectangles from the document page, places that result on a temporary
canvas, then pans the camera across it. The key operation is effectively:

```lua
document:drawPagePart(page, union_of_panel_rectangles, 0)
```

An embedded image has no `page`/`drawPagePart()` coordinate pair. Passing its
image-space rectangles to that API would crop unrelated text-page content, or
fail. This is why enabling the existing option would be misleading and could
produce a bad render.

Unlike Deep detection, **smooth navigation inside one embedded image is
plausible**. Panels+ retains the decoded source bitmap, so a dedicated
image-space implementation could crop the union from that bitmap and reuse
the existing camera animation. It should be implemented behind a renderer
callback rather than special-casing document drawing in `PanelViewer`.

Smooth animation **between images** is a separate, more expensive problem:
the images may be on different reflow pages, have unrelated sizes, and require
a page turn plus an asynchronous search before the next image is known. The
safe first scope would therefore be smooth movement between panels of the same
image, with classic movement retained for image-to-image boundaries.

## What remains available

- Manga/Comic reading order. The viewer re-detects and reorders the same image.
- Strict, loose, margin, and no-crop modes. The viewer rebuilds from the
  retained source bitmap when a crop needs new pixels.
- Tap/swipe configuration, progress bar, screenshots, zoom, and rotation.
- Forward/backward image flow: after a boundary, Panels+ moves through text
  pages until it finds another embedded image whose panel layout is accepted.

## Practical roadmap

1. Add an image-space renderer callback to `PanelViewer`, then implement
   same-image smooth transitions with existing memory safeguards.
2. Add a second, image-space detector for layouts Quick cannot separate.
3. Only expose it as an EPUB/MOBI detector choice after it has fixtures for
   manga, comics, dark pages, SVG/raster edge cases, and small inline images.

The current disabled controls are therefore intentional capability boundaries,
not a claim that the features are impossible. They prevent fixed-page code
from operating on a reflow image with incompatible coordinates.
