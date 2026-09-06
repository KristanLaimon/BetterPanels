local Blitbuffer = require("ffi/blitbuffer")
local Event = require("ui/event")
local Geometry = require("src._geometry")
local PageBitmap = require("src._pagebitmap")
local PanelViewer = require("src._panelviewer")
local Segmenter = require("src._segmenter")
local Settings = require("src._settings")
local Timing = require("src._timing")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen

--- Embedded-image support for reflowable EPUB and MOBI documents.
---
--- KOReader's fixed-page panel API deliberately does not run in ReaderRolling.
--- Its document API can still extract the image under a hold, so we segment
--- that bitmap itself and feed its crops to the normal Panels+ viewer.
local EmbeddedImage = {}

local function isSupportedDocument(document)
    local file = document and document.file
    if type(file) ~= "string" then
        return false
    end
    file = file:lower()
    return file:match("%.epub$") ~= nil or file:match("%.mobi$") ~= nil
end

local function freeImage(image)
    if image and image.free then
        image:free()
    end
end

local function dimensions(bb)
    if not bb then
        return nil, nil
    end
    local w = bb.getWidth and bb:getWidth() or bb.w
    local h = bb.getHeight and bb:getHeight() or bb.h
    return w, h
end

local function expandRect(rect, width, height, settings)
    if settings.crop_mode ~= "loose" then
        return rect
    end
    local bleed = math.max(
        settings.panel_bleed_min or Settings.defaults.panel_bleed_min,
        math.max(rect.w, rect.h) * (settings.panel_bleed_ratio or Settings.defaults.panel_bleed_ratio)
    )
    local x = math.max(0, rect.x - bleed)
    local y = math.max(0, rect.y - bleed)
    local right = math.min(width, rect.x + rect.w + bleed)
    local bottom = math.min(height, rect.y + rect.h + bleed)
    return { x = x, y = y, w = math.max(1, right - x), h = math.max(1, bottom - y) }
end

local function cropImage(source, rect, crop_mode)
    local source_w, source_h = dimensions(source)
    if not source_w or not source_h or not source.getType then
        return nil
    end
    if crop_mode == "none" and source.copy then
        return source:copy()
    end
    local x = math.max(0, math.floor(rect.x + 0.5))
    local y = math.max(0, math.floor(rect.y + 0.5))
    local w = math.min(source_w - x, math.max(1, math.floor(rect.w + 0.5)))
    local h = math.min(source_h - y, math.max(1, math.floor(rect.h + 0.5)))
    if w <= 0 or h <= 0 then
        return nil
    end
    local crop = Blitbuffer.new(w, h, source:getType())
    crop:blitFrom(source, 0, 0, x, y, w, h)
    return crop
end

local function extractImage(document, pos)
    local ok, image = pcall(document.getImageFromPosition, document, pos, false, false)
    if ok and image and type(image.getType) == "function" then
        return image
    end
    return nil
end

local function startIndex(panels, point)
    if not point then
        return 1
    end
    local best_idx, best_distance = 1, math.huge
    for index, panel in ipairs(panels) do
        local cx, cy = Geometry.rectCenter(panel)
        local distance = (cx - point.x) ^ 2 + (cy - point.y) ^ 2
        if distance < best_distance then
            best_idx, best_distance = index, distance
        end
    end
    return best_idx
end

--- Open an already-extracted image. This takes ownership of `image` on
--- success and frees it when detection rejects the bitmap.
function EmbeddedImage:showEmbeddedImagePanelsForImage(image, options)
    options = options or {}
    local width, height = dimensions(image)
    if not width or not height then
        freeImage(image)
        return false
    end

    local map, reason = PageBitmap.buildFromBlitbuffer(image, self.settings)
    if not map then
        Timing.log("embedded image skipped: " .. tostring(reason))
        freeImage(image)
        return false
    end
    local panels = Segmenter.segment(map, self.settings)
    local accepted, rejection = Segmenter.accept(panels, map, self.settings)
    if not accepted or #panels == 0 then
        Timing.log("embedded image segmenter rejected: " .. tostring(rejection))
        freeImage(image)
        return false
    end
    panels = Geometry.sortReadingOrder(panels, self.settings.mode)

    local images = { image_disposable = true }
    local image_rects, full_page_flags = {}, {}
    for _, panel in ipairs(panels) do
        local image_rect = expandRect(panel, width, height, self.settings)
        table.insert(image_rects, image_rect)
        table.insert(
            full_page_flags,
            panel.w * panel.h >= (self.settings.full_page_panel_ratio or 0.92) * width * height
        )
        table.insert(images, function()
            return cropImage(image, image_rect, self.settings.crop_mode)
        end)
    end

    local viewer = PanelViewer:new({
        image = images,
        image_disposable = true,
        images_list_nb = #images,
        panels = panels,
        image_rects = image_rects,
        panel_is_full_page = full_page_flags,
        reader_ui = self.ui,
        embedded_source_image = image,
        reading_mode = self.settings.mode,
        crop_mode = self.settings.crop_mode,
        margin_ratio = self.settings.panel_margin_ratio,
        bleed_ratio = self.settings.panel_bleed_ratio,
        detector = "fast",
        invert_swipe = self.settings.invert_swipe == true,
        tap_navigation = self.settings.tap_navigation == true,
        swipe_navigation = self.settings.swipe_navigation ~= false,
        progress_bar_visible = self.settings.progress_bar_visible ~= false,
        hold_text_selection = false,
        image_rotation = self.settings.image_rotation,
        -- Smooth transitions compose a document-page union. An embedded image
        -- has no document-page rectangle, so these use the instant transition.
        nav_transition_mode = "classic",
        buttons_visible = options.buttons_visible == true,
        boundary_callback = function(direction, current_viewer)
            return self:onEmbeddedImageBoundary(direction, current_viewer)
        end,
        mode_toggle_callback = function(current_viewer)
            self:setMode(self.settings.mode == "manga" and "comic" or "manga")
            return self:reopenEmbeddedImagePanels(current_viewer)
        end,
        crop_toggle_callback = function(current_viewer)
            local next_mode = { strict = "loose", loose = "margin", margin = "none", none = "strict" }
            self:setCropMode(next_mode[self.settings.crop_mode] or "strict")
            return self:reopenEmbeddedImagePanels(current_viewer)
        end,
        margin_ratio_callback = function(current_viewer, ratio, activate_margin_mode)
            self:setMarginRatio(ratio)
            if activate_margin_mode then
                self:setCropMode("margin")
            end
            current_viewer.margin_ratio = self.settings.panel_margin_ratio
            current_viewer.crop_mode = self.settings.crop_mode
            current_viewer:replaceButtonTable()
            current_viewer:update()
            return true
        end,
        bleed_ratio_callback = function(current_viewer, ratio, activate_loose_mode)
            self:setBleedRatio(ratio)
            if activate_loose_mode then
                self:setCropMode("loose")
            end
            return self:reopenEmbeddedImagePanels(current_viewer)
        end,
        progress_bar_toggle_callback = function(current_viewer)
            self:setProgressBarVisible(current_viewer.progress_bar_visible == false)
            current_viewer.progress_bar_visible = self.settings.progress_bar_visible ~= false
            current_viewer:replaceButtonTable()
            current_viewer:update()
            return true
        end,
        image_rotation_callback = function(_, value)
            self:setImageRotation(value)
            return true
        end,
        more_config_callback = function(current_viewer)
            return self:showMoreConfigMenu(current_viewer)
        end,
    })
    UIManager:show(viewer)
    local index = startIndex(panels, options.start_point)
    if index > 1 then
        viewer:switchToImageNum(index)
    end
    return true
end

--- Rebuild an embedded image viewer after changing its reading order or crop.
function EmbeddedImage:reopenEmbeddedImagePanels(viewer)
    local panel = viewer.panels and viewer.panels[viewer._images_list_cur or 1]
    local start_point = panel
        and {
            x = (panel.x or 0) + (panel.w or 0) / 2,
            y = (panel.y or 0) + (panel.h or 0) / 2,
        }
    local image = viewer.embedded_source_image
    viewer.embedded_source_image = nil -- transfer ownership to the replacement viewer
    UIManager:close(viewer)
    return self:showEmbeddedImagePanelsForImage(image, { start_point = start_point, buttons_visible = true })
end

--- Probe a reader page for an image. ReaderRolling positions use screen
--- coordinates directly, so a modest grid finds an image even when it is not
--- centred on its text page.
function EmbeddedImage:findEmbeddedImageOnCurrentPage()
    local ui = self.ui
    local document, view = ui and ui.document, ui and ui.view
    if not document or not view or type(document.getImageFromPosition) ~= "function" then
        return nil
    end
    local xs = { 0.1, 0.25, 0.4, 0.6, 0.75, 0.9 }
    local ys = { 0.08, 0.2, 0.35, 0.5, 0.65, 0.8, 0.92 }
    for _, y_ratio in ipairs(ys) do
        for _, x_ratio in ipairs(xs) do
            local pos = view:screenToPageTransform({
                x = math.floor(Screen:getWidth() * x_ratio),
                y = math.floor(Screen:getHeight() * y_ratio),
            })
            if pos then
                local image = extractImage(document, pos)
                if image then
                    return image
                end
            end
        end
    end
    return nil
end

--- Turn through reflow pages until another image with a panel layout appears.
function EmbeddedImage:openNextEmbeddedImagePage(page, direction)
    local ui, document = self.ui, self.ui and self.ui.document
    if not document then
        return false
    end
    local image = self:findEmbeddedImageOnCurrentPage()
    if image and self:showEmbeddedImagePanelsForImage(image) then
        return true
    end

    local next_page = direction == "next" and document:getNextPage(page) or document:getPrevPage(page)
    if not next_page or next_page == 0 then
        return false
    end
    ui:handleEvent(Event:new("GotoPage", next_page))
    UIManager:tickAfterNext(function()
        self:openNextEmbeddedImagePage(next_page, direction)
    end)
    return true
end

--- Continue past the first/last panel by seeking the next/previous image.
function EmbeddedImage:onEmbeddedImageBoundary(direction, viewer)
    if viewer._panels_plus_boundary_pending then
        return true
    end
    viewer._panels_plus_boundary_pending = true
    local document = self.ui and self.ui.document
    local page = document and document:getCurrentPage()
    local next_page = page and (direction == "next" and document:getNextPage(page) or document:getPrevPage(page))
    if not next_page or next_page == 0 then
        viewer._panels_plus_boundary_pending = nil
        return true
    end

    UIManager:close(viewer)
    self.ui:handleEvent(Event:new("GotoPage", next_page))
    UIManager:tickAfterNext(function()
        self:openNextEmbeddedImagePage(next_page, direction)
    end)
    return true
end

--- Open Panels+ on an image embedded in a supported reflowable document.
--- Returning false deliberately lets ReaderHighlight resume its native image
--- viewer or text-selection path when the hold was not on a usable bitmap.
function EmbeddedImage:showEmbeddedImagePanels(reader_highlight, ges)
    local ui = self.ui
    local document = ui and ui.document
    if not (ui and ui.rolling and isSupportedDocument(document)) then
        return false
    end
    local view = reader_highlight and reader_highlight.view
    local pos = view and view.screenToPageTransform and view:screenToPageTransform(ges and ges.pos)
    if not pos or type(document.getImageFromPosition) ~= "function" then
        return false
    end

    local image = extractImage(document, pos)
    if not image then
        return false
    end
    local shown = self:showEmbeddedImagePanelsForImage(image)
    if shown then
        reader_highlight:clear()
    end
    return shown
end

return EmbeddedImage
