local texts = require('texts')
local images = require('images')
local db = require('database/Objectives')
local categories = require('database/category')
local resources = require('resources')
local text_util = require('ui/text_util')
local overviews = require('database/overview_loader')
local item_hover = require('ui/item_hover')
local manual = require('database/manual')
local recommendation_logics = require('recommendations/init')
local zone_recommendation = require('recommendations/zone')
local completion_history = require('services/completion_history')
local item_overrides = require('database/item_overrides')
local prerequisites = require('services/prerequisites')
local objective_filter = require('services/objective_filter')

local popup = {}
local state_ref, config_ref, main_hud_ref, item_hover_ref, send_objective_ref
local box
local background_strips = {}
local rows = {}
local PAGE_SIZE = 18

local function clear_background()
    for _, image in ipairs(background_strips) do image:destroy() end
    background_strips = {}
end

local function update_background()
    clear_background()
    box:bg_visible(true)
    box:bg_color(0, 0, 0)
    box:bg_alpha(150)
end

local function add_row(text, action, value)
    table.insert(rows, { text = text or '', action = action, value = value })
end

local function add_multiline(text, color)
    text = tostring(text or '')
    local found = false
    for line in (text .. '\n'):gmatch('(.-)\n') do
        add_row((color or '') .. line .. (color and '\\cr' or ''))
        found = true
    end
    if not found then add_row('') end
end

local function sorted_numeric_keys(source)
    local keys = {}
    for key in pairs(source or {}) do
        if type(key) == 'number' then table.insert(keys, key) end
    end
    table.sort(keys)
    return keys
end

local function color_objective_items(value, dd, lang, restore_color)
    if type(value) ~= 'string' then return value end
    local marked_lines = {}
    for line in (value .. '\n'):gmatch('(.-)\n') do
        if not line:find('{item:', 1, true) then
            if lang == 'ja' then
                line = line:gsub('戦利品%(([^%)]+)%)', '戦利品({item:search}%1{/item})')
                line = line:gsub('^([^、。]+)を戦利品として、',
                    '{item:search}%1{/item}を戦利品として、')
            else
                line = line:gsub('Spoils%s*%(([^%)]+)%)', 'Spoils ({item:search}%1{/item})')
            end
        end
        marked_lines[#marked_lines + 1] = line
    end
    value = table.concat(marked_lines, '\n')
    -- Explicit, inferred, and search markers are authoritative.
    -- Auto-generated title markers are authoritative as well.
    if value:find('{item:', 1, true) then return value end
    local item_ids = {}
    local function collect(source)
        if type(source) ~= 'string' then return end
        for id_text in source:gmatch('{item:(%d+)}') do item_ids[tonumber(id_text)] = true end
    end
    collect(value)
    for _, source in pairs(dd or {}) do collect(source) end

    for item_id in pairs(item_ids) do
        local item = resources.items and resources.items[item_id]
        local name = item and (item[lang] or item.en or item.ja)
        if name and name ~= '' then
            local pattern = name:gsub('([^%w])', '%%%1')
            value = value:gsub(pattern, '{item:' .. tostring(item_id) .. '}')
        end
    end
    return value
end

local function dump_value(value)
    if type(value) ~= 'table' then return tostring(value) end
    local parts = {}
    for key, child in pairs(value) do
        table.insert(parts, tostring(key) .. '=' .. tostring(child))
    end
    table.sort(parts)
    return '{' .. table.concat(parts, ', ') .. '}'
end

local function get_active_roe(id)
    for _, roe in ipairs(state_ref.active_roes) do
        if roe.id == id then return roe, true end
    end
    return { id = id, prog = 0 }, false
end

local function is_completed_nonrepeat(id, data)
    if not data or data.rpt ~= false then return false end
    local monthly = (type(data.ja) == 'string' and data.ja:find('%(M%)') ~= nil)
        or (type(data.en) == 'string' and data.en:find('%(M%)') ~= nil)
    if monthly then
        return completion_history.is_current_complete(id) == true
    end
    return state_ref.completed_roes
        and state_ref.completed_roes[tonumber(id)] == true or false
end

local function mark_completed(id, data, label, lang)
    if not is_completed_nonrepeat(id, data) then return label end
    local marker = lang == 'ja' and '[済]' or '[Done]'
    return '\\cs(150,150,150)' .. marker .. '\\cr ' .. label
end

local function repeat_header(dd, lang)
    if dd.rpt == nil then return lang == 'ja' and '報酬' or 'Rewards' end
    local popup_config = config_ref.settings.popup
    local label_config = dd.rpt
        and popup_config.repeat_labels.repeatable
        or popup_config.repeat_labels.not_repeatable
    local left = lang == 'ja' and '報酬' or 'Rewards'
    local right = label_config[lang] or label_config.en or ''
    local width = popup_config.content_width or 40
    local spaces = math.max(1, width - text_util.get_width(left) - text_util.get_width(right))
    return left .. string.rep(' ', spaces)
        .. (label_config.color or '') .. right .. '\\cr'
end

local function extra_field_value(key, dd, roe, lang)
    if key == 'category_id' then
        local category = dd.category_id and categories[dd.category_id]
        return category and (category[lang] or category.en or category.ja)
    elseif key == 'sub_category_id' then
        local category = dd.category_id and categories[dd.category_id]
        local subcategory = category and category.sub_cat and dd.sub_category_id
            and category.sub_cat[dd.sub_category_id]
        return subcategory and (subcategory[lang] or subcategory.en or subcategory.ja)
    elseif key == 'first_time_reward_item' then
        local reward = dd.first_time_reward_item
        if not reward or not reward.id then return nil end
        local item = (resources.items and resources.items[reward.id])
            or item_overrides[reward.id]
        local name = item and (item[lang] or item.en or item.ja)
            or ('Item ID: ' .. tostring(reward.id))
        return '{item:' .. tostring(reward.id) .. '} x' .. tostring(reward.count or 1)
    end
    local value = dd[key]
    if value == nil then value = roe[key] end
    if value == nil or value == '' then return nil end
    if key == 'target' then
        return value
    end
    return dump_value(value)
end

local function build_extra_lines(dd, roe, lang)
    local popup_config = config_ref.settings.popup
    local result, displayed = {}, {}
    for _, field in ipairs(popup_config.extra_fields or {}) do
        local value = extra_field_value(field.key, dd, roe, lang)
        displayed[field.key] = true
        if value ~= nil then
            table.insert(result, (field[lang] or field.en or field.key) .. ': ' .. tostring(value))
        end
    end
    if not displayed.first_time_reward_text then
        local reward_text = extra_field_value('first_time_reward_text', dd, roe, lang)
        if reward_text ~= nil then
            table.insert(result, (lang == 'ja' and '初回報酬' or 'First reward')
                .. ': ' .. tostring(reward_text))
        end
        displayed.first_time_reward_text = true
    end

    local unknown = popup_config.unknown_keys or {}
    if unknown.enabled then
        local unknown_lines, seen = {}, {}
        local function add_unknown(key, value)
            if value ~= nil and not seen[key] and not displayed[key]
                and not (unknown.ignore and unknown.ignore[key]) then
                table.insert(unknown_lines, tostring(key) .. ': ' .. dump_value(value))
                seen[key] = true
            end
        end
        for key, value in pairs(roe) do add_unknown(key, value) end
        for key, value in pairs(dd) do add_unknown(key, value) end
        table.sort(unknown_lines)
        if #unknown_lines > 0 then
            local title = unknown.title or {}
            table.insert(result, title[lang] or title.en or '==== Unknown keys ====')
            for _, line in ipairs(unknown_lines) do table.insert(result, line) end
        end
    end
    return result
end

local function build_detail(lang)
    local id = state_ref.selected_roe_id
    local dd = db[id]
    local roe, is_active = get_active_roe(id)
    if not dd then
        add_row((lang == 'ja' and '不明な目標 ID: ' or 'Unknown Objective ID: ') .. tostring(id))
        add_row('----------------------------------------')
        add_row(lang == 'ja' and '目標HUDを閉じる' or 'Close Objective HUD', 'close_detail')
        return
    end

    local title = dd[lang]
    if not title or title == '' then
        title = (lang == 'ja' and '不明な目標' or 'Unknown Objective') .. ' (ID: ' .. id .. ')'
    end
    title = mark_completed(id, dd, title, lang)
    add_row('\\cs(255,230,150)' .. color_objective_items(title, dd, lang,
        '\\cs(255,230,150)') .. '\\cr')
    add_row('----------------------------------------')

    local overview_data = overviews[id]
    local overview = overview_data and overview_data['overview_' .. lang]
    if overview and overview ~= '' then
        overview = color_objective_items(overview, dd, lang, '\\cs(200,200,200)')
        add_multiline(overview, '\\cs(200,200,200)')
    end
    add_row('')
    add_row((lang == 'ja' and '指定数: ' or 'Required: ')
        .. tostring(roe.prog or 0) .. ' / ' .. tostring(dd.times or '?'))
    add_row(repeat_header(dd, lang))

    local rewards = {}
    if dd.emi then table.insert(rewards, tostring(dd.emi) .. 'EMI') end
    if dd.exp then table.insert(rewards, tostring(dd.exp) .. 'EXP') end
    if dd.uni then table.insert(rewards, tostring(dd.uni) .. 'UNI') end
    add_row(table.concat(rewards, '  '))

    if is_completed_nonrepeat(id, dd) then
        add_row(lang == 'ja' and '[済] クリア済み（再受領不可）'
            or '[Done] Completed (cannot be repeated)')
    end

    local extra_lines = build_extra_lines(dd, roe, lang)
    if #extra_lines > 0 then
        add_row('==== ' .. (lang == 'ja' and '追加情報' or 'Additional information') .. ' ====')
        for _, line in ipairs(extra_lines) do add_row(line) end
    end

    if state_ref.confirming_cancel_id == id then
        add_row('----------------------------------------')
        add_row(lang == 'ja' and '目標が進行中です。' or 'Objective in progress.')
        add_row(lang == 'ja' and '本当に破棄しますか？' or 'Really cancel?')
        add_row(lang == 'ja' and 'はい' or 'Yes', 'confirm_cancel', id)
        add_row(lang == 'ja' and 'いいえ' or 'No', 'decline_cancel', id)
        return
    end

    if roe.is_limited then
        add_row('----------------------------------------')
        add_row(lang == 'ja' and '目標HUDを閉じる' or 'Close Objective HUD', 'close_detail')
        if not state_ref.is_menu_open then
            add_row(lang == 'ja' and 'メニューを開く' or 'Open Menu', 'open_menu')
        end
        return
    end

    add_row('----------------------------------------')
    if is_completed_nonrepeat(id, dd) and not is_active then
        add_row(lang == 'ja' and 'クリア済みのため受領できません'
            or 'Completed objectives cannot be accepted again')
    else
        add_row(is_active
            and (lang == 'ja' and '目標を破棄する' or 'Cancel Objective')
            or (lang == 'ja' and '目標を受領する' or 'Accept Objective'),
            is_active and 'cancel_objective' or 'accept_objective', id)
    end
    add_row(lang == 'ja' and '目標HUDを閉じる' or 'Close Objective HUD', 'close_detail')
    if not state_ref.is_menu_open then
        add_row(lang == 'ja' and 'メニューを開く' or 'Open Menu', 'open_menu')
    end
end

local function category_entries(lang)
    local result = {}
    local global_id = prerequisites.global_id(db, state_ref)
    if global_id then
        local objective = db[global_id]
        local label = objective and (objective[lang] or objective.en or objective.ja)
            or ((lang == 'ja' and '前提目標' or 'Prerequisite') .. ' (ID: ' .. global_id .. ')')
        result[1] = {action='select_objective', value=global_id, label=label}
        return result
    end
    for _, id in ipairs(sorted_numeric_keys(categories)) do
        local data = categories[id]
        table.insert(result, { action = 'select_category', value = id,
            label = data[lang] or data.en or data.ja })
    end
    return result
end

local UNITY_COMMON_ANCHOR = 1784818800 -- 2026-07-24 00:00:00 JST = A
local UNITY_COMMON_GROUPS = {'A', 'B', 'C', 'D', 'E', 'F'}

local function current_unity_common_group()
    if not state_ref or not tonumber(state_ref.current_unity_id)
        or tonumber(state_ref.current_unity_id) == 0 then
        return nil
    end
    local elapsed_days = math.floor((os.time() - UNITY_COMMON_ANCHOR) / 86400)
    local index = ((elapsed_days % #UNITY_COMMON_GROUPS)
        + #UNITY_COMMON_GROUPS) % #UNITY_COMMON_GROUPS + 1
    return UNITY_COMMON_GROUPS[index]
end

local function subcategory_entries(lang)
    local result = {}
    local category = categories[state_ref.current_cat_id]
    if tonumber(state_ref.current_cat_id) == 9 then
        local subcategories = category and category.sub_cat or {}
        local common_group = current_unity_common_group()
        local unity_id = tonumber(state_ref.current_unity_id)
        local ordered = {}
        if common_group and subcategories[common_group] then
            ordered[#ordered + 1] = common_group
        end
        if unity_id and unity_id >= 1 and unity_id <= 11
            and subcategories[unity_id] then
            ordered[#ordered + 1] = unity_id
        end
        for _, id in ipairs({13, 14, 15}) do
            if subcategories[id] then ordered[#ordered + 1] = id end
        end
        for _, id in ipairs(ordered) do
            local data = subcategories[id]
            table.insert(result, { action = 'select_subcategory', value = id,
                label = data[lang] or data.en or data.ja })
        end
        return result
    end
    for _, id in ipairs(sorted_numeric_keys(category and category.sub_cat)) do
        local data = category.sub_cat[id]
        table.insert(result, { action = 'select_subcategory', value = id,
            label = data[lang] or data.en or data.ja })
    end
    return result
end

local function objective_entries(lang)
    local all = {}
    local global_id = prerequisites.global_id(db, state_ref)
    if global_id then
        local objective = db[global_id]
        local label = objective and (objective[lang] or objective.en or objective.ja)
            or ((lang == 'ja' and '前提目標' or 'Prerequisite') .. ' (ID: ' .. global_id .. ')')
        all[1] = {action='select_objective', value=global_id, label=label}
        return all
    end
    local prerequisite_id = prerequisites.subcategory_id(
        categories, state_ref.current_cat_id, state_ref.current_sub_cat_id)
    if prerequisite_id then
        local objective = db[prerequisite_id]
        local title = objective and (objective[lang] or objective.en or objective.ja)
            or ('ID: ' .. prerequisite_id)
        all[1] = {label=lang == 'ja'
            and ('『' .. title .. '』を達成すると追加されます。')
            or ('Complete "' .. title .. '" to unlock these objectives.')}
        all[2] = {action='select_objective', value=prerequisite_id,
            label=lang == 'ja' and ('前提目標を表示する：' .. title)
                or ('Show prerequisite: ' .. title)}
        return all
    end
    for _, id in ipairs(sorted_numeric_keys(db)) do
        local data = db[id]
        local selected_subcategory = state_ref.current_sub_cat_id
        local matches_subcategory
        if tonumber(state_ref.current_cat_id) == 9
            and type(selected_subcategory) == 'string' then
            matches_subcategory = data.uc_shared_group == selected_subcategory
        else
            matches_subcategory = data.sub_category_id == selected_subcategory
                and not (tonumber(state_ref.current_cat_id) == 9
                    and data.uc_shared_group ~= nil)
        end
        if data.category_id == state_ref.current_cat_id
            and matches_subcategory
            and objective_filter.matches_unity(data, state_ref) then
            local label = data[lang]
            if not label or label == '' then
                label = (lang == 'ja' and '不明な目標' or 'Unknown Objective') .. ' (ID: ' .. id .. ')'
            end
            label = mark_completed(id, data, label, lang)
            table.insert(all, { action = 'select_objective', value = id,
                label = color_objective_items(label, data, lang, '\\cr') })
        end
    end

    local result = {}
    local page_count = math.max(1, math.ceil(#all / PAGE_SIZE))
    state_ref.menu_page = math.max(1, math.min(state_ref.menu_page or 1, page_count))
    local first = (state_ref.menu_page - 1) * PAGE_SIZE + 1
    local last = math.min(#all, first + PAGE_SIZE - 1)
    for index = first, last do table.insert(result, all[index]) end
    if state_ref.menu_page > 1 then
        table.insert(result, { action = 'previous_page', label = lang == 'ja' and '前のページ' or 'Previous page' })
    end
    if state_ref.menu_page < page_count then
        table.insert(result, { action = 'next_page', label = lang == 'ja' and '次のページ' or 'Next page' })
    end
    return result
end

local function recommended_entries(lang)
    local all = {}
    for _, id in ipairs(zone_recommendation.get_ids(db)) do
        local data = db[id]
        if data and objective_filter.matches_unity(data, state_ref) then
            local label = data[lang]
            if not label or label == '' then
                label = (lang == 'ja' and '不明な目標' or 'Unknown Objective')
                    .. ' (ID: ' .. id .. ')'
            end
            label = mark_completed(id, data, label, lang)
            table.insert(all, { action = 'select_objective', value = id,
                label = color_objective_items(label, data, lang, '\\cr') })
        end
    end

    local result = {}
    local page_count = math.max(1, math.ceil(#all / PAGE_SIZE))
    state_ref.menu_page = math.max(1, math.min(state_ref.menu_page or 1, page_count))
    local first = (state_ref.menu_page - 1) * PAGE_SIZE + 1
    local last = math.min(#all, first + PAGE_SIZE - 1)
    for index = first, last do table.insert(result, all[index]) end
    if state_ref.menu_page > 1 then
        table.insert(result, { action = 'previous_page', label = lang == 'ja' and '前のページ' or 'Previous page' })
    end
    if state_ref.menu_page < page_count then
        table.insert(result, { action = 'next_page', label = lang == 'ja' and '次のページ' or 'Next page' })
    end
    return result
end

local function has_zone_recommendations()
    return zone_recommendation.has_any(db)
end

local function recommendation_logic(key)
    for _, logic in ipairs(recommendation_logics or {}) do
        if logic.key == key then return logic end
    end
end

local function logic_entries(logic, lang)
    local all = {}
    if prerequisites.global_id(db, state_ref) then return all end
    for _, id in ipairs(logic and logic.get_ids(db) or {}) do
        local data = db[id]
        if data and objective_filter.matches_unity(data, state_ref)
            and not prerequisites.objective_id(categories, data) then
            local label = data[lang]
            if not label or label == '' then
                label = (lang == 'ja' and '不明な目標' or 'Unknown Objective')
                    .. ' (ID: ' .. id .. ')'
            end
            if logic.decorate_label then label = logic.decorate_label(id, label, lang) end
            label = mark_completed(id, data, label, lang)
            all[#all + 1] = {action='select_objective', value=id,
                label=color_objective_items(label, data, lang, '\\cr')}
        end
    end
    local result = {}
    local page_count = math.max(1, math.ceil(#all / PAGE_SIZE))
    state_ref.menu_page = math.max(1, math.min(state_ref.menu_page or 1, page_count))
    local first = (state_ref.menu_page - 1) * PAGE_SIZE + 1
    local last = math.min(#all, first + PAGE_SIZE - 1)
    for index = first, last do result[#result + 1] = all[index] end
    if state_ref.menu_page > 1 then
        result[#result + 1] = {action='previous_page', label=lang == 'ja' and '前のページ' or 'Previous page'}
    end
    if state_ref.menu_page < page_count then
        result[#result + 1] = {action='next_page', label=lang == 'ja' and '次のページ' or 'Next page'}
    end
    return result
end

local function available_logic_entries(lang)
    local result = {}
    if prerequisites.global_id(db, state_ref) then return result end
    for _, logic in ipairs(recommendation_logics or {}) do
        local visible = false
        for _, id in ipairs(logic.get_ids(db) or {}) do
            if objective_filter.matches_unity(db[id], state_ref) then
                visible = true
                break
            end
        end
        if visible then
            result[#result + 1] = {action='open_recommendation', value=logic.key,
                label=logic.label[lang] or logic.label.en or logic.key}
        end
    end
    return result
end

local function has_any_recommendations()
    if has_zone_recommendations() then return true end
    return #available_logic_entries(config_ref.settings.lang or 'ja') > 0
end

local function current_zone_name(lang)
    local info = windower.ffxi.get_info()
    local zone = resources.zones and info and resources.zones[info.zone]
    return zone and (zone[lang] or zone.en or zone.ja)
        or (lang == 'ja' and '不明なエリア' or 'Unknown Zone')
end

local function menu_heading(lang)
    if state_ref.menu_layer == 'setup' then return '[[ Initial Setup / 初期設定 ]]' end
    if state_ref.menu_layer == 'config' then return '[Config]' end
    if state_ref.menu_layer == 'manual' then return '[Manual]' end
    if state_ref.menu_layer == 'manual_page' then
        local page = manual.pages[state_ref.current_manual_page]
        return '[[' .. tostring(page and page.title and (page.title[lang] or page.title.en) or 'Manual') .. ']]'
    end
    if state_ref.menu_layer == 'main' then return '[Menu]' end
    if state_ref.menu_layer == 'category' then return '[Categories]' end
    if state_ref.menu_layer == 'subcategory' then
        local category = categories[state_ref.current_cat_id]
        return '[[' .. tostring(category and (category[lang] or category.en or category.ja) or '') .. ']]'
    end
    if state_ref.menu_layer == 'recommend' then return '[Recommend]' end
    if state_ref.menu_layer == 'recommend_zone' then
        return '[[ ' .. current_zone_name(lang) .. ' ]]'
    end
    if state_ref.menu_layer == 'recommend_logic' then
        local logic = recommendation_logic(state_ref.current_recommendation)
        return '[[ ' .. tostring(logic and logic.heading(lang) or 'Recommendation') .. ' ]]'
    end
    local category = categories[state_ref.current_cat_id]
    local subcategory = category and category.sub_cat and category.sub_cat[state_ref.current_sub_cat_id]
    return '[[' .. tostring(subcategory and (subcategory[lang] or subcategory.en or subcategory.ja) or '') .. ']]'
end

local function build_menu(lang)
    add_row(menu_heading(lang))
    local entries
    if state_ref.menu_layer == 'setup' then
        add_row('Drag each HUD \\cs(255,220,80)with the mouse\\cr')
        add_row('to the desired position.')
        add_row('This HUD displays objective details,')
        add_row('lists, and menus. You can change its')
        add_row('position and language later in Config.')
        add_row('')
        add_row('各HUDを\\cs(255,220,80)マウス操作\\crでドラッグして')
        add_row('配置してください。')
        add_row('このHUDには、目標の詳細や一覧、')
        add_row('メニューが表示されます。')
        add_row('位置と言語は、あとからConfigで')
        add_row('変更できます。')
        add_row('')
        add_row('Language / 言語')
        entries = {
            {action='setup_language', value='en',
                label=(config_ref.settings.lang == 'en' and state_ref.setup_language_selected and '[*] ' or '')
                    .. 'English / 英語'},
            {action='setup_language', value='ja',
                label=(config_ref.settings.lang == 'ja' and state_ref.setup_language_selected and '[*] ' or '')
                    .. 'Japanese / 日本語'},
        }
        entries[#entries + 1] = {label=''}
        entries[#entries + 1] = {label='Alignment / 文字揃え'}
        entries[#entries + 1] = {action='setup_alignment', value='left',
            label=(config_ref.settings.main_hud.alignment == 'left' and '[*] ' or '')
                .. 'Left / 左寄せ'}
        entries[#entries + 1] = {action='setup_alignment', value='right',
            label=(config_ref.settings.main_hud.alignment ~= 'left' and '[*] ' or '')
                .. 'Right / 右寄せ'}
        entries[#entries + 1] = {label=''}
        entries[#entries + 1] = {action='cycle_mouse_scale',
            label=string.format('Mouse Scale / マウス倍率: %d%%',
                math.floor((tonumber(config_ref.settings.mouse.scale_y) or 1) * 100 + 0.5))}
        if state_ref.setup_language_selected then
            entries[#entries + 1] = {action='finish_setup', label='Finish / 完了'}
            entries[#entries + 1] = {label=''}
            entries[#entries + 1] = {label='After setup, the HUD will begin updating'}
            entries[#entries + 1] = {label='when you change areas or an objective changes.'}
            entries[#entries + 1] = {label='完了後、エリアチェンジや目標変化が'}
            entries[#entries + 1] = {label='あった場合に表示が始まります。'}
        else
            entries[#entries + 1] = {label='Select a language to continue. / 言語を選択してください。'}
        end
    elseif state_ref.menu_layer == 'main' then
        entries = {
            { action = 'open_categories', label = lang == 'ja' and '目標一覧' or 'Objective List' },
            { action = 'open_config', label = lang == 'ja' and 'コンフィグ' or 'Config' },
            { action = 'open_manual', label = lang == 'ja' and 'マニュアル' or 'Manual' },
        }
        if has_any_recommendations() then
            table.insert(entries, 2, {action='recommend',
                label=lang == 'ja' and 'オススメ' or 'Recommendations'})
        end
    elseif state_ref.menu_layer == 'config' then
        local size = config_ref.settings.font_size or config_ref.settings.popup.font.size or 10
        local locked = config_ref.settings.hud_locked ~= false
        entries = {
            { action = 'toggle_language', label = 'Language: ' .. string.upper(lang) },
            { action = 'font_down', label = 'Font Size: ' .. size .. '  [-1]' },
            { action = 'font_up', label = 'Font Size: ' .. size .. '  [+1]' },
            { action = 'toggle_sound', label = (lang == 'ja' and '効果音: ' or 'Sound: ')
                .. (config_ref.settings.sound.enabled == false and 'OFF' or 'ON') },
            { action = 'toggle_alignment', label = (lang == 'ja' and '目標リストの文字揃え: ' or 'Objective List Alignment: ')
                .. (config_ref.settings.main_hud.alignment == 'left'
                    and (lang == 'ja' and '左' or 'Left')
                    or (lang == 'ja' and '右' or 'Right')) },
            { action = 'cycle_mouse_scale', label = string.format(
                lang == 'ja' and 'マウス倍率: %d%%' or 'Mouse Scale: %d%%',
                math.floor((tonumber(config_ref.settings.mouse.scale_y) or 1) * 100 + 0.5)) },
            { action = 'mouse_offset_x_down', label = string.format(
                lang == 'ja' and 'マウスX補正: %d  [-5]' or 'Mouse X Offset: %d  [-5]',
                tonumber(config_ref.settings.mouse.offset_x) or 0) },
            { action = 'mouse_offset_x_up', label = string.format(
                lang == 'ja' and 'マウスX補正: %d  [+5]' or 'Mouse X Offset: %d  [+5]',
                tonumber(config_ref.settings.mouse.offset_x) or 0) },
            { action = 'mouse_offset_y_down', label = string.format(
                lang == 'ja' and 'マウスY補正: %d  [-5]' or 'Mouse Y Offset: %d  [-5]',
                tonumber(config_ref.settings.mouse.offset_y) or 0) },
            { action = 'mouse_offset_y_up', label = string.format(
                lang == 'ja' and 'マウスY補正: %d  [+5]' or 'Mouse Y Offset: %d  [+5]',
                tonumber(config_ref.settings.mouse.offset_y) or 0) },
            { action = 'reset_mouse', label = lang == 'ja' and 'マウス補正を初期化' or 'Reset Mouse Correction' },
            { action = 'toggle_mouse_debug', label = (lang == 'ja' and 'マウス座標デバッグ: ' or 'Mouse Coordinate Debug: ')
                .. (state_ref.debug_mouse and 'ON' or 'OFF') },
            { action = state_ref.layout_editing and 'save_layout' or 'start_layout',
                label = state_ref.layout_editing
                    and (lang == 'ja' and 'HUD配置を保存' or 'Save HUD Layout')
                    or (lang == 'ja' and 'HUD配置を編集' or 'Edit HUD Layout') },
            { action = 'cancel_layout', label = lang == 'ja' and 'HUD配置編集を取消' or 'Cancel Layout Edit' },
            { action = 'toggle_hud_lock', label = (lang == 'ja' and '通常時のHUD移動: ' or 'Normal HUD Drag: ')
                .. (locked and (lang == 'ja' and 'ロック' or 'Locked') or (lang == 'ja' and '許可' or 'Enabled')) },
            { action = 'reset_layout', label = lang == 'ja' and 'HUD配置を初期化' or 'Reset HUD Layout' },
        }
    elseif state_ref.menu_layer == 'manual' then
        entries = {}
        for _, key in ipairs(manual.order or {}) do
            local page = manual.pages[key]
            if page then
                entries[#entries + 1] = {action='open_manual_page', value=key,
                    label=page.title[lang] or page.title.en or key}
            end
        end
    elseif state_ref.menu_layer == 'manual_page' then
        entries = {}
        local page = manual.pages[state_ref.current_manual_page]
        for _, line in ipairs(page and (page[lang] or page.en) or {}) do
            entries[#entries + 1] = {label=line}
        end
    elseif state_ref.menu_layer == 'category' then
        entries = category_entries(lang)
    elseif state_ref.menu_layer == 'subcategory' then
        entries = subcategory_entries(lang)
    elseif state_ref.menu_layer == 'recommend' then
        entries = {}
        if has_zone_recommendations() then
            entries[#entries + 1] = {action='open_recommend_zone',
                label=lang == 'ja' and '現在エリアのオススメ目標' or 'Current Zone Recommendations'}
        end
        for _, entry in ipairs(available_logic_entries(lang)) do entries[#entries + 1] = entry end
    elseif state_ref.menu_layer == 'recommend_zone' then
        entries = recommended_entries(lang)
    elseif state_ref.menu_layer == 'recommend_logic' then
        entries = logic_entries(recommendation_logic(state_ref.current_recommendation), lang)
    else
        entries = objective_entries(lang)
    end

    for _, entry in ipairs(entries) do
        local label = tostring(entry.label or '')
        if entry.action == 'select_objective' and entry.value == state_ref.selected_roe_id then
            label = '[[' .. label .. ']]'
        end
        add_row(label, entry.action, entry.value)
    end
    if #entries == 0 then add_row(lang == 'ja' and '該当する目標はありません' or 'No objectives found') end

    add_row('----------------------------------------')
    if state_ref.menu_layer ~= 'main' and state_ref.menu_layer ~= 'setup' then
        add_row(lang == 'ja' and '戻る' or 'Back', 'back')
    end
    if state_ref.menu_layer ~= 'setup' then
        add_row(lang == 'ja' and 'メニューを閉じる' or 'Close Menu', 'close_menu')
        add_row(lang == 'ja' and '全てを閉じる' or 'Close All', 'close_all')
    end
end

local function go_back()
    if state_ref.menu_layer == 'manual_page' then
        state_ref.menu_layer = 'manual'
        state_ref.current_manual_page = nil
    elseif state_ref.menu_layer == 'manual' then
        state_ref.menu_layer = 'main'
    elseif state_ref.menu_layer == 'config' then
        state_ref.menu_layer = 'main'
    elseif state_ref.menu_layer == 'objectives' then
        state_ref.menu_layer = 'subcategory'
        state_ref.menu_page = 1
    elseif state_ref.menu_layer == 'subcategory' then
        state_ref.menu_layer = 'category'
        state_ref.current_sub_cat_id = nil
    elseif state_ref.menu_layer == 'category' then
        state_ref.menu_layer = 'main'
        state_ref.current_cat_id = nil
    elseif state_ref.menu_layer == 'recommend_zone' then
        state_ref.menu_layer = 'recommend'
        state_ref.menu_page = 1
    elseif state_ref.menu_layer == 'recommend_logic' then
        state_ref.menu_layer = 'recommend'
        state_ref.current_recommendation = nil
        state_ref.menu_page = 1
    elseif state_ref.menu_layer == 'recommend' then
        state_ref.menu_layer = 'main'
    else
        state_ref.is_menu_open = false
        state_ref.menu_layer = 'none'
    end
end

local function copy_pos(pos)
    return {x = tonumber(pos and pos.x) or 0, y = tonumber(pos and pos.y) or 0}
end

local function apply_font_size(size)
    size = math.max(8, math.min(20, tonumber(size) or 10))
    config_ref.settings.font_size = size
    config_ref.settings.main_hud.font.size = size
    config_ref.settings.popup.font.size = size
    config_ref.settings.item_popup.font.size = size
    box:size(size)
    if main_hud_ref then main_hud_ref.update() end
    if item_hover_ref then item_hover_ref.refresh_layout_preview() end
    config_ref.save()
end

local function set_layout_draggable(enabled)
    box:draggable(enabled == true)
    if main_hud_ref then main_hud_ref.set_draggable(enabled) end
end

local function begin_layout_edit()
    if state_ref.layout_editing then return end
    local main_x, main_y = main_hud_ref.get_pos()
    local popup_x, popup_y = box:pos()
    state_ref.layout_snapshot = {
        main_hud = {x=main_x, y=main_y},
        popup = {x=popup_x, y=popup_y},
        item_popup = copy_pos(config_ref.settings.item_popup.pos),
    }
    state_ref.layout_editing = true
    set_layout_draggable(true)
    if item_hover_ref then item_hover_ref.show_layout_preview() end
end

local function finish_layout_edit(save)
    if not state_ref.layout_editing then return end
    if save then
        local main_x, main_y = main_hud_ref.get_pos()
        local popup_x, popup_y = box:pos()
        local item_x, item_y = item_hover_ref.get_layout_preview_pos()
        config_ref.settings.main_hud.pos = {x=main_x, y=main_y}
        config_ref.settings.popup.pos = {x=popup_x, y=popup_y}
        config_ref.settings.item_popup.pos = {x=item_x, y=item_y}
        config_ref.save()
    elseif state_ref.layout_snapshot then
        local old = state_ref.layout_snapshot
        main_hud_ref.set_pos(old.main_hud.x, old.main_hud.y)
        box:pos(old.popup.x, old.popup.y)
        config_ref.settings.item_popup.pos = copy_pos(old.item_popup)
    end
    state_ref.layout_editing = false
    state_ref.layout_snapshot = nil
    set_layout_draggable(config_ref.settings.hud_locked == false)
    if item_hover_ref then item_hover_ref.hide_layout_preview() end
    update_background()
end

local function reset_layout()
    if state_ref.layout_editing then finish_layout_edit(false) end
    config_ref.settings.main_hud.pos = {x=-125, y=45}
    config_ref.settings.popup.pos = {x=145, y=210}
    config_ref.settings.item_popup.pos = {x=80, y=100}
    main_hud_ref.set_pos(-125, 45)
    box:pos(145, 210)
    config_ref.save()
    update_background()
end

local function initial_setup_positions()
    local settings = windower.get_windower_settings() or {}
    local screen_width = tonumber(settings.ui_x_res) or 1280
    local screen_height = tonumber(settings.ui_y_res) or 720
    -- The main HUD is right-aligned, so its x value is relative to the screen's right edge.
    local main_right_edge = math.floor(screen_width * 0.72)
    return {
        popup = {
            x=math.max(40, math.floor(screen_width * 0.045)),
            y=math.max(40, math.floor(screen_height * 0.045)),
        },
        item_popup = {
            x=math.max(360, math.floor(screen_width * 0.35)),
            y=math.max(70, math.floor(screen_height * 0.07)),
        },
        main_hud = {
            x=main_right_edge - screen_width,
            y=math.max(250, math.floor(screen_height * 0.24)),
        },
    }
end

local function execute_action(row)
    if not row or not row.action then return end
    local action = row.action
    if action == 'close_detail' then
        state_ref.selected_roe_id = nil
        state_ref.confirming_cancel_id = nil
    elseif action == 'open_menu' then
        state_ref.is_menu_open = true
        state_ref.menu_layer = 'main'
    elseif action == 'close_menu' then
        state_ref.is_menu_open = false
        state_ref.menu_layer = 'none'
    elseif action == 'close_all' then
        state_ref.selected_roe_id = nil
        state_ref.confirming_cancel_id = nil
        state_ref.is_menu_open = false
        state_ref.menu_layer = 'none'
    elseif action == 'open_categories' then
        state_ref.menu_layer = 'category'
    elseif action == 'open_config' then
        state_ref.menu_layer = 'config'
    elseif action == 'open_manual' then
        state_ref.menu_layer = 'manual'
        state_ref.current_manual_page = nil
    elseif action == 'open_manual_page' then
        state_ref.menu_layer = 'manual_page'
        state_ref.current_manual_page = row.value
    elseif action == 'recommend' then
        state_ref.menu_layer = 'recommend'
        state_ref.menu_page = 1
    elseif action == 'open_recommend_zone' then
        state_ref.menu_layer = 'recommend_zone'
        state_ref.menu_page = 1
    elseif action == 'open_recommendation' then
        state_ref.current_recommendation = row.value
        state_ref.menu_layer = 'recommend_logic'
        state_ref.menu_page = 1
    elseif action == 'select_category' then
        state_ref.current_cat_id = row.value
        state_ref.current_sub_cat_id = nil
        state_ref.menu_layer = 'subcategory'
    elseif action == 'select_subcategory' then
        state_ref.current_sub_cat_id = row.value
        state_ref.menu_layer = 'objectives'
        state_ref.menu_page = 1
    elseif action == 'select_objective' then
        state_ref.selected_roe_id = row.value
        state_ref.confirming_cancel_id = nil
    elseif action == 'previous_page' then
        state_ref.menu_page = math.max(1, state_ref.menu_page - 1)
    elseif action == 'next_page' then
        state_ref.menu_page = state_ref.menu_page + 1
    elseif action == 'back' then
        go_back()
    elseif action == 'toggle_language' then
        config_ref.settings.lang = config_ref.settings.lang == 'ja' and 'en' or 'ja'
        config_ref.save()
        if main_hud_ref then main_hud_ref.update() end
        if item_hover_ref then item_hover_ref.refresh_layout_preview() end
    elseif action == 'setup_language' then
        if row.value == 'ja' or row.value == 'en' then
            config_ref.settings.lang = row.value
            state_ref.setup_language_selected = true
            if main_hud_ref then main_hud_ref.update() end
            if item_hover_ref then item_hover_ref.refresh_layout_preview() end
        end
    elseif action == 'setup_alignment' then
        if row.value == 'left' or row.value == 'right' then
            config_ref.settings.main_hud.alignment = row.value
            if main_hud_ref then main_hud_ref.update() end
        end
    elseif action == 'finish_setup' then
        if state_ref.setup_language_selected then
            finish_layout_edit(true)
            config_ref.settings.setup_completed = true
            config_ref.save()
            state_ref.setup_active = false
            state_ref.is_menu_open = false
            state_ref.menu_layer = 'none'
            if main_hud_ref then main_hud_ref.update() end
        end
    elseif action == 'font_down' then
        apply_font_size((config_ref.settings.font_size or 10) - 1)
    elseif action == 'font_up' then
        apply_font_size((config_ref.settings.font_size or 10) + 1)
    elseif action == 'toggle_sound' then
        config_ref.settings.sound.enabled = config_ref.settings.sound.enabled == false
        config_ref.save()
    elseif action == 'toggle_alignment' then
        config_ref.settings.main_hud.alignment =
            config_ref.settings.main_hud.alignment == 'left' and 'right' or 'left'
        config_ref.save()
        if main_hud_ref then main_hud_ref.update() end
    elseif action == 'cycle_mouse_scale' then
        local values = {0.95, 1, 1.05, 1.09, 1.10, 1.15}
        local current = tonumber(config_ref.settings.mouse.scale_y) or 1
        local next_value = values[1]
        for index, value in ipairs(values) do
            if math.abs(current - value) < 0.01 then
                next_value = values[index % #values + 1]
                break
            end
        end
        config_ref.settings.mouse.scale_y = next_value
        if not state_ref.setup_active then config_ref.save() end
    elseif action == 'mouse_offset_x_down' then
        config_ref.settings.mouse.offset_x = (tonumber(config_ref.settings.mouse.offset_x) or 0) - 5
        config_ref.save()
    elseif action == 'mouse_offset_x_up' then
        config_ref.settings.mouse.offset_x = (tonumber(config_ref.settings.mouse.offset_x) or 0) + 5
        config_ref.save()
    elseif action == 'mouse_offset_y_down' then
        config_ref.settings.mouse.offset_y = (tonumber(config_ref.settings.mouse.offset_y) or 0) - 5
        config_ref.save()
    elseif action == 'mouse_offset_y_up' then
        config_ref.settings.mouse.offset_y = (tonumber(config_ref.settings.mouse.offset_y) or 0) + 5
        config_ref.save()
    elseif action == 'reset_mouse' then
        config_ref.settings.mouse.scale_x = 1
        config_ref.settings.mouse.scale_y = 1
        config_ref.settings.mouse.offset_x = 0
        config_ref.settings.mouse.offset_y = 0
        config_ref.save()
    elseif action == 'toggle_mouse_debug' then
        state_ref.debug_mouse = not state_ref.debug_mouse
    elseif action == 'start_layout' then
        begin_layout_edit()
    elseif action == 'save_layout' then
        finish_layout_edit(true)
    elseif action == 'cancel_layout' then
        finish_layout_edit(false)
    elseif action == 'toggle_hud_lock' then
        config_ref.settings.hud_locked = config_ref.settings.hud_locked == false
        if not state_ref.layout_editing then
            set_layout_draggable(config_ref.settings.hud_locked == false)
        end
        config_ref.save()
    elseif action == 'reset_layout' then
        reset_layout()
    elseif action == 'accept_objective' then
        if send_objective_ref then send_objective_ref('accept', row.value) end
    elseif action == 'cancel_objective' then
        local roe = get_active_roe(row.value)
        if (roe.prog or 0) > 0 then
            state_ref.confirming_cancel_id = row.value
        elseif send_objective_ref then
            send_objective_ref('cancel', row.value)
        end
    elseif action == 'confirm_cancel' then
        if send_objective_ref then send_objective_ref('cancel', row.value) end
        state_ref.confirming_cancel_id = nil
    elseif action == 'decline_cancel' then
        state_ref.confirming_cancel_id = nil
    end
    state_ref.popup_hovered_index = nil
    popup.update()
end

function popup.init(state, config, main_hud, item_hover, send_objective)
    state_ref = state
    config_ref = config
    main_hud_ref = main_hud
    item_hover_ref = item_hover
    send_objective_ref = send_objective
    box = texts.new({
        pos = config.settings.popup.pos,
        text = { font = 'ＭＳ ゴシック', size = config.settings.popup.font.size or 10 },
        bg = { visible = false, alpha = 0 },
        padding = config.settings.popup.padding or 5,
    })
    box:draggable(config.settings.hud_locked == false)
    box:hide()
end

function popup.show() box:show(); update_background() end
function popup.hide() box:hide(); clear_background() end
function popup.is_visible()
    return state_ref.selected_roe_id ~= nil or state_ref.is_menu_open
end

function popup.get_bounds()
    local x, y = box:pos()
    local width, height = texts.extents(box)
    x, y, width, height = x or 0, y or 0, width or 0, height or 0
    local bounds = state_ref.bounds.popup
    bounds.x1, bounds.y1 = x, y
    bounds.x2, bounds.y2 = x + width, y + height
    bounds.buttons = {}

    local row_height = #rows > 0 and height / #rows or 0
    local current_y = y
    for index, row in ipairs(rows) do
        bounds.buttons[index] = {
            y1 = current_y, y2 = current_y + row_height,
            action = row.action, value = row.value,
        }
        current_y = current_y + row_height
    end
    return bounds
end

function popup.contains(x, y)
    if not popup.is_visible() then return false end
    local bounds = popup.get_bounds()
    return x >= bounds.x1 and x <= bounds.x2 and y >= bounds.y1 and y <= bounds.y2
end

function popup.sync_layout_preview()
    if state_ref.layout_editing then update_background() end
end

local function row_at(y)
    local bounds = popup.get_bounds()
    for index, button in ipairs(bounds.buttons) do
        if y >= button.y1 and y <= button.y2 then
            return index, rows[index], button
        end
    end
    return nil, nil, nil
end

function popup.handle_mouse(type, x, y)
    if type == 4 then
        return true
    elseif type == 5 then
        if state_ref.setup_active then return true end
        if state_ref.confirming_cancel_id then
            state_ref.confirming_cancel_id = nil
        elseif state_ref.is_menu_open then
            go_back()
        else
            state_ref.selected_roe_id = nil
        end
        state_ref.popup_hovered_index = nil
        popup.update()
        return true
    end

    local index, row, button = row_at(y)
    if state_ref.debug_mouse and type ~= 0 then
        windower.add_to_chat(207, string.format(
            '[RoEHUD menu] type=%s row=%s action=%s row_y=%s..%s',
            tostring(type), tostring(index), tostring(row and row.action),
            button and string.format('%.1f', button.y1) or '-',
            button and string.format('%.1f', button.y2) or '-'
        ))
    end
    if type == 0 then
        local hovered = row and row.action and index or nil
        if state_ref.popup_hovered_index ~= hovered then
            state_ref.popup_hovered_index = hovered
            popup.update()
        end
        return true
    elseif type == 1 and row and row.action then
        execute_action(row)
        return true
    end
    return true
end

function popup.start_setup(is_first_run)
    if state_ref.setup_active then return end
    if state_ref.layout_editing then finish_layout_edit(false) end

    if is_first_run == true then config_ref.settings.lang = 'en' end

    local positions = initial_setup_positions()
    main_hud_ref.set_pos(positions.main_hud.x, positions.main_hud.y)
    box:pos(positions.popup.x, positions.popup.y)
    config_ref.settings.item_popup.pos = copy_pos(positions.item_popup)

    state_ref.selected_roe_id = nil
    state_ref.confirming_cancel_id = nil
    state_ref.setup_active = true
    state_ref.setup_language_selected = is_first_run ~= true
    state_ref.is_menu_open = true
    state_ref.menu_layer = 'setup'
    state_ref.popup_hovered_index = nil

    begin_layout_edit()
    if main_hud_ref then main_hud_ref.update() end
    popup.update()
end

function popup.clear_hover()
    if state_ref.popup_hovered_index then
        state_ref.popup_hovered_index = nil
        popup.update()
    end
end

function popup.request_cancel(id)
    local roe, is_active = get_active_roe(id)
    if not is_active or roe.is_limited then return false end
    state_ref.selected_roe_id = id
    state_ref.popup_hovered_index = nil
    if (roe.prog or 0) > 0 then
        state_ref.confirming_cancel_id = id
    else
        state_ref.confirming_cancel_id = nil
        if send_objective_ref then send_objective_ref('cancel', id) end
    end
    popup.update()
    return true
end

function popup.update()
    box:size(config_ref.settings.popup.font.size or 10)
    rows = {}
    local lang = config_ref.settings.lang or 'ja'
    if state_ref.menu_layer == 'recommend_zone' and not has_zone_recommendations() then
        state_ref.is_menu_open = false
        state_ref.menu_layer = 'none'
    elseif state_ref.menu_layer == 'recommend_logic' then
        local logic = recommendation_logic(state_ref.current_recommendation)
        if not logic or #(logic.get_ids(db) or {}) == 0 then
            state_ref.is_menu_open = false
            state_ref.menu_layer = 'none'
            state_ref.current_recommendation = nil
        end
    end
    if state_ref.selected_roe_id then build_detail(lang) end
    if state_ref.is_menu_open then
        if #rows > 0 then add_row('----------------------------------------') end
        build_menu(lang)
    end
    if #rows == 0 then box:hide(); clear_background(); return end

    local output = {}
    for index, row in ipairs(rows) do
        local text = row.text
        if row.action and state_ref.popup_hovered_index == index then
            text = '[[' .. text .. ']]'
        end
        table.insert(output, text)
    end
    item_hover.set_text(box, table.concat(output, '\n'),
        {key='popup', size=config_ref.settings.popup.font.size or 10,
            padding=config_ref.settings.popup.padding or 5, right=false})
    box:show()
    popup.get_bounds()
    update_background()
end

return popup
