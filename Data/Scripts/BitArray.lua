-- fixed size compact, serializable bitarray
-- NB. as 11.10.2021 - breaking change: 0-based indices
local BitArray = {type = "BitArray"}
BitArray.__index = BitArray

local function nbytes(size)
    local r, n = size % 8, size // 8
    return r == 0 and n or n + 1, r
end

function BitArray.new(size, default)
    size = size or 32
    local n, used = nbytes(size)
    local _size = size
    -- hide _size in closure
    local self = {size = function() return _size end}

    local fill = default and 0xFF or 0x00
    for i = 1, n do
        self[i] = fill
    end
    -- set unused bits to zero for correct equality compare
    self[#self] = self[#self] & ~(-1 << used)
    return setmetatable(self, BitArray)
end
BitArray.New = BitArray.new

-- bitarray.eq :: self, other -> bool
local rawequal = rawequal
function BitArray:eq(other)
    if rawequal(self, other) then
        return true
    end
    if other.type ~= BitArray.type then
        return false
    end
    local size = self.size()
    if size ~= other.size() then
        return false
    end
    local n, _ = nbytes(size)
    for i = 1, n - 1 do
        if self[i] ~= other[i] then
            return false
        end
    end
    return self[n] == other[n]
end

-- `==` overload
BitArray.__eq = BitArray.eq

-- @ bitarray.set :: self, i, bool ^-> self
function BitArray:set(i, val)
    assert(i >= 0 and i < self.size())
    local idx, bit = i // 8 + 1, i % 8
    local byte = self[idx]
    byte = val and byte | (1 << bit) or byte & ~(1 << bit)
    self[idx] = byte
    return self
end

-- @ bitarray.get :: self, i -> bool
function BitArray:get(i)
    assert(i >= 0 and i < self.size())
    local idx, bit = i // 8 + 1, i % 8
    return self[idx] & (1 << bit) ~= 0
end

-- @ bitarray.find_and_swap :: self[, bool=false] ^-> i | nil
-- finds first asked boolean value, swap it and return it's index
function BitArray:find_and_swap(bool)
    bool = bool and true or false
    for i = 0, self.size() - 1 do
        if bool == self:get(i) then
            self:set(i, not bool)
            return i
        end
    end
end

-- NB. default always false(0)
function BitArray:expand(new_size)
    assert(new_size > self.size(), "new size should be greater than current size")
    local out = BitArray.new(new_size)
    for i=1, #self do
        out[i] = self[i]
    end
    return out
end

-- @ bitarray.swap :: self, i ^-> i
-- swap boolean at index i
function BitArray:swap(i)
    assert(i >= 0 and i < self.size())
    local val = self:get(i)
    self:set(i, not val)
    return i
end

-- NOTE: 0-based index array
local BIT_COUNT_BYTE = {[0]=
    0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    4, 5, 5, 6, 5, 6, 6, 7, 5, 6, 6, 7, 6, 7, 7, 8,
}

function BitArray:popcount()
    local count = 0
    for i = 1, #self do
        count = count + BIT_COUNT_BYTE[self[i]]
    end
    return count
end

-------------------------------------------------------------------------------
local function _bitarray_test()
    local ba1 = BitArray.new(9, true)
    assert(ba1.size() == 9)
    assert(ba1:eq(ba1))
    assert(ba1 == ba1)
    ba1:set(1, nil)
    assert(not ba1:get(1))
    assert(ba1:get(2) and ba1:get(8))

    local ba2 = BitArray.new(7)
    assert(ba2.size() == 7)
    assert(ba2:find_and_swap() == 0 and ba2:get(0))
    ba2:swap(0)
    assert(not ba2:get(0))
    ba2:set(1, true):set(6, true)
    for i = 0, 6 do
        if i == 1 or i == 6 then
            assert(ba2:get(i))
        else
            assert(not ba2:get(i))
        end
    end

    -- still equal with different fills
    local ba71 = BitArray.new(7, true)
    local ba72 = BitArray.new(7, false)
    for i = 0, ba72.size() - 1 do
        ba72:set(i, true)
    end
    assert(ba71:eq(ba72))
    ba71:set(2, nil)
    ba72:set(2, nil)
    assert(ba71:eq(ba72))

    -- expand
    local ba_9 = BitArray.new(9, true)
    local ba_11 = ba_9:expand(11)
    assert(ba_11:size() == 11)
    assert(ba_11:popcount() == 9)
    assert(ba_11:popcount() == ba_9:popcount())

    for i=0, ba_9.size() - 1 do
        assert(ba_9[i] == ba_11[i])
    end
    for i = ba_9.size() - 1, ba_11:size() - 1 do
        assert(not ba_11[i])
    end
    --
    print("bitarray -- ok")

end

_bitarray_test()

return BitArray
