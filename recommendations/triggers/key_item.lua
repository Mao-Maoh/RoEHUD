local resources = require('resources')

local key_item = {
    key = 'trigger_key_item',
}

local function is_owned(owned, id)
    if type(owned) ~= 'table' then return false end
    if owned[id] == true or owned[id] == 1 then return true end
    for key, value in pairs(owned) do
        if tonumber(key) == id and value ~= false and value ~= nil and value ~= 0 then
            return true
        end
        if tonumber(value) == id then return true end
    end
    return false
end

function key_item.matches(value)
    local id = tonumber(value)
    if not id or not resources.key_items or not resources.key_items[id] then
        return false
    end
    local ok, owned = pcall(windower.ffxi.get_key_items)
    return ok and is_owned(owned, id) or false
end

return key_item
