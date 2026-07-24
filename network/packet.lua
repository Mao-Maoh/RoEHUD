-- Windowerのパケット環境を初期化する。移植元と同様にdata:unpack()より先に読み込む。
require('packets')
local packets = require('packets')
local db = require('database/Objectives')
local resources = require('resources')
local zone_recommendation = require('recommendations/zone')
local completion_history = require('services/completion_history')
local unities = require('database/unities')
local packet = {}
local state_ref, update_main_ref, update_popup_ref
local sound_ref, config_ref, item_hover_ref
local last_sequence = 0

local function update_unity(data)
    local ok, parsed = pcall(packets.parse, 'incoming', data)
    if not ok then return false end
    local unity_id = parsed and tonumber(parsed['Unity ID'])
    if unity_id == nil or unity_id == state_ref.current_unity_id then return false end
    state_ref.current_unity_id = unity_id
    state_ref.current_unity = unities[unity_id]
    return true
end

function packet.init(state, update_main, update_popup, sound, config, item_hover)
    state_ref = state
    update_main_ref = update_main
    update_popup_ref = update_popup
    sound_ref = sound
    config_ref = config
    item_hover_ref = item_hover
end

local function has_zone_recommendations()
    return zone_recommendation.has_any(db)
end

local function active_roe(id, roes)
    for _, roe in ipairs(roes or state_ref.active_roes) do
        if roe.id == id then return roe end
    end
    return nil
end

local function resolve_title(id)
    local objective = db[id]
    local lang = config_ref and config_ref.settings.lang or 'ja'
    local title = objective and objective[lang]
    if not title or title == '' then
        title = (lang == 'ja' and '不明な目標' or 'Unknown Objective') .. ' (ID: ' .. id .. ')'
    end
    return tostring(title):gsub('{item:(%d+)}', function(item_id)
        local item = resources.items and resources.items[tonumber(item_id)]
        return item and (item[lang] or item.en or item.ja) or ('{item:' .. item_id .. '}')
    end)
end

local function check_pending_action(new_roes)
    local pending = state_ref.pending_objective_action
    if not pending then return end

    local is_active = active_roe(pending.id, new_roes) ~= nil
    if sound_ref then
        sound_ref.debug(string.format(
            'server check: action=%s id=%d active_in_0x111=%s progress=%s/%s',
            pending.action, pending.id, tostring(is_active),
            tostring(pending.progress), tostring(pending.maximum)))
    end
    local succeeded = (pending.action == 'accept' and is_active)
        or (pending.action == 'cancel' and not is_active)
    if not succeeded then
        if sound_ref then sound_ref.debug('server check: no state change yet; pending retained') end
        return
    end

    if pending.action == 'accept' then
        if sound_ref then
            sound_ref.debug('accept acknowledged; test sound is disabled for normal operation')
        end
    else
        local lang = config_ref and config_ref.settings.lang or 'ja'
        local message
        local title_color = string.char(0x1E, 8)
        local color_reset = string.char(0x1E, 1)
        if lang == 'ja' then
            message = string.format('RoEHUD：進行度%s/%sの『%s』を破棄しました。',
                tostring(pending.progress), tostring(pending.maximum),
                title_color .. pending.title .. color_reset)
            message = windower.to_shift_jis(message)
        else
            message = string.format('[RoEHUD] Canceled "%s" at progress %s/%s.',
                title_color .. pending.title .. color_reset,
                tostring(pending.progress), tostring(pending.maximum))
        end
        windower.add_to_chat(121, message)
    end
    state_ref.pending_objective_action = nil
end

function packet.handle_outgoing(id, data, modified, injected)
    if not injected and data and #data >= 4 then
        last_sequence = data:byte(3) + data:byte(4) * 256
    end
end

function packet.send_objective(action, objective_id)
    objective_id = tonumber(objective_id)
    if (action ~= 'accept' and action ~= 'cancel') or not objective_id then
        return false
    end

    local sequence_low = bit.band(last_sequence, 0xFF)
    local sequence_high = bit.band(bit.rshift(last_sequence, 8), 0xFF)
    local id_low = bit.band(objective_id, 0xFF)
    local id_high = bit.band(bit.rshift(objective_id, 8), 0xFF)
    local packet_low = action == 'cancel' and 0x0D or 0x0C
    local raw = string.char(packet_low, 0x05, sequence_low, sequence_high,
        id_low, id_high, 0x00, 0x00)
    local outgoing = packets.parse('outgoing', raw)
    if not outgoing then
        if sound_ref then sound_ref.debug('packet parse failed: action=' .. action .. ' id=' .. objective_id) end
        return false
    end
    if sound_ref then
        sound_ref.debug(string.format('packet ready: action=%s id=%d sequence=%d packet=0x05%02X',
            action, objective_id, last_sequence, packet_low))
    end
    packets.inject(outgoing)
    local current = active_roe(objective_id)
    local objective = db[objective_id]
    state_ref.pending_objective_action = {
        action = action,
        id = objective_id,
        progress = current and (current.prog or 0) or 0,
        maximum = objective and objective.times or '?',
        title = resolve_title(objective_id),
    }
    if sound_ref then
        sound_ref.debug(string.format('pending stored: action=%s id=%d progress=%s/%s title=%s',
            action, objective_id, tostring(state_ref.pending_objective_action.progress),
            tostring(state_ref.pending_objective_action.maximum),
            tostring(state_ref.pending_objective_action.title)))
    end
    return true
end

function packet.handle_incoming(id, data)
    if id == 0x061 and update_unity(data) then
        update_main_ref()
        update_popup_ref()
    end

    if id == 0x01C or id == 0x020 then
        if sound_ref and sound_ref.refresh_inventory() then
            update_main_ref()
        end
    end

    if id == 0x00B then
        state_ref.reset_ui()
        state_ref.open_recommend_after_zone = true
        state_ref.is_hidden = true
        if item_hover_ref then item_hover_ref.hide() end
        update_main_ref()
        update_popup_ref()
    elseif id == 0x112 then
        if completion_history.handle_packet(data) then
            update_main_ref()
            update_popup_ref()
        end
    elseif id == 0x111 then
        local new_roes = {}
        if #data >= 259 then
            local limit_id = (data:unpack('H', 257) or 0) % 4096
            if limit_id ~= 0 then
                local limit_prog = math.floor(((data:unpack('H', 258) or 0) / 16) % 1048576)
                table.insert(new_roes, { id = limit_id, prog = limit_prog, is_limited = true })
            end
        end

        for j = 1, 30 do
            local id_offset = j * 4 + 1
            local prog_offset = j * 4 + 2
            if #data >= prog_offset + 3 then
                local roe_id = (data:unpack('H', id_offset) or 0) % 4096
                if roe_id ~= 0 then
                    local prog = math.floor(((data:unpack('I', prog_offset) or 0) / 16) % 1048576)
                    table.insert(new_roes, { id = roe_id, prog = prog, is_limited = false })
                end
            end
        end

        if sound_ref then sound_ref.check_progress(new_roes) end
        check_pending_action(new_roes)
        state_ref.active_roes = new_roes
        state_ref.is_hidden = false
        if state_ref.open_recommend_after_zone then
            state_ref.open_recommend_after_zone = false
            if has_zone_recommendations() then
                state_ref.is_menu_open = true
                state_ref.menu_layer = 'recommend_zone'
                state_ref.menu_page = 1
            end
        end
        update_main_ref()
        update_popup_ref()
    end
end

return packet
