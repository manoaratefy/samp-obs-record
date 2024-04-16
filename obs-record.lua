script_name("OBS Recording Toggler")
script_authors("Neutrinou")
script_version("0.0.1")

require "moonloader"
require "sampfuncs"
local sampev = require "lib.samp.events"

local base64 = require "base64"
local inicfg = require "inicfg"
local sha = require "sha2"
local uuid = require "uuid"
local websocket = require "websocket"

local client = websocket.client.sync{
    timeout = 2
}

--require 'deps' {
--    "compat53"
--}

local config

local config_dir_path = getWorkingDirectory() .. "\\config\\"
if not doesDirectoryExist(config_dir_path) then createDirectory(config_dir_path) end
local config_file_path = config_dir_path .. "obsrecord.ini"
config_dir_path = nil

local function saveConfig()
    if not inicfg.save(config, config_file_path) then
        sampAddChatMessage("{E02222}OBS Record: {FFFFFF}Unable to write configuration file.", 0xFFFFFF)
    end
end

local function loadConfig()
    if doesFileExist(config_file_path) then
        config = inicfg.load(nil, config_file_path)

        if not type(config.OBS.hostname) == "string" then config.OBS.hostname = "" end
        if not type(config.OBS.port) == "string" then config.OBS.port = "" end
        if not type(config.OBS.password) == "string" then config.OBS.password = "" end

        saveConfig()
    else
        local new_config = io.open(config_file_path, "w")
        new_config:close()
        new_config = nil

        config = {
            OBS = {
                hostname = "",
                port = "",
                password = ""
            }
        }
        save()
    end
end

local function obsConnect()

    local ok,err = client:connect("ws://" .. config.OBS.hostname .. ":" .. config.OBS.port)
    if not ok then
        sampAddChatMessage("Unable to connect to websocket: " .. err, 0xFFFFFF)
    end

    local message, opcode, close_was_clean, close_code, close_reason = client:receive()
    if not message then
        sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
        if close_reason then
            sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
        end
        return
    end

    if opcode ~= 1 then
        sampAddChatMessage("OBS Websocket returned unexpected opcode: " .. opcode, 0xFFFFFF)
        client:close(4001, "lost interest")
    end

    local success, data = pcall(decodeJson, message)
    if not success then
        sampAddChatMessage("OBS Websocket returned unexpected message (non JSON format)", 0xFFFFFF)
        client:close(4001, "lost interest")
    end

    if data['d']['authentication'] ~= nil then
        -- OBS requires authentication

        local authentication_string = config.OBS.password .. data['d']['authentication']['salt']
        authentication_string = sha.hex_to_bin(sha.sha256(authentication_string))
        authentication_string = base64.encode(authentication_string)
        authentication_string = authentication_string .. data['d']['authentication']['challenge']
        authentication_string = sha.hex_to_bin(sha.sha256(authentication_string))
        authentication_string = base64.encode(authentication_string)

        local success, close_was_clean, close_code, close_reason = client:send(encodeJson({
            op = 1,
            d = {
                rpcVersion = 1,
                authentication = authentication_string
            }
        }))

        if not success then
            sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
            if close_reason then
                sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
            end
            return
        end

        local message, opcode, close_was_clean, close_code, close_reason = client:receive()
        if not message then
            sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
            if close_reason then
                sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
            end
            return
        end

        if opcode ~= 1 then
            sampAddChatMessage("OBS Websocket returned unexpected opcode during auth:", 0xE02222)
            sampAddChatMessage(opcode, 0xFFFFFF)
            client:close(4001, "lost interest")
        end
    end
end

local function cmd_toggle()
    sampAddChatMessage("Toggling OBS recording status.", 0xFFFFFF)

    obsConnect()
    local req_id = uuid()
    local success, close_was_clean, close_code, close_reason = client:send(encodeJson({
        op = 6,
        d = {
            requestType = "ToggleRecord",
            requestId = req_id,
        }
    }))

    if not success then
        sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
        if close_reason then
            sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
        end
        return
    end

    local message, opcode, close_was_clean, close_code, close_reason = client:receive()
    if not message then
        sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
        if close_reason then
            sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
        end
        return
    end

    local success, data = pcall(decodeJson, message)
    if not success then
        sampAddChatMessage("OBS Websocket returned unexpected message (non JSON format)", 0xFFFFFF)
        client:close(4001, "lost interest")
    end

    client:close(4001, "lost interest")

    if data['d']['responseData']['outputActive'] then
        sampAddChatMessage("OBS is now recording", 0x27AE60)
    else
        sampAddChatMessage("OBS stopped recording", 0xE74C3C)
    end
end

local function cmd_status()
    obsConnect()
    local req_id = uuid()
    local success, close_was_clean, close_code, close_reason = client:send(encodeJson({
        op = 6,
        d = {
            requestType = "GetRecordStatus",
            requestId = req_id,
        }
    }))

    if not success then
        sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
        if close_reason then
            sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
        end
        return
    end

    local message, opcode, close_was_clean, close_code, close_reason = client:receive()
    if not message then
        sampAddChatMessage("OBS Websocket connection closed", 0xE02222)
        if close_reason then
            sampAddChatMessage("Error happened: " .. close_reason, 0xFFFFFF)
        end
        return
    end

    local success, data = pcall(decodeJson, message)
    if not success then
        sampAddChatMessage("OBS Websocket returned unexpected message (non JSON format)", 0xFFFFFF)
        client:close(4001, "lost interest")
    end

    client:close(4001, "lost interest")

    if data['d']['responseData']['outputActive'] then
        sampAddChatMessage("OBS is now recording", 0x27AE60)
    else
        sampAddChatMessage("OBS is not recording", 0xE74C3C)
    end
end

local function cmd_help()
    sampAddChatMessage("OBS Record commands:", 0xFF7675)
    sampAddChatMessage("/obsrec - Toggle OBS recording status", 0xFFFFFF)
    sampAddChatMessage("/obsrecstatus - Show current OBS recording status", 0xFFFFFF)
    
end

function main()
    loadConfig()

    repeat wait(50) until isSampAvailable()
    repeat wait(50) until string.find(sampGetCurrentServerName(), "Horizon Roleplay")

    sampAddChatMessage("OBS Record Mod - /obsrechelp to check all available commands.", 0xFFFFFF)

    sampRegisterChatCommand("obsrec", cmd_toggle)
    sampRegisterChatCommand("obsrecstatus", cmd_status)
    sampRegisterChatCommand("obsrechelp", cmd_help)
end