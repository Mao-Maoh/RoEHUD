local history = require('services/weather_history')
local elemental = require('recommendations/elemental')

local candidates = {
    key = 'weather_candidates',
    label = {ja='このエリアの天候候補', en='Possible Zone Weather'},
}

local function has_seen_weather(values, seen)
    if type(values) ~= 'table' then return false end
    for _, value in ipairs(values) do
        if seen[tonumber(value)] then return true end
    end
    return false
end

function candidates.get_ids(database)
    local seen = history.current_zone_weathers()
    local active = {}
    for _, id in ipairs(elemental.get_ids(database)) do active[id] = true end
    local result = {}
    for id, objective in pairs(database or {}) do
        if type(id) == 'number' and type(objective) == 'table'
            and not active[id] and has_seen_weather(objective.weathers, seen) then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

function candidates.heading(lang)
    return candidates.label[lang] or candidates.label.en
end

return candidates
