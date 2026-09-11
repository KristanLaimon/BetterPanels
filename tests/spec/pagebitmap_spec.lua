--- Specs for colour-aware background sampling in `src/_pagebitmap.lua`.
---
--- These stay render-free: they exercise the same RGB measurements used by the
--- page-map builder without needing a document or a real blitbuffer.

local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert = framework.describe, framework.it, framework.assert

local PageBitmap = require("src._pagebitmap")

describe("PageBitmap colour-aware background sampling", function()
    it("normalizes extracted-image detection to the fixed-page target raster", function()
        local width, height = PageBitmap._detectionRasterSize(1600, 2400, 480)
        assert.equals(480, width)
        assert.equals(720, height)

        -- Fixed-page rendering does not enlarge smaller source pages, and
        -- embedded images must retain that same behaviour.
        width, height = PageBitmap._detectionRasterSize(400, 600, 480)
        assert.equals(400, width)
        assert.equals(600, height)

        -- Keep an extracted vertical strip bounded too: it must never create
        -- an unbounded map merely because its width is already small.
        width, height = PageBitmap._detectionRasterSize(400, 2400, 480)
        assert.equals(160, width)
        assert.equals(960, height)
    end)

    it("estimates a conservative temporary resize working set", function()
        local bytes = PageBitmap._embeddedResizeWorkingSetBytes(1600, 2400, 480, 720)
        assert.equals(1600 * 2400 * 4 + 480 * 720 * 8 + 4 * 1024 * 1024, bytes)
    end)

    it("skips a resize when its allocation would breach the memory floor", function()
        local Memory = require("src._memory")
        local original_check = Memory.hasAllocationHeadroom
        local requested_floor, requested_bytes
        Memory.hasAllocationHeadroom = function(floor, bytes)
            requested_floor, requested_bytes = floor, bytes
            return false
        end

        assert.is_false(PageBitmap._hasEmbeddedResizeHeadroom(1600, 2400, 480, 720))
        assert.equals(15 * 1024 * 1024, requested_floor)
        assert.equals(PageBitmap._embeddedResizeWorkingSetBytes(1600, 2400, 480, 720), requested_bytes)

        Memory.hasAllocationHeadroom = original_check
    end)

    it("computes bounded sparse sampling step for low-memory fallback", function()
        -- Normal aspect ratio
        assert.equals(3, PageBitmap._embeddedSparseStep(1600, 2400, 480))
        -- Small image
        assert.equals(1, PageBitmap._embeddedSparseStep(400, 600, 480))
        -- Tall reflow image: caps step so height does not exceed target_width * 2
        assert.equals(3, PageBitmap._embeddedSparseStep(400, 2400, 480))
    end)

    it("skips copy and returns original bb when image already fits within bounds", function()
        local bb = { w = 400, h = 600 }
        local raster, owned, resampled = PageBitmap._makeEmbeddedDetectionRaster(bb, 480)
        assert.equals(bb, raster)
        assert.is_nil(owned)
        assert.is_false(resampled)
    end)

    it("resizes when memory headroom is available and marks raster as owned", function()
        local Memory = require("src._memory")
        local RenderImage = require("ui/renderimage")
        local original_check = Memory.hasAllocationHeadroom
        local original_scale = RenderImage.scaleBlitBuffer
        Memory.hasAllocationHeadroom = function()
            return true
        end

        local fake_copy = { w = 1600, h = 2400 }
        local copied = false
        local fake_bb = {
            w = 1600,
            h = 2400,
            copy = function()
                copied = true
                return fake_copy
            end,
        }
        local fake_raster = { w = 480, h = 720 }
        RenderImage.scaleBlitBuffer = function(self, bb_arg, w, h, free_orig)
            assert.equals(fake_copy, bb_arg)
            assert.equals(480, w)
            assert.equals(720, h)
            assert.is_true(free_orig)
            return fake_raster
        end

        local raster, owned, resampled = PageBitmap._makeEmbeddedDetectionRaster(fake_bb, 480)
        assert.is_true(copied)
        assert.equals(fake_raster, raster)
        assert.equals(fake_raster, owned)
        assert.is_true(resampled)

        Memory.hasAllocationHeadroom = original_check
        RenderImage.scaleBlitBuffer = original_scale
    end)

    it("falls back to bounded sparse sampling and frees copy when resize throws error", function()
        local Memory = require("src._memory")
        local RenderImage = require("ui/renderimage")
        local original_check = Memory.hasAllocationHeadroom
        local original_scale = RenderImage.scaleBlitBuffer
        Memory.hasAllocationHeadroom = function()
            return true
        end

        local freed = false
        local fake_copy = {
            w = 1600,
            h = 2400,
            free = function()
                freed = true
            end,
        }
        local fake_bb = {
            w = 1600,
            h = 2400,
            copy = function()
                return fake_copy
            end,
        }
        RenderImage.scaleBlitBuffer = function()
            error("simulated scaling failure")
        end

        local raster, owned, resampled = PageBitmap._makeEmbeddedDetectionRaster(fake_bb, 480)
        assert.equals(fake_bb, raster)
        assert.is_nil(owned)
        assert.is_false(resampled)
        assert.is_true(freed, "intermediate copy must be freed if scaling fails")

        Memory.hasAllocationHeadroom = original_check
        RenderImage.scaleBlitBuffer = original_scale
    end)

    it("uses the border's solid RGB colour as the background", function()
        local background = { r = 145, g = 120, b = 0 }
        local panel = { r = 0, g = 170, b = 75 }
        local function sample(x, y)
            if x == 0 or y == 0 or x == 5 or y == 5 then
                return background.r, background.g, background.b
            end
            return panel.r, panel.g, panel.b
        end

        local r, g, b = PageBitmap._estimateBackground(sample, 6, 6)
        assert.equals(background.r, r)
        assert.equals(background.g, g)
        assert.equals(background.b, b)
    end)

    it("keeps a same-luminance coloured panel distinct from its background", function()
        -- These colours differ by only five luminance levels, so the old
        -- greyscale-only map treated the panel and backdrop as the same area.
        local background = { r = 145, g = 120, b = 0 }
        local panel = { r = 0, g = 170, b = 75 }

        assert.near(
            PageBitmap._luminance(background.r, background.g, background.b),
            PageBitmap._luminance(panel.r, panel.g, panel.b),
            5
        )
        assert.is_true(
            PageBitmap._colourDistance(panel.r, panel.g, panel.b, background.r, background.g, background.b) > 40
        )
    end)

    it("keeps greyscale threshold behaviour unchanged", function()
        assert.equals(42, PageBitmap._colourDistance(42, 42, 42, 0, 0, 0))
    end)

    it("does not block documents without configurable table", function()
        assert.is_nil(PageBitmap.getBlockReason({}))
        assert.is_nil(PageBitmap.getBlockReason({ configurable = { text_wrap = 0 } }))
        assert.equals("reflow mode", PageBitmap.getBlockReason({ configurable = { text_wrap = 1 } }))
        local mock_kopt = {
            is_optimizing_page = function()
                return true
            end,
        }
        assert.equals(
            "page optimization enabled",
            PageBitmap.getBlockReason({ configurable = { text_wrap = 0 }, koptinterface = mock_kopt })
        )
    end)
end)
