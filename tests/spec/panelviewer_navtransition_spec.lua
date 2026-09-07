local framework = require("tests.PanelsPlusTestFramework")
local describe, it, assert, spy = framework.describe, framework.it, framework.assert, framework.spy

local PanelViewer = require("src._panelviewer")
local UIManager = require("ui/uimanager")

describe("PanelViewer nav transition hold options", function()
    it("delegates hold to nav_transition_options_callback when provided", function()
        local options_spy = spy()
        local viewer = PanelViewer:new({
            nav_transition_mode = "smooth",
            nav_transition_options_callback = options_spy,
        })
        viewer:replaceButtonTable()

        local nav_btn
        for _, row in ipairs(viewer.button_table.buttons or {}) do
            for _, btn in ipairs(row) do
                if btn.id == "nav_transition" then
                    nav_btn = btn
                    break
                end
            end
        end

        assert.is_not_nil(nav_btn)
        assert.is_not_nil(nav_btn.hold_callback)
        nav_btn.hold_callback()
        assert.is_true(options_spy:called())
    end)

    it("falls back to onShowNavTransitionOptionsMenu when options callback is nil", function()
        local viewer = PanelViewer:new({
            nav_transition_mode = "smooth",
            nav_transition_options_callback = nil,
        })
        local menu_spy = spy()
        viewer.onShowNavTransitionOptionsMenu = menu_spy
        viewer:replaceButtonTable()

        local nav_btn
        for _, row in ipairs(viewer.button_table.buttons or {}) do
            for _, btn in ipairs(row) do
                if btn.id == "nav_transition" then
                    nav_btn = btn
                    break
                end
            end
        end

        assert.is_not_nil(nav_btn)
        nav_btn.hold_callback()
        assert.is_true(menu_spy:called())
    end)

    it("displays the menu with options when onShowNavTransitionOptionsMenu is invoked", function()
        local cross_page_spy = spy()
        local viewer = PanelViewer:new({
            nav_transition_mode = "smooth",
            nav_transition_cross_page = false,
            nav_transition_cross_page_callback = cross_page_spy,
        })

        assert.is_true(viewer:onShowNavTransitionOptionsMenu())
        local shown_menu = UIManager._last_shown
        assert.is_not_nil(shown_menu)
        assert.is_not_nil(shown_menu.item_table)
        assert.equals(3, #shown_menu.item_table)
    end)
end)
