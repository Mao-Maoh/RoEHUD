-- RoEHUD
-- Copyright (c) 2026 Maoh
-- SPDX-License-Identifier: MIT
--
-- Third-party components and data have separate license terms.
-- See LICENSE and THIRD_PARTY_NOTICES.md.

_addon.name = 'RoEHUD'
_addon.author = 'Maoh'
_addon.version = '0.9.0'
_addon.commands = {'roehud','rh'}

local state = require('state')
local config = require('config')
local packet = require('network/packet')
local command = require('input/command')
local mouse = require('input/mouse')
local main_hud = require('ui/main_hud')
local popup = require('ui/popup')
local sound = require('sound')
local item_hover = require('ui/item_hover')
local weather_history = require('services/weather_history')
local completion_history = require('services/completion_history')

config.load()
weather_history.init(config)
completion_history.init(state)
item_hover.init(state, config)
main_hud.init(state, config)
popup.init(state, config, main_hud, item_hover, packet.send_objective)
sound.init(state, config)
packet.init(state, main_hud.update, popup.update, sound, config, item_hover)
command.init(state, config, main_hud.update, popup.update, packet.send_objective, sound, popup.start_setup)
mouse.init(state, main_hud, popup, item_hover, config)

windower.register_event('incoming chunk', packet.handle_incoming)
windower.register_event('outgoing chunk', packet.handle_outgoing)
windower.register_event('addon command', command.handle)
windower.register_event('mouse', mouse.handle)

windower.register_event('load', function()
    completion_history.load()
    local last_complete = windower.packets.last_incoming(0x112)
    if last_complete then completion_history.handle_packet(last_complete) end
    local last_stats = windower.packets.last_incoming(0x061)
    if last_stats then packet.handle_incoming(0x061, last_stats) end
    weather_history.observe()
    sound.refresh_inventory()
    if windower.ffxi.get_info().logged_in then
        main_hud.update()
    end
    if config.settings.setup_completed ~= true then popup.start_setup(true) end
end)

windower.register_event('login', function()
    completion_history.load()
    weather_history.observe()
    sound.refresh_inventory()
    main_hud.update()
    if config.settings.setup_completed ~= true then popup.start_setup(true) end
end)

windower.register_event('zone change', function()
    popup.update()
end)

windower.register_event('weather change', function(new_weather_id)
    weather_history.observe(nil, new_weather_id)
    popup.update()
end)

windower.register_event('day change', function()
    popup.update()
end)

windower.register_event('logout', function()
    completion_history.reset_session()
    state.reset_ui()
    main_hud.hide()
    popup.hide()
    item_hover.hide()
end)
