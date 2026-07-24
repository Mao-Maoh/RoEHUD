local command = {}
local db_editor = require('database/editor')
local state_ref, config_ref, update_main_ref, update_popup_ref, send_objective_ref, sound_ref, start_setup_ref

function command.init(state, config, update_main, update_popup, send_objective, sound, start_setup)
    state_ref = state
    config_ref = config
    update_main_ref = update_main
    update_popup_ref = update_popup
    send_objective_ref = send_objective
    sound_ref = sound
    start_setup_ref = start_setup
    db_editor.init(config, update_main, update_popup)
end

function command.handle(cmd, ...)
    local args = {...}
    if not cmd then return end

    cmd = cmd:lower()
    if cmd == 'debug' then
        state_ref.debug_mouse = not state_ref.debug_mouse
        windower.add_to_chat(207, '[RoEHUD] mouse debug: ' .. (state_ref.debug_mouse and 'ON' or 'OFF'))
    elseif cmd == 'menu' then
        if state_ref.setup_active then
            update_popup_ref()
            return
        end
        state_ref.is_menu_open = not state_ref.is_menu_open
        state_ref.menu_layer = state_ref.is_menu_open and 'main' or 'none'
        state_ref.popup_hovered_index = nil
        state_ref.confirming_cancel_id = nil
        update_popup_ref()
    elseif cmd == 'lang' then
        local next_lang = args[1] and args[1]:lower()
            or (config_ref.settings.lang == 'ja' and 'en' or 'ja')
        if next_lang ~= 'ja' and next_lang ~= 'en' then return end
        config_ref.settings.lang = next_lang
        config_ref.save()
        update_main_ref()
        update_popup_ref()
    elseif cmd == 'setup' then
        if start_setup_ref then start_setup_ref(false) end
    elseif cmd == 'mouse' then
        local value = args[1] and tostring(args[1]):lower() or ''
        if value == 'reset' then
            config_ref.settings.mouse.scale_x = 1
            config_ref.settings.mouse.scale_y = 1
            config_ref.settings.mouse.offset_x = 0
            config_ref.settings.mouse.offset_y = 0
        elseif value == 'debug' then
            state_ref.debug_mouse = not state_ref.debug_mouse
            windower.add_to_chat(207, '[RoEHUD] mouse coordinate debug: '
                .. (state_ref.debug_mouse and 'ON' or 'OFF'))
            return
        else
            local percent = tonumber(value)
            if not percent then
                windower.add_to_chat(167, '[RoEHUD] usage: //rh mouse 109 -3')
                return
            end
            local scale = percent > 10 and percent / 100 or percent
            if scale < 0.5 or scale > 3 then return end
            config_ref.settings.mouse.scale_x = 1
            config_ref.settings.mouse.scale_y = scale
            if tonumber(args[2]) then config_ref.settings.mouse.offset_y = tonumber(args[2]) end
        end
        config_ref.save()
        windower.add_to_chat(207, string.format(
            '[RoEHUD] mouse correction: scale=(%d%%,%d%%) offset=(%d,%d)',
            math.floor((config_ref.settings.mouse.scale_x or 1) * 100 + 0.5),
            math.floor((config_ref.settings.mouse.scale_y or 1) * 100 + 0.5),
            config_ref.settings.mouse.offset_x or 0,
            config_ref.settings.mouse.offset_y or 0
        ))
    elseif cmd == 'accept' or cmd == 'cancel' then
        local id = tonumber(args[1])
        if id and send_objective_ref then send_objective_ref(cmd, id) end
    elseif cmd == 'sound' then
        local key = args[1] and args[1]:lower() or 'complete'
        if key == 'repeat' then key = 'repeatable' end
        if sound_ref then
            sound_ref.debug('manual command received: //rh sound ' .. key)
            sound_ref.play(key)
        end
    elseif cmd == 'db' then
        local operation = args[1] and tostring(args[1]):lower()
        if operation == 'confirm' then
            db_editor.confirm()
        elseif operation == 'cancel' then
            db_editor.cancel()
        else
            local values = {}
            for index = 3, #args do values[#values + 1] = tostring(args[index]) end
            db_editor.prepare(args[1], args[2], values)
        end
    end
end

return command
