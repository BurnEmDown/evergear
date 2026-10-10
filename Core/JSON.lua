-- Minimal pure-Lua JSON encode/decode. Hand-written for EverGear rather than
-- vendoring a third-party library -- WoW addons can't `require` anything
-- from outside their own files, so "vendoring" always means copy-pasting a
-- whole library's source in anyway, and the actual JSON surface this addon
-- needs (see EPProfiles.lua's SerializeProfile/DeserializeProfile) is small:
-- flat-ish objects of strings/numbers/booleans/nested objects, no need for
-- unicode escape sequences, numbers in scientific notation, etc. Encode is
-- pretty-printed (2-space indent) since the output is meant to be copy-
-- pasted into a text file a player might actually open.
--
-- Exposed as EverGear.JSON.encode(value) -> string
--            EverGear.JSON.decode(str) -> value  (throws a Lua error with a
--                                                  position-annotated message
--                                                  on malformed input -- wrap
--                                                  in pcall, which
--                                                  DeserializeProfile below
--                                                  does)

EverGear = EverGear or {}
EverGear.JSON = EverGear.JSON or {}

-- ===== Encode =====

local ESCAPES = {
    ["\\"] = "\\\\", ["\""] = "\\\"",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function EncodeString(s)
    local escaped = s:gsub('[\\"\n\r\t]', ESCAPES)
    return '"' .. escaped .. '"'
end

-- A Lua table is encoded as a JSON array if every key is a positive integer
-- 1..n with no gaps, otherwise as a JSON object. An empty table encodes as
-- `{}` (object), since every profile-shaped table EverGear actually encodes
-- is object-like even when momentarily empty (e.g. a spec with no offStat
-- entries), never meant to be an array.
-- EverGear.JSON.emptyArray (below) is an empty table that encodes as `[]`,
-- for formats that want an empty list there (gear set export).
local EMPTY_ARRAY_MARK = {}

local function IsArray(t)
    local mt = getmetatable(t)
    if mt and mt.jsonArray == EMPTY_ARRAY_MARK then return true end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    if count == 0 then return false end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

local EncodeValue

local function EncodeTable(t, indent)
    local innerIndent = indent .. "  "
    if IsArray(t) then
        if #t == 0 then return "[]" end
        local parts = {}
        for _, v in ipairs(t) do
            table.insert(parts, innerIndent .. EncodeValue(v, innerIndent))
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end

    -- Object: sort keys for stable, diff-friendly output (two exports of the
    -- same profile should produce byte-identical JSON).
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    if #keys == 0 then return "{}" end

    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, innerIndent .. EncodeString(tostring(k)) .. ": " .. EncodeValue(t[k], innerIndent))
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

EncodeValue = function(value, indent)
    local valueType = type(value)
    if valueType == "string" then
        return EncodeString(value)
    elseif valueType == "number" then
        -- %.10g avoids both unnecessary trailing zeros (weights are always
        -- at most 2 decimal places already, see ClampWeight) and float noise
        -- like 0.30000000000000004.
        return string.format("%.10g", value)
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "table" then
        return EncodeTable(value, indent)
    elseif valueType == "nil" then
        return "null"
    else
        error("EverGear.JSON.encode: cannot encode a value of type " .. valueType)
    end
end

-- A fresh empty list that encodes as `[]` rather than `{}`.
function EverGear.JSON.emptyArray()
    return setmetatable({}, { jsonArray = EMPTY_ARRAY_MARK })
end

function EverGear.JSON.encode(value)
    return EncodeValue(value, "")
end

-- ===== Decode =====
-- Small recursive-descent parser. Throws (error()) with a 1-based character
-- position on malformed input rather than returning partial/garbage data --
-- callers (DeserializeProfile) wrap this in pcall.

local function NewDecodeState(str)
    return { str = str, pos = 1, len = #str }
end

local function Fail(state, message)
    error(string.format("%s at character %d", message, state.pos))
end

local function SkipWhitespace(state)
    local _, stop = state.str:find("^%s*", state.pos)
    state.pos = stop + 1
end

local DecodeValue

local function DecodeString(state)
    -- state.pos is at the opening quote.
    state.pos = state.pos + 1
    local parts = {}
    while true do
        if state.pos > state.len then Fail(state, "Unterminated string") end
        local c = state.str:sub(state.pos, state.pos)
        if c == '"' then
            state.pos = state.pos + 1
            return table.concat(parts)
        elseif c == "\\" then
            local next = state.str:sub(state.pos + 1, state.pos + 1)
            local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }
            if map[next] then
                table.insert(parts, map[next])
                state.pos = state.pos + 2
            elseif next == "u" then
                -- \uXXXX -- only ASCII range actually needed for this
                -- addon's data (stat names, profile names); anything
                -- outside it is passed through as "?" rather than
                -- implementing full UTF-16 surrogate-pair decoding for a
                -- case that shouldn't occur in practice.
                local hex = state.str:sub(state.pos + 2, state.pos + 5)
                local code = tonumber(hex, 16)
                table.insert(parts, (code and code < 128) and string.char(code) or "?")
                state.pos = state.pos + 6
            else
                Fail(state, "Invalid escape sequence '\\" .. next .. "'")
            end
        else
            table.insert(parts, c)
            state.pos = state.pos + 1
        end
    end
end

local function DecodeNumber(state)
    local _, stop, numStr = state.str:find("^(%-?%d+%.?%d*[eE]?[%+%-]?%d*)", state.pos)
    if not numStr then Fail(state, "Invalid number") end
    state.pos = stop + 1
    return tonumber(numStr)
end

local function DecodeArray(state)
    state.pos = state.pos + 1  -- skip '['
    local result = {}
    SkipWhitespace(state)
    if state.str:sub(state.pos, state.pos) == "]" then
        state.pos = state.pos + 1
        return result
    end
    while true do
        SkipWhitespace(state)
        table.insert(result, DecodeValue(state))
        SkipWhitespace(state)
        local c = state.str:sub(state.pos, state.pos)
        if c == "," then
            state.pos = state.pos + 1
        elseif c == "]" then
            state.pos = state.pos + 1
            return result
        else
            Fail(state, "Expected ',' or ']' in array")
        end
    end
end

local function DecodeObject(state)
    state.pos = state.pos + 1  -- skip '{'
    local result = {}
    SkipWhitespace(state)
    if state.str:sub(state.pos, state.pos) == "}" then
        state.pos = state.pos + 1
        return result
    end
    while true do
        SkipWhitespace(state)
        if state.str:sub(state.pos, state.pos) ~= '"' then
            Fail(state, "Expected string key in object")
        end
        local key = DecodeString(state)
        SkipWhitespace(state)
        if state.str:sub(state.pos, state.pos) ~= ":" then
            Fail(state, "Expected ':' after object key")
        end
        state.pos = state.pos + 1
        SkipWhitespace(state)
        result[key] = DecodeValue(state)
        SkipWhitespace(state)
        local c = state.str:sub(state.pos, state.pos)
        if c == "," then
            state.pos = state.pos + 1
        elseif c == "}" then
            state.pos = state.pos + 1
            return result
        else
            Fail(state, "Expected ',' or '}' in object")
        end
    end
end

DecodeValue = function(state)
    SkipWhitespace(state)
    local c = state.str:sub(state.pos, state.pos)
    if c == '"' then
        return DecodeString(state)
    elseif c == "{" then
        return DecodeObject(state)
    elseif c == "[" then
        return DecodeArray(state)
    elseif c == "-" or c:match("%d") then
        return DecodeNumber(state)
    elseif state.str:sub(state.pos, state.pos + 3) == "true" then
        state.pos = state.pos + 4
        return true
    elseif state.str:sub(state.pos, state.pos + 4) == "false" then
        state.pos = state.pos + 5
        return false
    elseif state.str:sub(state.pos, state.pos + 3) == "null" then
        state.pos = state.pos + 4
        return nil
    else
        Fail(state, "Unexpected character '" .. c .. "'")
    end
end

function EverGear.JSON.decode(str)
    if type(str) ~= "string" or str:match("^%s*$") then
        error("Empty input")
    end
    local state = NewDecodeState(str)
    local value = DecodeValue(state)
    SkipWhitespace(state)
    if state.pos <= state.len then
        Fail(state, "Trailing content after JSON value")
    end
    return value
end
