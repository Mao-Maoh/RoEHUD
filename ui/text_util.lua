-- ui/text_util.lua
local text_util = {}

-- 日本語（全角）と英語（半角）の文字幅を正しく計算する
function text_util.get_width(str)
    str = tostring(str or '')
    local width = 0
    local i = 1
    while i <= #str do
        local byte = string.byte(str, i)
        if not byte then
            break
        elseif byte < 128 then
            width = width + 1
            i = i + 1
        elseif byte < 224 then
            width = width + 1
            i = i + 2
        elseif byte < 240 then
            width = width + 2
            i = i + 3
        else
            width = width + 2
            i = i + 4
        end
    end
    return width
end

-- 指定された幅に合わせて、右側に空白を詰める（右揃え用）
function text_util.pad_right(str, total_width)
    local current_width = text_util.get_width(str)
    local needed = total_width - current_width
    if needed <= 0 then return str end
    return str .. string.rep(' ', needed)
end

-- 右側の数値をきれいに右揃えにするためのパディング
function text_util.format_row(title, progress_str, max_width)
    local title_w = text_util.get_width(title)
    local prog_w = text_util.get_width(progress_str)
    local space_needed = max_width - title_w - prog_w
    
    if space_needed < 1 then space_needed = 1 end
    return title .. string.rep(' ', space_needed) .. progress_str
end

return text_util
