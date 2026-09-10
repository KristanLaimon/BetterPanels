# Component detector candidate — 2026-09-09

The candidate reaches 90% precision and recall on **each** of the two local
volumes. It is available through `--detector components`; it is not yet wired
into the reader. The reader currently uses `NativeDetector`, while the existing
benchmark and historical records evaluate `Segmenter`. The baseline numbers
below therefore describe the benchmarked segmenter, not measured native-reader
performance.

## Full-volume results

The annotation files, 480-pixel map width, IoU threshold of 0.50, and existing
35-native-pixel coordinate tolerance are unchanged. All 356 pages were evaluated.

| Book / detector | Precision | Recall | F1 | Entire page correct, including order |
| --- | ---: | ---: | ---: | ---: |
| Bloom Into You 8 — segmenter | 74.58% | 86.09% | 79.92% | 86/213 (40.38%) |
| Bloom Into You 8 — components | 94.80% | 90.36% | 92.52% | 169/213 (79.34%) |
| Miss Kobayashi 2 — segmenter | 70.17% | 62.63% | 66.19% | 40/143 (27.97%) |
| Miss Kobayashi 2 — components | 96.36% | 90.27% | 93.22% | 105/143 (73.43%) |

Bloom: 726 annotated panels, 692 candidate detections, 656 matches.
Kobayashi: 586 annotated panels, 549 candidate detections, 529 matches.
The exact 90% recall floor requires 654 and 528 matches respectively, so recall
has only a small margin above the requested target at this map resolution.

These datasets informed the candidate design and parameter selection. These
results are measured corpus performance, not an independent held-out estimate
or a guarantee for other manga. A 90% whole-page target has **not** been reached.

## Candidate behavior

- Follow 8-connected ink regions, retaining thin frames and tilted layouts.
- Drop components that are too small to be panels.
- Require evidence of all four frame edges for narrow or short candidates.
- Suppress regions contained in a larger component's box.
- Apply the existing full-page fallback and reading-order sorter.
- Clip the one-map-cell crop padding to the native page boundaries.

The input map is never modified. LuaJIT scratch arrays use five bytes per map
cell, approximately 1.5 MB for a 480-by-637 map, plus the candidate boxes. Device
latency, native rendering differences, and reader integration are not validated.

## Decisions pending before reader integration

1. Does “correctness” mean panel recall or complete pages including reading order?
2. Bloom dataset page 10 (`09.png`) annotates its two top framed scenes as one
   group where a speech balloon crosses the divider. Confirm that this grouping
   is intentional before adopting that behavior in the reader.
3. Confirm switching the reader to the validated manga candidate with native
   detection retained as a fallback, rather than keeping this as an experiment.

Containment suppression also needs care: it removes duplicate speech-balloon
regions, but can lose intentional insets. Bloom annotations contain nested boxes
on pages 46, 50, 67, 94, and 98. The current scores include these limitations;
the annotations have not been changed. Borderless art, joined regions, small
panels, and four pure reading-order mismatches in Kobayashi also remain.

## Reproduce

From the repository root, use LuaJIT with real FFI arrays (as in KOReader):

```sh
luajit -l ffi tools/benchmark_panels.lua --detector components --book Bloom_Into_You_Vol_8
luajit -l ffi tools/benchmark_panels.lua --detector components --book "Miss_Kobayashi's_Dragon_Maid_Vol_2"
```

Plain Lua is also supported through the existing test stubs:

```sh
./run-benchmark.sh --detector components --all
```

`--detector segmenter` remains the default. Candidate runs do not overwrite the
existing segmenter records; combining `--detector components --update-best` is
rejected explicitly.

Seven new synthetic regressions cover thin frames, tilted connectivity,
containment versus overlapping boxes, letterboxes versus unframed marks, native
coordinate clipping, sparse title pages, blank pages, and the panel-count limit.
The existing segmenter remains unchanged.
