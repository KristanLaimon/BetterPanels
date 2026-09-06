--- Reflow image-panel flow: cross a reader-page boundary and keep seeking.
local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert, spy = framework.describe, framework.it, framework.assert, framework.spy

local EmbeddedImage = require("src.embedded_image")
local UIManager = require("ui/uimanager")

describe("EmbeddedImage boundary flow", function()
    it("turns the reader page, closes the old viewer, and seeks the next image", function()
        local close = spy()
        local handle = spy()
        local seek = spy()
        local old_close, old_tick = UIManager.close, UIManager.tickAfterNext
        UIManager.close = close
        UIManager.tickAfterNext = function(_, callback)
            UIManager._embedded_image_test_callback = callback
            return true
        end

        local plugin = {
            ui = {
                document = {
                    getCurrentPage = function()
                        return 4
                    end,
                    getNextPage = function(_, page)
                        return page == 4 and 5 or 0
                    end,
                },
                handleEvent = handle,
            },
            openNextEmbeddedImagePage = seek,
        }
        local viewer = {}

        assert.is_true(EmbeddedImage.onEmbeddedImageBoundary(plugin, "next", viewer))
        assert.is_true(close:called(), "old panel viewer should close before the page turn")
        assert.equals("GotoPage", handle:lastCall()[2].name)
        assert.equals(5, handle:lastCall()[2].args[1])

        UIManager._embedded_image_test_callback()
        assert.equals(5, seek:lastCall()[2])
        assert.equals("next", seek:lastCall()[3])

        UIManager.close, UIManager.tickAfterNext = old_close, old_tick
    end)
end)
