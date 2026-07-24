local completion_history = require('services/completion_history')

local prerequisites = {}
local global_ids_by_database = setmetatable({}, {__mode='k'})

local function has_other_active_objective(state, prerequisite_id)
    for _, active in ipairs(state and state.active_roes or {}) do
        local id = tonumber(active and active.id)
        if id and id ~= prerequisite_id then return true end
    end
    return false
end

function prerequisites.global_id(database, state)
    if type(database) ~= 'table' then return nil end
    local ids = global_ids_by_database[database]
    if not ids then
        ids = {}
        for id, objective in pairs(database) do
            if type(id) == 'number' and type(objective) == 'table'
                and objective.prq_all == false then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        global_ids_by_database[database] = ids
    end
    for _, id in ipairs(ids) do
        if not completion_history.is_complete(id) then
            -- ID 1 unlocks the entire RoE system. Some characters do not
            -- receive its completion bit, although accepting any later
            -- objective proves that it has already been completed.
            if id ~= 1 or not has_other_active_objective(state, id) then
                return id
            end
        end
    end
end

function prerequisites.subcategory_id(categories, category_id, subcategory_id)
    local category = categories and categories[tonumber(category_id)]
    local subcategory = category and category.sub_cat
        and category.sub_cat[tonumber(subcategory_id)]
    local id = subcategory and tonumber(subcategory.prq_id)
    if id and not completion_history.is_complete(id) then return id end
end

function prerequisites.objective_id(categories, objective)
    if type(objective) ~= 'table' then return nil end
    return prerequisites.subcategory_id(
        categories, objective.category_id, objective.sub_category_id)
end

return prerequisites
