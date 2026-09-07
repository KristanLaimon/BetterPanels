--- Spec tests for panel detection against real manga pages from `tests/dataset-manga`.
---
--- Evaluates detection accuracy, IoU alignment, and stability against
--- representative real-world pages in the golden set.

local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert = framework.describe, framework.it, framework.assert

local Manifest = require("tests.dataset-mangas.dataset_manifest")
local Loader = require("tests.dataset-mangas.dataset_loader")
local Evaluator = require("tests.dataset-mangas.panel_evaluator")
local Segmenter = require("src._segmenter")
local Geometry = require("src._geometry")

describe("Manga dataset golden set panel detection", function()
    local golden_pages = Manifest.getGoldenPages()

    it("loads all golden pages and their ground-truth frames", function()
        assert.is_true(#golden_pages >= 5, "Expected at least 5 golden pages")
        for _, page in ipairs(golden_pages) do
            assert.is_not_nil(page.book_title)
            assert.is_true(#page.book_title > 0)
            assert.is_not_nil(page.page_index)
            assert.is_true(page.page_index > 0)
            assert.is_not_nil(page.image_path)
            assert.is_true(#page.image_path > 0)
            assert.is_not_nil(page.frames)
            assert.is_true(#page.frames > 0)
        end
    end)

    it("calculates accurate box IoU metrics", function()
        local box1 = { x = 0, y = 0, w = 100, h = 100 }
        local box2 = { x = 50, y = 0, w = 100, h = 100 }
        -- Intersection: 50x100 = 5000; Union: 10000 + 10000 - 5000 = 15000; IoU = 1/3
        local iou = Evaluator.boxIoU(box1, box2)
        assert.near(1 / 3, iou, 0.001)

        -- Identical boxes -> 1.0
        assert.near(1.0, Evaluator.boxIoU(box1, box1), 0.001)

        -- Non-overlapping -> 0.0
        local box3 = { x = 200, y = 200, w = 50, h = 50 }
        assert.equals(0, Evaluator.boxIoU(box1, box3))
    end)

    it("segments real manga pages without crashing and extracts valid panels", function()
        for _, page in ipairs(golden_pages) do
            local map = Loader.loadPageMap(page.image_path)
            assert.is_true(map.w > 0 and map.h > 0)
            assert.is_true(map.native_w > 0 and map.native_h > 0)
            assert.is_true(map.ink > 0)

            local raw_panels = Segmenter.segment(map, { mode = page.reading_order })
            local detected = Geometry.sortReadingOrder(raw_panels, page.reading_order)
            assert.is_true(#detected > 0, "Expected at least 1 detected panel on page " .. page.page_index)

            local eval_result = Evaluator.evaluate(page.frames, detected)
            assert.equals(#page.frames, eval_result.ground_truth_count)
            assert.equals(#detected, eval_result.detected_count)
            -- Verify all detected panels stay within native bounds
            for _, p in ipairs(detected) do
                assert.is_true(p.x >= 0 and p.x < map.native_w)
                assert.is_true(p.y >= 0 and p.y < map.native_h)
                assert.is_true(p.w > 0 and p.h > 0)
            end
        end
    end)

    it("successfully identifies multi-panel layout on rasetugari page 1", function()
        local page = Manifest.getPage("rasetugari", 1)
        assert.is_not_nil(page)

        local map = Loader.loadPageMap(page.image_path)
        local raw_panels = Segmenter.segment(map, { mode = "manga" })
        local detected = Geometry.sortReadingOrder(raw_panels, "manga")
        local result = Evaluator.evaluate(page.frames, detected)

        -- Detected panels should achieve high precision and matched IoU
        assert.is_true(result.precision >= 0.75, "Expected precision >= 75%")
        assert.is_true(result.mean_iou >= 0.80, "Expected matched IoU >= 0.80")
        assert.is_true(result.true_positives >= 3, "Expected at least 3 matched panels")
    end)
end)
