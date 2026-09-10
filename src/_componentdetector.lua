local ffi = require("ffi")
local Geometry = require("src._geometry")
local Segmenter = require("src._segmenter")
local Settings = require("src._settings")

--- Experimental panel detector over the same small ink map as the X-Y cut.
--- Connected frames survive tilted gutters and white space inside artwork.
--- This is benchmark-selectable; the reader still uses NativeDetector until
--- the grouping policy and reader integration have been reviewed.
local ComponentDetector = {}

--- Extract substantial 8-connected components without modifying the input.
--- The two scratch arrays cost five bytes per map cell with LuaJIT (about
--- 1.5 MB at 480x637). Tiny components are discarded before allocating boxes.
local function collectComponents(map, min_side, min_area)
    local width, height, data = map.w, map.h, map.data
    local seen = ffi.new("uint8_t[?]", width * height)
    local queue = ffi.new("int32_t[?]", width * height)
    local components = {}

    for index = 0, width * height - 1 do
        if data[index] == 1 and seen[index] == 0 then
            local head, tail = 0, 1
            queue[0], seen[index] = index, 1
            local left, right, top, bottom = width, 0, height, 0
            while head < tail do
                local position = queue[head]
                head = head + 1
                local y = math.floor(position / width)
                local x = position - y * width
                left, right = math.min(left, x), math.max(right, x)
                top, bottom = math.min(top, y), math.max(bottom, y)
                for ny = math.max(0, y - 1), math.min(height - 1, y + 1) do
                    for nx = math.max(0, x - 1), math.min(width - 1, x + 1) do
                        local neighbor = ny * width + nx
                        if seen[neighbor] == 0 and data[neighbor] == 1 then
                            seen[neighbor] = 1
                            queue[tail] = neighbor
                            tail = tail + 1
                        end
                    end
                end
            end
            local w, h = right - left + 1, bottom - top + 1
            if w >= width * min_side and h >= height * min_side and w * h >= min_area then
                components[#components + 1] = { x = left, y = top, w = w, h = h }
            end
        end
    end
    return components
end

--- Small panels need evidence of a frame so large letters and isolated faces
--- do not qualify on size alone. Sample a narrow band along all four edges.
local function hasFrame(map, box)
    local top, bottom, left, right = 0, 0, 0, 0
    local band = math.min(3, box.w, box.h)
    for x = box.x, box.x + box.w - 1 do
        for offset = 0, band - 1 do
            if map.data[(box.y + offset) * map.w + x] == 1 then
                top = top + 1
                break
            end
        end
        for offset = 0, band - 1 do
            if map.data[(box.y + box.h - 1 - offset) * map.w + x] == 1 then
                bottom = bottom + 1
                break
            end
        end
    end
    for y = box.y, box.y + box.h - 1 do
        for offset = 0, band - 1 do
            if map.data[y * map.w + box.x + offset] == 1 then
                left = left + 1
                break
            end
        end
        for offset = 0, band - 1 do
            if map.data[y * map.w + box.x + box.w - 1 - offset] == 1 then
                right = right + 1
                break
            end
        end
    end
    return top > box.w * 0.8 and bottom > box.w * 0.8 and left > box.h * 0.8 and right > box.h * 0.8
end

--- Return native-coordinate candidate boxes, with contained regions removed.
--- Containment is a candidate policy: it removes speech balloons inside frames
--- but can also remove an intentional inset. It does not merge partial overlaps.
function ComponentDetector.segment(map, settings)
    settings = settings or Settings.defaults
    local min_side = math.max(0.06, settings.segment_min_panel_side or Settings.defaults.segment_min_panel_side)
    local min_area = map.w * map.h * (settings.segment_min_panel_area or Settings.defaults.segment_min_panel_area)
    local components = collectComponents(map, min_side, min_area)
    local panels = {}
    for _, box in ipairs(components) do
        local keep = true
        for _, other in ipairs(components) do
            if
                other ~= box
                and other.w * other.h > box.w * box.h
                and box.x >= other.x - 1
                and box.y >= other.y - 1
                and box.x + box.w <= other.x + other.w + 1
                and box.y + box.h <= other.y + other.h + 1
            then
                keep = false
                break
            end
        end
        if keep and (box.w < map.w * 0.10 or box.h < map.h * 0.10) then
            keep = hasFrame(map, box)
        end
        if keep then
            local x = math.max(0, (box.x - 1) * map.scale_x)
            local y = math.max(0, (box.y - 1) * map.scale_y)
            local right = math.min(map.native_w, (box.x + box.w + 1) * map.scale_x)
            local bottom = math.min(map.native_h, (box.y + box.h + 1) * map.scale_y)
            panels[#panels + 1] = { x = x, y = y, w = right - x, h = bottom - y }
        end
    end
    if #panels > (settings.segment_max_panels or Settings.defaults.segment_max_panels) then
        return {} -- Let the caller fall back instead of returning a partial page.
    end
    return panels
end

--- Apply the existing coverage guards and reading order to component boxes.
function ComponentDetector.detectPage(map, settings)
    settings = settings or Settings.defaults
    local panels = ComponentDetector.segment(map, settings)
    local accepted, reason = Segmenter.accept(panels, map, settings)
    if not accepted then
        return { { x = 0, y = 0, w = map.native_w, h = map.native_h } }, false, reason
    end
    return Geometry.sortReadingOrder(panels, settings.mode or "manga"), true
end

return ComponentDetector
