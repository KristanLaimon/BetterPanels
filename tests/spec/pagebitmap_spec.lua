--- Specs for colour-aware background sampling in `src/_pagebitmap.lua`.
---
--- These stay render-free: they exercise the same RGB measurements used by the
--- page-map builder without needing a document or a real blitbuffer.

local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert = framework.describe, framework.it, framework.assert

local PageBitmap = require("src._pagebitmap")

describe("PageBitmap colour-aware background sampling", function()
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
end)
