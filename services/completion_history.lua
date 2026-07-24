-- Records of Eminence completion-packet decoding was informed by ROE.
-- Copyright (c) 2017 Cair. BSD-3-Clause licensed.
-- See THIRD_PARTY_NOTICES.md for the complete notice.

local files = require('files')

local history = {}
local FORMAT_VERSION = 2
local state_ref
local character_name
local received_pages = {}
local session_pages = {}

local function safe_name(value)
    return tostring(value or ''):gsub('[^%w_%-]', '_')
end

local function relative_path(name)
    return 'data/completion/' .. safe_name(name) .. '.lua'
end

local function current_name()
    local player = windower.ffxi.get_player()
    return player and player.name and player.name ~= '' and player.name or nil
end

local function sorted_numeric_keys(values)
    local result = {}
    for key in pairs(values or {}) do
        if type(key) == 'number' then result[#result + 1] = key end
    end
    table.sort(result)
    return result
end

local function serialize(name)
    local lines = {'return {', '    format=' .. tostring(FORMAT_VERSION) .. ',',
        '    character=' .. string.format('%q', name) .. ',', '    pages={'}
    for _, page in ipairs(sorted_numeric_keys(received_pages)) do
        if received_pages[page] then lines[#lines + 1] = string.format('        [%d]=true,', page) end
    end
    lines[#lines + 1] = '    },'
    lines[#lines + 1] = '    completed={'
    for _, id in ipairs(sorted_numeric_keys(state_ref.completed_roes)) do
        if state_ref.completed_roes[id] then lines[#lines + 1] = string.format('        [%d]=true,', id) end
    end
    lines[#lines + 1] = '    },'
    lines[#lines + 1] = '}'
    return table.concat(lines, '\n') .. '\n'
end

local function ensure_directory()
    if windower.create_dir then
        pcall(windower.create_dir, windower.addon_path .. 'data')
        pcall(windower.create_dir, windower.addon_path .. 'data/completion')
    end
end

local function save()
    if not character_name or not state_ref then return false end
    ensure_directory()
    files.new(relative_path(character_name)):write(serialize(character_name))
    return true
end

function history.init(state)
    state_ref = state
    state_ref.completed_roes = state_ref.completed_roes or {}
end

function history.load()
    if not state_ref then return false end
    local name = current_name()
    if not name then return false end
    if character_name == name then return true end

    character_name = name
    state_ref.completed_roes = {}
    received_pages = {}
    session_pages = {}
    local path = windower.addon_path .. relative_path(name)
    local ok, saved = pcall(dofile, path)
    if ok and type(saved) == 'table' then
        local migrate = tonumber(saved.format) ~= FORMAT_VERSION
        for id, value in pairs(saved.completed or {}) do
            id = tonumber(id)
            if id and value == true then
                if migrate then
                    local page_start = math.floor(id / 1024) * 1024
                    local local_id = id - page_start
                    if local_id >= 8 then
                        state_ref.completed_roes[id - 8] = true
                    end
                else
                    state_ref.completed_roes[id] = true
                end
            end
        end
        if not migrate then
            for page, value in pairs(saved.pages or {}) do
                page = tonumber(page)
                if page and value == true then received_pages[page] = true end
            end
        else
            save()
        end
    end
    return true
end

function history.handle_packet(data)
    if not state_ref or not data or #data < 134 then return false end
    history.load()
    if not character_name then return false end

    local page = tonumber(data:unpack('H', 133))
    if not page then return false end
    local bits = T{data:unpack(('b1'):rep(1024), 5)}
    local first_id = page * 1024
    for index = 1, 1024 do
        local id = first_id + index - 1
        if bits[index] == 1 then
            state_ref.completed_roes[id] = true
        else
            state_ref.completed_roes[id] = nil
        end
    end
    received_pages[page] = true
    session_pages[page] = true
    save()
    return true
end

function history.is_complete(id)
    return state_ref and state_ref.completed_roes[tonumber(id)] == true or false
end

function history.has_current_page(id)
    id = tonumber(id)
    if not id then return false end
    return session_pages[math.floor(id / 1024)] == true
end

function history.is_current_complete(id)
    if not history.has_current_page(id) then return nil end
    return history.is_complete(id)
end

function history.reset_session()
    character_name = nil
    received_pages = {}
    session_pages = {}
    if state_ref then state_ref.completed_roes = {} end
end

return history
