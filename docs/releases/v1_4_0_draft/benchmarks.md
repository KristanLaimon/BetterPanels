  They are Panel Detection Algorithms (or Panel Detection Engines).

  In PanelsPlus, there are 3 detector engines in total:
  ──────
  ### 1. components — Connected-Components Detector (Active Default)

  • File: _componentdetector.lua
  • Algorithm: Connected-Component Analysis (8-connected pixel region grouping + frame boundary fitting).
  • How it works: It analyzes ink density and finds connected artwork/border contours.
  • Why it's better: It easily handles tilted panel borders, speech bubbles breaking borders, and colored/gray gutters
  without needing straight, page-wide cuts.
  ──────
  ### 2. segmenter — Recursive X-Y Cut Segmenter (Legacy Prototype)

  • File: _segmenter.lua
  • Algorithm: Recursive X-Y Projection Cut (Top-down splitting).
  • How it works: It scans the page for full horizontal and vertical white gaps (gutters) and recursively slices the
  page into smaller boxes.
  • Drawback: If a single panel is tilted or has artwork "bleeding" across a gutter, the straight cut fails and merges
  multiple panels together.
  ──────
  ### 3. native — KOReader Native Detector (Fallback)

  • File: _nativedetector.lua
  • Algorithm: KOReader’s built-in k2pdfopt C-library detector.
  • How it works: Probe-point sampling through KOReader's document engine.
  • Role: Used as a fallback if a document page cannot produce a bitmap.



  ### Efficacy Comparison (Full 764-Page Volume Evaluation)

   Metric                      │ Legacy segmenter (X-Y Cut) │ New components (Active Reader Detector) │   Improvement
  ─────────────────────────────┼────────────────────────────┼─────────────────────────────────────────┼─────────────────
   Global Precision            │           78.2%            │                  95.8%                  │     +17.6%
   Global Recall               │           80.5%            │                  93.8%                  │     +13.3%
   Global F1 Score             │           79.4%            │                  94.8%                  │     +15.4%
   Average Matched IoU         │            0.89            │                  0.95                   │      +0.06
   Perfect Reading Order Pages │     358 / 764 (46.9%)      │            626 / 764 (81.9%)            │     +35.0%
  ──────
  ### Per-Dataset Breakdown

  Each dataset's bestbenchmark.json records two separate baseline blocks:

  • "full_volume" (the legacy detector record)
  • "components_full_volume" (the production detector record)

   Volume                             │ Metric                  │    Legacy segmenter     │ New components (Production)
  ────────────────────────────────────┼─────────────────────────┼─────────────────────────┼─────────────────────────────
   Bloom Into You Vol 8               │ F1 / Precision / Recall │  79.9% / 74.6% / 86.1%  │    93.4% / 96.8% / 90.2%
   Komi Can't Communicate Vol 1       │ F1 / Precision / Recall │  87.6% / 89.8% / 85.5%  │    96.4% / 97.3% / 95.6%
   Miss Kobayashi's Dragon Maid Vol 2 │ F1 / Precision / Recall │  66.2% / 70.2% / 62.6%  │    92.9% / 95.0% / 91.0%
   Scott Pilgrim Vol 5                │ F1 / Precision / Recall │  80.4% / 77.2% / 83.8%  │    95.9% / 94.4% / 97.4%
  ──────
  ### How the Tests Use Them

  1. Production Tests (new_dataset_benchmark_spec.lua:70): Tests run the production ComponentDetector against the cached
  page maps, asserting that accuracy never drops below components_full_volume baselines (and enforcing >95% gates for
  Komi & Scott).
  2. Benchmark Tool (benchmark_panels.lua): Allows running --detector components or --detector segmenter (or --all) to
  check either or both algorithms for regressions at any time.



 ### 1. ¿Qué significan Precision, Recall y F1 Score?

  En la detección de paneles de cómic/manga:

  • Precision (Precisión): "De los paneles que la IA encontró, ¿cuántos fueron correctos?"
      • Fórmula: Paneles correctos detectados/Total de paneles que el detector dijo encontrar
      • Ejemplo: Si el detector marca 10 recuadros en la página, pero 1 es falso positivo (un texto flotante o espacio
      en blanco), la Precision es del 90% (9/10).
      • Importancia: Alta precisión evita que la pantalla haga zoom en cosas que no son paneles.
  • Recall (Exhaustividad / Cobertura): "De todos los paneles reales que existen en la página, ¿cuántos logró
  encontrar?"
      • Fórmula: Paneles correctos detectados/Total de paneles reales dibujados por el autor
      • Ejemplo: Si la página tiene 10 paneles reales pero la IA solo detecta 9 y se salta 1, el Recall es del 90%
      (9/10).
      • Importancia: Alto recall evita que el lector se salte paneles mientras lee.
  • F1 Score: "La nota global equilibrada"
      • Fórmula: 2 × (Precision × Recall)/(Precision + Recall)
      • Es el promedio armónico entre Precision y Recall. Garantiza que la puntuación solo sea alta si ambas métricas
      son excelentes.

  ──────
  ### 2. Totales de Páginas y Paneles en tus Datasets

  Tienes 4 volúmenes completos en tus datasets con los siguientes totales:

   Dataset                            │ Tipo                   │        Páginas         │ Paneles Reales (Ground Truth)
  ────────────────────────────────────┼────────────────────────┼────────────────────────┼───────────────────────────────
   Bloom Into You Vol 8               │ Manga                  │          213           │              726
   Komi Can't Communicate Vol 1       │ Manga                  │          190           │              747
   Miss Kobayashi's Dragon Maid Vol 2 │ Manga                  │          143           │              586
   Scott Pilgrim Vol 5                │ Comic                  │          218           │              838
   TOTAL COMBINADO                    │                        │      764 páginas       │         2,897 paneles

