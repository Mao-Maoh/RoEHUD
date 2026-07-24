local data = require('database/species')

local species_zone = {}

local function contains(values, wanted)
    if type(values) ~= 'table' then
        return tonumber(values) == wanted
    end
    for _, value in ipairs(values) do
        if tonumber(value) == wanted then return true end
    end
    return false
end

local function intersects(values, available)
    if type(values) ~= 'table' then
        local value = tonumber(values)
        return value ~= nil and available[value] == true
    end
    for _, value in ipairs(values) do
        value = tonumber(value)
        if value and available[value] then return true end
    end
    return false
end

local function type_id_for_species(species_id)
    for type_id, type_data in pairs(data.types or {}) do
        local range = type_data and type_data.range
        local first = range and tonumber(range[1])
        local last = range and tonumber(range[2])
        if first and last and species_id >= first and species_id <= last then
            return tonumber(type_id)
        end
    end
end

function species_zone.facts(zone_id)
    zone_id = tonumber(zone_id)
    local facts = {
        species_ids = {},
        monster_types_ids = {},
        crystal_ids = {},
    }
    if not zone_id then return facts end

    for species_id, species in pairs(data.species or {}) do
        species_id = tonumber(species_id)
        if species_id and contains(species and species.zones, zone_id) then
            facts.species_ids[species_id] = true
            local type_id = type_id_for_species(species_id)
            if type_id then facts.monster_types_ids[type_id] = true end

            local element_id = tonumber(species.crystal)
            if element_id and element_id >= 0 and element_id <= 7 then
                facts.crystal_ids[4096 + element_id] = true
            end
        end
    end
    return facts
end

function species_zone.matches(objective, facts)
    if type(objective) ~= 'table' or type(facts) ~= 'table' then return false end
    if objective.species_ids ~= nil
        and intersects(objective.species_ids, facts.species_ids or {}) then
        return true
    end
    if objective.monster_types_ids ~= nil
        and intersects(objective.monster_types_ids, facts.monster_types_ids or {}) then
        return true
    end
    if objective.target_crystal ~= nil
        and intersects(objective.target_crystal, facts.crystal_ids or {}) then
        return true
    end
    return false
end

return species_zone
