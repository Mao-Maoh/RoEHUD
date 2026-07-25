-- ui/main_hud.lua
local texts = require('texts')
local db = require('database/Objectives')
local text_util = require('ui/text_util')
local resources = require('resources')
local item_hover = require('ui/item_hover')
local completion_history = require('services/completion_history')
local main_hud = {}
local state_ref, config_ref
local box

local function align_lines(lines, alignment)
    if alignment ~= 'right' then return table.concat(lines, '\n') end
    local widths, max_width = {}, 0
    for index, line in ipairs(lines) do
        local plain = tostring(line or '')
            :gsub('\\cs%([%d,]+%)', ''):gsub('\\cr', '')
        widths[index] = text_util.get_width(plain)
        if widths[index] > max_width then max_width = widths[index] end
    end
    local output = {}
    for index, line in ipairs(lines) do
        local padding = math.max(0, max_width - widths[index])
        output[index] = string.rep(' ', padding) .. line
    end
    return table.concat(output, '\n')
end

local function title_item_id(title, lang)
    if type(title) ~= 'string' then return nil end
    local pattern = lang == 'ja'
        and '^戦利品%(([^%)]+)%)(.*)$'
        or '^Spoils%s*%(([^%)]+)%)(.*)$'
    local name, remainder = title:match(pattern)
    if not name then return nil end
    if remainder and (remainder:find('(', 1, true) or remainder:find('（', 1, true)) then
        return nil
    end
    return item_hover.resolve_unique_item(name, lang)
end

local function resolve_item_tokens(value, lang, color, restore_color)
    if type(value) ~= 'string' then return value end
    value = value:gsub('{item:search}', '')
    value = value:gsub('{/item}', '')
    return value:gsub('{item:(%d+)[^}]*}', function(id_text)
        local item = resources.items and resources.items[tonumber(id_text)]
        local name = item and (item[lang] or item.en or item.ja) or ('{item:' .. id_text .. '}')
        if color then return color .. name .. (restore_color or '\\cr') end
        return name
    end)
end

local function mark_spoils_title(value, lang)
    if type(value) ~= 'string' or value:find('{item:', 1, true) then return value end
    if lang == 'ja' then
        return value:gsub('戦利品%(([^%)]+)%)', '戦利品({item:search}%1{/item})')
    end
    return value:gsub('Spoils%s*%(([^%)]+)%)', 'Spoils ({item:search}%1{/item})')
end

function main_hud.init(state, config)
    state_ref = state
    config_ref = config
    
    box = texts.new({
        pos = config.settings.main_hud.pos,
        text = { font = 'ＭＳ ゴシック', size = config.settings.main_hud.font.size or 10, stroke = { width = 2, alpha = 150, red = 0, green = 0, blue = 0 } },
        bg = { visible = false },
        padding = config.settings.main_hud.padding or 5,
        flags = { right = true, draggable = not config.settings.hud_locked }
    })
    box:text('Waiting for data...')
    box:hide()
end

function main_hud.show()
    if windower.ffxi.get_info().logged_in then
        box:show()
    end
end

function main_hud.hide()
    box:hide()
end

function main_hud.set_draggable(enabled)
    if box then box:draggable(enabled == true) end
end

function main_hud.get_pos()
    if not box then return 0, 0 end
    return box:pos()
end

function main_hud.set_pos(x, y)
    if box then box:pos(x, y) end
end

-- texts.extents()は描画フレーム後に確定するため、マウス判定時にも実寸から再計算する。
function main_hud.get_bounds()
    local pos_x, pos_y = box:pos()
    local width, total_height = texts.extents(box)
    pos_x, pos_y = pos_x or 0, pos_y or 0
    width, total_height = width or 0, total_height or 0

    local settings = windower.get_windower_settings()
    local abs_x = settings and (settings.ui_x_res + pos_x - width) or pos_x
    local bounds = state_ref.bounds.main_hud
    bounds.x1 = abs_x
    bounds.y1 = pos_y
    bounds.x2 = abs_x + width
    bounds.y2 = pos_y + total_height
    bounds.rows = {}

    local count = state_ref.setup_active and 0 or #state_ref.active_roes
    if count > 0 then
        local row_height = total_height / count
        local current_y = pos_y
        for _, roe in ipairs(state_ref.active_roes) do
            table.insert(bounds.rows, {
                id = roe.id,
                y1 = current_y,
                y2 = current_y + row_height,
            })
            current_y = current_y + row_height
        end
    end

    return bounds
end

function main_hud.update()
    box:size(config_ref.settings.main_hud.font.size or 10)
    if not windower.ffxi.get_info().logged_in or state_ref.is_hidden then 
        box:hide()
        return 
    end
    
    local lang = config_ref.settings.lang or 'ja'
    if state_ref.setup_active then
        local setup_unselected = not state_ref.setup_language_selected
        local lines
        if setup_unselected then
            lines = {
                '\\cs(255,230,150)[Objective List / 目標リスト]\\cr',
                'This HUD displays up to 31 active objectives.',
                '受領中の目標が最大31件表示されます。',
                '\\cs(255,230,150)Physical Damage / 物理ダメージ\\cr',
                '\\cs(180,240,255)8 / 20\\cr',
                '\\cs(255,230,150)Spoils (Rabbit Hide) / 戦利品（野兎の毛皮）\\cr',
                '\\cs(180,240,255)1 / 2\\cr',
                '\\cs(255,230,150)Vanquish Multiple Enemies / モンスター討伐数合計\\cr',
                '\\cs(180,240,255)12 / 30\\cr',
            }
        elseif lang == 'ja' then
            lines = {
                '\\cs(255,230,150)[目標リスト]\\cr',
                '受領中の目標が最大31件表示されます。',
                '\\cs(255,230,150)物理ダメージ\\cr',
                '\\cs(180,240,255)8 / 20\\cr',
                '\\cs(255,230,150)戦利品（野兎の毛皮）\\cr',
                '\\cs(180,240,255)1 / 2\\cr',
                '\\cs(255,230,150)モンスター討伐数合計\\cr',
                '\\cs(180,240,255)12 / 30\\cr',
            }
        else
            lines = {
                '\\cs(255,230,150)[Objective List]\\cr',
                'This HUD displays up to 31 active objectives.',
                '\\cs(255,230,150)Physical Damage\\cr',
                '\\cs(180,240,255)8 / 20\\cr',
                '\\cs(255,230,150)Spoils (Rabbit Hide)\\cr',
                '\\cs(180,240,255)1 / 2\\cr',
                '\\cs(255,230,150)Vanquish Multiple Enemies\\cr',
                '\\cs(180,240,255)12 / 30\\cr',
            }
        end
        local text = align_lines(lines, config_ref.settings.main_hud.alignment)
        state_ref.bounds.main_hud.rows = {}
        item_hover.set_text(box, text,
            {key='main', size=config_ref.settings.main_hud.font.size or 10,
                padding=config_ref.settings.main_hud.padding or 5, right=true})
        box:show()
        return
    end
    local display_settings = config_ref.settings.hud_display
    local raw_lines = {}

    for i, roe in ipairs(state_ref.active_roes) do
        local dd = db[roe.id]
        local name = dd and dd[lang]
        if name == '' then name = nil end

        local plain_title = name or ('Unknown Objective (ID: ' .. roe.id .. ')')
        local monthly = dd and ((type(dd.ja) == 'string' and dd.ja:find('%(M%)') ~= nil)
            or (type(dd.en) == 'string' and dd.en:find('%(M%)') ~= nil))
        local completed
        if monthly then
            completed = completion_history.is_current_complete(roe.id) == true
        else
            completed = state_ref.completed_roes and state_ref.completed_roes[roe.id] == true
        end
        if dd and dd.rpt == false and completed == true then
            plain_title = (lang == 'ja' and '[済] ' or '[Done] ') .. plain_title
        end
        local title = mark_spoils_title(plain_title, lang)
        if state_ref.hovered_roe_id == roe.id then
            title = '[[' .. title .. ']]'
        end

        local max_times = dd and dd.times or 999999
        local max_str = (max_times == 999999) and '?' or tostring(max_times)
        local current_prog = roe.prog or 0
        
        local prog_line_str = ""
        for _, item in ipairs(display_settings) do
            if item.key == 'title' then
                local display_title = title
                local title_line_str = item.color .. item.prefix .. display_title .. '\\cr'
                local clean_title = resolve_item_tokens(display_title, lang)
                    :gsub('\\cs%([%d,]+%)', ''):gsub('\\cr', '')
                table.insert(raw_lines, { text = title_line_str,
                    width = text_util.get_width(clean_title) })
            elseif item.key == '_default_prog' then
                local current_color = item.color
                if max_times ~= 999999 and current_prog > max_times then
                    current_color = config_ref.settings.invalid_progress_color or '\\cs(255,80,255)'
                elseif max_times ~= 999999 and current_prog == max_times then
                    current_color = config_ref.settings.inventory_full_color or '\\cs(255,100,100)'
                end
                prog_line_str = prog_line_str .. current_color .. item.prefix .. current_prog
                    .. '\\cr' .. item.color .. ' / ' .. max_str .. '\\cr'
            elseif item.key == 'target_item' and dd and tonumber(dd.target_item) then
                prog_line_str = prog_line_str .. item.prefix .. '{item:'
                    .. tostring(tonumber(dd.target_item)) .. ':target_item} ' .. '\\cr'
            elseif dd and dd[item.key] and dd[item.key] ~= '' then
                local val_str = tostring(dd[item.key])
                prog_line_str = prog_line_str .. item.color .. item.prefix .. val_str .. ' ' .. '\\cr'
            end
        end
        local clean_prog_str = resolve_item_tokens(prog_line_str, lang)
            :gsub('\\cs%([%d,]+%)', ''):gsub('\\cr', '')

        table.insert(raw_lines, { text = prog_line_str, width = text_util.get_width(clean_prog_str) })
    end

    if #raw_lines == 0 then
        state_ref.bounds.main_hud.rows = {}
        item_hover.set_text(box,
            '\\cs(255,230,150)[Eminence Tracker]\\cr\n\\cs(180,240,255)No Objectives Active\\cr',
            {key='main', size=config_ref.settings.main_hud.font.size or 10,
                padding=config_ref.settings.main_hud.padding or 5, right=true})
        box:show()
        return
    end

    local max_w = 0
    for _, line in ipairs(raw_lines) do
        if line.width > max_w then max_w = line.width end
    end

    local final_lines = {}
    for _, line in ipairs(raw_lines) do
        local pad = config_ref.settings.main_hud.alignment == 'left' and 0 or max_w - line.width
        local spaces = pad > 0 and string.rep(' ', pad) or ''
        table.insert(final_lines, spaces .. line.text)
    end
    
    item_hover.set_text(box, table.concat(final_lines, '\n'),
        {key='main', size=config_ref.settings.main_hud.font.size or 10,
            padding=config_ref.settings.main_hud.padding or 5, right=true})
    box:show()
    main_hud.get_bounds()
end

return main_hud
