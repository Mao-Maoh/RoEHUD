local loader = {}

local function report_error(message)
    windower.add_to_chat(167, '[RoEHUD] overview load error: ' .. tostring(message))
end

local function normalize_overview(entry, key)
    if type(entry[key]) == 'string' then
        entry[key] = entry[key]:gsub('_NL_', '\n')
    end
end

function loader.load()
    local path = windower.addon_path .. 'database/overviews.lua'
    local chunk, compile_error = loadfile(path)
    if not chunk then
        report_error(compile_error or 'file not found')
        return {}
    end

    local environment = setmetatable({}, { __index = _G })
    setfenv(chunk, environment)

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        report_error(ok and 'data is not a table' or data)
        return {}
    end

    for _, entry in pairs(data) do
        if type(entry) == 'table' then
            normalize_overview(entry, 'overview_ja')
            normalize_overview(entry, 'overview_en')
        end
    end

    return data
end

return loader.load()
