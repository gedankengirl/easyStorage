--[[
    API holder for easyStorage
    TODO: Concurrent Player Data
    Copyright (c) 2021 Andrew Zhilin (https://github.com/zoon).
    Core user: zoonior https://www.coregames.com/user/eec0239c0d644f5bb9f59779307edb17

    easyStorageAPI is a module, to import it:
    ```
    _ENV.require = _G.import or require
    local easyStorageAPI = require "easyStorageAPI"
    ```
    = Server and Client API:

        ---@param data any
        ---@param toBase64 boolean -- optional (false)
        ---@return string
        * easyStorageAPI.CompressData(data, toBase64)

        ---@param compressedData string -- output of CompressData
        ---@param fromBase64 boolean    -- mandatory, if data was compressed with toBase64=true
        ---@return any
        * easyStorageAPI:DecompressData(compressedData, fromBase64)

    = Server only API:
        ---@param player Player
        ---@return table   -- player data
        ---@return integer -- version of data in storage
        * easyStorageAPI.GetPlayerData(player)

        ---@param player Player
        ---@param data table
        ---@return StorageResultCode
        * easyStorageAPI.SetPlayerData(player, data)

        ---@param player Player
        ---@return table   -- player data
        ---@return integer -- version of data in storage
        * easyStorageAPI.GetSharedPlayerData(player)

        ---@param player Player
        ---@param data table
        ---@return StorageResultCode
        * easyStorageAPI.SetSharedPlayerData(player, data)
]]
_ENV.require = _G.import or require
local mp = require("MessagePack")
local b64 = require("QuickBase64")
local lzw = require("LibLZW")

local format = string.format
local assert, error, type = assert, error, type

local SERVER = Environment.IsServer()

local ROOT = World.FindObjectByName("@easyStorage")
assert(ROOT, "error: can't find object by name: '@easyStorage'")

local STORAGE_VERSION = ROOT:GetCustomProperty("STORAGE_VERSION")
local SHARED_STORAGE_VERSION = ROOT:GetCustomProperty("SHARED_STORAGE_VERSION")
local SHARED_STORAGE_KEY = ROOT:GetCustomProperty("SHARED_STORAGE_KEY")
if SHARED_STORAGE_KEY then
    assert(SHARED_STORAGE_VERSION > 0, "SHARED_STORAGE_VERSION must be > 0")
end

---------------------------------------
-- easyStorage API module
---------------------------------------
local easyStorageAPI = {type="easyStorageAPI"}
easyStorageAPI.__index = easyStorageAPI

------------------------------
-- Constants
------------------------------
-- NB. keys should be resonably short
local COMPRESSED_DATA_KEY = "@data"
local VERSION_KEY = "@data_ver"
local MAX_STORAGE_DATA_SIZE = 32768 -- ref: https://docs.coregames.com/api/storage/

-- export
easyStorageAPI.VERSION_KEY = VERSION_KEY
easyStorageAPI.STORAGE_VERSION = STORAGE_VERSION
easyStorageAPI.SHARED_STORAGE_VERSION = SHARED_STORAGE_VERSION


local function compress(data)
    local ok, compressed_data = pcall(function()
        local bin = mp.encode(data)
        local z = lzw.compress(bin)
        return b64.encode(z)
    end)
    if not ok then
        error("compression error: " .. compressed_data, 3)
    end
    return compressed_data
end

local function decompress(compressed_data)
    local ok, data = pcall(function()
        local z = b64.decode(compressed_data)
        local bin = lzw.decompress(z)
        return mp.decode(bin)
    end)
    if not ok then
        error("decompression error: " .. data, 3)
    end
    return data
end

local epock

---@param data any
---@param toBase64 boolean -- optional (false)
---@return string
function easyStorageAPI.CompressData(data, toBase64)
    local ok, compressed_data = pcall(function()
        local bin = mp.encode(data)
        local z = lzw.compress(bin)
        return not toBase64 and z or b64.encode(z)
    end)
    if not ok then
        error("compression error: " .. compressed_data, 2)
    end
    return compressed_data
end

---@param compressedData string -- output of CompressData
---@param fromBase64 boolean    -- mandatory, if data was compressed with toBase64=true
---@return any
function easyStorageAPI.DecompressData(compressedData, fromBase64)
    assert(type(compressedData) == "string", type(compressedData))
    local ok, data = pcall(function()
        local z = not fromBase64 and compressedData or b64.decode(compressedData)
        local bin = lzw.decompress(z)
        return mp.decode(bin)
    end)
    if not ok then
        error("decompression error: " .. data, 2)
    end
    return data
end

if SERVER then
    ---@param player Player
    ---@return table   -- player data
    ---@return integer -- version of data in storage
    function easyStorageAPI.GetPlayerData(player)
        local all_data = Storage.GetPlayerData(player)
        local compressed_data = all_data[COMPRESSED_DATA_KEY]
        -- data not set yet...
        if not compressed_data then
            return {}, STORAGE_VERSION
        end
        local data = decompress(compressed_data)
        local version = data[VERSION_KEY]
        if version ~= STORAGE_VERSION then
            warn(format("data in Storage is not of the current version: %d, data version is: %d", STORAGE_VERSION, version))
        end
        data[VERSION_KEY] = nil
        return data, version
    end

    ---@param player Player
    ---@param data table
    ---@return StorageResultCode
    function easyStorageAPI.SetPlayerData(player, data)
        assert(player and type(player) == "userdata" and Object.IsA(player, "Player"), "first arg must be a player")
        assert(type(data) == "table", "second arg must be a table")
        data[VERSION_KEY] = STORAGE_VERSION
        local compressed_data = compress(data)
        local all_data = {[COMPRESSED_DATA_KEY] = compressed_data}
        local storage_size = Storage.SizeOfData(all_data)
        if storage_size > MAX_STORAGE_DATA_SIZE then
            warn("storage size of data too big: %d (max: %d)", storage_size, MAX_STORAGE_DATA_SIZE)
            return StorageResultCode.EXCEEDED_SIZE_LIMIT
        end
        return Storage.SetPlayerData(player, all_data), storage_size
    end

    ---@param player Player
    ---@return table   -- player data
    ---@return integer -- version of data in storage
    function easyStorageAPI.GetSharedPlayerData(player)
        if not SHARED_STORAGE_KEY then
            warn("Custom Property: @easyData:SHARED_STORAGE_KEY (NetReference) was not set")
            return nil
        end
        local all_data = Storage.GetSharedPlayerData(SHARED_STORAGE_KEY, player)
        local compressed_data = all_data[COMPRESSED_DATA_KEY]
        -- data not set yet...
        if not compressed_data then
             return {}, SHARED_STORAGE_VERSION
        end
        local data = decompress(compressed_data)
        local version = data[VERSION_KEY]
        if version ~= SHARED_STORAGE_VERSION then
            warn(format("data in Shared Storage is not of the current version: %d, data version is: %d", STORAGE_VERSION, version))
        end
        data[VERSION_KEY] = nil
        return data, version
    end

    ---@param player Player
    ---@param data table
    ---@return StorageResultCode
    function easyStorageAPI.SetSharedPlayerData(player, data)
        if not SHARED_STORAGE_KEY then
            warn("Custom Property: @easyData:SHARED_STORAGE_KEY (NetReference) was not set")
            return StorageResultCode.STORAGE_DISABLED
        end
        assert(player and type(player) == "userdata" and Object.IsA("Player"), "first arg must be a player")
        assert(type(data) == "table", "second arg ust be a table")
        data[VERSION_KEY] = STORAGE_VERSION
        local compressed_data = compress
        local all_data = {[COMPRESSED_DATA_KEY] = compressed_data}
        local storage_size = Storage.SizeOfData(all_data)
        if storage_size > MAX_STORAGE_DATA_SIZE then
            warn("storage size of data too big: %d (max: %d)", storage_size, MAX_STORAGE_DATA_SIZE)
            return StorageResultCode.EXCEEDED_SIZE_LIMIT
        end
        return Storage.SetSharedPlayerData(SHARED_STORAGE_KEY, player, data)
    end
end

-- local spack = string.pack
-- local rand = math.random
-- local concat = table.concat
-- local function data64K_test()
--     local data = {}
--     for _ = 1, (1 << 16) / 8 do
--         data[#data + 1] = spack("d", rand())
--     end
--     data = concat(data)
--     local c = compress({data})
--     local u = decompress(c)
--     assert(u[1] == data)
-- end
-- local t1 = os.clock()
-- data64K_test()
-- local t2 = os.clock()
-- print("data64K_test", t2 - t1)


return easyStorageAPI
