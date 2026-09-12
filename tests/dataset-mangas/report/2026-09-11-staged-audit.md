# Dataset and memory audit — 2026-09-11

The staged implementation does not achieve 95% in every accuracy metric on
every dataset. These are the measured production (`components`) results, before
and after the audit changes, at IoU 0.50 with the existing 35-pixel edge tolerance:

| Dataset | Pages | Precision | Recall | F1 | Mean matched IoU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Bloom Into You | 213 | 96.75% | 90.22% | 93.37% | 0.9369 |
| Komi Can't Communicate | 190 | 97.28% | 95.58% | 96.42% | 0.9708 |
| Miss Kobayashi's Dragon Maid | 143 | 95.01% | 90.96% | 92.94% | 0.9569 |
| Scott Pilgrim | 218 | 94.44% | 97.37% | 95.89% | 0.9553 |

The default benchmark measures the legacy segmenter. Its F1 scores remain
79.92%, 87.59%, 66.19%, and 80.37%, respectively. Existing historical records
for Bloom and Kobayashi remain unchanged; separate production records were
added, plus both detector baselines for the two new datasets.

## Findings and changes

- The new tests checked F1, recall, and matched IoU above 95%, but omitted a
  precision floor. Scott's 94.44% precision therefore passed. Production
  baseline checks now cover all four metrics on all four datasets. The existing
  95% gates remain for Komi and Scott; baseline preservation is not presented
  as meeting the unfinished universal 95% target.
- The regression tracker allowed F1/recall to drop 0.5 percentage points and
  IoU to drop 0.02, while ignoring precision. Only four-decimal record rounding
  is now allowed. Tests no longer update their own expected results.
- Benchmark `--all` previously did not check any historical records, and a
  reported regression did not cause a failing exit status. Both are fixed.
  Production records use `components_full_volume`; legacy records retain
  `full_volume`. Custom IoU thresholds do not overwrite default records.
- Full-volume production tests now report unavailable images as skipped, with
  `PANELSPLUS_REQUIRE_DATASETS=1` available to require all images.
- The dataset loader retained a Lua table of pixels for every visited page.
  It now retains one map, using byte arrays with real LuaJIT FFI. In an isolated
  20-page check, retained Lua heap growth fell from 80.835 MiB to 1.114 MiB.
  This saving is in the benchmark/test loader; it is not a measurement of
  KOReader's total memory usage.
- The runtime white-separator scan now stops once a row/column certainly
  passes or cannot possibly reach the unchanged 80% threshold. It needs no
  additional pixel buffers. On a synthetic 480×640 dark page, 200 scans took
  0.611 s before and 0.193 s after on this host. This is a focused CPU check,
  not a Kindle page-turn timing claim.
- Comic-only `color_mode` accepts `true_b/w`, `colorless_b/w`, or `color`.
  Scott is `colorless_b/w`. The annotator and manifest validate/preserve this
  metadata; it does not change the algorithm. Legacy comics may omit it
  rather than having their artwork history guessed. Root annotation files
  also resolve each book's own metadata correctly.

## Evidence and limits

The full before/after audit produced identical panel rectangles and evaluation
results on all 764 pages for both detectors. A separate real-FFI check through
the production bitmap builder produced identical ink maps, border maps, and
background estimates for all 764 cached page rasters. Boundary tests cover
79%, 80%, and 81% white separators, both orientations, sampling stride, and
legitimate dense side-stack layouts that must not be rejected as page furniture.

The staged page-furniture heuristic remains unchanged. Its narrow geometric
and density conditions reduce its reach, but passing these datasets cannot
guarantee that it never rejects an unseen legitimate sparse comic layout.
Likewise, desaturated test rasters do not validate detection of original-color
editions. Matching still uses the existing tolerance and matched-page IoU
averaging; these numbers are not strict-IoU-only scores.

No physical Kindle or 300 MiB process cap was used. Source-image decoding,
KOReader rendering, and the rest of the reader's working set still need device
measurement. The production optimization changes neither detector thresholds
nor page-map dimensions.

Reproduce the volume checks with:

```sh
PANELSPLUS_REQUIRE_DATASETS=1 luajit -l ffi tests/run_tests.lua
luajit -l ffi tools/benchmark_panels.lua --all --detector components --summary-only
luajit -l ffi tools/benchmark_panels.lua --all --summary-only
```

The original staged diff SHA-256 is
`ff41f3ddaac5ea50c8905335f51cd851d6a9312778eaf4caf0fd3e87797fe1a0`.
All audit changes are unstaged; no commit, push, or author attribution was made.

Validation: 217 LuaJIT tests passed with all datasets required and no skips;
27 Python annotator tests passed; Lua lint reported no warnings or errors.
The changed Lua files pass formatting checks. Repository-wide formatting
still reports pre-existing differences in untouched `src/_componentdetector.lua`.
