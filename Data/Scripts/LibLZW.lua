-- Based on Go's compress/lzw package.

-- Copyright (c) 2009-2021 The Go Authors. All rights reserved.

-- Ported to Lua 5.3 by Andrew Zhilin (https://github.com/zoon).
-- Copyright (c) 2021 Andrew Zhilin.

-- Licensed under BSD 3-Clause License.

-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are
-- met:
--    * Redistributions of source code must retain the above copyright
-- notice, this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above
-- copyright notice, this list of conditions and the following disclaimer
-- in the documentation and/or other materials provided with the
-- distribution.
--    * Neither the name of Google Inc. nor the names of its
-- contributors may be used to endorse or promote products derived from
-- this software without specific prior written permission.
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
-- LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
-- A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
-- OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
-- LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
-- DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
-- THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
-- OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
_ENV.require = _G.import or require
local mp = require("MessagePack")
local b64 = require("QuickBase64")

local min, max = math.min, math.max
local byte, char = string.byte, string.char
local unpack, concat = table.unpack, table.concat
local type, mtype = type, math.type
local pcall = pcall
local assert, error = assert, error
local print, format = print, string.format
local setmetatable = setmetatable
local tonumber = tonumber
local noop = function() end
-- for test
local rand, spack = math.random, string.pack
local os = os
-- Core
local CORE_ENV = not not CoreDebug
local Task = Task
local warn = CORE_ENV and warn or noop
_ENV = nil

-----------------------------
-- Module
-----------------------------
---@class lzw
---@field LSB integer
---@field MSB integer
---@field Writer lzw.Writer
---@field Reader lzw.Reader
local m = {}

-- TODO: export functions signatures
-- TODO: optimize it! This implementation took ~15ms (with ratio: 1.637) on
-- 17KB json_mp.bin, previous (all state in locals) took ~10ms.

-- TODO: code style
-- TODO: rename toRead to "dst"

-----------------
-- Const
-----------------
-- A code is a 12 bit value, stored as a uint32 when encoding to avoid
--  type conversions when shifting bits.
local maxCode = (1 << 12) - 1 -- 4095
local invalidCode = (1 << 32) - 1 -- 0xffffffff
-- There are 1<<12 possible codes, which is an upper bound on the number of
-- valid hash table entries at any given point in time. tableSize is 4x that.
-- TODO: use static table
local tableSize = 4 * 1 << 12 -- 16348
local tableMask = tableSize - 1
-- A hash table entry is a uint32. Zero is an invalid entry since the
-- lower 12 bits of a valid entry must be a non-literal code.
local invalidEntry = 0

local maxWidth = 12
local decoderInvalidCode = 0xffff
local flushBuffer = 1 << maxWidth


local uninitialised = function()
    error("uninitialised instance")
end
local empty = setmetatable({}, {__index = uninitialised, __newindex = uninitialised})

-- byte order
local LSB = 1
local MSB = 2


-----------------------------
-- Core utils
-----------------------------
local wait = CORE_ENV and Task.Wait or noop

-----------------------------
-- compress/decompress header
-----------------------------
-- For our format litWith always 8 bits, we get byte order from first *clear*
-- byte.
local LSB_LW8_CLEAR_BYTE = 0x00
local MSB_LW8_CLEAR_BYTE = 0x80

-- header prefix
local HB0, HB1, HB2 = byte("lzw", 1, 3)

local function emit_header(writer)
    assert(type(writer) == "table" and writer.type == "lzw.Writer")
    local w = writer.w
    w[#w + 1] = HB0
    w[#w + 1] = HB1
    w[#w + 1] = HB2
end

-- returns LSB | MSB | nil
local function check_header(s)
    local hb0, hb1, hb2, hb3 = byte(s, 1, 4)
    if hb0 == HB0 and hb1 == HB1 and hb2 == HB2 then
        if hb3 == LSB_LW8_CLEAR_BYTE then
            return LSB
        end
        if hb3 == MSB_LW8_CLEAR_BYTE then
            return MSB
        end
    end
end

-----------------------------
-- Debug Utils
-----------------------------
local function hexify(s)
    if mtype(s) == "integer" then
        assert(s == s & 0xFF, "argument should be a byte")
        if s > 31 and s < 127 then
            return char(s)
        end
        return format("\\x%.2x", s)
    end
    if (type(s) ~= "string") then
        error(format("argument should be a string, got: '%s'", type(s)))
    end
    local out = {}
    for i = 1, #s do
        out[#out + 1] = format("\\x%.2x", byte(s, i))
    end
    if #out == 0 then
        return "\"\""
    end
    return concat(out)
end

-----------------------------
-- Static arrays (lazy init)
-----------------------------
-- NB. total static memory allocation ~512KB
-- for writer
local _hashtable = nil -- size: 16384
local function clear_hashtable()
    if CORE_ENV then return {} end
    if not _hashtable then
        _hashtable = {}
    end
    local ht = _hashtable
    for i = 0, tableSize - 1 do
        ht[i] = invalidEntry
    end
    return ht
end
-- for reader
local _suffix = nil -- size: 4095
local _prefix = nil -- size: 4095
local _output = nil -- size: 8191

local function allocate_output()
    -- we newer clear output, suffix and prefix
    local alloc = not (_output and _suffix and _prefix)
    if alloc then
        _output = {}
        _suffix = {}
        _prefix = {}
        if not _output then
            _output = {}
        end
        for i = 0, (2 * 1 << maxWidth) - 1 do
            _output[i] = 0
        end
        assert(#_output == (2 * 1 << maxWidth) - 1, #_output)
        for i = 0, (1 << maxWidth) - 1 do
            _suffix[i], _prefix[i] = 0, 0
        end
        assert(#_suffix == (1 * 1 << maxWidth) - 1)
        assert(#_prefix == (1 * 1 << maxWidth) - 1)
    end
    return _output, _suffix, _prefix
end

-----------------------------
--- Writer
-----------------------------
local Writer_mt = {}
Writer_mt.__index = Writer_mt
---@class lzw.Writer
local Writer = setmetatable({type = "lzw.Writer"}, Writer_mt)
Writer.__index = Writer

-- TODO: cleanup go-style ctors
local function newWriter(dst, order, litWidth)
    assert(dst == nil or type(dst) == "table")
    local w = Writer.new()
    w:init(dst, order, litWidth)
    return w
end

-- shortcut for constuctor
function Writer_mt:__call(dst, order, litWidth)
    return newWriter(dst, order, litWidth)
end

-- creates empty writer state
function Writer.new()
    return setmetatable({
        -- w is the writer that compressed bytes are written to.
        w = empty, -- writer
        -- order, write, bits, nBits and width are the state for
        -- converting a code stream into a byte stream.
        order = LSB, -- Order
        write = noop, -- func(*Writer, uint32) error
        bits = 0, --  uint32
        nBits = 0, -- uint
        width = 0, -- uint
        -- litWidth is the width in bits of literal codes.
        litWidth = 0, -- uint
        -- hi is the code implied by the next code emission.
        -- overflow is the code at which hi overflows the code width.
        hi = 0,
        overflow = 0, -- uint32
        -- savedCode is the accumulated code at the end of the most recent Write
        -- call. It is equal to invalidCode if there was no such call.
        savedCode = 0, -- uint32
        -- err is the first error encountered during writing. Closing the writer
        -- will make any future Write calls return errClosed
        -- table is the hash table from 20-bit keys to 12-bit values. Each table
        -- entry contains key<<12|val and collisions resolve by linear probing.
        -- The keys consist of a 12-bit code prefix and an 8-bit byte suffix.
        -- The values are a 12-bit code.
        hashtable = empty -- [tableSize]uint32
    }, Writer)
end

Writer.New = Writer.new

-- all args optional
function Writer:init(dst, order, litWidth)
    local w = self
    order = order or LSB
    if order == LSB then
        w.write = Writer.WriteLSB
    elseif order == MSB then
        w.write = Writer.WriteMSB
    else
        error("lzw: unknown order")
    end
    litWidth = litWidth or 8
    if litWidth < 2 or 8 < litWidth then
        error(format("lzw: litWidth %d out of range", litWidth))
    end
    w.w = dst or {}
    w.order = order
    w.width = 1 + litWidth
    w.litWidth = litWidth
    w.hi = (1 << litWidth) + 1
    w.overflow = 1 << (litWidth + 1)
    w.savedCode = invalidCode
    -- reset or init table
    w.hashtable = {} -- clear_hashtable()
    return self
end

-- TODO: inline
function Writer:WriteLSB(c)
    local w = self
    local ww = w.w
    w.bits = w.bits | c << w.nBits
    w.nBits = w.nBits + w.width
    while w.nBits >= 8 do
        -- NB. ww[#ww+1] = w.bits & 0xff took 2-4ms
        ww[#ww + 1] = w.bits & 0xff
        w.bits = w.bits >> 8
        w.nBits = w.nBits - 8
    end
end

-- NB. do not optimize it, let it be ref. for perf comparison
function Writer:WriteMSB(c)
    local w = self
    w.bits = w.bits | c << (32 - w.width - w.nBits)
    w.nBits = w.nBits + w.width
    while w.nBits >= 8 do
        w.w[#w.w + 1] = w.bits >> 24 & 0xff
        w.bits = w.bits << 8
        w.nBits = w.nBits - 8
    end
end

function Writer:incHi()
    local w = self
    w.hi = w.hi + 1
    if w.hi == w.overflow then
        w.width = w.width + 1
        w.overflow = w.overflow << 1
    end
    if w.hi == maxCode then
        local clear = 1 << w.litWidth
        w:write(clear)
        w.width = w.litWidth + 1
        w.hi = clear + 1
        w.overflow = clear << 1
        w.hashtable = clear_hashtable()
        return true -- errOutOfCodes
    end
end

-- Write writes a compressed representation of str to w's underlying writer.
function Writer:Write(str, from, to)
    assert(type(str) == "string", "p must be a string")
    from = from or 1
    to = to or #str
    local len = to - from + 1
    if len <= 0 then
        return 0
    end
    local w = self
    local maxLit = (1 << w.litWidth) - 1
    if maxLit ~= 0xff then
        for i = from, to do
            local x = byte(str, i)
            if x > maxLit then
                error(format("lzw: input byte too large for the litWidth: %d", w.litWidth))
            end
        end
    end
    local code = w.savedCode
    if code == invalidCode then
        -- This is the first write; send a clear code.
        -- https://www.w3.org/Graphics/GIF/spec-gif89a.txt Appendix F
        -- "Variable-Length-Code LZW Compression" says that "Encoders should
        -- output a Clear code as the first code of each image data stream".
        -- LZW compression isn't only used by GIF, but it's cheap to follow
        -- that directive unconditionally.
        local clear = 1 << w.litWidth
        w:write(clear)
        -- After the starting clear code, the next code sent (for non-empty
        -- input) is always a literal code.
        code = byte(str, from)
        from = from + 1
    end
    ::loop::
    for i = from, to do
        local literal = byte(str, i)
        local key = (code << 8) | literal
        -- If there is a hash table hit for this key then we continue the loop
        -- and do not emit a code yet.
        local hash = (key >> 12) ~ key & tableMask
        local h, t = hash, w.hashtable[hash]
        -- if we don't use static ta
        while t and t ~= invalidEntry do
            if key == (t >> 12) then
                code = t & maxCode
                from = i + 1
                goto loop
            end
            h = (h + 1) & tableMask
            t = w.hashtable[h]
        end
        -- Otherwise, write the current code, and literal becomes the start of
        -- the next emitted code.
        w:write(code)
        code = literal
        -- Increment w.hi, the next implied code. If we run out of codes, reset
        -- the writer state (including clearing the hash table) and continue.
        if w:incHi() then
            goto continue
        end
        while true do
            if not w.hashtable[hash] or w.hashtable[hash] == invalidEntry then
                w.hashtable[hash] = (key << 12) | w.hi
                break
            end
            hash = (hash + 1) & tableMask
        end
        ::continue::
    end
    w.savedCode = code
    return len
end

function Writer:Close(str)
    local w = self
    -- Write the savedCode if valid.
    if w.savedCode ~= invalidCode then
        w:write(w.savedCode)
        w:incHi()
    else
        -- Write the starting clear code, as w.Write did not.
        local clear = 1 << w.litWidth
        w:write(clear)
    end
    -- Write the eof code.
    local eof = (1 << w.litWidth) + 1
    w:write(eof)
    --  Write the final bits.
    if w.nBits > 0 then
        if w.order == MSB then
            w.bits = w.bits >> 24
        end
        w.w[#w.w + 1] = w.bits & 0xff
    end
    return str and char(unpack(w.w)) or w.w
end

function Writer:Reset(dst, order, litWidth)
    order = order or self.order
    litWidth = litWidth or self.litWidth
    self.bits = 0
    self.nBits = 0
    self.width = 0
    self:init(dst, order, litWidth)
    return self
end

-----------------------------
-- Reader
-----------------------------
local Reader_mt = {}
Reader_mt.__index = Reader_mt

---@class lzw.Reader
local Reader = setmetatable({type = "lzw.Reader"}, Reader_mt)
Reader.__index = Reader

function Reader.new()
    return setmetatable({
        r = nil, -- io.ByteReader
        rFrom = 0, -- index for reader
        rTo = 0, -- last byte index

        bits = 0, -- uint32
        nBits = 0, -- uint
        width = 0, -- uint
        read = noop, -- func(*Reader) (uint16, error) readLSB or readMSB
        litWidth = 0, -- int, width in bits of literal codes
        -- // The first 1<<litWidth codes are literal codes.
        -- // The next two codes mean clear and EOF.
        -- // Other valid codes are in the range [lo, hi] where lo := clear + 2,
        -- // with the upper bound incrementing on each code seen.
        -- //
        -- // overflow is the code at which hi overflows the code width. It always
        -- // equals 1 << width.
        -- //
        -- // last is the most recently seen code, or decoderInvalidCode.
        -- //
        -- // An invariant is that hi < overflow.
        clear = 0,
        eof = 0,
        hi = 0,
        overflow = 0,
        last = 0, -- uint16 = 0

        -- // Each code c in [lo, hi] expands to two or more bytes. For c != hi:
        -- //   suffix[c] is the last of these bytes.
        -- //   prefix[c] is the code for all but the last byte.
        -- //   This code can either be a literal code or another code in [lo, c).
        -- // The c == hi case is a special case.
        suffix = empty, -- [1 << maxWidth]uint8 #4096
        prefix = empty, -- [1 << maxWidth]uint16 #4096
        -- // output is the temporary output buffer.
        -- // Literal codes are accumulated from the start of the buffer.
        -- // Non-literal codes decode to a sequence of suffixes that are first
        -- // written right-to-left from the end of the buffer before being copied
        -- // to the start of the buffer.
        -- // It is flushed when it contains >= 1<<maxWidth bytes,
        -- // so that there is always room to decode an entire code.
        output = empty, -- [2 * 1 << maxWidth]byte 2*4096

        o = 0, -- int    // write index into output
        toRead = empty -- []byte // bytes to return from Read
    }, Reader)
end

function Reader_mt:__call(src, from, to, order, litWidth, dst)
    return self:newReader(src, from, to, order, litWidth, dst)
end

function Reader:newReader(src, from, to, order, litWidth, dst)
    local r = Reader.new()
    r:init(src, from, to, order, litWidth, dst)
    return r
end

function Reader:Reset(src, from, to, order, litWidth, dst)
    local r = self
    r.bits = 0
    r.nBits = 0
    r.o = 0
    r:init(src, from, to, order, litWidth, dst)
end
-- all args optional
function Reader:init(src, from, to, order, litWidth, dst)
    assert(src, "Reader must be initialized with compressed string")
    local r = self
    r.r = src
    from = from or 1
    to = to or #r.r
    r.rFrom = from
    r.rTo = to

    local o, s, p = allocate_output()
    r.output = o
    r.suffix = s
    r.prefix = p

    order = order or LSB
    if order == LSB then
        r.read = Reader.ReadLSB
    elseif order == MSB then
        r.read = Reader.ReadMSB
    else
        error("lzw: unknown order ")
    end

    litWidth = litWidth or 8
    if litWidth < 2 or 8 < litWidth then
        error(format("lzw: litWidth %d out of range", litWidth))
    end
    r.litWidth = litWidth
    r.width = 1 + litWidth
    r.clear = 1 << litWidth & 0xffff
    r.eof, r.hi = r.clear + 1, r.clear + 1
    r.overflow = 1 << r.width & 0xffff
    r.last = decoderInvalidCode
    r.toRead = dst or {} -- array to copy output to, i.e. user output
end

function Reader:ReadLSB()
    local r = self
    assert(r.rFrom > 0)
    while r.nBits < r.width do
        -- read byte
        if r.rFrom > r.rTo then
            error("lzw - unexpected EOF")
        end
        local x = byte(r.r, r.rFrom)
        r.rFrom = r.rFrom + 1
        r.bits = r.bits | x << r.nBits
        r.nBits = r.nBits + 8
    end
    local code = (r.bits & (1 << r.width) - 1) & 0xffff
    r.bits = r.bits >> r.width
    r.nBits = r.nBits - r.width
    return code
end

function Reader:ReadMSB()
    local r = self
    while r.nBits < r.width do
        -- read byte
        if r.rFrom > r.rTo then
            error("unexpected EOF")
        end
        local x = byte(r.r, r.rFrom)
        r.rFrom = r.rFrom + 1
        r.bits = (r.bits | x << (24 - r.nBits)) & 0xffffffff
        r.nBits = r.nBits + 8
    end
    local code = (r.bits >> (32 - r.width)) & 0xffff
    r.bits = r.bits << r.width
    r.nBits = r.nBits - r.width
    return code
end

---@return boolean -- retuns true when decompression complete
function Reader:Read()
    local r = self
    return r:decode()
end

function Reader:Close(str)
    local r = self
    local out = not str and r.toRead or char(unpack(r.toRead))
    r.toRead = empty
    return out
end

function Reader:decode()
    local r = self
    local eof = false
    ::loop::
    while true do
        local code = r:read() -- ReadLSB | ReadMSB
        -- classify codes
        if code < r.clear then
            -- we have a literal code
            r.output[r.o] = code & 0xff
            r.o = r.o + 1
            if r.last ~= decoderInvalidCode then
                -- Save what the hi code expands to.
                r.suffix[r.hi] = code & 0xff
                r.prefix[r.hi] = r.last
            end
        elseif code == r.clear then
            r.width = 1 + r.litWidth
            r.hi = r.eof
            r.overflow = 1 << r.width
            r.last = decoderInvalidCode
            goto continue
        elseif code == r.eof then
            eof = true
            break
        elseif code <= r.hi then
            -- output is 0-indexed
            local c, i = code, #r.output -- len(r.output) - 1
            if code == r.hi and r.last ~= decoderInvalidCode then
                -- code == hi is a special case which expands to the last expansion
                -- followed by the head of the last expansion. To find the head, we walk
                -- the prefix chain until we find a literal code.
                c = r.last
                while c >= r.clear do
                    c = r.prefix[c]
                end
                r.output[i] = c & 0xff
                i = i - 1
                c = r.last
            end
            -- Copy the suffix chain into output and then write that to w.
            while c >= r.clear do
                r.output[i] = r.suffix[c]
                i = i - 1
                c = r.prefix[c]
            end
            r.output[i] = c & 0xff
            -- r.o += copy(r.output[r.o:], r.output[i:])
            for oi = i, #r.output do
                r.output[r.o] = r.output[oi]
                r.o = r.o + 1
            end
            if r.last ~= decoderInvalidCode then
                -- Save what the hi code expands to.
                r.suffix[r.hi] = c & 0xff
                r.prefix[r.hi] = r.last
            end
        else
            error("lzw - invalid code")
        end -- if code ...
        r.last, r.hi = code, r.hi + 1
        if r.hi >= r.overflow then
            if r.hi > r.overflow then
                error("lzw - unreachable")
            end
            if r.width == maxWidth then
                r.last = decoderInvalidCode
                -- Undo the d.hi++ a few lines above, so that (1) we maintain
                -- the invariant that d.hi < d.overflow, and (2) d.hi does not
                -- eventually overflow a uint16.
                r.hi = r.hi - 1
            else
                r.width = r.width + 1
                r.overflow = 1 << r.width
            end
        end
        if r.o >= flushBuffer then
            break
        end
        ::continue::
    end -- loop
    -- Flush pending output.
    for oi = 0, r.o - 1 do
        r.toRead[#r.toRead + 1] = r.output[oi]
    end
    r.o = 0
    -- if r.rFrom < r.rTo then
    --     goto loop
    -- end
    return eof
end

-----------------------------
-- Test
-----------------------------
-- returns lw, order, tag
local function split(s)
    assert(type(s) == "string" and #s > 7)
    local lw = tonumber(s:sub(-1))
    local order = s:sub(-5, -3)
    return lw, order == "LSB" and LSB or MSB, s:sub(1, -7)
end

-- LuaFormatter off
local TEST_DATA = {
    { -- 1
        "empty;LSB;7",
        "",
        "\x80\x81",
        nil
    },
    {
        "nonempty;LSB;7",
        "Hi",
        "\x80Hi\x81",
        nil
    },
    {
        "empty;LSB;8",
        "",
        "\x00\x03\x02",
        nil,
    },
    {
        "empty;MSB;7",
        "",
        "\x80\x81",
        nil,
    },
    { -- 5
        "empty;MSB;8",
        "",
        "\x80@@",
        nil,
    },
    {
        "tobe;LSB;7",
        "TOBEORNOTTOBEORTOBEORNOT",
        "\x80TOBEORNOT\x82\x84\x86\x8b\x85\x87\x89\x81",
        nil,
    },
    {
        "tobe;LSB;8",
        "TOBEORNOTTOBEORTOBEORNOT",
        "\x00\xa9<\x11R\xe4\x89\x14'O\xa8\b$hpa\xc1\x83\t\x03\x02",
        nil,
    },
    {
        "tobe;MSB;7",
        "TOBEORNOTTOBEORTOBEORNOT",
        "\x80TOBEORNOT\x82\x84\x86\x8b\x85\x87\x89\x81",
        nil,
    },
    {
        "tobe;MSB;8",
        "TOBEORNOTTOBEORTOBEORNOT",
        "\x80\x15\t\xe4\")<\xa4N'\x95 PH4.\v\a\x84\xc0@",
        nil,
    },
    -- This example comes from https://en.wikipedia.org/wiki/Graphics_Interchange_Format.
    { -- 10
        "gif;LSB;8",
        "\x28\xff\xff\xff\x28\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff",
        "\x00\x51\xfc\x1b\x28\x70\xa0\xc1\x83\x01\x01",
        nil,
    },
    -- This example comes from http://compgroups.net/comp.lang.ruby/Decompressing-LZW-compression-from-PDF-file
    {
        "pdf;MSB;8",
        "-----A---B",
        "\x80\x0b\x60\x50\x22\x0c\x0c\x85\x01",
        nil,
    },
}
-- LuaFormatter on

local function internals_test()

    -- write return test
    local w = newWriter({}, LSB, 8)
    local n = w:Write("asdf")
    assert(n == 4)
    local s1 = char(unpack(w.w))
    w:Reset()
    n = w:Write("asdf")
    local s2 = char(unpack(w.w))
    assert(n == 4)
    assert(s1 == s2)

    -- from-to test
    local s = "123TOBEORNOTTOBEORTOBEORNOT123"
    w:Reset(nil, LSB, 7)
    n = w:Write(s, 1 + 3, #s - 3)
    assert(n == #s - 3 - 3)
    do
        local got = w:Close("string")
        local compressed = "\x80TOBEORNOT\x82\x84\x86\x8b\x85\x87\x89\x81"
        if got ~= compressed then
            error(format("FAIL mismatch result for '%s'\n -> got: %s\n expect: %s", "from-to;LSB;7",
                hexify(got), hexify(compressed)))
        end
    end

    -- Writer test
    for i = 1, #TEST_DATA do
        local tt = TEST_DATA[i]
        local desc, raw, compressed, err = tt[1], tt[2], tt[3], tt[4]
        local lw, order, tag = split(desc)
        w:Reset(nil, order, lw)
        w:Write(raw)
        local got = w:Close("string")
        if got ~= compressed then
            error(format("FAIL(Writer#%d) mismatch result for '%s'\ngot:    %s\nexpect: %s",
                i, tt[1], hexify(got), hexify(compressed)))
        elseif false then
            print("[OK]", "Writer test", tag)
        end
    end

    -- Reader test
    local r = Reader("")
    for i = 1, #TEST_DATA do
        local tt = TEST_DATA[i]
        local desc, raw, compressed, err = tt[1], tt[2], tt[3], tt[4]
        local lw, order, tag = split(desc)
        r:Reset(compressed, nil, nil, order, lw)
        while not r:Read() do
            -- read chanks
        end
        local got = r:Close("string")
        assert(got ~= nil)
        if got ~= raw then
            error(format("FAIL(Reader#%d) mismatch result for '%s'\ngot:    %s\nexpect: %s",
                i, tt[1], hexify(got), hexify(compressed)))
        elseif false then
            print("[OK]", i, "Reader test", tag)
        end
    end
end

local function compress_test()
    for i = 1, #TEST_DATA do
        local tt = TEST_DATA[i]
        local desc, raw = tt[1], tt[2]
        local c = m.compress(raw)
        local u = m.decompress(c)
        assert(raw == u, desc)
        c = m.compress(raw, nil, nil, MSB)
        u = m.decompress(c)
        assert(raw == u, desc)
    end
end

local function chank_test()
    local raws = {}
    for i=1, #TEST_DATA do
        raws[i] = TEST_DATA[i][2]
    end
    local data = concat(raws)
    local w = Writer()
    for i=1, #raws do
        w:Write(raws[i])
    end
    local c = w:Close("str")
    local r = Reader(c)
    while not r:Read() do end
    local u = r:Close("str")
    assert(u == data)
end

-----------------------------
-- Export lzw
-----------------------------
-- lazy initialization
local _comp_writer = nil
local _comp_reader = nil

m.Writer = Writer
m.Reader = Reader


m.compress = function(str, from, to, msb)
    if str == m then
        error("compress is a static method, consider remove ':'")
    end
    from = from or 1
    to = to or #str
    local n = to - from + 1
    -- NB. this is the result of Core instruction count limitation (~10K). lzw
    -- can split compression to several frames, but it's impractical for
    -- working with Storage. Meybe I will change my mind about it.
    if CORE_ENV and to - from > 4090 then
        -- warn(format("compress: string too long: %.4gKB, max: 4KB", (to - from)/1000))
        return str, n, n, 1.0
    end
    if not _comp_writer then
        _comp_writer = Writer()
    end
    local writer = _comp_writer
    if not msb then
        writer:Reset(nil, LSB, 8)
    else
        writer:Reset(nil, MSB, 8)
    end
    emit_header(writer)
    n = writer:Write(str, from, to)
    local z = writer:Close(true)
    -- 3 digits after dot
    local ratio = n / #z + 0.0005
    ratio = ratio - ratio % .001
    return z, n, #z, ratio
end

-- if str do not begin with 'lzw\0x00' or 'lzw\0x80' then pass it throw.
m.decompress = function(lzw_string)
    if lzw_string == m then
        error("decompress is a static method, consider remove ':'")
    end
    local order = check_header(lzw_string)
    -- i.e. string not compressed at all, pass verbatim
    if not order then
        return lzw_string
    end
    assert(order == LSB or order == MSB, "lzw - unknown byte order")
    if not _comp_reader then
        _comp_reader = Reader("")
    end
    local reader = _comp_reader
    -- skip 3 byte of header (but not 'clear')
    if order == LSB then
        reader:Reset(lzw_string, 4, nil, LSB, 8)
    else
        reader:Reset(lzw_string, 4, nil, MSB, 8)
    end
    local ok, result = pcall(function()
        while not reader:Read() do
            if CORE_ENV then
                wait() -- 4KB per frame
            end
        end
        return reader:Close(true)
    end)
    if not ok then
        error(result)
    end
    return result
end

local function data64K_test()
    local data = {}
    for _ = 1, (1 << 16) / 8 do
        data[#data + 1] = spack("d", rand())
    end
    data = concat(data)
    local c, x, y, z = m.compress(data)
    -- print("compress 64K", x, y, z)
    local u = m.decompress(c)
    assert(u == data)
end

local function data4K_test()
    local data = {}
    for _ = 1, (1 << 12) / 8 - 6 do
        data[#data + 1] = spack("d", rand())
    end
    data = concat(data)
    local t1 = os.clock()
    local c, x, y, z = m.compress(data)
    local t2 = os.clock()
    -- print("compress 4K", x, y, z)
    local u = m.decompress(c)
    local t3 = os.clock()
    -- print("4K compress", t2 - t1, "decompress", t3 - t2)
    assert(u == data)
end

local function run_test()
	internals_test()
	compress_test()
	data64K_test()
	data4K_test()
	chank_test()
    print("lzw -- ok")
end

if not CORE_ENV then
    run_test()
else
    -- Task.Spawn(run_test, 1)
end

return m
