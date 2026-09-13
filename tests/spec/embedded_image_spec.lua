--- Reflow image-panel flow: cross a reader-page boundary and keep seeking.
local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert, spy = framework.describe, framework.it, framework.assert, framework.spy

local EmbeddedImage = require("src.embedded_image")
local PanelViewer = require("src._panelviewer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen

describe("EmbeddedImage KEPUB compatibility", function()
    it("opens image panels for direct and Kobo-synced KEPUB filenames", function()
        for _, filename in ipairs({ "/books/manga.kepub", "/books/manga.kepub.epub", "/books/MANGA.KEPUB" }) do
            local opened = spy()
            opened.return_value = true
            local image = {
                getType = function()
                    return 1
                end,
            }
            local plugin = {
                ui = {
                    rolling = true,
                    document = {
                        file = filename,
                        getImageFromPosition = function()
                            return image
                        end,
                    },
                },
                showEmbeddedImagePanelsForImage = opened,
            }
            local cleared = spy()
            local highlight = {
                view = {
                    screenToPageTransform = function()
                        return { x = 10, y = 20 }
                    end,
                },
                clear = cleared,
            }

            assert.is_true(EmbeddedImage.showEmbeddedImagePanels(plugin, highlight, { pos = { x = 1, y = 1 } }))
            assert.equals(image, opened:lastCall()[2], filename .. " should use the embedded-image panel path")
            assert.is_true(cleared:called())
        end
    end)
end)

describe("EmbeddedImage boundary flow", function()
    it("turns the reader page, keeps the viewer up, and seeks the next image", function()
        local close = spy()
        local handle = spy()
        local seek = spy()
        local cancel_animation = spy()
        local old_close, old_tick = UIManager.close, UIManager.tickAfterNext
        local old_set_swipe_animations = Screen.setSwipeAnimations
        UIManager.close = close
        Screen.setSwipeAnimations = function(...)
            return cancel_animation(...)
        end
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
        local release_source = spy()
        local viewer = {
            releaseEmbeddedSource = release_source,
        }

        assert.is_true(EmbeddedImage.onEmbeddedImageBoundary(plugin, "next", viewer))
        assert.is_false(close:called(), "old panel viewer must stay up while the next image is being found")
        assert.equals("GotoPage", handle:lastCall()[2].name)
        assert.equals(5, handle:lastCall()[2].args[1])
        assert.equals(false, cancel_animation:lastCall()[2])
        assert.is_true(release_source:called())
        assert.equals(true, release_source:lastCall()[2])

        UIManager._embedded_image_test_callback()
        assert.equals(5, seek:lastCall()[2])
        assert.equals("next", seek:lastCall()[3])
        assert.equals(viewer, seek:lastCall()[4], "the found image should replace this viewer without a reader flash")

        UIManager.close, UIManager.tickAfterNext = old_close, old_tick
        Screen.setSwipeAnimations = old_set_swipe_animations
    end)

    it("cancels every hidden search turn, including pages without an image", function()
        local handle = spy()
        local cancel_animation = spy()
        local old_tick = UIManager.tickAfterNext
        local old_set_swipe_animations = Screen.setSwipeAnimations
        UIManager.tickAfterNext = function(_, callback)
            UIManager._embedded_image_test_callback = callback
            return true
        end
        Screen.setSwipeAnimations = function(...)
            return cancel_animation(...)
        end

        local plugin = {
            ui = {
                document = {
                    getNextPage = function(_, page)
                        return page + 1
                    end,
                },
                handleEvent = handle,
            },
            findEmbeddedImageOnCurrentPage = function()
                return nil
            end,
            _embedded_search_generation = 7,
        }
        local viewer = {}
        plugin._embedded_search_viewer = viewer

        assert.is_true(EmbeddedImage.openNextEmbeddedImagePage(plugin, 5, "next", viewer, 7))
        assert.equals("GotoPage", handle:lastCall()[2].name)
        assert.equals(6, handle:lastCall()[2].args[1])
        assert.equals(1, cancel_animation:callCount())
        assert.equals(false, cancel_animation:lastCall()[2])

        UIManager.tickAfterNext = old_tick
        Screen.setSwipeAnimations = old_set_swipe_animations
    end)
end)

describe("EmbeddedImage native page animation", function()
    it("arms one normal page animation only when replacing the source viewer", function()
        local PageBitmap = require("src._pagebitmap")
        local ComponentDetector = require("src._componentdetector")
        local old_build = PageBitmap.buildFromBlitbuffer
        local old_detect = ComponentDetector.detectPage
        local old_close, old_show = UIManager.close, UIManager.show
        PageBitmap.buildFromBlitbuffer = function()
            return {}
        end
        ComponentDetector.detectPage = function()
            return { { x = 0, y = 0, w = 600, h = 800 } }
        end
        UIManager.close = function() end
        UIManager.show = function() end

        local arm_animation = spy()
        local plugin = {
            settings = {
                mode = "manga",
                crop_mode = "strict",
                embedded_nav_transition_mode = "classic",
            },
            ui = {},
            armPageTurnAnimation = arm_animation,
        }
        local function image()
            return {
                w = 600,
                h = 800,
                getType = function()
                    return 1
                end,
            }
        end

        assert.is_true(EmbeddedImage.showEmbeddedImagePanelsForImage(plugin, image()))
        assert.is_false(arm_animation:called(), "initial opens must not look like page turns")

        local source_viewer = {}
        assert.is_true(EmbeddedImage.showEmbeddedImagePanelsForImage(plugin, image(), {
            replace_viewer = source_viewer,
            boundary_direction = "next",
        }))
        assert.equals(1, arm_animation:callCount())
        assert.equals("next", arm_animation:lastCall()[2])
        assert.equals(source_viewer, arm_animation:lastCall()[3])

        PageBitmap.buildFromBlitbuffer = old_build
        ComponentDetector.detectPage = old_detect
        UIManager.close, UIManager.show = old_close, old_show
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

describe("EmbeddedImage source lifetime", function()
    it("releases the full source and lazy navigation closures during a boundary search", function()
        local free = spy()
        local viewer = PanelViewer:new({
            embedded_source_image = { free = free },
            image_union_renderer = function() end,
            _images_list = { function() end },
            image_rects = { {} },
            panels = { {} },
            panel_is_full_page = { false },
        })

        viewer:releaseEmbeddedSource(true)

        assert.is_true(free:called())
        assert.equals(nil, viewer.embedded_source_image)
        assert.equals(nil, viewer.image_union_renderer)
        assert.equals(nil, viewer._images_list)
        assert.equals(nil, viewer.image_rects)
        assert.equals(nil, viewer.panels)
    end)

    it("consumes navigation while its source has been released for a boundary search", function()
        local viewer = PanelViewer:new({
            _panels_plus_boundary_pending = true,
            _images_list_cur = 2,
            _images_list_nb = 2,
        })

        assert.is_true(viewer:onShowNextImage())
        assert.is_true(viewer:onShowPrevImage())
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

describe("EmbeddedImage device rotation", function()
    it("reopens the viewer at the current panel across screen rotation", function()
        local show = spy()
        show.return_value = true
        local close = spy()
        local broadcast = spy()
        local rotated = spy()
        local old_close, old_broadcast, old_rotation = UIManager.close, UIManager.broadcastEvent, UIManager.onRotation
        UIManager.close = close
        UIManager.broadcastEvent = broadcast
        UIManager.onRotation = rotated

        local image = { w = 800, h = 1200 }
        local plugin = {
            showEmbeddedImagePanelsForImage = show,
        }
        local viewer = {
            panels = { { x = 0, y = 0, w = 400, h = 600 }, { x = 400, y = 0, w = 400, h = 600 } },
            _images_list_cur = 2,
            embedded_source_image = image,
            buttons_visible = true,
        }

        assert.is_true(EmbeddedImage.setDeviceRotation(plugin, viewer, 1))
        assert.is_true(close:called())
        assert.is_true(broadcast:called())
        assert.equals("SetRotationMode", broadcast:lastCall()[2].name)
        assert.equals(1, broadcast:lastCall()[2].args[1])
        assert.is_true(rotated:called())
        assert.equals(image, show:lastCall()[2])
        assert.equals(600, show:lastCall()[3].start_point.x)
        assert.equals(300, show:lastCall()[3].start_point.y)
        assert.is_true(show:lastCall()[3].buttons_visible)

        UIManager.close, UIManager.broadcastEvent, UIManager.onRotation = old_close, old_broadcast, old_rotation
    end)
end)

describe("EmbeddedImage repaint suppression during search", function()
    it("suspends repaints when boundary search begins to prevent screen flashing", function()
        local suspend_calls = {}
        local old_suspend = UIManager.setSuspendRepaints
        UIManager.setSuspendRepaints = function(_, state, timeout)
            table.insert(suspend_calls, { state = state, timeout = timeout })
        end

        local handle = spy()
        local plugin = {
            ui = {
                document = {
                    getCurrentPage = function()
                        return 10
                    end,
                    getNextPage = function(_, page)
                        return page == 10 and 11 or 0
                    end,
                },
                handleEvent = handle,
            },
            openNextEmbeddedImagePage = function() end,
        }
        local viewer = {
            releaseEmbeddedSource = function() end,
        }

        assert.is_true(EmbeddedImage.onEmbeddedImageBoundary(plugin, "next", viewer))
        assert.equals(1, #suspend_calls)
        assert.equals(true, suspend_calls[1].state)
        assert.equals(5, suspend_calls[1].timeout)
        assert.equals(true, plugin._embedded_search_suspended)

        UIManager.setSuspendRepaints = old_suspend
    end)

    it("uses internal document:gotoPage(page, true) when present during search turns", function()
        local goto_calls = {}
        local handle_calls = {}

        local plugin = {
            ui = {
                document = {
                    getCurrentPage = function()
                        return 10
                    end,
                    getNextPage = function(_, page)
                        return page == 10 and 11 or 0
                    end,
                    gotoPage = function(_, page, internal)
                        table.insert(goto_calls, { page = page, internal = internal })
                    end,
                },
                handleEvent = function(_, ev)
                    table.insert(handle_calls, ev)
                end,
            },
            openNextEmbeddedImagePage = function() end,
        }
        local viewer = {
            releaseEmbeddedSource = function() end,
        }

        assert.is_true(EmbeddedImage.onEmbeddedImageBoundary(plugin, "next", viewer))
        assert.equals(1, #goto_calls, "internal document.gotoPage should be called instead of broadcasting GotoPage")
        assert.equals(11, goto_calls[1].page)
        assert.equals(true, goto_calls[1].internal)
        assert.equals(0, #handle_calls, "no full UI GotoPage event should be broadcast on intermediate search steps")
    end)

    it("keeps repaints suspended across intermediate pages and resumes when image is found", function()
        local suspend_calls = {}
        local old_suspend = UIManager.setSuspendRepaints
        local old_tick = UIManager.tickAfterNext
        UIManager.setSuspendRepaints = function(_, state, timeout)
            table.insert(suspend_calls, { state = state, timeout = timeout })
        end
        UIManager.tickAfterNext = function(_, callback)
            UIManager._test_tick = callback
            return true
        end

        local handle = spy()
        local image = { w = 600, h = 800 }
        local show_calls = 0
        local current_page_has_image = false

        local plugin = {
            ui = {
                document = {
                    getNextPage = function(_, page)
                        return page + 1
                    end,
                },
                handleEvent = handle,
            },
            findEmbeddedImageOnCurrentPage = function()
                return current_page_has_image and image or nil
            end,
            showEmbeddedImagePanelsForImage = function(plugin_self)
                show_calls = show_calls + 1
                EmbeddedImage.resumeSearchRepaints(plugin_self)
                return true
            end,
            _embedded_search_generation = 1,
            _embedded_search_suspended = true,
        }
        local viewer = {}
        plugin._embedded_search_viewer = viewer

        -- Page 11 has no image: repaints must stay suspended and advance to page 12
        assert.is_true(EmbeddedImage.openNextEmbeddedImagePage(plugin, 11, "next", viewer, 1))
        assert.equals(0, #suspend_calls, "repaints should remain suspended while traversing text pages")
        assert.equals(true, plugin._embedded_search_suspended)
        assert.equals("GotoPage", handle:lastCall()[2].name)
        assert.equals(12, handle:lastCall()[2].args[1])

        -- Page 12 has an image: the real replacement resumes only after the
        -- destination viewer has been stacked above the source viewer.
        current_page_has_image = true
        assert.is_true(EmbeddedImage.openNextEmbeddedImagePage(plugin, 12, "next", viewer, 1))
        assert.equals(1, #suspend_calls)
        assert.equals(false, suspend_calls[1].state)
        assert.equals(nil, plugin._embedded_search_suspended)
        assert.equals(1, show_calls)

        UIManager.setSuspendRepaints = old_suspend
        UIManager.tickAfterNext = old_tick
    end)

    it("stacks the destination before resuming and closing the source viewer", function()
        local PageBitmap = require("src._pagebitmap")
        local ComponentDetector = require("src._componentdetector")
        local old_build = PageBitmap.buildFromBlitbuffer
        local old_detect = ComponentDetector.detectPage
        local old_show, old_close = UIManager.show, UIManager.close
        local old_suspend = UIManager.setSuspendRepaints
        local events = {}

        PageBitmap.buildFromBlitbuffer = function()
            return {}
        end
        ComponentDetector.detectPage = function()
            return { { x = 0, y = 0, w = 600, h = 800 } }
        end
        UIManager.show = function(_, widget)
            table.insert(events, { name = "show", widget = widget })
        end
        UIManager.close = function(_, widget)
            table.insert(events, { name = "close", widget = widget })
        end
        UIManager.setSuspendRepaints = function(_, state)
            table.insert(events, { name = "suspend", state = state })
        end

        local source = {}
        local plugin = {
            settings = {
                mode = "manga",
                crop_mode = "strict",
                embedded_nav_transition_mode = "classic",
            },
            ui = {},
            armPageTurnAnimation = function() end,
            _embedded_search_suspended = true,
        }
        local image = {
            w = 600,
            h = 800,
            getType = function()
                return 1
            end,
        }

        assert.is_true(EmbeddedImage.showEmbeddedImagePanelsForImage(plugin, image, {
            replace_viewer = source,
            boundary_direction = "next",
        }))
        assert.equals("show", events[1].name)
        assert.equals("suspend", events[2].name)
        assert.equals(false, events[2].state)
        assert.equals("close", events[3].name)
        assert.equals(source, events[3].widget)

        PageBitmap.buildFromBlitbuffer = old_build
        ComponentDetector.detectPage = old_detect
        UIManager.show, UIManager.close = old_show, old_close
        UIManager.setSuspendRepaints = old_suspend
    end)

    it("resumes repaints when reaching document boundary without an image", function()
        local suspend_calls = {}
        local old_suspend = UIManager.setSuspendRepaints
        local old_close = UIManager.close
        local close_spy = spy()
        UIManager.setSuspendRepaints = function(_, state, timeout)
            table.insert(suspend_calls, { state = state, timeout = timeout })
        end
        UIManager.close = close_spy

        local plugin = {
            ui = {
                document = {
                    getNextPage = function()
                        return 0 -- End of document
                    end,
                },
            },
            findEmbeddedImageOnCurrentPage = function()
                return nil
            end,
            _embedded_search_generation = 1,
            _embedded_search_suspended = true,
        }
        local viewer = {}
        plugin._embedded_search_viewer = viewer

        assert.is_false(EmbeddedImage.openNextEmbeddedImagePage(plugin, 20, "next", viewer, 1))
        assert.equals(1, #suspend_calls)
        assert.equals(false, suspend_calls[1].state)
        assert.equals(nil, plugin._embedded_search_suspended)
        assert.is_true(close_spy:called())

        UIManager.setSuspendRepaints = old_suspend
        UIManager.close = old_close
    end)

    it("resumes repaints when search is cancelled", function()
        local suspend_calls = {}
        local old_suspend = UIManager.setSuspendRepaints
        UIManager.setSuspendRepaints = function(_, state, timeout)
            table.insert(suspend_calls, { state = state, timeout = timeout })
        end

        local viewer = {}
        local plugin = {
            _embedded_search_generation = 3,
            _embedded_search_viewer = viewer,
            _embedded_search_suspended = true,
        }

        EmbeddedImage.cancelEmbeddedImageSearch(plugin, viewer)
        assert.equals(4, plugin._embedded_search_generation)
        assert.equals(nil, plugin._embedded_search_viewer)
        assert.equals(1, #suspend_calls)
        assert.equals(false, suspend_calls[1].state)
        assert.equals(nil, plugin._embedded_search_suspended)

        UIManager.setSuspendRepaints = old_suspend
    end)
end)
