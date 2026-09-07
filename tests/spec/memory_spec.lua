local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert = framework.describe, framework.it, framework.assert

local Memory = require("src._memory")

describe("Memory allocation reservation", function()
    it("requires the safety floor and the next allocation to fit together", function()
        local original_free_bytes = Memory.freeBytes
        Memory.freeBytes = function()
            return 150
        end

        assert.is_false(Memory.hasAllocationHeadroom(100, 51))
        assert.is_true(Memory.hasAllocationHeadroom(100, 50))

        Memory.freeBytes = original_free_bytes
    end)
end)
