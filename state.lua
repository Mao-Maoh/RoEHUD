-- state.lua
local state = {
    active_roes = {},
    previous_roes = {},
    completed_roes = {},
    is_inventory_full = false,
    current_unity_id = nil,
    current_unity = nil,
    debug_mouse = false,
    selected_roe_id = nil,
    is_menu_open = false,
    menu_layer = 'none', -- includes recommend, recommend_zone, recommend_day
    current_cat_id = nil,
    current_sub_cat_id = nil,
    popup_hovered_index = nil,
    confirming_cancel_id = nil,
    pending_objective_action = nil,
    main_right_click_id = nil,
    open_recommend_after_zone = false,
    menu_page = 1,
    menu_history = {},
    layout_editing = false,
    layout_snapshot = nil,
    setup_active = false,
    setup_language_selected = false,
    current_manual_page = nil,
    current_recommendation = nil,
    
    -- マウス判定用の各HUDの座標データ（四角い箱）を保持する領域
    bounds = {
        main_hud = { x1 = 0, y1 = 0, x2 = 0, y2 = 0, rows = {} },
        popup = { x1 = 0, y1 = 0, x2 = 0, y2 = 0, buttons = {} },
        hud3 = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 }
    }
}

function state.reset_ui()
    state.selected_roe_id = nil
    state.hovered_roe_id = nil
    state.is_menu_open = false
    state.menu_layer = 'none'
    state.current_cat_id = nil
    state.current_sub_cat_id = nil
    state.popup_hovered_index = nil
    state.confirming_cancel_id = nil
    state.pending_objective_action = nil
    state.main_right_click_id = nil
    state.open_recommend_after_zone = false
    state.menu_page = 1
    state.menu_history = {}
    state.layout_editing = false
    state.layout_snapshot = nil
    state.setup_active = false
    state.setup_language_selected = false
    state.current_manual_page = nil
    state.current_recommendation = nil
    state.bounds.main_hud.rows = {}
    state.previous_roes = {}
    state.is_inventory_full = false
end

return state
