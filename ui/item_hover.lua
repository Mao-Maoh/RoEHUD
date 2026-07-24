local texts = require('texts')
local images = require('images')
local resources = require('resources')
local item_overrides = require('database/item_overrides')
local furnishings = require('database/furnishings')
local placement_ok, placements = pcall(require, 'database/placement')
if not placement_ok or type(placements) ~= 'table' then placements = {} end

local item_hover = {}
local state_ref, config_ref
local targets = {}
local hovered_key, hovered_id
local hovered_target
local tooltip, icon_image
local tooltip_backgrounds = {}
local icon_extractor
local item_name_index
local layout_preview = false

local slot_names = {
    ja = {[0]='[主]',[1]='[副]',[2]='[遠]',[3]='[矢]',[4]='[頭]',[5]='[胴]',[6]='[両手]',[7]='[両脚]',[8]='[両足]',[9]='[首]',[10]='[腰]',[11]='[耳]',[12]='[耳]',[13]='[指]',[14]='[指]',[15]='[背]'},
    en = {[0]='[Main]',[1]='[Sub]',[2]='[Range]',[3]='[Ammo]',[4]='[Head]',[5]='[Body]',[6]='[Hands]',[7]='[Legs]',[8]='[Feet]',[9]='[Neck]',[10]='[Waist]',[11]='[Ear]',[12]='[Ear]',[13]='[Ring]',[14]='[Ring]',[15]='[Back]'},
}

local job_names = {
    ja = {'戦','モ','白','黒','赤','シ','ナ','暗','獣','吟','狩','侍','忍','竜','召','青','コ','か','踊','学','風','剣'},
    en = {'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'},
}

local function clean_width(text, size)
    text = tostring(text or ''):gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', '')
    local width, index = 0, 1
    while index <= #text do
        local byte = text:byte(index)
        if byte < 128 then width = width + size * 0.5; index = index + 1
        elseif byte < 224 then width = width + size * 0.5; index = index + 2
        elseif byte < 240 then width = width + size; index = index + 3
        else width = width + size; index = index + 4 end
    end
    return width
end

local function table_count(value)
    local count = 0
    if type(value) == 'table' then
        for _, enabled in pairs(value) do if enabled then count = count + 1 end end
    end
    return count
end

local function bit_names(value, names, first_bit)
    local result, seen = {}, {}
    if type(value) == 'table' then
        for key, enabled in pairs(value) do
            local index = tonumber(key)
            local name = index and names[index]
            if enabled and name and not seen[name] then result[#result + 1] = name; seen[name] = true end
        end
    else
        local number = tonumber(value) or 0
        for bit_index = 0, 31 do
            if math.floor(number / (2 ^ bit_index)) % 2 == 1 then
                local name = names[bit_index - (first_bit or 0)]
                if name and not seen[name] then result[#result + 1] = name; seen[name] = true end
            end
        end
    end
    return result
end

local function localized(resource, lang)
    if type(resource) ~= 'table' then return nil end
    return resource[lang] or resource.en or resource.ja
end

local function resource_item(id)
    return (resources.items and resources.items[id]) or item_overrides[id]
end

local function build_item_name_index()
    if item_name_index then return end
    item_name_index = {ja={}, en={}}
    for id, item in pairs(resources.items or {}) do
        if type(id) == 'number' and type(item) == 'table' then
            for _, lang in ipairs({'ja', 'en'}) do
                local name = item[lang]
                if type(name) == 'string' and name ~= '' then
                    local ids = item_name_index[lang][name] or {}
                    ids[#ids + 1] = id
                    item_name_index[lang][name] = ids
                end
            end
        end
    end
    for id, item in pairs(item_overrides or {}) do
        if type(id) == 'number' and type(item) == 'table' then
            for _, lang in ipairs({'ja', 'en'}) do
                local name = item[lang]
                if type(name) == 'string' and name ~= '' then
                    local ids = item_name_index[lang][name] or {}
                    ids[#ids + 1] = id
                    item_name_index[lang][name] = ids
                end
            end
        end
    end
end

local function search_candidate(line, token_end, lang)
    local remainder = line:sub(token_end + 1)
    local close_start, close_end = remainder:find('{/item}', 1, true)
    if close_start then
        local raw_name = remainder:sub(1, close_start - 1)
        local name = raw_name:gsub('^%s+', ''):gsub('%s+$', '')
        if name == '' then return nil, 0 end
        return name, close_end
    end
    local delimiters = lang == 'ja'
        and {')', '）', 'を戦利品として', 'を入手', 'を', '、', '。'}
        or {')', ' as spoils', ' as a spoil', ' to obtain', ' and obtain', ',', '.'}
    local boundary
    for _, delimiter in ipairs(delimiters) do
        local position = remainder:find(delimiter, 1, true)
        if position and position > 1 and (not boundary or position < boundary) then
            boundary = position
        end
    end
    if not boundary then return nil, 0 end
    local raw_name = remainder:sub(1, boundary - 1)
    local name = raw_name:gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return nil, 0 end
    return name, #raw_name
end

local function resolve_item_name(name, lang)
    build_item_name_index()
    local ids = item_name_index[lang] and item_name_index[lang][name]
    if not ids or #ids ~= 1 then return nil end
    return ids[1]
end

local function has_numeric_flag(value, mask)
    value = tonumber(value) or 0
    return math.floor(value / mask) % 2 == 1
end

local function item_flags(value)
    local alt, rare, exclusive = false, false, false
    if type(value) == 'table' then
        alt = value.Alt or value['Account Bound'] or value['Can Send POL'] or false
        rare = value.Rare or false
        exclusive = value.Ex or value.Exclusive or false
    else
        alt = has_numeric_flag(value, 16)
        rare = has_numeric_flag(value, 32768)
        exclusive = has_numeric_flag(value, 8192)
    end

    local result = {}
    if alt then result[#result + 1] = '\\cs(100,200,255)Alt\\cr' end
    if rare then result[#result + 1] = '\\cs(255,220,80)Rare\\cr' end
    if exclusive then result[#result + 1] = '\\cs(100,255,160)Ex\\cr' end
    return table.concat(result, ' ')
end

local function right_aligned(label)
    local width = (config_ref.settings.item_popup and config_ref.settings.item_popup.content_width) or 48
    local visible_width = 0
    local index = 1
    while index <= #label do
        local byte = label:byte(index)
        if byte < 128 then visible_width = visible_width + 1; index = index + 1
        elseif byte < 224 then visible_width = visible_width + 1; index = index + 2
        elseif byte < 240 then visible_width = visible_width + 2; index = index + 3
        else visible_width = visible_width + 2; index = index + 4 end
    end
    return string.rep(' ', math.max(1, width - visible_width)) .. label
end

local function moghancement_names(value, lang)
    local ids, names = {}, {}
    if type(value) == 'table' then
        for _, child in pairs(value) do ids[#ids + 1] = tonumber(child) end
    elseif value ~= nil then
        for id_text in tostring(value):gmatch('%d+') do ids[#ids + 1] = tonumber(id_text) end
    end
    for _, id in ipairs(ids) do
        local key_item = id and resources.key_items and resources.key_items[id]
        names[#names + 1] = localized(key_item, lang) or ('ID ' .. tostring(id))
    end
    return names
end

local function build_tooltip(id, has_icon)
    local item = resource_item(id)
    if not item then return nil end
    local lang = config_ref.settings.lang or 'ja'
    local name = item[lang] or item.en or item.ja or ('Item ' .. id)
    local lines = {}

    local slots = bit_names(item.slots, slot_names[lang] or slot_names.en, 0)
    local race = table_count(item.races) == 8 and (lang == 'ja' and '全種' or 'All Races') or ''
    local flags = item_flags(item.flags)
    local suffix = table.concat(slots, '') .. race
    if flags ~= '' then suffix = suffix .. '  ' .. flags end
    lines[#lines + 1] = '\\cs(100,200,255)' .. name .. '\\cr  ' .. suffix

    local descriptions = resources.item_descriptions or {}
    local description = descriptions[id] and descriptions[id][lang]
    if description and description ~= '' then
        for line in (description .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    end

    if item.level then
        local jobs = bit_names(item.jobs, job_names[lang] or job_names.en, -1)
        local job_text = #jobs == 22 and 'All Jobs' or table.concat(jobs, ' ')
        lines[#lines + 1] = 'Lv' .. tostring(item.level) .. '～ ' .. job_text
    end
    if item.item_level and item.item_level > 0 then
        local label = '<ItemLevel:' .. tostring(item.item_level) .. '>'
        lines[#lines + 1] = right_aligned(label)
    end

    local furnishing = furnishings[id]
    if furnishing then
        local element_id = tonumber(furnishing.element)
        local element = element_id and resources.elements and resources.elements[element_id]
        local element_name = localized(element, lang) or tostring(furnishing.element or '?')
        local storage_label = lang == 'ja' and '収納' or 'Storage'
        lines[#lines + 1] = right_aligned('<' .. element_name .. ' '
            .. storage_label .. '+' .. tostring(furnishing.Storage or 0) .. '>')
    end
    lines[#lines + 1] = '----------------------------------------'
    if furnishing then
        local energy_label = lang == 'ja' and '属性力' or 'Elemental energy'
        local size_label = lang == 'ja' and 'サイズ' or 'Size'
        local placement_label = lang == 'ja' and '置き方' or 'Placement'
        lines[#lines + 1] = energy_label .. ': ' .. tostring(furnishing.ele_energy or '?')
        lines[#lines + 1] = size_label .. ': ' .. tostring(furnishing.size or '?')
        local placement = placements[tonumber(furnishing.Placement)]
        lines[#lines + 1] = placement_label .. ': '
            .. tostring(localized(placement, lang) or furnishing.Placement or '?')
        local mog_names = moghancement_names(furnishing.moghancements, lang)
        if #mog_names > 0 then lines[#lines + 1] = table.concat(mog_names, ', ') end
    end
    lines[#lines + 1] = 'ID: ' .. tostring(id)
    if has_icon then
        for index = 1, math.min(3, #lines) do lines[index] = '        ' .. lines[index] end
    else
        table.insert(lines, 1, '[No Image]')
    end
    return table.concat(lines, '\n')
end

local function render(target)
    local normal_color = config_ref.settings.item_name_color or '\\cs(120,255,160)'
    local hover_color = config_ref.settings.item_hover_color or '\\cs(255,220,80)'
    local size = target.size
    local output, line_data, occurrence = {}, {}, 0

    for line in (target.raw_text .. '\n'):gmatch('(.-)\n') do
        local parsed, search_start, line_width = '', 1, 0
        local current_color, items = '\\cr', {}
        while true do
            local start_pos, end_pos, marker = line:find('{item:([^}]+)}', search_start)
            if not start_pos then
                local remainder = line:sub(search_start)
                parsed = parsed .. remainder
                line_width = line_width + clean_width(remainder, size)
                break
            end
            local prefix = line:sub(search_start, start_pos - 1)
            for red, green, blue in prefix:gmatch('\\cs%((%d+),(%d+),(%d+)%)') do
                current_color = string.format('\\cs(%s,%s,%s)', red, green, blue)
            end
            if prefix:match('\\cr') then current_color = '\\cr' end
            parsed = parsed .. prefix
            line_width = line_width + clean_width(prefix, size)

            local lang = config_ref.settings.lang or 'ja'
            local numeric_marker, marker_style = marker:match('^(%d+):([%w_]+)$')
            local id = tonumber(numeric_marker or marker)
            local consumed = 0
            local candidate
            if marker == 'search' then
                local candidate_length
                candidate, candidate_length = search_candidate(line, end_pos, lang)
                id = candidate and resolve_item_name(candidate, lang) or nil
                consumed = candidate_length or 0
            end

            if not id or not resource_item(id) then
                -- Remove an unresolved search marker, but leave its visible text.
                -- Invalid numeric markers retain the old Item N diagnostic text.
                if marker == 'search' then
                    if candidate then
                        parsed = parsed .. candidate
                        line_width = line_width + clean_width(candidate, size)
                    end
                    search_start = end_pos + 1 + consumed
                else
                    local diagnostic = 'Item ' .. tostring(marker)
                    parsed = parsed .. diagnostic
                    line_width = line_width + clean_width(diagnostic, size)
                    search_start = end_pos + 1
                end
            else
            occurrence = occurrence + 1
            local key = target.key .. ':' .. occurrence .. ':' .. tostring(id)
            local item = resource_item(id)
            local name = item[lang] or item.en or item.ja or ('Item ' .. tostring(id))
            if consumed == 0 and line:sub(end_pos + 1, end_pos + #name) == name then
                consumed = #name
            end
            local name_width = clean_width(name, size)
            items[#items + 1] = {key=key, id=id, offset_x=line_width, width=name_width}
            local marker_color = marker_style == 'target_item'
                and (config_ref.settings.target_item_color or '\\cs(100,200,255)')
                or normal_color
            parsed = parsed .. (hovered_key == key and hover_color or marker_color) .. name .. current_color
            line_width = line_width + name_width
            search_start = end_pos + 1 + consumed
            end
        end
        output[#output + 1] = parsed
        line_data[#line_data + 1] = {width=line_width, items=items}
    end

    target.hud:text(table.concat(output, '\n'))
    local pos_x, pos_y = target.hud:pos()
    local _, extent_height = texts.extents(target.hud)
    local settings = windower.get_windower_settings()
    local current_y = pos_y
    local line_height = #line_data > 0 and (extent_height or 0) / #line_data or size * 1.2
    if line_height <= 0 then line_height = size * 1.2 end
    target.hitboxes = {}
    for _, data in ipairs(line_data) do
        local line_x = pos_x
        if target.right then
            local right_edge = settings and settings.ui_x_res + pos_x or pos_x
            line_x = right_edge - data.width
        end
        for _, item in ipairs(data.items) do
            target.hitboxes[#target.hitboxes + 1] = {
                key=item.key, id=item.id, x1=line_x + item.offset_x,
                x2=line_x + item.offset_x + item.width,
                y1=current_y, y2=current_y + line_height,
            }
        end
        current_y = current_y + line_height
    end
end

function item_hover.init(state, config)
    state_ref, config_ref = state, config
end

local function destroy_tooltip_layers()
    if tooltip then tooltip:destroy() end
    for _, background in ipairs(tooltip_backgrounds) do background:destroy() end
    tooltip, tooltip_backgrounds = nil, {}
end

local function tooltip_dimensions(text)
    local cfg = config_ref.settings.item_popup
    local font_size = cfg.font.size or 10
    local padding = cfg.padding or 0
    local width, line_count = 0, 0
    for line in (tostring(text or '') .. '\n'):gmatch('(.-)\n') do
        width = math.max(width, clean_width(line, font_size))
        line_count = line_count + 1
    end
    local min_width = cfg.min_width or 360
    local width_margin = cfg.width_margin or 80
    return math.max(min_width, width + padding * 2 + width_margin),
        math.max(1, line_count * font_size * 1.2 + padding * 2)
end

local function create_tooltip_background(text)
    local cfg = config_ref.settings.item_popup
    local width, height = tooltip_dimensions(text)
    local tile_path = windower.addon_path .. 'assets/tile.png'
    for offset = 0, height - 1, 32 do
        local strip_height = math.min(32, height - offset)
        local background = images.new({draggable=false, texture={fit=false}})
        background:path(tile_path)
        background:pos(cfg.pos.x or 0, (cfg.pos.y or 0) + offset)
        background:size(width, strip_height)
        background:alpha(210)
        background:show()
        tooltip_backgrounds[#tooltip_backgrounds + 1] = background
    end
end

local function create_tooltip_foreground(text)
    local cfg = config_ref.settings.item_popup
    tooltip = texts.new({
        pos = cfg.pos, padding = cfg.padding,
        text = {font='MS Gothic', size=cfg.font.size, stroke={width=1, alpha=255}},
        bg = {visible=false, alpha=0},
    })
    tooltip:text(text)
    tooltip:show()
    return tooltip
end

local function load_icon_extractor()
    if icon_extractor ~= nil then return icon_extractor or nil end
    icon_extractor = false
    local addon_dir = windower.addon_path:gsub('[\\/]+$', '')
    local addons_dir = addon_dir:match('^(.*[\\/])[^\\/]+$')
    if not addons_dir then return nil end
    local chunk = loadfile(addons_dir .. 'icons/icon_extractor.lua')
    if not chunk then return nil end
    local ok, extractor = pcall(chunk)
    if not ok or type(extractor) ~= 'table' then return nil end
    if extractor.ffxi_path then extractor.ffxi_path(windower.ffxi_path) end
    icon_extractor = extractor
    return extractor
end

local function get_icon_path(id)
    local cache_dir = windower.addon_path .. 'icons/'
    if windower.create_dir then pcall(windower.create_dir, cache_dir) end
    local path = cache_dir .. tostring(id) .. '.bmp'
    if not windower.file_exists(path) then
        local extractor = load_icon_extractor()
        if not extractor or not extractor.item_by_id then return nil end
        local ok = pcall(extractor.item_by_id, id, path)
        if not ok then return nil end
    end
    if not windower.file_exists(path) then return nil end
    return path
end

local function prepare_icon_path(id)
    if icon_image then icon_image:destroy(); icon_image = nil end
    return get_icon_path(id)
end

local function create_icon(path)
    if not path then return false end
    local ok, image = pcall(images.new, {draggable=false, texture={fit=false}})
    if not ok or not image then return false end
    icon_image = image
    icon_image:path(path)
    icon_image:size(32, 32)
    return true
end

local function source_bounds(target)
    if not target or not target.hud then return nil end
    local pos_x, pos_y = target.hud:pos()
    local width, height = texts.extents(target.hud)
    pos_x, pos_y = pos_x or 0, pos_y or 0
    width, height = width or 0, height or 0
    local settings = windower.get_windower_settings()
    if target.right and settings then
        pos_x = settings.ui_x_res + pos_x - width
    end
    return pos_x, pos_y, pos_x + width, pos_y + height
end

local function position_tooltip(target, mouse_y)
    if not tooltip then return end
    local settings = windower.get_windower_settings() or {}
    local screen_width = settings.ui_x_res or 1920
    local screen_height = settings.ui_y_res or 1080
    local width, height = tooltip_dimensions(tooltip:text())
    local cfg_pos = config_ref.settings.item_popup.pos or {}
    local popup_x = tonumber(cfg_pos.x) or 20
    local popup_y = tonumber(cfg_pos.y) or 120
    if popup_x <= 0 then popup_x = 20 end
    if popup_y <= 0 then popup_y = 120 end
    popup_x = math.max(0, math.min(popup_x, screen_width - width))
    popup_y = math.max(0, math.min(popup_y, screen_height - height))
    tooltip:pos(popup_x, popup_y)
    for index, background in ipairs(tooltip_backgrounds) do
        background:pos(popup_x, popup_y + (index - 1) * 32)
    end
    if icon_image then
        local padding = config_ref.settings.item_popup.padding or 0
        icon_image:pos(popup_x + padding + 6, popup_y + padding)
    end
end

local function sync_layout_preview_layers()
    if not layout_preview or not tooltip then return end
    local x, y = tooltip:pos()
    x, y = x or 0, y or 0
    for index, background in ipairs(tooltip_backgrounds) do
        background:pos(x, y + (index - 1) * 32)
    end
    if icon_image then
        local padding = config_ref.settings.item_popup.padding or 0
        icon_image:pos(x + padding + 6, y + padding)
    end
end

function item_hover.show_layout_preview()
    layout_preview = true
    destroy_tooltip_layers()
    if icon_image then icon_image:destroy(); icon_image = nil end
    local lang = config_ref.settings.lang or 'ja'
    local setup_unselected = state_ref.setup_active and not state_ref.setup_language_selected
    local text
    if setup_unselected then
        text = '[Item Details / アイテム詳細]\n'
            .. 'Hover over an item name in the objective details or list.\n'
            .. '目標の詳細や目標リストにあるアイテム名へマウスを重ねると、\n'
            .. 'ここにアイテムの説明が表示されます。\n'
            .. '------------------------------\n'
            .. 'Sample Item / サンプルアイテム\nID: 0000'
    elseif lang == 'ja' then
        text = '[アイテム詳細]\n'
            .. '目標の詳細や目標リストにあるアイテム名へマウスを重ねると、\n'
            .. 'ここにアイテムの説明が表示されます。\n'
            .. '------------------------------\n'
            .. 'サンプルアイテム\nID: 0000'
    else
        text = '[Item Details]\n'
            .. 'Hover over an item name in the objective details or list\n'
            .. 'to display its description here.\n'
            .. '------------------------------\n'
            .. 'Sample Item\nID: 0000'
    end
    create_tooltip_foreground(text)
    create_tooltip_background(text)
    tooltip:draggable(true)
    local pos = config_ref.settings.item_popup.pos or {}
    tooltip:pos(pos.x or 80, pos.y or 100)
    sync_layout_preview_layers()
end

function item_hover.refresh_layout_preview()
    if not layout_preview then return end
    local x, y = item_hover.get_layout_preview_pos()
    item_hover.show_layout_preview()
    tooltip:pos(x, y)
    sync_layout_preview_layers()
end

function item_hover.get_layout_preview_pos()
    if tooltip then
        local x, y = tooltip:pos()
        return x or 80, y or 100
    end
    local pos = config_ref.settings.item_popup.pos or {}
    return pos.x or 80, pos.y or 100
end

function item_hover.sync_layout_preview()
    sync_layout_preview_layers()
end

function item_hover.hide_layout_preview()
    layout_preview = false
    destroy_tooltip_layers()
    if icon_image then icon_image:destroy(); icon_image = nil end
end

function item_hover.set_text(hud, raw_text, options)
    options = options or {}
    local target = targets[options.key]
    if not target then
        target = {key=options.key, hud=hud}
        targets[options.key] = target
    end
    target.raw_text = tostring(raw_text or '')
    target.size = options.size or 10
    target.padding = options.padding or 0
    target.right = options.right == true
    render(target)
end

function item_hover.resolve_unique_item(name, lang)
    if type(name) ~= 'string' or name == '' then return nil end
    return resolve_item_name(name, lang or 'ja')
end

function item_hover.get_icon_path(id)
    return get_icon_path(tonumber(id))
end

function item_hover.handle_mouse(type, x, y)
    if layout_preview then
        sync_layout_preview_layers()
        return false
    end
    if type ~= 0 then return false end
    local next_key, next_id, next_target
    for _, target in pairs(targets) do
        if target.hud:visible() then
            for _, box in ipairs(target.hitboxes or {}) do
                if x >= box.x1 and x <= box.x2 and y >= box.y1 and y <= box.y2 then
                    next_key, next_id, next_target = box.key, box.id, target
                    break
                end
            end
        end
        if next_key then break end
    end

    if next_key ~= hovered_key then
        hovered_key, hovered_id, hovered_target = next_key, next_id, next_target
        for _, target in pairs(targets) do render(target) end
        if hovered_id then
            local icon_path = prepare_icon_path(hovered_id)
            local text = build_tooltip(hovered_id, icon_path ~= nil)
            if text then
                destroy_tooltip_layers()
                create_tooltip_foreground(text)
                -- Text primitives always render above image primitives. Build a
                -- solid image primitive for the panel, then the item icon above it.
                create_tooltip_background(text)
                -- Generate the image only after both text layers are complete.
                if create_icon(icon_path) then
                    icon_image:show()
                end
            end
        else
            if tooltip then tooltip:hide() end
            for _, background in ipairs(tooltip_backgrounds) do background:hide() end
            if icon_image then icon_image:hide() end
        end
    end
    if hovered_id and tooltip then position_tooltip(hovered_target, y) end
    return hovered_id ~= nil
end

function item_hover.hide()
    layout_preview = false
    hovered_key, hovered_id, hovered_target = nil, nil, nil
    if tooltip then tooltip:hide() end
    for _, background in ipairs(tooltip_backgrounds) do background:hide() end
    if icon_image then icon_image:hide() end
end

return item_hover
