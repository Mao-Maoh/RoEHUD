local resources = require('resources')

local jobs = {
    key = 'jobs',
    label = {ja='現在のジョブ', en='Current Jobs'},
}

local function contains(values, expected)
    if type(values) ~= 'table' or type(expected) ~= 'number' then return false end
    for _, value in ipairs(values) do
        if type(value) == 'number' and value == expected then return true end
    end
    return false
end

local function current_jobs()
    local player = windower.ffxi.get_player()
    if not player then return nil, nil end
    return player.main_job_id, player.sub_job_id
end

function jobs.get_ids(database)
    local main_id, sub_id = current_jobs()
    local result = {}
    if not main_id then return result end
    for id, objective in pairs(database or {}) do
        if type(id) == 'number' and type(objective) == 'table' then
            -- Insert once per objective even when both main and support match.
            if contains(objective.jobs, main_id) or contains(objective.sjobs, sub_id) then
                result[#result + 1] = id
            end
        end
    end
    table.sort(result)
    return result
end

local function short_name(id)
    local job = id and resources.jobs and resources.jobs[id]
    return job and (job.ens or job.en or job.ja) or nil
end

function jobs.heading(lang)
    local main_id, sub_id = current_jobs()
    local main_name = short_name(main_id)
    local sub_name = short_name(sub_id)
    if main_name and sub_name then return main_name .. ' / ' .. sub_name end
    if main_name then return main_name end
    return lang == 'ja' and '不明なジョブ' or 'Unknown Job'
end

return jobs
