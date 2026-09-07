local _ = require("gettext")

--- Main-menu methods mixed into `PanelsPlus`.
---
--- @class PPMenuMethods
local Menu = {}

--- Return the active detector (Deep mode / exact).
---
--- @return PPDetector detector Current detector selection.
function Menu:getDetector()
    return "exact"
end

--- Return the main-menu label for the current reading mode.
---
--- @return string text Localized menu label.
function Menu:getModeText()
    if self.settings.mode == "comic" then
        return _("Panels+: comic mode")
    end
    return _("Panels+: manga mode")
end

--- Add the plugin's submenu to KOReader's main menu.
---
--- @param menu_items table<string, table> Mutable KOReader menu item table.
function Menu:addToMainMenu(menu_items)
    menu_items.panels_plus = {
        text_func = function()
            return self:getModeText()
        end,
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Disable plugin panel focusing"),
                checked_func = function()
                    return not self:isEnabled()
                end,
                callback = function()
                    self:setEnabled(not self:isEnabled())
                end,
                help_text = _("Use KOReader's native panel zoom instead of the Panels+ panel sequence viewer."),
            },
            {
                text = _("Manga mode (right to left)"),
                checked_func = function()
                    return self.settings.mode == "manga"
                end,
                radio = true,
                callback = function()
                    self:setMode("manga")
                end,
            },
            {
                text = _("Comic mode (left to right)"),
                checked_func = function()
                    return self.settings.mode == "comic"
                end,
                radio = true,
                callback = function()
                    self:setMode("comic")
                end,
            },
            {
                text = _("Invert panel swipe direction"),
                checked_func = function()
                    return self.settings.invert_swipe == true
                end,
                callback = function()
                    self:setInvertSwipe(not self.settings.invert_swipe)
                end,
                help_text = _(
                    "Use this if panel navigation feels reversed on your device. It changes swipe direction only, not panel order."
                ),
            },
            {
                text = _("Touch & hold text selection in zoom [EXPERIMENTAL]"),
                checked_func = function()
                    return self.settings.hold_text_selection ~= false
                end,
                callback = function()
                    self:setHoldTextSelection(self.settings.hold_text_selection == false)
                end,
                help_text = _(
                    "Allow touch and hold on text inside zoomed panels to select text and trigger OCR-based dictionary lookups. On by default; turn off if the OCR word detection misfires often on your comics."
                ),
                separator = true,
            },

            {
                text = _("Pre-render next panel"),
                checked_func = function()
                    return self.settings.panel_prerender ~= false
                end,
                callback = function()
                    self:setPanelPrerender(self.settings.panel_prerender == false)
                end,
                help_text = _(
                    "Render the next panel while you read the current one, so swiping to it is instant. Skipped automatically when the device is low on memory."
                ),
            },
            {
                text = _("Enable debugging logs"),
                checked_func = function()
                    return self.settings.debug_mode == true
                end,
                callback = function()
                    self:setDebugMode(not self.settings.debug_mode)
                end,
                help_text = _(
                    "Write panel detection, render timings, and memory usage to KOReader's log. Useful for diagnosing slowness or crashes, otherwise leave off."
                ),
            },
            {
                text = _("OCR debug review mode"),
                checked_func = function()
                    return self.settings.ocr_debug_mode == true
                end,
                callback = function()
                    self:setOcrDebugMode(self.settings.ocr_debug_mode ~= true)
                end,
                help_text = _(
                    "After each dictionary lookup that used OCR in a zoomed panel, ask whether the word was read correctly. If not, draw the correct word box and type what it actually says. Everything -- including the exact long-press point -- is appended to OCR.debug.session.log for later review. Off by default."
                ),
            },
        },
    }
end

return Menu
