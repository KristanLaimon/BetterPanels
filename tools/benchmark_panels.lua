#!/usr/bin/env lua
--- Panel segmentation benchmark and evaluation tool for manga and comic datasets.
---
--- Usage:
---   lua tools/benchmark_panels.lua                         # Evaluates golden manga pages
---   lua tools/benchmark_panels.lua --all                   # Evaluates all 214 manga pages
---   lua tools/benchmark_panels.lua --book tojime_no_siora  # Evaluates one book
---   lua tools/benchmark_panels.lua --book tojime_no_siora --page 2 # Detailed box inspect
---   lua tools/benchmark_panels.lua --failures-only         # Only reports pages with issues
---   lua tools/benchmark_panels.lua --threshold 0.75        # Strict IoU threshold

local script_dir = arg[0]:match("(.*/)") or "./"
local repo_root = script_dir .. "../"
package.path = repo_root .. "?.lua;" .. repo_root .. "?/init.lua;" .. package.path

require("tests.spec.helper")

local Manifest = require("tests.dataset-mangas.dataset_manifest")
local Loader = require("tests.dataset-mangas.dataset_loader")
local Evaluator = require("tests.dataset-mangas.panel_evaluator")
local Segmenter = require("src._segmenter")
local BenchmarkTracker = require("tests.dataset-mangas.benchmark_tracker")

-- Parse CLI arguments
local target_book = nil
local target_page = nil
local run_all = false
local failures_only = false
local update_best = false
local detector_name = "segmenter"
local iou_threshold = 0.5
local dataset_dir = repo_root .. "tests/dataset-mangas/dataset"

local idx = 1
while idx <= #arg do
    local a = arg[idx]
    if a == "--all" then
        run_all = true
    elseif a == "--failures-only" then
        failures_only = true
    elseif a == "--update-best" or a == "--update" then
        update_best = true
    elseif a == "--book" and arg[idx + 1] then
        idx = idx + 1
        target_book = arg[idx]
    elseif a == "--page" and arg[idx + 1] then
        idx = idx + 1
        target_page = tonumber(arg[idx])
    elseif a == "--threshold" and arg[idx + 1] then
        idx = idx + 1
        iou_threshold = tonumber(arg[idx]) or 0.5
    elseif a == "--dataset" and arg[idx + 1] then
        idx = idx + 1
        dataset_dir = arg[idx]
    elseif a == "--detector" and arg[idx + 1] then
        idx = idx + 1
        detector_name = arg[idx]
    end
    idx = idx + 1
end

local detector = Segmenter
if detector_name == "components" then
    detector = require("src._componentdetector")
elseif detector_name ~= "segmenter" then
    io.stderr:write("Unknown detector: " .. detector_name .. " (choose segmenter or components)\n")
    os.exit(1)
end
if update_best and detector_name ~= "segmenter" then
    io.stderr:write("Experimental component results must not overwrite segmenter benchmark records.\n")
    os.exit(1)
end

-- Select pages to evaluate
local pages = {}
if target_book and target_page then
    local p = Manifest.getPage(target_book, target_page, dataset_dir)
    if not p then
        io.stderr:write(string.format("Page not found: book=%s, page=%d\n", target_book, target_page))
        os.exit(1)
    end
    table.insert(pages, p)
elseif target_book then
    local books = Manifest.loadManga(dataset_dir)
    for _, b in ipairs(books) do
        if b.book_title == target_book then
            for _, p in ipairs(b.pages) do
                table.insert(pages, p)
            end
        end
    end
    if #pages == 0 then
        io.stderr:write(string.format("Book not found: %s\n", target_book))
        os.exit(1)
    end
elseif run_all then
    pages = Manifest.getAllPages(dataset_dir)
else
    pages = Manifest.getGoldenPages(dataset_dir)
end

if #pages == 0 then
    print(string.format("No pages found in dataset directory '%s'.", dataset_dir))
    print("Run the annotator app (python3 tests/dataset-mangas/annotator.py) to build your dataset,")
    print("or specify --dataset <path> pointing to your annotated dataset folder.")
    os.exit(0)
end

print(string.format("Evaluating %d page(s) (IoU threshold: %.2f)...", #pages, iou_threshold))
print("Detector: " .. detector_name)
print(string.rep("-", 80))

local total_gt = 0
local total_det = 0
local total_tp = 0
local sum_f1 = 0
local sum_iou = 0
local evaluated_count = 0
local total_order_ok = 0
local page_count = 0
local failure_count = 0

for _, page in ipairs(pages) do
    if page.frames and #page.frames > 0 then
        local map = Loader.loadPageMap(page.image_path)
        local detected = detector.detectPage(map, { mode = page.reading_order })
        local result = Evaluator.evaluate(page.frames, detected, iou_threshold, 35)

        total_gt = total_gt + result.ground_truth_count
        total_det = total_det + result.detected_count
        total_tp = total_tp + result.true_positives
        sum_f1 = sum_f1 + result.f1
        if result.true_positives > 0 then
            sum_iou = sum_iou + result.mean_iou
            evaluated_count = evaluated_count + 1
        end
        if result.reading_order_correct then
            total_order_ok = total_order_ok + 1
        end
        page_count = page_count + 1

        local is_imperfect = (result.f1 < 0.99 or not result.reading_order_correct)
        if is_imperfect then
            failure_count = failure_count + 1
        end

        if not failures_only or is_imperfect then
            local status_symbol = is_imperfect and "[x]" or "[o]"
            print(
                string.format(
                    "%s %-16s p.%-2d | GT: %d  Det: %d  TP: %d | Prec: %5.1f%%  Rec: %5.1f%%  F1: %5.1f%% | mIoU: %.2f | Order: %s",
                    status_symbol,
                    page.book_title,
                    page.page_index,
                    result.ground_truth_count,
                    result.detected_count,
                    result.true_positives,
                    result.precision * 100,
                    result.recall * 100,
                    result.f1 * 100,
                    result.mean_iou,
                    result.reading_order_correct and "OK     " or "MISMATCH"
                )
            )

            if #result.failures > 0 then
                print("    Issues: " .. table.concat(result.failures, ", "))
            end

            -- If single-page mode, print detailed box coordinates
            if target_page then
                print("\n  Ground Truth Panels:")
                for gi, gb in ipairs(page.frames) do
                    print(string.format("    GT %d: x=%4d y=%4d w=%4d h=%4d", gi, gb.x, gb.y, gb.w, gb.h))
                end
                print("\n  Detected Panels:")
                for di, db in ipairs(detected) do
                    print(
                        string.format(
                            "    Det %d: x=%4d y=%4d w=%4d h=%4d",
                            di,
                            math.floor(db.x),
                            math.floor(db.y),
                            math.floor(db.w),
                            math.floor(db.h)
                        )
                    )
                end
            end
        end
    end
end

print(string.rep("-", 80))
local global_prec = total_det > 0 and (total_tp / total_det) or 0
local global_rec = total_gt > 0 and (total_tp / total_gt) or 0
local global_f1 = (global_prec + global_rec > 0) and (2 * global_prec * global_rec / (global_prec + global_rec)) or 0
local avg_page_f1 = page_count > 0 and (sum_f1 / page_count) or 0
local avg_m_iou = evaluated_count > 0 and (sum_iou / evaluated_count) or 0

print("SUMMARY METRICS:")
print(string.format("  Pages Evaluated:       %d (%d with issues)", page_count, failure_count))
print(string.format("  Total Panels:          %d Ground Truth, %d Detected, %d Matched", total_gt, total_det, total_tp))
print(string.format("  Global Precision:      %.1f%%", global_prec * 100))
print(string.format("  Global Recall:         %.1f%%", global_rec * 100))
print(string.format("  Global F1 Score:       %.1f%%", global_f1 * 100))
print(string.format("  Average Page F1:       %.1f%%", avg_page_f1 * 100))
print(string.format("  Average Matched IoU:   %.2f", avg_m_iou))
print(
    string.format(
        "  Perfect Reading Order: %d/%d (%.1f%%)",
        total_order_ok,
        page_count,
        page_count > 0 and (total_order_ok * 100 / page_count) or 0
    )
)

if target_book and not target_page and detector_name == "segmenter" then
    local book_dir = dataset_dir .. "/" .. target_book
    local is_full = (page_count >= 100)
    local mode = is_full and "full_volume" or "preview"
    local current_metrics = {
        pages_evaluated = page_count,
        total_ground_truth = total_gt,
        total_detected = total_det,
        true_positives = total_tp,
        precision = global_prec,
        recall = global_rec,
        f1 = global_f1,
        mean_iou = avg_m_iou,
        gap_tolerance = 35,
        iou_threshold = iou_threshold,
    }
    local ok, reason = BenchmarkTracker.checkAndUpdate(book_dir, mode, current_metrics, update_best)
    if not ok then
        print("\n  [REGRESSION ALERT] " .. tostring(reason))
    end
end
