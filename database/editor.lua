local files = require('files')
local resources = require('resources')
local db = require('database/Objectives')

local editor = {}
local config_ref, update_main_ref, update_popup_ref
local pending

local function chat(message, color)
    windower.add_to_chat(color or 207, '[RoEHUD DB] ' .. tostring(message))
end

local function serialize(value)
    local value_type = type(value)
    if value_type == 'string' then return string.format('%q', value) end
    if value_type == 'number' or value_type == 'boolean' then return tostring(value) end
    if value_type ~= 'table' then return 'nil' end
    local parts = {}
    for index, child in ipairs(value) do parts[#parts + 1] = serialize(child) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function display(value)
    if value == nil then return 'nil' end
    return serialize(value)
end

local function parse_table(text)
    local chunk = loadstring('return ' .. text)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= 'table' then return nil end
    for key, child in pairs(value) do
        if type(key) ~= 'number' or (type(child) ~= 'number'
            and type(child) ~= 'string' and type(child) ~= 'boolean') then
            return nil
        end
    end
    return value
end

local function parse_generic(text)
    if text == 'true' then return true end
    if text == 'false' then return false end
    local number = tonumber(text)
    if number ~= nil then return number end
    if text:match('^%s*{.*}%s*$') then return parse_table(text) end
    return text
end

local function resolve_item(text)
    local numeric_id = tonumber(text)
    if numeric_id then
        return resources.items and resources.items[numeric_id] and numeric_id or nil,
            resources.items and resources.items[numeric_id] and nil or 'unknown item ID'
    end

    local function trimmed(value)
        return type(value) == 'string' and value:match('^%s*(.-)%s*$') or value
    end
    local candidates, seen = {}, {}
    local function add_candidate(value)
        value = trimmed(value)
        if type(value) == 'string' and value ~= '' and not seen[value] then
            candidates[#candidates + 1], seen[value] = value, true
        end
    end
    add_candidate(text)
    if type(windower.from_shift_jis) == 'function' then
        local ok, converted = pcall(windower.from_shift_jis, text)
        if ok then add_candidate(converted) end
    end

    local lang = config_ref and config_ref.settings.lang or 'ja'
    local matches = {}
    for id, item in pairs(resources.items or {}) do
        if type(id) == 'number' and type(item) == 'table' then
            local name = item[lang]
            local matched = false
            for _, candidate in ipairs(candidates) do
                if name == candidate then matched = true; break end
            end
            if not matched and type(windower.to_shift_jis) == 'function' and type(name) == 'string' then
                local ok, encoded = pcall(windower.to_shift_jis, name)
                matched = ok and encoded == text
            end
            if matched then matches[#matches + 1] = id end
        end
    end
    if #matches == 1 then return matches[1] end
    if #matches == 0 then return nil, 'item name was not found by exact match' end
    return nil, 'multiple items have the same name; use an item ID'
end

local function current_target_name()
    local mob = windower.ffxi.get_mob_by_target('t')
    return mob and mob.name ~= '' and mob.name or nil
end

local function find_entry(source, id)
    local marker_start, marker_end = source:find('%[' .. tostring(id) .. '%]%s*=%s*{')
    if not marker_start then return nil end
    local brace_start = source:find('{', marker_start, true)
    local depth, quote, escaped = 0, nil, false
    for index = brace_start, #source do
        local char = source:sub(index, index)
        if quote then
            if escaped then escaped = false
            elseif char == '\\' then escaped = true
            elseif char == quote then quote = nil end
        elseif char == '"' or char == "'" then
            quote = char
        elseif char == '{' then
            depth = depth + 1
        elseif char == '}' then
            depth = depth - 1
            if depth == 0 then return brace_start, index end
        end
    end
    return nil
end

local function top_level_segments(inner)
    local result, start_at = {}, 1
    local depth, quote, escaped = 0, nil, false
    for index = 1, #inner do
        local char = inner:sub(index, index)
        if quote then
            if escaped then escaped = false
            elseif char == '\\' then escaped = true
            elseif char == quote then quote = nil end
        elseif char == '"' or char == "'" then
            quote = char
        elseif char == '{' or char == '(' or char == '[' then
            depth = depth + 1
        elseif char == '}' or char == ')' or char == ']' then
            depth = math.max(0, depth - 1)
        elseif char == ',' and depth == 0 then
            result[#result + 1] = {first=start_at, last=index - 1}
            start_at = index + 1
        end
    end
    result[#result + 1] = {first=start_at, last=#inner}
    return result
end

local function update_entry(entry, key, serialized_value)
    local inner = entry:sub(2, -2)
    for _, segment in ipairs(top_level_segments(inner)) do
        local text = inner:sub(segment.first, segment.last)
        local found_key = text:match('^%s*([%a_][%w_]*)%s*=')
        if found_key == key then
            local whitespace = text:match('^(%s*)') or ''
            local replacement = whitespace .. key .. '=' .. serialized_value
            return '{' .. inner:sub(1, segment.first - 1) .. replacement
                .. inner:sub(segment.last + 1) .. '}'
        end
    end

    local trailing = inner:match('(%s*)$') or ''
    local body = inner:sub(1, #inner - #trailing)
    local separator = body:match('%S') and ',' or ''
    return '{' .. body .. separator .. key .. '=' .. serialized_value .. trailing .. '}'
end

local function write_pending(change)
    local source_file = files.new('database/Objectives.lua')
    local source = source_file:read()
    if type(source) ~= 'string' or source == '' then return false, 'Objectives.lua could not be read' end
    local first, last = find_entry(source, change.id)
    if not first then return false, 'objective entry was not found in source' end

    local new_entry = update_entry(source:sub(first, last), change.key, change.serialized)
    local new_source = source:sub(1, first - 1) .. new_entry .. source:sub(last + 1)
    local temp_file = files.new('database/Objectives.lua.tmp')
    temp_file:write(new_source)
    local chunk, compile_error = loadfile(windower.addon_path .. 'database/Objectives.lua.tmp')
    if not chunk then return false, 'validation failed: ' .. tostring(compile_error) end

    files.new('database/Objectives.lua.bak'):write(source)
    source_file:write(new_source)
    os.remove(windower.addon_path .. 'database/Objectives.lua.tmp')
    return true
end

function editor.init(config, update_main, update_popup)
    config_ref, update_main_ref, update_popup_ref = config, update_main, update_popup
end

function editor.prepare(id_text, key, values)
    local id = tonumber(id_text)
    if not id or type(db[id]) ~= 'table' then chat('unknown objective ID: ' .. tostring(id_text), 167); return end
    if type(key) ~= 'string' or not key:match('^[%a_][%w_]*$') then chat('invalid key', 167); return end
    local raw = table.concat(values or {}, ' ')
    local value, parse_error

    if key == 'target' and raw == '' then
        value = current_target_name()
        if not value then chat('no target is selected', 167); return end
    elseif key == 'target_item' then
        if raw == '' then chat('target_item requires an item ID or exact name', 167); return end
        value, parse_error = resolve_item(raw)
        if not value then chat(parse_error, 167); return end
    else
        if raw == '' then chat('a value is required', 167); return end
        value = parse_generic(raw)
        if value == nil then chat('value could not be parsed', 167); return end
    end

    pending = {id=id, key=key, value=value, serialized=serialize(value), old=db[id][key]}
    chat(string.format('ID %d: %s = %s -> %s', id, key, display(pending.old), display(value)))
    chat('apply with //rh db confirm, or cancel with //rh db cancel')
end

function editor.confirm()
    if not pending then chat('no pending change', 167); return end
    local change = pending
    local ok, write_error = write_pending(change)
    if not ok then chat(write_error, 167); return end
    db[change.id][change.key] = change.value
    pending = nil
    if update_main_ref then update_main_ref() end
    if update_popup_ref then update_popup_ref() end
    chat(string.format('saved ID %d %s; backup: database/Objectives.lua.bak', change.id, change.key), 158)
end

function editor.cancel()
    if pending then chat('pending change cancelled') end
    pending = nil
end

return editor
