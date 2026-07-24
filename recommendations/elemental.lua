local resources = require('resources')

local elemental = {
    key = 'elemental',
    label = {ja='属性オススメ', en='Elemental Recommendations'},
}
local active_source
local day_only_ids = {}

local function contains(values, wanted)
    if type(values) ~= 'table' then return false end
    for _, value in ipairs(values) do
        if tonumber(value) == wanted then return true end
    end
    return false
end

local function matches_day(value, current_id)
    if value == nil or current_id == nil then return false end
    if tonumber(value) == current_id then return true end
    local day = resources.days and resources.days[current_id]
    return type(value) == 'string' and day
        and (value == day.en or value == day.ja)
end

function elemental.get_ids(database)
    local info = windower.ffxi.get_info()
    local weather_id = info and tonumber(info.weather)
    local day_id = info and tonumber(info.day)
    local weather_matches, day_matches = {}, {}
    local weather_seen = {}

    for id, objective in pairs(database or {}) do
        if type(id) == 'number' and type(objective) == 'table'
            and type(objective.weathers) == 'table' then
            if weather_id and contains(objective.weathers, weather_id) then
                weather_matches[#weather_matches + 1] = id
                weather_seen[id] = true
            end
            if matches_day(objective.day, day_id) then
                day_matches[#day_matches + 1] = id
            end
        end
    end

    active_source = #weather_matches > 0 and 'weather' or 'day'
    day_only_ids = {}
    local result, added = {}, {}
    for _, id in ipairs(weather_matches) do
        if not added[id] then result[#result + 1], added[id] = id, true end
    end
    for _, id in ipairs(day_matches) do
        if active_source == 'weather' and not weather_seen[id] then day_only_ids[id] = true end
        if not added[id] then result[#result + 1], added[id] = id, true end
    end
    table.sort(result)
    return result
end

function elemental.decorate_label(id, label, lang)
    if active_source == 'weather' and day_only_ids[id] then
        local note = lang == 'ja'
            and '（天候ナシで曜日属性適応）'
            or ' (Day element applies without weather)'
        return label .. note
    end
    return label
end

function elemental.heading(lang)
    local info = windower.ffxi.get_info()
    local weather = active_source == 'weather'
        and resources.weather and info and resources.weather[info.weather]
    if weather then
        return weather[lang] or weather.en or weather.ja or elemental.label[lang]
    end
    local day = resources.days and info and resources.days[info.day]
    return day and (day[lang] or day.en or day.ja) or elemental.label[lang] or elemental.label.en
end

return elemental
