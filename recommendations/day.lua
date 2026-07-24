local resources = require('resources')

local day = {
    key = 'day',
    label = {ja='現在の曜日', en='Current Day'},
}

local function current_resource()
    local info = windower.ffxi.get_info()
    local id = info and info.day
    return id, id ~= nil and resources.days and resources.days[id] or nil
end

local function matches(value, current_id, current_day)
    if value == nil or current_day == nil then return false end
    if type(value) == 'number' then return value == current_id end
    if type(value) ~= 'string' then return false end
    return value == tostring(current_id)
        or value == current_day.en
        or value == current_day.ja
end

function day.get_ids(database)
    local current_id, current_day = current_resource()
    local result = {}
    if not current_day then return result end
    for id, objective in pairs(database or {}) do
        if type(id) == 'number' and type(objective) == 'table'
            and type(objective.weathers) ~= 'table'
            and matches(objective.day, current_id, current_day) then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

function day.heading(lang)
    local id, current_day = current_resource()
    if not current_day then return lang == 'ja' and '不明な曜日' or 'Unknown Day' end
    return current_day[lang] or current_day.en or current_day.ja or tostring(id)
end

return day
