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

A dedicated CLI tool (`tools/benchmark_panels.lua`) is provided to evaluate panel detection across real manga pages:

### Evaluate the Curated Golden Set
```bash
lua tools/benchmark_panels.lua
```

### Evaluate the Entire 214-Page Manga Dataset
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
- **Reading Order**: Verifies that detected panels are sorted in exact chronological reading order (top-to-bottom, right-to-left for manga).

---

## Adding Custom Test Pages

To add your own manga or comic pages for testing:
1. Place the image (JPG or PNG) under `tests/dataset-mangas/dataset/images/custom_book/ja/001.jpg` (or in a new subfolder).
2. Add the page entry and ground truth frames to `tests/dataset-mangas/dataset/annotation.json`:
   ```json
   {
     "book_title": "custom_book",
     "pages": [
       {
         "page_index": 1,
         "image_paths": {
           "ja": "images/custom_book/ja/001.jpg"
         },
         "frame": [
           { "x": 50, "y": 60, "w": 400, "h": 300 },
           { "x": 480, "y": 60, "w": 400, "h": 300 }
         ]
       }
     ]
   }
   ```
3. Run the benchmark tool on your custom page:
   ```bash
   lua tools/benchmark_panels.lua --book custom_book --page 1
   ```

---

## Licensing & Compliance

- **PanelsPlus Codebase**: MIT License (permits commercial redistribution).
- **`tests/dataset-mangas/dataset`**: Licensed under **Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)** from the OpenMantra project (Ryota Hinami et al., AAAI 2021).
- **Packaging Boundary**: The `build.sh` script packages only `src/`, `locales/`, and plugin metadata into `dist/`. The `tests/` directory is never bundled into plugin release zip files.
