-- config.lua
local file = require('files')
local json = require('json')
local config_manager = {}
local settings_file = file.new('settings.lua')

config_manager.settings = {
    main_hud = {
        pos = { x = -125, y = 45 },
        alignment = 'right',
        padding = 5,
		font = { size = 10 }
    },
    popup = {
        pos = { x = 145, y = 210 },
        padding = 5,
        font = { size = 10 },
        content_width = 40,
        repeat_labels = {
            repeatable = { ja = '<繰り返し可>', en = '<Repeatable>', color = '\\cs(150,255,150)' },
            not_repeatable = { ja = '<繰り返し不可>', en = '<Not repeatable>', color = '\\cs(255,140,200)' },
        },

        -- この配列の順番が、詳細HUD下段の表示順になる。
        -- 通常のObjectivesキーも { key='zone_id', ja='エリアID', en='Zone ID' } のように追加できる。
        extra_fields = {
            { key = 'category_id', ja = 'カテゴリー', en = 'Category' },
            { key = 'sub_category_id', ja = 'サブカテゴリー', en = 'Subcategory' },
            { key = 'first_time_reward_text', ja = '初回報酬', en = 'First reward' },
            -- { key = 'target', ja = '対象', en = 'Target' },
            -- { key = 'first_time_reward_item', ja = '初回報酬', en = 'First reward' },
        },

        unknown_keys = {
            enabled = true,
            title = { ja = '==== 未知のキー ====', en = '==== Unknown keys ====' },
            ignore = {
                --id = false, ja = true, en = true,
                overview_ja = true, overview_en = true,
                times = true, emi = true, exp = true, uni = true, rpt = true,
                category_id = true, sub_category_id = true,
            },
        },
    },
    lang = 'en',
    setup_completed = false,
    weather_history = {},
    font_size = 10,
    hud_locked = false,
    mouse = {
        scale_x = 1.0,
        scale_y = 1.0,
        offset_x = 0,
        offset_y = 0,
    },
    sound = {
        enabled = true,
        debug = false,
        complete = 'complete.wav',
        repeatable = 'repeat.wav',
        full = 'full.wav',
    },
    inventory_full_color = '\\cs(255,100,100)',
    invalid_progress_color = '\\cs(255,80,255)',
    item_name_color = '\\cs(120,255,160)',
    target_item_color = '\\cs(100,200,255)',
    item_hover_color = '\\cs(255,220,80)',
    item_popup = {
        pos = {x = 80, y = 100},
        padding = 8,
        font = {size = 10},
        content_width = 48,
        min_width = 360,
        width_margin = 80,
    },
    -- 各行の表示項目とカラー設定を一元管理するテーブル
    hud_display = {
        -- タイトル行の設定
        { key = 'title', prefix = '', color = '\\cs(255,230,150)' },	

        { key = 'target', prefix = '', color = '\\cs(150,255,150)' },
        { key = 'target_item', prefix = '', color = '\\cs(100,200,255)' },
        
        -- 最終的に進捗数値を描画するデフォルト設定
        { key = '_default_prog', prefix = '', color = '\\cs(180,240,255)' }

	}
}

local function merge_settings(defaults, saved)
    if type(saved) ~= 'table' then
        return defaults
    end

    for key, value in pairs(saved) do
        if type(value) == 'table' and type(defaults[key]) == 'table' then
            merge_settings(defaults[key], value)
        else
            defaults[key] = value
        end
    end
    return defaults
end

local function normalize_hud_display()
    local source = config_manager.settings.hud_display
    if type(source) ~= 'table' then source = {} end

    local target_item
    local default_progress
    for _, entry in ipairs(source) do
        if type(entry) == 'table' and entry.key == 'target_item' and not target_item then
            target_item = entry
        elseif type(entry) == 'table' and entry.key == '_default_prog' and not default_progress then
            default_progress = entry
        end
    end
    target_item = target_item
        or {key='target_item', prefix='', color='\\cs(100,200,255)'}
    default_progress = default_progress
        or {key='_default_prog', prefix='', color='\\cs(180,240,255)'}

    local normalized = {}
    local progress_inserted = false
    for _, entry in ipairs(source) do
        local key = type(entry) == 'table' and entry.key or nil
        if key == 'target_item' then
            -- Reinsert once immediately before the progress field.
        elseif key == '_default_prog' then
            if not progress_inserted then
                normalized[#normalized + 1] = target_item
                normalized[#normalized + 1] = default_progress
                progress_inserted = true
            end
        else
            normalized[#normalized + 1] = entry
        end
    end
    if not progress_inserted then
        normalized[#normalized + 1] = target_item
        normalized[#normalized + 1] = default_progress
    end
    config_manager.settings.hud_display = normalized
end

local function serialize(value, indent)
    indent = indent or 0
    local value_type = type(value)
    if value_type == 'string' then
        return string.format('%q', value)
    elseif value_type == 'number' or value_type == 'boolean' then
        return tostring(value)
    elseif value_type ~= 'table' then
        return 'nil'
    end

    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return tostring(a) < tostring(b)
        end
        return type(a) < type(b)
    end)

    local padding = string.rep(' ', indent)
    local child_padding = string.rep(' ', indent + 4)
    local lines = {'{'}
    for _, key in ipairs(keys) do
        table.insert(lines, child_padding .. '[' .. serialize(key) .. '] = '
            .. serialize(value[key], indent + 4) .. ',')
    end
    table.insert(lines, padding .. '}')
    return table.concat(lines, '\n')
end

function config_manager.init()
    config_manager.load()
end

function config_manager.load()
    if settings_file:exists() then
        local ok, data = pcall(dofile, windower.addon_path .. 'settings.lua')
        if ok and type(data) == 'table' then
            merge_settings(config_manager.settings, data)
        else
            windower.add_to_chat(167, '[RoEHUD] settings.lua could not be loaded; defaults are in use.')
        end
        normalize_hud_display()
        return
    end

    -- 初期版のJSON設定が存在する場合は一度だけ読み込み、次回保存時にsettings.luaへ移行する。
    local legacy_file = file.new('data/settings.json')
    if legacy_file:exists() then
        local data = json.read(legacy_file)
        if type(data) == 'table' then
            merge_settings(config_manager.settings, data)
        end
    end
    normalize_hud_display()
end

function config_manager.save()
    settings_file:write('return ' .. serialize(config_manager.settings) .. '\n')
end

return config_manager
