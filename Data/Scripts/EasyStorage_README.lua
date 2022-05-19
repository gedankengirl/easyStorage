--[[
                        ______
     ___ ___ ____ __ __/ __/ /____  _______ ____ ____
    / -_) _ `(_-</ // /\ \/ __/ _ \/ __/ _ `/ _ `/ -_)
    \__/\_,_/___/\_, /___/\__/\___/_/  \_,_/\_, /\__/
               /___/                      /___/
    easyStorage by zoonior

    Copyright (c) 2021 Andrew Zhilin (https://github.com/zoon).
    Core user: zoonior https://www.coregames.com/user/eec0239c0d644f5bb9f59779307edb17

    == easyStorage
    * very fast: less then 10ms for 32K data, you can update storage very often if needed
      with no impact on performance
    * convenient: only 4 methods that mimic Core Storage API
    * automatically uses lzw compression when suitable

    == To use easyStorage
    1.  Drag the @easyStorage template and place it on the very top of your
        scene hierarchy.
    2.  Load the easyStorageAPI module:
        ```lua
            _ENV.require = _G.import or require
            local easyStorageAPI = require("easyStorageAPI")
        ```
        But you can use the vanilla Core 'require':
        ```lua
            local easyStorageAPI = require("895FB503000AFB3E:easyStorageAPI")
        ```
    3.  If you plan to use Shared Storage, fill in the custom property SHARED_STORAGE_KEY
        at the hierarchy root object of @easyStorage instance
        with the NetReference shared storage that you are going to use in your project.
    4.  For Storage use methods (server only):
        `easyStorageAPI.GetStorageData(player)`
        `easyStorageAPI.SetStorageData(player, data)`
    5.  For Shared Storage use methods (server only):
        easyStorageAPI.GetSharedPlayerData(player)
        easyStorageAPI.SetSharedPlayerData(player, data)
    (!) Note that GetStorageData and GetSharedPlayerData return two values: data and data version.
        The current data version can be set as a custom property STORAGE_VERSION
        and SHARED_STORAGE_VERSION at the hierarchy root object of @easyStorage instance.
    6.  For additional convenience there are 2 additional methods:
        `easyStorageAPI.CompressData(data, toBase64)`
        `easyStorageAPI:DecompressData(compressedData, fromBase64)`
        You can use them to compress/decompress multiple lua and Core types (or nested tables of them):
             * All lua types (including numerics: uint64, double etc.)
             * Vector2/3/4
             * Color
             * Rotation
             * Player
             * CoreObjectReference
    (!) Current limitation of CompressData is that it will only use lzw compression on the objects
        that are less than 4KB after binary serialization. The main reason for that is not the
        performance, but Core's limitation on Lua instruction count.
        But even without compression, serialization format is very compact (internally it uses
        MessagePack https://msgpack.org/).
]]

--[[ == easyStorage Runnable Example Block
-- ------------------------------------------------------------------------------------------------
-- To run it:
-- 1.  Drag the @easyStorage template and place it on the very top of your
--    scene hierarchy.
-- 2. Uncomment this block (add the 3-rd dash: `---[[ == easyStorage Runnable ...)`.
-- ------------------------------------------------------------------------------------------------
_ENV.require = _G.import or require
local easyStorageAPI = require("easyStorageAPI")

print("\n%%% easyStorage Runnable Example %%%\n")

------------
-- DATA
------------
local DataExample = require(script:GetCustomProperty("DataExample"))
-- the save file from Farmers Market ^_^
-- CyberChief view of this data: https://tinyurl.com/rs8am5bd
local FM_DATA_TABLE = easyStorageAPI.DecompressData(DataExample.FM_DATA, true)


local function OnPlayerJoined(player)
    local data = easyStorageAPI.GetPlayerData(player)
    if not data[easyStorageAPI.VERSION_KEY] then
        -- player has no saved state
        local ok = easyStorageAPI.SetPlayerData(player, FM_DATA_TABLE)
        assert(ok == StorageResultCode.SUCCESS)
    end

    Task.Wait(1)

    local saved_data, version = easyStorageAPI.GetPlayerData(player)
    assert(version == easyStorageAPI.STORAGE_VERSION, version)
    for k, v in pairs(saved_data.inventory) do
        -- do something with data like print(k, v) ^_^
    end

    Task.Wait(1)

    --------------------
    -- Size comparison
    --------------------
    -- Storage size as-is:
    local storage_size = Storage.SizeOfData(FM_DATA_TABLE)
    local compressed_base64 = easyStorageAPI.CompressData(FM_DATA_TABLE, true)
    -- Storage size after compression and base64 encoding:
    local compressed_storage_size = Storage.SizeOfData({compressed_base64})
    print("Storage size of the Farmers Market save file BEFORE compression:", storage_size)
    print("Storage size of the Farmers Market save file AFTER compression:", compressed_storage_size)
    -- output:
    -- Storage size of the Farmers Market save file BEFORE compression	6112
    -- Storage size of the Farmers Market save file AFTER compression	2692

    -- NB. 6112 vs 2692 (R=2.27) is a very good result for real-world data

end

Game.playerJoinedEvent:Connect(OnPlayerJoined)
--]] -- end of runnable example block
