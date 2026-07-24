local region_resolver = require('database/region_resolver')
local completion_history = require('services/completion_history')
local categories = require('database/category')
local prerequisites = require('services/prerequisites')
local objective_filter = require('services/objective_filter')
local state = require('state')
local species_zone = require('recommendations/species_zone')

local trigger_modules = {
    require('recommendations/triggers/key_item'),
}

local zone = {}
local triggers = {}
for _, trigger in ipairs(trigger_modules) do
    triggers[trigger.key] = trigger
end

local function has_challenge_key(objective)
    for key in pairs(objective or {}) do
        if type(key) == 'string' and key:match('^challenge_') then return true end
    end
    return false
end

local function matches_objective_zone(objective, zone_id)
    if tonumber(objective.zone_id) == zone_id then return true end
    if type(objective.zones_id) == 'table' then
        for _, candidate in ipairs(objective.zones_id) do
            if tonumber(candidate) == zone_id then return true end
        end
    end
    local objective_region = tonumber(objective.region_id)
    if objective_region ~= nil
        and region_resolver.get_region_id(zone_id) == objective_region then
        return true
    end
    return false
end

local nation_zones = {
    [0] = {[230]=true, [231]=true, [232]=true, [233]=true},
    [1] = {[234]=true, [235]=true, [236]=true, [237]=true},
    [2] = {[238]=true, [239]=true, [240]=true, [241]=true, [242]=true},
}

local nation_names = {
    sandoria = 0, ["san d'oria"] = 0,
    bastok = 1, windurst = 2,
}

local function player_nation_id()
    local player = windower.ffxi.get_player()
    local nation = player and player.nation
    if type(nation) == 'number' then return nation end
    if type(nation) == 'string' then
        return nation_names[nation:lower():gsub('[%s_%-]+$', '')]
    end
end

local function matches_nation_home(objective, zone_id)
    if objective.nation_home ~= true then return false end
    local zones = nation_zones[player_nation_id()]
    return zones and zones[zone_id] == true or false
end

local function is_monthly(objective)
    return type(objective) == 'table'
        and ((type(objective.ja) == 'string' and objective.ja:find('%(M%)') ~= nil)
            or (type(objective.en) == 'string' and objective.en:find('%(M%)') ~= nil))
end

local function monthly_available(id, objective)
    if not is_monthly(objective) then return true end
    local completed = completion_history.is_current_complete(id)
    return completed ~= nil and completed == false
end

local function has_trigger_zone(objective)
    return objective.trigger_zone ~= nil or type(objective.trigger_zones) == 'table'
end

local function matches_trigger_zone(objective, zone_id)
    if tonumber(objective.trigger_zone) == zone_id then return true end
    if type(objective.trigger_zones) == 'table' then
        for _, candidate in ipairs(objective.trigger_zones) do
            if tonumber(candidate) == zone_id then return true end
        end
    end
    return false
end

local function matches_triggers(objective)
    for key, value in pairs(objective) do
        if type(key) == 'string' and key:match('^trigger_')
            and key ~= 'trigger_zone' and key ~= 'trigger_zones' then
            local trigger = triggers[key]
            -- Unknown trigger conditions must not accidentally expose an objective.
            if not trigger or not trigger.matches(value, objective) then return false end
        end
    end
    return true
end

function zone.get_ids(database)
    local global_id = prerequisites.global_id(database, state)
    if global_id then return {global_id} end
    local info = windower.ffxi.get_info()
    local zone_id = info and tonumber(info.zone)
    local result = {}
    if not zone_id then return result end
    local species_facts = species_zone.facts(zone_id)

    for id, objective in pairs(database or {}) do
        if type(id) == 'number' and type(objective) == 'table'
            and not has_challenge_key(objective)
            and objective_filter.matches_unity(objective, state) then
            local objective_zone_match = matches_objective_zone(objective, zone_id)
                or matches_nation_home(objective, zone_id)
                or species_zone.matches(objective, species_facts)
            local entrance_zone_match = matches_trigger_zone(objective, zone_id)
            local uses_entrance_zone = has_trigger_zone(objective)
            local trigger_match = true
            if entrance_zone_match or (objective_zone_match and not uses_entrance_zone) then
                trigger_match = matches_triggers(objective)
            end

            -- In the actual objective zone, entrance items may already be consumed.
            -- Legacy zone_id + trigger_* records keep their existing gated behavior.
            local matches_inside = objective_zone_match
                and (uses_entrance_zone or trigger_match)
            local matches_entrance = entrance_zone_match and trigger_match
            if matches_inside or matches_entrance then
                local prerequisite_id = prerequisites.objective_id(categories, objective)
                if prerequisite_id then
                    local seen = false
                    for _, existing in ipairs(result) do
                        if existing == prerequisite_id then seen = true; break end
                    end
                    if not seen then result[#result + 1] = prerequisite_id end
                elseif monthly_available(id, objective) then
                    result[#result + 1] = id
                end
            end
        end
    end
    table.sort(result)
    return result
end

function zone.has_any(database)
    return #zone.get_ids(database) > 0
end

return zone
