local weather_history = {}
local config_ref

function weather_history.init(config)
    config_ref = config
    config_ref.settings.weather_history = config_ref.settings.weather_history or {}
end

function weather_history.observe(zone_id, weather_id)
    if not config_ref then return false end
    local info = windower.ffxi.get_info()
    if not info or info.logged_in == false then return false end
    zone_id = tonumber(zone_id) or (info and tonumber(info.zone))
    weather_id = tonumber(weather_id) or (info and tonumber(info.weather))
    if not zone_id or zone_id <= 0 or not weather_id then return false end

    local history = config_ref.settings.weather_history
    history[zone_id] = history[zone_id] or {}
    if history[zone_id][weather_id] then return false end
    history[zone_id][weather_id] = true
    config_ref.save()
    return true
end

function weather_history.seen(zone_id, weather_id)
    if not config_ref then return false end
    local zones = config_ref.settings.weather_history or {}
    return zones[tonumber(zone_id)] and zones[tonumber(zone_id)][tonumber(weather_id)] == true
end

function weather_history.current_zone_weathers()
    if not config_ref then return {} end
    local info = windower.ffxi.get_info()
    local zone_id = info and tonumber(info.zone)
    return zone_id and (config_ref.settings.weather_history[zone_id] or {}) or {}
end

return weather_history
