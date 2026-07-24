local files = require('files')
local db = require('database/Objectives')

local sound = {}
local state_ref, config_ref

local function settings()
    return config_ref and config_ref.settings.sound or {}
end

local function debug_log(message)
    if settings().debug ~= false then
        windower.add_to_chat(207, '[RoEHUD sound] ' .. tostring(message))
    end
end

sound.debug = debug_log

local function play(key)
    local cfg = settings()
    debug_log('play requested: key=' .. tostring(key))
    if cfg.enabled == false then
        debug_log('stopped: sound.enabled=false')
        return false
    end

    local filename = cfg[key]
    debug_log('configured file=' .. tostring(filename))
    if type(filename) ~= 'string' or filename == '' then
        debug_log('stopped: filename is empty')
        return false
    end

    local relative_path = 'sounds/' .. filename
    local full_path = windower.addon_path .. relative_path
    local exists = files.new(relative_path):exists()
    debug_log('file check: relative=' .. relative_path .. ' exists=' .. tostring(exists))
    debug_log('full path=' .. full_path)
    if exists then
        local ok, result = pcall(windower.play_sound, full_path)
        debug_log('play_sound returned: ok=' .. tostring(ok) .. ' result=' .. tostring(result))
        if not ok then
            windower.add_to_chat(167, '[RoEHUD] play_sound error: ' .. tostring(result))
        end
        return ok
    end
    windower.add_to_chat(167, '[RoEHUD] Sound file not found: ' .. relative_path)
    return false
end

sound.play = play

function sound.init(state, config)
    state_ref = state
    config_ref = config
    sound.refresh_inventory()
end

function sound.refresh_inventory()
    if not state_ref then return false end
    local bag = windower.ffxi.get_bag_info(0)
    local was_full = state_ref.is_inventory_full
    state_ref.is_inventory_full = bag ~= nil and bag.max ~= nil and bag.count ~= nil
        and bag.max - bag.count <= 0
    return was_full ~= state_ref.is_inventory_full
end

function sound.check_progress(new_roes)
    if not state_ref then return end

    sound.refresh_inventory()
    local previous = state_ref.previous_roes or {}

    for _, roe in ipairs(new_roes) do
        local old = previous[roe.id]
        local objective = db[roe.id]
        local maximum = objective and tonumber(objective.times)

        if old and maximum and maximum > 0 then
            if old.prog < maximum and roe.prog >= maximum then
                debug_log(string.format('completion detected: id=%d old=%s new=%s max=%s bag_full=%s',
                    roe.id, tostring(old.prog), tostring(roe.prog), tostring(maximum),
                    tostring(state_ref.is_inventory_full)))
                play('complete')
                roe.full_notified = false
            elseif roe.prog == maximum and old.prog == maximum then
                if not old.full_notified then
                    debug_log(string.format('held-at-maximum detected: id=%d progress=%s',
                        roe.id, tostring(roe.prog)))
                    play('full')
                    roe.full_notified = true
                else
                    roe.full_notified = true
                end
            elseif objective.rpt == true and old.prog >= maximum and roe.prog == 0 then
                debug_log(string.format('repeat detected: id=%d old=%s new=0 max=%s',
                    roe.id, tostring(old.prog), tostring(maximum)))
                play('repeatable')
            end
        end
    end

    state_ref.previous_roes = {}
    for _, roe in ipairs(new_roes) do
        state_ref.previous_roes[roe.id] = {
            prog = roe.prog or 0,
            full_notified = roe.full_notified or false,
        }
    end
end

return sound
