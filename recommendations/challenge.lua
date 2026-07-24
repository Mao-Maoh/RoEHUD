local challenge = {
    key = 'challenge',
    label = {ja='チャレンジオススメ', en='Challenge Recommendations'},
}

local function matches_zone(objective, zone_id)
    return type(objective.challenge_zone) == 'number'
        and objective.challenge_zone == zone_id
end

function challenge.has_key(objective)
    if type(objective) ~= 'table' then return false end
    for key in pairs(objective) do
        if type(key) == 'string' and key:match('^challenge_') then return true end
    end
    return false
end

function challenge.get_ids(database)
    local info = windower.ffxi.get_info()
    local zone_id = info and info.zone
    local result = {}
    if type(zone_id) ~= 'number' then return result end
    for id, objective in pairs(database or {}) do
        if type(id) == 'number' and type(objective) == 'table'
            and matches_zone(objective, zone_id) then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

function challenge.heading(lang)
    return challenge.label[lang] or challenge.label.en
end

return challenge
