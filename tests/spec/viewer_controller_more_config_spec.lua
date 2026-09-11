--- Shared More-config controls and native page-turn animation behavior.
local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert, spy = framework.describe, framework.it, framework.assert, framework.spy

local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local PanelCollector = require("src._panelcollector")
local PanelViewer = require("src._panelviewer")
local ViewerController = require("src.viewer_controller")

describe("ViewerController page-turn animation settings", function()
    local function withAnimationEnvironment(callback)
        local old_reader_settings = G_reader_settings
        local old_can_do_swipe_animation = Device.canDoSwipeAnimation
        local global_enabled = false
        local global_writes = spy()
        G_reader_settings = {
            isTrue = function(_, key)
                return key == "swipe_animations" and global_enabled
            end,
            makeTrue = function(_, key)
                if key == "swipe_animations" then
                    global_enabled = true
                    global_writes(key, true)
                end
            end,
            makeFalse = function(_, key)
                if key == "swipe_animations" then
                    global_enabled = false
                    global_writes(key, false)
                end
            end,
        }
        Device.canDoSwipeAnimation = function()
            return true
        end

        callback({
            setGlobal = function(enabled)
                global_enabled = enabled
            end,
            globalWrites = global_writes,
        })

        G_reader_settings = old_reader_settings
        Device.canDoSwipeAnimation = old_can_do_swipe_animation
    end

    local function makeController(settings)
        local saved = spy()
        local controller = setmetatable({
            settings = settings,
            saveSettings = saved,
        }, { __index = ViewerController })
        return controller, saved
    end

    it("follows and updates KOReader while synchronization is enabled", function()
        withAnimationEnvironment(function(env)
            local controller, saved = makeController({
                page_turn_animation_enabled = true,
                page_turn_animation_sync = true,
            })

            assert.is_false(controller:getPageTurnAnimationPreference())
            env.setGlobal(true)
            assert.is_true(controller:getPageTurnAnimationPreference())

            controller:setPageTurnAnimationEnabled(false)
            assert.equals(1, env.globalWrites:callCount())
            assert.equals(false, env.globalWrites:lastCall()[2])
            assert.is_false(controller.settings.page_turn_animation_enabled)
            assert.is_true(saved:called())
        end)
    end)

    it("keeps an independent preference after synchronization is disabled", function()
        withAnimationEnvironment(function(env)
            env.setGlobal(true)
            local controller = makeController({
                page_turn_animation_enabled = false,
                page_turn_animation_sync = true,
            })

            controller:setPageTurnAnimationSync(false)
            assert.is_false(controller.settings.page_turn_animation_sync)
            assert.is_true(controller.settings.page_turn_animation_enabled)

            controller:setPageTurnAnimationEnabled(false)
            assert.equals(0, env.globalWrites:callCount())
            assert.is_false(controller:getPageTurnAnimationPreference())
            assert.is_true(G_reader_settings:isTrue("swipe_animations"))
        end)
    end)

    it("temporarily suppresses the saved preference in Smooth mode", function()
        withAnimationEnvironment(function(env)
            env.setGlobal(true)
            local controller = makeController({
                page_turn_animation_enabled = true,
                page_turn_animation_sync = true,
            })

            assert.is_false(controller:isPageTurnAnimationActive({ nav_transition_mode = "smooth" }))
            assert.is_true(controller:isPageTurnAnimationActive({ nav_transition_mode = "classic" }))
            assert.is_true(controller.settings.page_turn_animation_enabled)
        end)
    end)

    it("exposes animation and synchronization controls in More config", function()
        withAnimationEnvironment(function(env)
            env.setGlobal(true)
            local controller = makeController({
                tap_navigation = false,
                swipe_navigation = true,
                page_turn_animation_enabled = true,
                page_turn_animation_sync = true,
            })
            local viewer = { nav_transition_mode = "smooth" }

            controller:showMoreConfigMenu(viewer)
            local animation_item = UIManager._last_shown.item_table[3]
            local sync_item = UIManager._last_shown.item_table[4]
            assert.is_not_nil(animation_item)
            assert.is_not_nil(sync_item)
            assert.is_false(animation_item.enabled_func())
            assert.is_false(animation_item.checked_func())
            assert.is_true(sync_item.checked_func())

            viewer.nav_transition_mode = "classic"
            assert.is_true(animation_item.enabled_func())
            assert.is_true(animation_item.checked_func())
        end)
    end)
end)

describe("ViewerController native page-turn animation", function()
    it("arms one screen animation with direction and reading-order support", function()
        local old_reader_settings = G_reader_settings
        local old_can_do_swipe_animation = Device.canDoSwipeAnimation
        local old_set_animations = Screen.setSwipeAnimations
        local old_set_direction = Screen.setSwipeDirection
        local animations, directions = spy(), spy()
        G_reader_settings = {
            isTrue = function()
                return false
            end,
        }
        Device.canDoSwipeAnimation = function()
            return true
        end
        Screen.setSwipeAnimations = function(...)
            animations(...)
        end
        Screen.setSwipeDirection = function(...)
            directions(...)
        end

        local controller = setmetatable({
            settings = {
                page_turn_animation_enabled = true,
                page_turn_animation_sync = false,
            },
            ui = { view = { inverse_reading_order = false } },
        }, { __index = ViewerController })

        assert.is_true(controller:armPageTurnAnimation("next", { nav_transition_mode = "classic" }))
        assert.equals(true, animations:lastCall()[2])
        assert.equals(true, directions:lastCall()[2])

        controller.ui.view.inverse_reading_order = true
        assert.is_true(controller:armPageTurnAnimation("next", { nav_transition_mode = "classic" }))
        assert.equals(false, directions:lastCall()[2])

        local animation_count = animations:callCount()
        assert.is_false(controller:armPageTurnAnimation("next", { nav_transition_mode = "smooth" }))
        assert.equals(animation_count, animations:callCount())

        G_reader_settings = old_reader_settings
        Device.canDoSwipeAnimation = old_can_do_swipe_animation
        Screen.setSwipeAnimations = old_set_animations
        Screen.setSwipeDirection = old_set_direction
    end)

    it("arms a fixed-layout handoff after building the destination and before replacing the viewer", function()
        local old_build_images = PanelCollector.buildImages
        local old_new = PanelViewer.new
        local old_close, old_show = UIManager.close, UIManager.show
        local sequence = {}
        local source_viewer = { nav_transition_mode = "classic" }
        local destination_viewer = {}

        PanelCollector.buildImages = function()
            table.insert(sequence, "build")
            return { {} }, { {} }, { false }
        end
        PanelViewer.new = function()
            return destination_viewer
        end
        UIManager.close = function(_, viewer)
            assert.equals(source_viewer, viewer)
            table.insert(sequence, "close")
        end
        UIManager.show = function(_, viewer)
            assert.equals(destination_viewer, viewer)
            table.insert(sequence, "show")
        end

        local controller = setmetatable({
            settings = {
                mode = "manga",
                crop_mode = "strict",
                nav_transition_mode = "classic",
            },
            ui = {},
            armPageTurnAnimation = function(_, direction, viewer)
                assert.equals("next", direction)
                assert.equals(source_viewer, viewer)
                table.insert(sequence, "arm")
                return true
            end,
        }, { __index = ViewerController })

        assert.is_true(controller:showPanelViewerForPage(2, { {} }, 1, {
            replace_viewer = source_viewer,
            boundary_direction = "next",
            defer_preload = true,
        }))
        assert.equals("build,arm,close,show", table.concat(sequence, ","))

        PanelCollector.buildImages = old_build_images
        PanelViewer.new = old_new
        UIManager.close, UIManager.show = old_close, old_show
    end)
end)
