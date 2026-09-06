local Blitbuffer = require("ffi/blitbuffer")
local Document = require("document/document")
local Geom = require("ui/geometry")
local Settings = require("src._settings")
local Timing = require("src._timing")
local ffi = require("ffi")
local logger = require("logger")

--- Low-resolution binary ink map of a document page.
---
--- The map is the input to `src._segmenter`. Two properties matter:
---
--- 1. It costs a *single* page render, at roughly 1/5 linear scale, instead of
---    one full-resolution render per probe point.
--- 2. "Ink" is defined relative to the page's own border colour rather than
---    against white. A page printed white-on-black produces exactly the same
---    map as the equivalent black-on-white page, which is what lets panel
---    detection work on inverted artwork at all.
---
--- @class PPPageBitmapModule
local PageBitmap = {}

--- @class PPPageMap
--- @field w integer Map width in cells.
--- @field h integer Map height in cells.
--- @field data ffi.cdata* `uint8_t[w*h]` of 0/1 ink flags.
--- @field ink integer Total ink cells.
--- @field native_w number Native page width.
--- @field native_h number Native page height.
--- @field scale_x number Native units per map cell, horizontally.
--- @field scale_y number Native units per map cell, vertically.
--- @field background integer Estimated page background luminance (0-255).
--- @field background_color table<{r:integer, g:integer, b:integer}> Estimated page background RGB colour.
--- @field inverted boolean Whether the page background is dark.
--- @field border ffi.cdata*|nil `uint8_t[w*h]` of 0/1 border-stroke candidate flags, comic mode only.

--- Return why the segmenter cannot run on this document, if it cannot.
---
--- `KoptInterface:renderPage()` only honors a caller-supplied zoom on its plain
--- path. Under reflow the rendered geometry does not correspond to native page
--- coordinates at all, and the page-optimization path runs an extra k2pdfopt
--- pass that defeats the point of a cheap render.
---
--- @param document table KOReader document object.
--- @return string|nil reason Blocking reason, or nil when usable.
function PageBitmap.getBlockReason(document)
    local configurable = document.configurable
    if not configurable then
        return "no configurable"
    end
    if configurable.text_wrap == 1 then
        return "reflow mode"
    end
    local koptinterface = document.koptinterface
    if koptinterface and koptinterface.is_optimizing_page and koptinterface:is_optimizing_page(document) then
        return "page optimization enabled"
    end
    return nil
end

--- Render one page at a fraction of its native size.
---
--- Uses the same `rect.scaled_rect` convention as `Document:drawPagePart()`,
--- which is what tells `renderPage()` that the caller has already handled
--- scaling and that it should not fall back to a full-size render.
---
--- @param document table KOReader document object.
--- @param page number Document page number.
--- @param target_width integer Desired render width in pixels.
--- @return table|nil bb Rendered blitbuffer.
--- @return PPPageSize|nil native Native page dimensions.
local function renderSmall(document, page, target_width)
    local native = Document.getNativePageDimensions(document, page)
    if not native or not native.w or not native.h or native.w <= 0 or native.h <= 0 then
        return nil
    end

    local zoom = math.min(1, target_width / native.w)
    local rect = Geom:new({ x = 0, y = 0, w = native.w, h = native.h })
    rect.scaled_rect = document:transformRect(rect, zoom, 0)
    if rect.scaled_rect.w < 32 or rect.scaled_rect.h < 32 then
        return nil
    end

    -- No hinting: this render is small and must not spin up extra CPU cores.
    local tile = document:renderPage(page, rect, zoom, 0, document.GAMMA_NO_GAMMA or 1.0, 1.0, false)
    if not tile or not tile.bb then
        return nil
    end
    return tile.bb, native
end

--- Return a buffer whose raw pixels can be sampled without applying a rotation
--- or inverse transform in Lua.
---
--- Keep colour buffers in colour. A solid coloured page background can share a
--- luminance with its panels, and reducing both to greyscale before comparing
--- them makes that gutter disappear. Rotated or inverted buffers are copied so
--- the raw fast paths below see their displayed pixels.
---
--- @param bb table Rendered blitbuffer.
--- @return table bb Buffer to sample.
--- @return table|nil owned Buffer the caller must free, if one was allocated.
local function normalizeForSampling(bb)
    if bb:getRotation() == 0 and bb:getInverse() == 0 then
        return bb, nil
    end

    local ok, normalized = pcall(function()
        local target_type = bb:isRGB() and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8
        local target = Blitbuffer.new(bb.w, bb.h, target_type)
        target:blitFrom(bb, 0, 0, 0, 0, bb.w, bb.h)
        return target
    end)
    if ok and normalized then
        return normalized, normalized
    end
    return bb, nil
end

--- Build the fastest available RGB accessor for a blitbuffer.
---
--- Reading raw pixels directly avoids a Lua colour object allocation per pixel,
--- which matters across ~150k of them. The generic accessor stays as a fallback
--- in case the raw pointer is unavailable.
---
--- @param bb table Buffer to sample.
--- @return fun(x:integer, y:integer):integer,integer,integer sample RGB accessor.
--- @return string kind Accessor name, for timing logs.
local function makeSampler(bb)
    if bb:getType() == Blitbuffer.TYPE_BB8 then
        local ok, data = pcall(ffi.cast, "uint8_t *", bb.data)
        if ok and data ~= nil then
            local stride = tonumber(bb.stride)
            return function(x, y)
                local value = data[y * stride + x]
                return value, value, value
            end, "bb8"
        end
    end

    local pixel_stride = tonumber(bb.pixel_stride)
    if bb:getType() == Blitbuffer.TYPE_BBRGB24 then
        local ok, data = pcall(ffi.cast, "ColorRGB24 *", bb.data)
        if ok and data ~= nil then
            return function(x, y)
                local pixel = data[y * pixel_stride + x]
                return pixel.r, pixel.g, pixel.b
            end, "rgb24"
        end
    elseif bb:getType() == Blitbuffer.TYPE_BBRGB32 then
        local ok, data = pcall(ffi.cast, "ColorRGB32 *", bb.data)
        if ok and data ~= nil then
            return function(x, y)
                local pixel = data[y * pixel_stride + x]
                return pixel.r, pixel.g, pixel.b
            end, "rgb32"
        end
    elseif bb:getType() == Blitbuffer.TYPE_BBRGB16 then
        local ok, data = pcall(ffi.cast, "ColorRGB16 *", bb.data)
        if ok and data ~= nil then
            return function(x, y)
                local value = tonumber(data[y * pixel_stride + x].v)
                local r = math.floor(value / 2048)
                local g = math.floor(value / 32) % 64
                local b = value % 32
                return r * 8 + math.floor(r / 4), g * 4 + math.floor(g / 16), b * 8 + math.floor(b / 4)
            end, "rgb16"
        end
    end

    return function(x, y)
        local color = bb:getPixel(x, y):getColorRGB24()
        return color.r, color.g, color.b
    end, "generic"
end

--- Return an RGB colour's luminance using KOReader's own ColorRGB conversion.
---
--- @param r integer
--- @param g integer
--- @param b integer
--- @return integer luminance
local function luminance(r, g, b)
    return math.floor((4898 * r + 9618 * g + 1869 * b) / 16384)
end

--- Return the greatest per-channel difference between two RGB colours.
---
--- This is deliberately equivalent to the old absolute luminance difference
--- for greyscale pixels, while also seeing hues that have almost the same
--- luminance as the background.
local function colourDistance(r, g, b, background_r, background_g, background_b)
    local dr = math.abs(r - background_r)
    local dg = math.abs(g - background_g)
    local db = math.abs(b - background_b)
    return math.max(dr, dg, db)
end

--- Estimate the page background colour from its outer border.
---
--- The border of a comic page is the page's own paper (or its inked backdrop),
--- never panel content, so its per-channel median is a reliable background
--- reference for normal, inverted, and coloured artwork.
---
--- @param sample fun(x:integer, y:integer):integer,integer,integer RGB accessor.
--- @param w integer Source width.
--- @param h integer Source height.
--- @return integer r Median border red channel (0-255).
--- @return integer g Median border green channel (0-255).
--- @return integer b Median border blue channel (0-255).
local function estimateBackground(sample, w, h)
    local red, green, blue = {}, {}, {}
    for value = 0, 255 do
        red[value], green[value], blue[value] = 0, 0, 0
    end

    local ring = math.max(1, math.floor(math.min(w, h) * 0.01))
    local total = 0

    local function tally(x, y)
        local r, g, b = sample(x, y)
        red[r] = red[r] + 1
        green[g] = green[g] + 1
        blue[b] = blue[b] + 1
        total = total + 1
    end

    for offset = 0, ring - 1 do
        for x = 0, w - 1 do
            tally(x, offset)
            tally(x, h - 1 - offset)
        end
        for y = ring, h - 1 - ring do
            tally(offset, y)
            tally(w - 1 - offset, y)
        end
    end

    if total == 0 then
        return 255, 255, 255
    end

    local function median(histogram)
        local half, seen = total / 2, 0
        for value = 0, 255 do
            seen = seen + histogram[value]
            if seen >= half then
                return value
            end
        end
        return 255
    end

    return median(red), median(green), median(blue)
end

--- Build a page's binary ink map.
---
--- @param document table KOReader document object.
--- @param page number Document page number.
--- @param settings PPSettings Plugin settings.
--- @return PPPageMap|nil map Ink map, or nil when the page cannot be mapped.
--- @return string|nil reason Failure reason when `map` is nil.
function PageBitmap.build(document, page, settings)
    settings = settings or Settings.defaults

    local blocked = PageBitmap.getBlockReason(document)
    if blocked then
        return nil, blocked
    end

    local stop = Timing.span("page bitmap")
    local target_width = settings.segment_target_width or Settings.defaults.segment_target_width
    local ink_delta = settings.segment_ink_delta or Settings.defaults.segment_ink_delta

    -- Manga pages are near-uniformly two-tone, so a background-relative ink
    -- map already separates panels cleanly there. Western comics routinely
    -- bleed differently-coloured or dark panels edge to edge with no blank
    -- gutter at all, only a drawn black border stroke between them -- which
    -- needs its own absolute (not background-relative) signal to find.
    --
    -- Only built when the reader has opted into splitting on those strokes
    -- (see `src._segmenter` for why that is off by default). Skipping it drops
    -- a per-cell comparison and a whole w*h allocation from every page.
    local detect_borders = settings.mode == "comic" and settings.segment_border_split == true
    local border_luminance_max = settings.segment_border_luminance_max or Settings.defaults.segment_border_luminance_max

    local map, reason, owned
    local ok, err = pcall(function()
        local bb, native = renderSmall(document, page, target_width)
        if not bb then
            reason = "render failed"
            return
        end

        local work
        work, owned = normalizeForSampling(bb)
        local src_w, src_h = work.w, work.h
        local sample, kind = makeSampler(work)

        -- Guard against a render path that ignored our zoom: subsample instead
        -- of scanning a full-resolution buffer cell by cell.
        local step = math.max(1, math.floor(src_w / target_width))
        local w = math.floor(src_w / step)
        local h = math.floor(src_h / step)
        if w < 16 or h < 16 then
            reason = "page too small to map"
            return
        end

        local background_r, background_g, background_b = estimateBackground(sample, src_w, src_h)
        local background = luminance(background_r, background_g, background_b)
        local data = ffi.new("uint8_t[?]", w * h)
        local border = detect_borders and ffi.new("uint8_t[?]", w * h) or nil
        local ink = 0
        local border_cells = 0

        if border then
            for y = 0, h - 1 do
                local src_y = y * step
                local row = y * w
                for x = 0, w - 1 do
                    local r, g, b = sample(x * step, src_y)
                    local delta = colourDistance(r, g, b, background_r, background_g, background_b)
                    local idx = row + x
                    if delta > ink_delta then
                        data[idx] = 1
                        ink = ink + 1
                    end
                    if luminance(r, g, b) <= border_luminance_max then
                        border[idx] = 1
                        border_cells = border_cells + 1
                    end
                end
            end
        else
            for y = 0, h - 1 do
                local src_y = y * step
                local row = y * w
                for x = 0, w - 1 do
                    local r, g, b = sample(x * step, src_y)
                    local delta = colourDistance(r, g, b, background_r, background_g, background_b)
                    if delta > ink_delta then
                        data[row + x] = 1
                        ink = ink + 1
                    end
                end
            end
        end

        map = {
            w = w,
            h = h,
            data = data,
            border = border,
            ink = ink,
            native_w = native.w,
            native_h = native.h,
            scale_x = native.w / w,
            scale_y = native.h / h,
            background = background,
            background_color = { r = background_r, g = background_g, b = background_b },
            inverted = background < 128,
        }
        local free_mb = Timing.enabled and Timing.freeMB() or nil
        stop(
            string.format(
                "%dx%d %s bg=%d,%d,%d%s ink=%d%%%s%s",
                w,
                h,
                kind,
                background_r,
                background_g,
                background_b,
                map.inverted and " inverted" or "",
                math.floor(ink * 100 / (w * h)),
                border and string.format(" border=%d%%", math.floor(border_cells * 100 / (w * h))) or "",
                free_mb and (" free=" .. free_mb .. "MB") or ""
            )
        )
    end)

    -- The normalized copy, if one was made, is ours; the rendered tile is not.
    if owned then
        pcall(owned.free, owned)
    end

    if not ok then
        logger.warn("[Panels+] page bitmap failed:", err)
        return nil, "error"
    end
    return map, reason
end

-- Exposed for the small, render-free colour-map specs.
PageBitmap._estimateBackground = estimateBackground
PageBitmap._colourDistance = colourDistance
PageBitmap._luminance = luminance

return PageBitmap
