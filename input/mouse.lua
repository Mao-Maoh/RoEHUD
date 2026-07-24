local mouse = {}
local state_ref, config_ref
local main_hud, popup, item_hover

function mouse.init(state, main_hud_mod, popup_mod, item_hover_mod, config)
    state_ref = state
    config_ref = config
    main_hud = main_hud_mod
    popup = popup_mod
    item_hover = item_hover_mod
end

local function corrected_position(x, y)
    local settings = config_ref and config_ref.settings.mouse or {}
    local scale_x = tonumber(settings and settings.scale_x) or 1
    local scale_y = tonumber(settings and settings.scale_y) or 1
    local offset_x = tonumber(settings and settings.offset_x) or 0
    local offset_y = tonumber(settings and settings.offset_y) or 0
    return x * scale_x + offset_x, y * scale_y + offset_y,
        scale_x, scale_y, offset_x, offset_y
end

local function main_target_at(x, y)
    local bounds = main_hud.get_bounds()
    local inside = x >= bounds.x1 and x <= bounds.x2
        and y >= bounds.y1 and y <= bounds.y2
    if not inside then return nil, false, nil end
    for _, row in ipairs(bounds.rows or {}) do
        if y >= row.y1 and y <= row.y2 then return row.id, true, row end
    end
    return nil, true, nil
end

function mouse.handle(type, x, y, delta, blocked)
    if state_ref.is_hidden then return end
    local raw_x, raw_y = x, y
    local scale_x, scale_y, offset_x, offset_y
    x, y, scale_x, scale_y, offset_x, offset_y = corrected_position(x, y)

    if state_ref.debug_mouse and type ~= 0 then
        windower.add_to_chat(207, string.format(
            '[RoEHUD mouse] raw=(%.1f,%.1f) corrected=(%.1f,%.1f) scale=(%.3f,%.3f) offset=(%.1f,%.1f)',
            raw_x, raw_y, x, y, scale_x, scale_y, offset_x, offset_y
        ))
    end

    if state_ref.layout_editing then
        if popup then popup.sync_layout_preview() end
        if item_hover then item_hover.sync_layout_preview() end
    end

    local matched_id, in_main, matched_row = main_target_at(x, y)
    if item_hover then item_hover.handle_mouse(type, x, y) end

    -- Main HUD right-click: remember the pressed row and act on release.
    if type == 4 and matched_id then
        state_ref.main_right_click_id = matched_id
        return true
    elseif type == 5 and state_ref.main_right_click_id then
        local pressed_id = state_ref.main_right_click_id
        state_ref.main_right_click_id = nil
        if matched_id == pressed_id then popup.request_cancel(pressed_id) end
        return true
    end

    -- Popup right-click remains global, matching EmiList behavior.
    if popup.is_visible() and (type == 4 or type == 5) then
        return popup.handle_mouse(type, x, y)
    end

    if popup.contains(x, y) then
        return popup.handle_mouse(type, x, y)
    elseif type == 0 then
        popup.clear_hover()
    end

    if in_main then
        if state_ref.debug_mouse and type ~= 0 then
            windower.add_to_chat(207, string.format(
                '[RoEHUD mouse] type=%s blocked=%s matched=%s row_y=%s..%s',
                tostring(type), tostring(blocked), tostring(matched_id),
                matched_row and string.format('%.1f', matched_row.y1) or '-',
                matched_row and string.format('%.1f', matched_row.y2) or '-'
            ))
        end

        if type == 0 then
            if state_ref.hovered_roe_id ~= matched_id then
                state_ref.hovered_roe_id = matched_id
                main_hud.update()
            end
            return true
        elseif type == 1 and matched_id then
            state_ref.selected_roe_id = matched_id
            state_ref.confirming_cancel_id = nil
            popup.update()
            return true
        end
        return true
    end

    if type == 0 and state_ref.hovered_roe_id then
        state_ref.hovered_roe_id = nil
        main_hud.update()
    end
end

return mouse
