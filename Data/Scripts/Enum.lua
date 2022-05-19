-- The MIT Licence (MIT)
-- Copyright (c) 2021 Andrew Zhilin (https://github.com/zoon)
--[[
    Enum: readonly ordered (by value) hash table with integer values.
    Index returns value by key and key by value.
    Main purpose - keys for networking events (hence the optimization
    for MessagePack).

    Interface:
     - Enum.New(key1, key2)   -> Enum { key1 = 1,  key2 = 2}
     - Enum{key1=11, key2=22} -> Enum { key1 = 11, key2 = 22}

     local e = Enum{a=11}
     e[11]    -> "a"
     e.a      -> 11
     e["a"]   -> 11
     e.a = 12 -> error

     for k, v in pairs(e) do print(k, v) end -> a 11
     print(e) -> Enum {a = 11}

     (!) MP serialization:
        local enc = MessagePack.encode(enum)
        local enum1 = Enum(MessagePack.decode(enc))
]]

local type, mtype = type, math.type
local select = select
local setmetatable = setmetatable
local tonumber = tonumber
local error = error
local assert = assert
local pcall = pcall
local print = print
local concat = table.concat
local pairs = pairs
local format = string.format
local CORE_ENV = CoreDebug and true
local get_trace = CORE_ENV and CoreDebug.GetStackTrace or function() return "" end
local MIN_INT = math.mininteger
local MAX_INT = math.maxinteger


-- Message Pack 1 byte should be in [-32, 127]
local MIN_MP_OPT = -32
local MAX_MP_OPT = 127

_ENV = nil

-- insertion sort
local function isort(keys, vals)
    local n = #vals
    for i = 2, n do
        local val = vals[i]
        local key = keys[i]
        local j = i - 1
        while j > 0 and val < vals[j] do
            vals[j + 1] = vals[j]
            keys[j + 1] = keys[j]
            j = j - 1
        end
        vals[j + 1] = val
        keys[j + 1] = key
    end
    return keys, vals
end

local function isort_gt(keys, vals)
    local n = #vals
    for i = 2, n do
        local val = vals[i]
        local key = keys[i]
        local j = i - 1
        while j > 0 and vals[j] < val do
            vals[j + 1] = vals[j]
            keys[j + 1] = keys[j]
            j = j - 1
        end
        vals[j + 1] = val
        keys[j + 1] = key
    end
    return keys, vals
end

local Enum_mt = {}
Enum_mt.__index = Enum_mt

---@class Enum
local Enum = setmetatable({type = "Enum"}, Enum_mt)
Enum.__index = Enum

---@return Enum
function Enum_mt:__call(...)
    return Enum.from_table(...)
end

function Enum.is(any)
    return type(any) == "table" and any.type == Enum.type
end

-- [from, max]
-- NB. works only for *less* enums
function Enum.is_in(any, min_value, max_value)
    if type(any) ~= "table" or any.type ~= Enum.type then return false end
    if not max_value then return any._vals[1] == min_value end
    local vals = any._vals
    return vals[1] == min_value and vals[#vals] <= max_value
end

local function from_kv(keys, vals, min_value, max_value)
    min_value = min_value or MIN_INT
    max_value = max_value or MAX_INT
    local reverse = {}
    local n = #keys
    if n == 0 then
        error("Enum is empty", 2)
    end
    for i=1, #keys do
        local k, v = keys[i], vals[i]
        if type(k) ~= "string" or tonumber(k) then error(("Enum: key '[%s] = %s' must be a string id"):format(k, v), 3) end
        if mtype(v) ~= "integer" or v > max_value or v < min_value then
            error(format("Enum: '%s = %s': value must be an integer in [%d, %d]", k, v, min_value, max_value), 3)
        end
        if reverse[v] then
            local dup = keys[reverse[v]]
            error(format("Enum: duplicated value: '%s' for keys: '%s', '%s'", v, k, dup), 3)
        end
        reverse[k] = i
        reverse[v] = i
    end
    return setmetatable({_keys = keys, _vals = vals, _reverse=reverse}, Enum)
end

-- export it for serialization purposes
Enum.from_kv = from_kv

-- New :: keys ... -> Enum
---@return Enum
function Enum.New(...)
    local keys = {}
    local vals = {}
    for i = 1, select("#", ...) do
        keys[i] = select(i, ...)
        vals[i] = i
    end
    return from_kv(keys, vals)
end

---@return Enum
function Enum.from_table(t, min, max)
    local keys = {}
    local vals = {}
    for k, v in pairs(t) do
        local i = #keys + 1
        keys[i] = k
        vals[i] = v
    end
    keys, vals = isort(keys, vals)
    return from_kv(keys, vals, min, max)
end

-- Message Pack optimized: values in [-32, 127]
---@return Enum
function Enum.mp(t)
    local keys = {}
    local vals = {}
    for k, v in pairs(t) do
        local i = #keys + 1
        keys[i] = k
        vals[i] = v
    end
    keys, vals = isort(keys, vals)
    return from_kv(keys, vals, MIN_MP_OPT, MAX_MP_OPT)
end

-- max-first ordered enum
---@return Enum
function Enum.gt(t)
    local keys = {}
    local vals = {}
    for k, v in pairs(t) do
        local i = #keys + 1
        keys[i] = k
        vals[i] = v
    end
    keys, vals = isort_gt(keys, vals)
    return from_kv(keys, vals)
end

---@return Enum
function Enum.uint8(t)
    local keys = {}
    local vals = {}
    for k, v in pairs(t) do
        local i = #keys + 1
        keys[i] = k
        vals[i] = v
    end
    keys, vals = isort(keys, vals)
    return from_kv(keys, vals, 0, 255)
end

function Enum:__tostring()
    local out = {"Enum {"}
    for k, v in pairs(self) do
        out[#out + 1] = format("  %s = %d,", k, v)
    end
    out[#out + 1] = "}"
    return concat(out, "\n")
end

function Enum:__index(k)
    if k == "type" then return Enum.type end
    local i = self._reverse[k]
    if mtype(k) == "integer" then
        return self._keys[i] or error(format("Enum has no value: '%s'\n%s\n%s", k, self, get_trace()), 2)
    end
    return self._vals[i] or error(format("Enum has no key: '%s'", k), 2)
end

function Enum:__newindex(_)
    error("Enum is read-only", 2)
end

function Enum:__len() return #self._keys end

local function enum_next(t, k)
    local i = k and t._reverse[k] or 0
    return t._keys[i + 1], t._vals[i + 1]
end

function Enum:__pairs()
    return enum_next, self, nil
end

function Enum.get_kv(self)
    return self._keys, self._vals
end

--[[ NOTE: there is no __ipairs metamethod in vanilla Lua 5.3
local function _inext(t, v)
    local i = v and t._reverse[v] or 0
    return t._vals[i + 1], t._keys[i + 1]
end

function Enum:__ipairs()
    return _inext, self, nil
end
--]]

-----------------------------
-- Test
-----------------------------
local function self_test()
    assert(not pcall(Enum, {uno=1, one=1}))
    assert(not pcall(Enum, {["1"]=1}))
    assert(not pcall(Enum, {pi=3.14}))
    assert(not pcall(Enum, {[{}]=3}))
    local e = Enum {a=1}
    assert(Enum.is(e))
    assert(not Enum.is({}))
    assert(not Enum.is(0))
    assert(Enum.is_in(e, 1))
    assert(Enum.is_in(e, 1, 32))
    assert(not pcall(function() return e[3] end))
    assert(not pcall(function() return e.WRONG end))
    assert(not pcall(function () return Enum{} end))
    e = Enum.New("One", "Two", "Three")
    assert(e.One == 1)
    assert(e[3] == "Three")
    e = Enum{A = -3, B = -1, C = 0, D = 11, E=14}
    assert(Enum.is_in(e, -3, 999))
    for k, v in pairs(e) do
        assert(e[k] == v and e[v] == k)
    end

    local _roman = Enum.gt {
        I = 1,
        V = 5,
        X = 10,
        L = 50,
        C = 100,
        D = 500,
        M = 1000
    }
    for k, v in pairs(_roman) do
        print(k, v)
        assert(v == 1000)
        break
    end

    -- roundtrip or roman
    local keys, vals = {}, {}
    for k, v in pairs(_roman) do
        keys[#keys+1] = k
        vals[#vals+1] = v
    end
    local ert =  from_kv(keys, vals)
    assert(#ert == #_roman)
    for k, v in pairs(_roman) do
        assert(_roman[k] == ert[k])
        assert(_roman[v] == ert[v])
    end

    -- print(Enum.New("key1", "key2"))
    print("enum -- ok")
end
self_test()

return Enum
