--[[
    _G.import: replacing Core `require` which can take the filename or MUID as
    an argument. This is convenient since you no longer need to do custom
    properties or hardcode MUID strings to export a module.

    If you make `require` an alias of `_G.import` and export modules by name,
    then they will continue to function correctly in the absence of Core - for
    example, you can run tests in vanilla Lua 5.3, and not just in the editor.

    ```lua
    -- begining of the script
    _ENV.require = _G.import or require

    ```
    (!) Server-only modules with conteiner in Server Context, will load
    *after* Default modules. Consider some form of lazy import.

    TODO: server-context modules loaded out of order
    WORKAROUND: no server-context modules, require them by muid

    TODO: FAQ
    - How to make "Module Container" by yourself.
    - How to prohibit an export of server-only modules in client context.
    - Where to place module containers in hierarchy.
    - Can I store templates in Module container and get them by name.
]]

local DEBUG = false

local format = string.format
local require = require
local pcall = pcall

local function protected_require(id)
    local ok, result = pcall(require, id)
    if not ok then
        error(result, 3)
    else
        return result
    end
end

-- This script must always be a child of Deafult and Client contexts of the root container.
local CONTAINER = script.parent.parent
local CONTEXT = CONTAINER.isServerOnly and "SCTX:" or ""
local SERVER_OR_CLIENT = CONTEXT .. (Environment.IsClient() and "Client" or "Server")

local MUID_DB_G_KEY = "<~ Muid Db ~>"

_G[MUID_DB_G_KEY] = _G[MUID_DB_G_KEY] or {}
local MUID_DB = _G[MUID_DB_G_KEY]

for name, muid in pairs(CONTAINER:GetCustomProperties()) do
    if MUID_DB[name] then
        error(string.format("ERROR: name duplication: `%s` in container `%s`", name, CONTAINER.name), 2)
    end
    if DEBUG then
        print(format("~~~> [%s] add module: %s", SERVER_OR_CLIENT, name))
    end
    MUID_DB[name] = muid
end

-- get MUID by name
local function get_muid(name)
    local muid = MUID_DB[name]
    if muid then
        return muid
    else
        error(format("[%s]:ERROR: unknown muid for: `%s`", SERVER_OR_CLIENT, name), 2)
    end
end

-- register :: muid [, module_name] ^-> nil
local function register(muid, name)
    local id, script_name = CoreString.Split(muid, ':')
    if not muid and tonumber(id, 16) then
        error(format("not a muid: '%s'", muid), 2)
    end
    name = name or script_name
    if not name then
        error(format("no file name was provided"))
    end
    MUID_DB[name] = muid
end

-- Replacement for Core's `require`, works with MUID, module name and AssetReference
-- like vanilla Lua.
local function import(id)
    local muid = MUID_DB[id]
    if not muid then
        -- does it looks like MUID?
        if type(id) == "string" and tonumber(CoreString.Split(id, ':'), 16) then
            return protected_require(id)
        else
            error(format("[%s]:ERROR: unknown module: '%s'", SERVER_OR_CLIENT, id), 2)
        end
    end
    local t1 = os.clock()
    local module = protected_require(muid)
    local dt = os.clock() - t1
    if dt > 0.025 then
        warn(format("[%s]: INFO: initial module loading time exceeds the 25 ms theshold: [%s]: %d ms.",
             SERVER_OR_CLIENT, id, dt*1000//1))
    end
    return module
end

-- export to global
_G.get_muid = get_muid
_G.import = import
_G.register = register
