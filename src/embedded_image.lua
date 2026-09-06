local Blitbuffer = require("ffi/blitbuffer")
local Geometry = require("src._geometry")
local PageBitmap = require("src._pagebitmap")
local PanelViewer = require("src._panelviewer")
local Segmenter = require("src._segmenter")
local Settings = require("src._settings")
local Timing = require("src._timing")
local UIManager = require("ui/uimanager")

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

local function cropImage(source, rect)
    local source_w, source_h = dimensions(source)
    if not source_w or not source_h or not source.getType then
        return nil
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

    -- Frames and SVG scaling functions are supported by KOReader's native
    -- ImageViewer, but not safely crop-able without first rasterizing them.
    local ok_image, image = pcall(document.getImageFromPosition, document, pos, false, false)
    if not ok_image or not image or type(image.getType) ~= "function" then
        return false
    end

    local width, height = dimensions(image)
    if not width or not height then
        return false
    end
    local map, reason = PageBitmap.buildFromBlitbuffer(image, self.settings)
    if not map then
        Timing.log("embedded image skipped: " .. tostring(reason))
        return false
    end
    local panels = Segmenter.segment(map, self.settings)
    local accepted, rejection = Segmenter.accept(panels, map, self.settings)
    if not accepted or #panels == 0 then
        Timing.log("embedded image segmenter rejected: " .. tostring(rejection))
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
            return cropImage(image, image_rect)
        end)
    end

    reader_highlight:clear()
    local viewer = PanelViewer:new({
        image = images,
        image_disposable = true,
        images_list_nb = #images,
        panels = panels,
        image_rects = image_rects,
        panel_is_full_page = full_page_flags,
        reader_ui = ui,
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
        -- Smooth transitions render a document-page union. Embedded images
        -- have no document-page rectangle, so keep these viewers on the safe,
        -- instant Panels+ transition.
        nav_transition_mode = "classic",
        buttons_visible = false,
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
    })
    UIManager:show(viewer)
    return true
end

return EmbeddedImage
