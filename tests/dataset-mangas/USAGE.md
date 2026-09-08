# Manga Panel Annotator & Private Dataset Guide

This guide explains how to use the Manga Panel Annotator desktop application to create your own ground-truth panel datasets by hand from real manga and comic books.

---

## Table of Contents
1. [Overview](#overview)
2. [Dataset Structure & DMCA Protection](#dataset-structure--dmca-protection)
3. [Supported Formats](#supported-formats)
4. [Launching the Annotator](#launching-the-annotator)
5. [Recent Projects Library (KOReader Style)](#recent-projects-library-koreader-style)
6. [Step-by-Step Workflow](#step-by-step-workflow)
7. [Keyboard & Mouse Controls](#keyboard--mouse-controls)
8. [Dataset Storage & Schema](#dataset-storage--schema)
9. [Running Benchmarks with Your Private Dataset](#running-benchmarks-with-your-private-dataset)
10. [Automated Tests](#automated-tests)

---

## Overview

Automated panel detectors can struggle with edge cases such as:
- Speech bubbles bridging across panel borders.
- Irregular, diagonal, or borderless panel layouts.
- Full-page splash panels misidentified as multiple pieces or missed entirely.
- Random ghost panels caused by background textures.

The **Manga Panel Annotator** allows you to search your system for comic and book archives, extract them into ordered page sequences, and hand-annotate panel bounding boxes with live progress tracking, book covers, and reading-order sequence numbers.

---

## Dataset Structure & DMCA Protection

Datasets are stored in:
```text
tests/dataset-mangas/dataset/<bookfriendlyname>/
├── 00.png             # Cover / Page 1 (git included)
├── 01.png             # Page 2         (git included)
├── 02.png             # Page 3         (git included)
├── 03.png             # Page 4+        (GIT-IGNORED)
├── ...
├── metadata.json      # Book progress & finished status
└── annotation.json    # Book panel annotations
```

> [!IMPORTANT]
> **DMCA Protection Rule**:
> To allow sharing annotations publicly while respecting copyright, the repository's `.gitignore` automatically **includes only the first 3 preview pages** (`00.png`, `01.png`, and `02.png`) so people know which volume/edition the dataset belongs to. All subsequent pages from `03.png` forward are **strictly gitignored**.

---

## Supported Formats

The annotator handles all popular comic and digital book formats:
- **Comic Archives**: `.cbz`, `.cbr` (unrar / bsdtar extraction)
- **E-Books & Documents**: `.pdf`, `.epub`, `.kepub.epub`, `.mobi` (PyMuPDF high-DPI rendering)
- **Image Collections**: Folders containing `.png`, `.jpg`, `.jpeg`, `.webp` images

---

## Launching the Annotator

From the repository root:

```bash
# General launcher (opens to Recent Projects library)
python3 tests/dataset-mangas/annotator.py

# Open a specific file directly
python3 tests/dataset-mangas/annotator.py /path/to/manga.cbz

# Or launch directly from tests/dataset-mangas/dataset/
python3 tests/dataset-mangas/dataset/app.py
```

---

## Recent Projects Library (KOReader Style)

When launched, the application presents the **📚 Recent Projects** tab:
- **Book Cards**: Shows each comic book in your dataset folder.
- **Cover Thumbnail**: Automatically renders `00.png` with book aspect ratio and shadow.
- **Progress Bar & Percentage**: Shows current annotation progress (e.g. `65% (13 of 20 pages annotated)`).
- **Status Badges**: Displays `[FINISHED]` in vibrant green or `[IN PROGRESS]` in orange.
- **Finished Shortcut**: Press **`Ctrl+M`** (or click the checkmark button) to toggle a book's finished state.
- **Quick Continue**: Click **▶ Continue** (or double-click the card) to immediately jump into annotation mode at your last read page.
- **Filter Bar**: Type in the search box to filter books by title.

---

## Step-by-Step Workflow

### 1. Open a File
- Click **File -> Open Comic File...** (or `Ctrl+O`) and choose your comic file (`.cbz`, `.cbr`, `.pdf`, `.epub`, etc.).
- Or click **File -> Open Image Folder...** if you have a folder of loose page images.

### 2. Verify Book Title & Output Folder
- In the right sidebar under **Dataset & Book**:
  - Check the **Book Title** field. It defaults to the file name stem (e.g. `naruto_ch01`). You can edit it if needed.
  - The **Output Folder** defaults to `tests/dataset-mangas/dataset-private`. Click **Change Output Folder...** if you want to store it elsewhere.

### 3. Navigate Pages
- Use **Next (D)** and **Prev (A)** or the left/right arrow keys to flip pages.
- Use the slider or number box at the bottom to jump to a specific page.

### 4. Annotate Panels
- **Draw Rectangles**: Click and drag with the left mouse button across each panel in the exact order you want them read.
- **Sequential Badges**: Each box displays its sequence number (`[1]`, `[2]`, `[3]`...).
- **Full-Page Panels**: If the entire page is a single splash image or spread, press **`F`** (or click **Add Full Page Panel (F)**) to instantly create a box covering the entire page `(0, 0, width, height)`.
- **Special Panels with Speech Bubbles**: You can draw boxes that encompass the artwork and speech bubbles without being constrained by grid lines.

### 5. Adjust, Fine-Tune & Reorder Panels
- **Undo / Redo**: Press **`Ctrl+Z`** to undo any panel placement, resize, or deletion. Press **`Ctrl+Y`** (or `Ctrl+Shift+Z`) to redo.
- **🎯 Precision Mouse Fine-Tuning**: When working on tight margins or corner pixels, check **🎯 Precision Fine-Tuning** (or press **`P`**). Slow, deliberate mouse movements will automatically be dampened (up to 4× slower) so you can hit corners with single-pixel accuracy without changing your operating system DPI. You can also hold **`Shift`** at any time during drawing or resizing to temporarily engage precision damping.
- **Resize**: Click any box to select it. Eight handles appear on the corners and edges; drag any handle to adjust down to the pixel.
- **Move**: Click and drag inside a selected box to reposition it.
- **Reorder**: If you drew panels out of order, select a panel in the sidebar list and click **▲ Move Up** or **▼ Move Down** to adjust its reading sequence.
- **Delete**: Select a panel and press `Delete` (or `Backspace`), or click **Delete (Del)**.
- **Clear**: Click **Clear Page** to remove all panels on the current page.

### 6. Save the Dataset & Mark Finished
- Click **💾 Save Dataset (Ctrl+S)**.
- The annotator will:
  1. Save individual pages (`00.png`, `01.png`, `02.png`...) and metadata inside `dataset/<bookfriendlyname>/`.
  2. Maintain `metadata.json` with progress % and status.
  3. Compile the master `annotation.json` compatible with PanelsPlus benchmarks.
- Press **`Ctrl+M`** when you've finished annotating all panels in the book to mark it as **`[FINISHED]`**.

---

## Keyboard & Mouse Controls

| Action | Control / Shortcut | Description |
|---|---|---|
| **Draw Panel** | `Left Click + Drag` | Draw bounding box in reading order |
| **Undo** | `Ctrl + Z` | Undo last panel draw, resize, move, or delete |
| **Redo** | `Ctrl + Y` or `Ctrl + Shift + Z` | Redo previously undone action |
| **🎯 Precision Fine-Tuning** | `P` or toggle checkbox | Dampens mouse speed on slow motions for pixel-perfect corner alignment |
| **Temporary Precision** | Hold `Shift` while dragging | Dynamically enables precision speed damping |
| **Full-Page Panel** | `F` | Create a panel covering the whole page |
| **Select Panel** | `Left Click` | Select a panel to view handles and details |
| **Deselect** | `Right Click` or `Escape` | Clear selection or cancel active drag |
| **Resize Box** | Drag border handles | 8 handles (corners and edges) |
| **Move Box** | Drag inside selected box | Reposition the rectangle |
| **Delete Panel** | `Delete` or `Backspace` | Remove selected panel |
| **Mark Finished** | `Ctrl + M` | Toggle book status between `[IN PROGRESS]` and `[FINISHED]` |
| **Next Page** | `D` or `Right Arrow` | Go to next page |
| **Prev Page** | `A` or `Left Arrow` | Go to previous page |
| **Zoom In / Out** | `Ctrl + Wheel` or `Ctrl +` / `Ctrl -` | Zoom centered on cursor |
| **Fit Window** | `View -> Fit Window` | Scale page to fit window dimensions |
| **Fit Width** | `View -> Fit Width` | Scale page width to fit window |
| **Zoom 100%** | `View -> Zoom 100%` | Reset to 1:1 pixel scale |
| **Pan Canvas** | `Middle Click + Drag` or `Space + Left Drag` | Move around zoomed page |
| **Save Dataset** | `Ctrl + S` | Export pages and save `annotation.json` |

---

## Dataset Storage & Schema

The output directory (default: `tests/dataset-mangas/dataset`) will contain:

```text
dataset/
├── <bookfriendlyname>/
│   ├── 00.png             # Cover / Page 1 (git-tracked)
│   ├── 01.png             # Page 2         (git-tracked)
│   ├── 02.png             # Page 3         (git-tracked)
│   ├── 03.png             # Page 4+        (git-ignored for DMCA protection)
│   ├── ...
│   ├── metadata.json      # Book progress % & finished status
│   └── annotation.json    # Book panel annotations
└── annotation.json        # Compiled master dataset manifest
```

### `annotation.json` Schema
The output strictly matches PanelsPlus's `dataset_manifest.lua` format:

```json
[
  {
    "book_title": "my_manga",
    "pages": [
      {
        "page_index": 1,
        "image_paths": {
          "ja": "my_manga/00.png"
        },
        "frame": [
          { "x": 50, "y": 60, "w": 400, "h": 300 },
          { "x": 50, "y": 380, "w": 400, "h": 500 }
        ]
      }
    ]
  }
]
```

Coordinates (`x`, `y`, `w`, `h`) are saved in the native pixel resolution of the page image.

---

## Running Benchmarks with Your Private Dataset

Once you have annotated pages, you can evaluate PanelsPlus's segmentation accuracy directly against your hand-crafted data using the benchmark tool:

```bash
# Evaluate all pages in your private dataset (default location)
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset

# Evaluate a specific book
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset --book my_manga

# Inspect a specific page with full box coordinates & IoU breakdown
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset --book my_manga --page 1

# Only report pages with detection discrepancies
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset --failures-only

# Strict IoU threshold (default is 0.50)
lua tools/benchmark_panels.lua --dataset tests/dataset-mangas/dataset --threshold 0.75
```

---

## Automated Tests

To ensure the annotator engine and reader backends are working correctly:

```bash
# Run annotator test suite (headless)
python3 -m unittest tests/dataset-mangas/annotator/test_annotator.py

# Run full PanelsPlus test suite
lua tests/run_tests.lua
```
