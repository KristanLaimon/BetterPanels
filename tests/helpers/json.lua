--- Dependency-free pure-Lua JSON decoder for tests and evaluation tools.
---
--- Supports objects, arrays, strings (with escapes and unicode), numbers, booleans, and null.
--- Operates under standard Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT.

local JSON = {}

function JSON.decode(str)
    if not str or type(str) ~= "string" then
        return nil, "expected string"
    end

    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        pos = pos + 1 -- opening quote
        local parts = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(parts)
            elseif c == "\\" then
                local esc = str:sub(pos + 1, pos + 1)
                local map = {
                    ['"'] = '"',
                    ["\\"] = "\\",
                    ["/"] = "/",
                    b = "\b",
                    f = "\f",
                    n = "\n",
                    r = "\r",
                    t = "\t",
                }
                if map[esc] then
                    table.insert(parts, map[esc])
                    pos = pos + 2
                elseif esc == "u" then
                    local hex = str:sub(pos + 2, pos + 5)
                    local cp = tonumber(hex, 16) or 63
                    if cp < 0x80 then
                        table.insert(parts, string.char(cp))
                    elseif cp < 0x800 then
                        table.insert(parts, string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40)))
                    else
                        table.insert(
                            parts,
                            string.char(
                                0xE0 + math.floor(cp / 0x1000),
                                0x80 + (math.floor(cp / 0x40) % 0x40),
                                0x80 + (cp % 0x40)
                            )
                        )
                    end
                    pos = pos + 6
                else
                    table.insert(parts, esc)
                    pos = pos + 2
                end
            else
                table.insert(parts, c)
                pos = pos + 1
            end
        end
        error("unterminated string in JSON at position " .. pos)
    end

    local function parseNumber()
        local start = pos
        while pos <= len and str:sub(pos, pos):match("[%d%.%-%+eE]") do
            pos = pos + 1
        end
        return tonumber(str:sub(start, pos - 1))
    end

    local function parseObject()
        pos = pos + 1 -- '{'
        local obj = {}
        skipWhitespace()
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        while true do
            skipWhitespace()
            local key = parseString()
            skipWhitespace()
            pos = pos + 1 -- ':'
            skipWhitespace()
            obj[key] = parseValue()
            skipWhitespace()
            local c = str:sub(pos, pos)
            pos = pos + 1
            if c == "}" then
                break
            end
        end
        return obj
    end

    local function parseArray()
        pos = pos + 1 -- '['
        local arr = {}
        skipWhitespace()
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        while true do
            skipWhitespace()
            table.insert(arr, parseValue())
            skipWhitespace()
            local c = str:sub(pos, pos)
            pos = pos + 1
            if c == "]" then
                break
            end
        end
        return arr
    end

    parseValue = function()
        skipWhitespace()
        local c = str:sub(pos, pos)
        if c == '"' then
            return parseString()
        elseif c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif c:match("[%d%-]") then
            return parseNumber()
        else
            error(string.format("unexpected character '%s' at position %d", c, pos))
        end
    end

    skipWhitespace()
    return parseValue()
end

return JSON
