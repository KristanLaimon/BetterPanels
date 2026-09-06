--- Regression coverage for panel reading order.

local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert = framework.describe, framework.it, framework.assert

local Geometry = require("src._geometry")

local function panel(id, x, y, w, h)
    return { id = id, x = x, y = y, w = w, h = h }
end

local function orderedIDs(panels)
    local ids = {}
    for _, rect in ipairs(panels) do
        table.insert(ids, rect.id)
    end
    return table.concat(ids, ",")
end

describe("Geometry.sortReadingOrder comic mode", function()
    it("keeps vertically staggered tiers out of one left-to-right row", function()
        -- The former union-find grouping links each neighbouring pair and
        -- turns all three panels into one row. It consequently sorts by x as
        -- middle, top, bottom, even though the top panel must be read first.
        local panels = {
            panel("middle", 0, 40, 100, 100),
            panel("bottom", 220, 80, 100, 100),
            panel("top", 220, 0, 100, 100),
        }

        Geometry.sortReadingOrder(panels, "comic")

        assert.equals("top,middle,bottom", orderedIDs(panels))
    end)

    it("reads panels with a shared tier top from left to right", function()
        local panels = {
            panel("right", 220, 4, 100, 96),
            panel("left", 0, 0, 200, 140),
        }

        Geometry.sortReadingOrder(panels, "comic")

        assert.equals("left,right", orderedIDs(panels))
    end)
end)

describe("Geometry.sortReadingOrder manga mode", function()
    it("keeps vertically staggered tiers out of one right-to-left row", function()
        local panels = {
            panel("middle", 220, 40, 100, 100),
            panel("bottom", 0, 80, 100, 100),
            panel("top", 0, 0, 100, 100),
        }

        Geometry.sortReadingOrder(panels, "manga")

        assert.equals("top,middle,bottom", orderedIDs(panels))
    end)

    it("reads panels with a shared tier top from right to left", function()
        local panels = {
            panel("right", 220, 4, 100, 96),
            panel("left", 0, 0, 200, 140),
        }

        Geometry.sortReadingOrder(panels, "manga")

        assert.equals("right,left", orderedIDs(panels))
    end)
end)
