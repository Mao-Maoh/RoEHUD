local filter = {}

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if tonumber(value) == wanted then return true end
    end
    return false
end

function filter.matches_unity(objective, state)
    if type(objective) ~= 'table' then return false end
    if objective.unity_id == nil and type(objective.unity_ids) ~= 'table' then
        return true
    end

    local current = tonumber(state and state.current_unity_id)
    if not current or current == 0 then return false end
    if objective.unity_id ~= nil then
        return tonumber(objective.unity_id) == current
    end
    return contains(objective.unity_ids, current)
end

return filter
