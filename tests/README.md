# PanelsPlus Test Suite & Panel Detection Benchmark

This directory contains the unit tests, integration specs, real-world datasets, and benchmarking tools for PanelsPlus.

## Architecture Overview

```
tests/
├── PanelsPlusTestFramework.lua    # Dependency-free Lua test framework (describe, it, assert)
├── dataset-mangas/                # Manga evaluation suite & OpenMantra dataset
│   ├── dataset/                   # OpenMantra Dataset (214 pages, 1,069 annotated frames)
│   │   ├── annotation.json        # Ground-truth frames and text annotations
│   │   └── images/                # 5 series: tojime_no_siora, balloon_dream, tencho_isoro, etc.
│   ├── dataset_loader.lua         # Converts image files into PPPageMap using ImageMagick streaming
│   ├── dataset_manifest.lua       # Indexes books, pages, and ground truth from datasets
│   ├── panel_evaluator.lua        # Calculates IoU, Precision, Recall, F1, and Reading Order
│   └── report/                    # Architectural benchmarks & detection improvement reports
├── helpers/
│   └── json.lua                   # Pure-Lua JSON decoder for manifests and annotations
├── run_tests.lua                  # Primary test runner (executes all spec files)
└── spec/                          # Unit and integration specifications
    ├── dataset_benchmark_spec.lua # Golden manga regression spec (<1.5s)
    └── ...
```

---

## Running the Tests

### 1. Fast Unit Test Suite
Runs all 22 test specifications in under 2 seconds:
```bash
lua tests/run_tests.lua
```

### 2. Code Quality and Linter
Formats with StyLua and validates with Luacheck:
```bash
./check.sh
```

---

## Panel Segmentation Benchmark Tool

A dedicated CLI tool (`tools/benchmark_panels.lua`) evaluates panel detection across real manga and comic pages.

The reader's connected-component detector can be evaluated with
`./run-benchmark.sh --detector components --all`. The default benchmark remains
the original Lua segmenter so its historical `bestbenchmark.json` records stay
comparable.

Every local volume has a separate `components_full_volume` production baseline.
Tests guard precision, recall, F1, and mean IoU to the four-decimal record
precision, without rewriting records. A passing regression test means scores
were preserved; it does **not** mean every metric reached 95%. The existing
Komi/Scott F1, recall, and IoU gates remain in place, but Scott's precision is
currently below 95%, and Bloom/Kobayashi's recall and F1 are below 95%.

Run `PANELSPLUS_REQUIRE_DATASETS=1 lua tests/run_tests.lua` to require all private
page images. Otherwise unavailable full-volume production checks are reported
as skipped. The loader keeps one page map in memory; under LuaJIT it uses the
same byte-array storage as the reader. Preload real FFI for a native-array run:
`luajit -l ffi tests/run_tests.lua`.

### Evaluate the Curated Golden Set
```bash
lua tools/benchmark_panels.lua
```

### Evaluate Every Discovered Dataset
```bash
lua tools/benchmark_panels.lua --all
```

### Evaluate a Specific Book or Page
```bash
lua tools/benchmark_panels.lua --book tojime_no_siora
lua tools/benchmark_panels.lua --book rasetugari --page 1
```

### Strict Matching & Failures Only
```bash
lua tools/benchmark_panels.lua --threshold 0.75 --failures-only
```

---

## Evaluation Metrics Explained

The benchmark calculates standard computer vision evaluation metrics:
- **IoU (Intersection over Union)**: Overlap area divided by union area of detected vs ground-truth bounding box.
- **Precision**: Fraction of detected panels that matched a ground-truth panel ($\text{IoU} \ge 0.5$).
- **Recall**: Fraction of ground-truth panels successfully detected ($\text{IoU} \ge 0.5$).
- **F1 Score**: Harmonic mean of Precision and Recall ($2 \times \frac{P \times R}{P + R}$).
- **Reading Order**: Verifies top-to-bottom/right-to-left ordering for manga and top-to-bottom/left-to-right ordering for comics.

---

---

## Manga Panel Annotator & Private Dataset

A PyQt6 desktop annotator application is provided to build custom ground-truth manga/comic datasets by hand:

```bash
# Launch annotator app
python3 tests/dataset-mangas/annotator.py

# Or launch directly with a comic file
python3 tests/dataset-mangas/annotator.py path/to/manga.cbz
```

### Supported Formats
- Comic archives: `.cbz`, `.cbr` (via `unrar` / `bsdtar`)
- Documents: `.pdf`, `.epub`, `.kepub.epub`, `.mobi` (via `PyMuPDF`)
- Image collections: folders of `.jpg`, `.jpeg`, `.png`, `.webp`

### Key Annotator Controls & Shortcuts
- **Click & Drag**: Draw panel bounding rectangles in sequential reading order. Each new box receives the next badge number (`[1]`, `[2]`, `[3]`...).
- **Full Page Panel (`F`)**: Instantly creates a panel bounding box covering the entire page (useful for splash pages and full-page spreads).
- **Resize & Move**: Click any rectangle to reveal 8 resize handles for fine adjustment, or drag inside the box to reposition.
- **Panel Reordering**: Use **Move Up** / **Move Down** buttons in the sidebar to reorder panels without redrawing.
- **Delete Panel (`Del` / `Backspace`)**: Remove the currently selected panel.
- **Save Dataset (`Ctrl+S`)**: Exports rendered/extracted page images to `images/<book_title>/` and updates `annotation.json` compatible with PanelsPlus.
- **Page Navigation**: `A` / `Left Arrow` for Previous Page, `D` / `Right Arrow` for Next Page, plus page slider and spinbox.

### Running Benchmarks Against Private Datasets
Once pages are annotated and saved:
```bash
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset-private
# Or evaluate a specific book/page:
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset-private --book my_manga --page 1
```

---

## Licensing & Compliance

- **PanelsPlus Codebase**: MIT License (permits commercial redistribution).
- **Dataset Privacy**: Your hand-crafted annotations and images stay strictly local under `tests/dataset-mangas/dataset-private/`.
- **Packaging Boundary**: The `build.sh` script packages only `src/`, `locales/`, and plugin metadata into `dist/`. The `tests/` directory is never bundled into plugin release zip files.
