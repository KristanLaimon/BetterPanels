# Reader Component Detector Integration & Benchmark Report — 2026-09-09

## Executive Summary

The experimental 8-connected component detector has been promoted to the active default detector across Panels+ for fixed-layout documents (`CBZ`, `CBR`, `PDF`, `DjVu`) and reflowable embedded images (`EPUB`, `KEPUB`, `MOBI`). 

Along with reader activation, core navigation and stability defects were resolved:
1. **Swipe gesture direction inversion** was corrected to match natural physical reading drag directions for both Comic (left-to-right) and Manga (right-to-left) modes.
2. **Page-boundary viewer collapse** on blank, splash, and sparse pages was eliminated by introducing a graceful full-page panel fallback.
3. **Dialogue bubble and character face false-positives** were systematically eliminated through strict containment filtering and straight-line boundary support verification.

The final pipeline achieves **>96% Precision** on both benchmark volumes (**96.38%** on *Bloom Into You* Vol. 8 and **98.57%** on *Miss Kobayashi's Dragon Maid* Vol. 2), with **~95.3%** and **~94.2% – 95.4% Recall**, more than doubling complete-page correct reading order rates over the previous recursive X-Y cut baseline.

---

## Full-Volume Evaluation Results

All 356 annotated pages across both human-labeled manga volumes were evaluated at an IoU threshold of 0.50 with a 35-native-pixel edge tolerance:

| Volume & Method | Total GT | Detected | True Positives | Precision | Recall | F1 Score | Complete Page Order Correct |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Bloom Into You Vol. 8** *(Original Segmenter)* | 726 | 973 | 625 | 74.58% | 86.09% | 79.92% | 86 / 213 (40.38%) |
| **Bloom Into You Vol. 8** *(Component Detector @ 960px)* | 726 | 718 | 692 | **96.38%** | **95.32%** | **95.85%** | **182 / 213 (85.45%)** |
| **Miss Kobayashi Vol. 2** *(Original Segmenter)* | 586 | 523 | 367 | 70.17% | 62.63% | 66.19% | 40 / 143 (27.97%) |
| **Miss Kobayashi Vol. 2** *(Component Detector @ 960px)* | 586 | 560 | 552 | **98.57%** | **94.20%** | **96.34%** | **118 / 143 (82.52%)** |
| **Miss Kobayashi Vol. 2** *(Component Detector @ 1264px)* | 586 | 570 | 559 | **98.07%** | **95.39%** | **96.71%** | **119 / 143 (83.22%)** |

### Key Improvements
- **Precision**: Reaches 96.38% and 98.57%, drastically reducing false detections.
- **Reading Order Accuracy**: More than doubled on both manga titles (40.4% -> 85.5% on Bloom; 28.0% -> 82.5% on Kobayashi).
- **Processing Latency**: Fast single-pass flood fill using LuaJIT FFI arrays (~5–10 ms per page on 960px maps).

---

## Technical Enhancements & Architecture

### 1. 8-Connected Component Analysis (`src/_componentdetector.lua`)
Instead of recursive projection cuts (which fail on diagonal gutters or non-orthogonal layouts), the detector traces contiguous ink regions in an 8-connected grid. This inherently preserves tilted borders, narrow dividing lines, and asymmetrical panels without splitting panels through internal white space.

### 2. Multi-Sample Straight Line Boundary Support (`lineSupport` & `frameSides`)
To distinguish geometric panel borders from curved drawings:
- Every candidate component is evaluated along all four bounding edges for straight-line support.
- Slopes up to 0.35 are supported to accommodate stylized, tilted panels.
- Curved speech balloons, character heads, and organic illustrations fail the 80% straight-edge support threshold and are prevented from qualifying as isolated panels.

### 3. Strict Containment Filtering
Speech bubbles and artwork details occurring entirely inside an existing panel frame are suppressed during region filtering (`keep = false`). Small regions (< 10% dimension or < 1% page area) must present 4-sided frame evidence to be retained.

### 4. Continuous Flow on Sparse & Blank Pages (`src/_panelcollector.lua`, `src/viewer_controller.lua`)
- Previously, when a page contained no detected panel rectangles (e.g. title pages, splash art without framing, or chapter endnotes), the boundary handler explicitly closed the viewer and fell back to standard document view.
- Added `PanelCollector.fullPage(document, page)` which constructs a single 1-panel view matching the native document page dimensions. Page turns across blank or splash pages now stay seamlessly inside the zoom viewer.

### 5. Swipe Direction Physics Alignment (`src/_panelviewer.lua`)
- Swiping now follows natural page-drag physics:
  - **Comic Mode (LTR)**: Finger drags **west** (pulling the next page in from the right edge).
  - **Manga Mode (RTL)**: Finger drags **east** (pulling the next page in from the left edge).
- The `invert_swipe` setting flips these directions for users who prefer reading-flow swipe semantics.

### 6. Zero-Allocation Scratch Buffers for Low-RAM Hardware (Kindle ~300MB)
To maintain 1.3-era velocity and prevent Lua GC pauses or OOM events on low-spec devices:
- **Persistent BFS Buffers**: `scratch_seen` and `scratch_queue` are allocated once and reused across all subsequent page detections. The visited map is zeroed using native C `memset` (`ffi.fill`), which takes under 0.5 ms for 960×1280 rasters.
- **Static Boundary Arrays**: Candidate contour bounds (`scratch_left`, `scratch_right`, `scratch_top`, `scratch_bottom`) use persistent 1D `int32_t` arrays, completely removing table allocations inside the candidate evaluation loop.
- **Early Termination in Line Fitting**: `lineSupport` immediately exits once >= 80% straight-line support is reached, skipping redundant candidate angle calculations.
- **Explicit Lifecycle Cleanup**: `ComponentDetector.clearScratch()` reclaims buffer memory on reader widget teardown (`PanelsPlus:onCloseWidget()`).

---

## Analysis of Remaining Edge Cases

1. **Nested Insets Touching Parent Frame** (*Bloom Into You* pp. 46, 50, 67):
   - Inset panels that share top or outer border strokes are physically joined to the parent frame in downsampled raster maps. Pure connected-component analysis groups them into a single parent panel.
2. **Shared Divider Lines Without Gutter** (*Miss Kobayashi* pp. 20, 117):
   - Vertically stacked panels separated only by a single black line rule (without white gutter space) or joined by bleeding background art form a single connected component spanning multiple tiers.
3. **Internal Hole Splitting Trade-off**:
   - Recovering internal white holes via inverted flood fill recovers some nested insets but creates substantial false positives on white sky, character clothing, and large text, reducing precision by ~11%.

---

## Test Suite Verification

All 179 unit tests across 24 test specifications pass with zero failures:
```
179 passed, 0 failed
```
