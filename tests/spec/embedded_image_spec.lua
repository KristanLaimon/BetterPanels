--- Reflow image-panel flow: cross a reader-page boundary and keep seeking.
local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert, spy = framework.describe, framework.it, framework.assert, framework.spy

local EmbeddedImage = require("src.embedded_image")
local PanelViewer = require("src._panelviewer")
local UIManager = require("ui/uimanager")

describe("EmbeddedImage boundary flow", function()
    it("turns the reader page, keeps the viewer up, and seeks the next image", function()
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
        assert.is_false(close:called(), "old panel viewer must stay up while the next image is being found")
        assert.equals("GotoPage", handle:lastCall()[2].name)
        assert.equals(5, handle:lastCall()[2].args[1])

        UIManager._embedded_image_test_callback()
        assert.equals(5, seek:lastCall()[2])
        assert.equals("next", seek:lastCall()[3])
        assert.equals(viewer, seek:lastCall()[4], "the found image should replace this viewer without a reader flash")

        UIManager.close, UIManager.tickAfterNext = old_close, old_tick
    end)
end)

describe("EmbeddedImage smooth boundaries", function()
    it("keeps a cross-image boundary classic while same-image smooth rendering is available", function()
        local boundary = spy()
        boundary.return_value = true
        local animated = spy()
        local viewer = PanelViewer:new({
            nav_transition_mode = "smooth",
            nav_transition_cross_page = true,
            image_union_renderer = function()
                return nil
            end,
            boundary_callback = boundary,
            animateBoundaryTransition = animated,
        })

        assert.is_true(viewer:onPanelBoundary("next"))
        assert.is_true(boundary:called())
        assert.is_false(animated:called())
    end)
end)

describe("EmbeddedImage backward landing", function()
    it("marks a previous-page image to open on its last panel", function()
        local show = spy()
        show.return_value = true
        local image = {}
        local plugin = {
            ui = {
                document = {},
            },
            findEmbeddedImageOnCurrentPage = function()
                return image
            end,
            showEmbeddedImagePanelsForImage = show,
        }

        assert.is_true(EmbeddedImage.openNextEmbeddedImagePage(plugin, 4, "previous", {}))
        assert.equals(image, show:lastCall()[2])
        assert.equals("previous", show:lastCall()[3].boundary_direction)
    end)
end)
