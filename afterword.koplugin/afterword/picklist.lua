-- The list on the What to read next / Pick next screen: KOReader's own Menu (title bar, page arrows, paging) with its rows drawn
-- here. A row is one of:
--
--   { kind = "picks", cards = { { heading, book, why, button, solid }, ... } }
--       up to two single picks side by side, each under its heading: a big cover, the details, a Start button
--   { kind = "lists", columns = { { heading, books, progress = bool }, ... } }
--       up to three groups side by side, each a heading over rows of a small cover, the title, the author and a quiet grey line
--       (which book of a series it is, how far through it you are, and a thin bar for what you are reading)
--
-- The covers of the picks are as big as the screen leaves room for, so the same layout fits portrait and landscape. A book is
-- { path, title, authors, series, series_index, percent, ... } as Suggest makes it. Tapping a book calls menu.on_open(book). Covers are
-- read from KOReader's book-info cache when a row is drawn, so only the page on screen costs anything.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local Suggest = require("afterword/suggest")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen
local GREY = Blitbuffer.COLOR_DARK_GRAY

local function s(n) return Screen:scaleBySize(n) end

local function face(size) return Font:getFace("cfont", size) end

local function line_height(f, bold)
    return TextWidget:new { text = "Ag", face = f, bold = bold }:getSize().h
end

-- Sizes for a list `width` wide. A cover is always two thirds as wide as it is tall.
local function dims(width)
    local d = { width = width, pad = s(22), col_gap = s(18), section_gap = s(14), thumb_gap = s(10), row_gap = s(8) }
    d.inner = width - 2 * d.pad
    d.card_w = math.floor((d.inner - d.col_gap) / 2) -- a pick's width
    d.col_w = math.floor((d.inner - 2 * d.col_gap) / 3) -- a list's width
    d.thumb_w = math.min(s(48), math.floor(d.col_w * 0.3)) -- a list's cover is the same size in portrait and landscape: the height is what is scarce
    d.thumb_h = math.floor(d.thumb_w * 1.5)
    d.text_w = d.col_w - d.thumb_w - d.thumb_gap
    d.f_title, d.f_author, d.f_meta, d.f_heading = face(12), face(11), face(11), face(14)
    d.lh_author, d.lh_meta = line_height(d.f_author), line_height(d.f_meta)
    d.lh_heading = line_height(d.f_heading, true)
    d.head_h = d.lh_heading + s(8) -- a heading and the space under it
    d.bar_h = s(3)
    return d
end

-- The cover of a book, in a box about w by h: the picture from KOReader's cache, or a plain box with the title when it has none.
local function cover(path, title, w, h)
    local image
    pcall(function()
        local BIM = require("bookinfomanager")
        local info = BIM:getBookInfo(path, true)
        if info and info.cover_bb then
            image = ImageWidget:new { image = info.cover_bb, width = w, height = h, scale_factor = 0 } -- fits the box; frees the picture itself
        end
    end)
    if image then
        return FrameContainer:new { bordersize = Size.border.thin, padding = 0, margin = 0, image }
    end
    -- No picture in the cache for this book: a soft grey card with its title in the middle, so a missing cover still looks like a book.
    local grey = Blitbuffer.COLOR_GRAY_E
    local limit = h - s(20)
    local text = TextBoxWidget:new { text = title or "?", face = face(13), bold = true, alignment = "center", width = w - s(20), bgcolor = grey }
    if text:getSize().h > limit then
        text:free()
        text = TextBoxWidget:new {
            text = title or "?", face = face(13), bold = true, alignment = "center", width = w - s(20), bgcolor = grey,
            height = limit, height_overflow_show_ellipsis = true,
        }
    end
    return FrameContainer:new {
        background = grey, bordersize = Size.border.thin, padding = 0, margin = 0,
        CenterContainer:new { dimen = Geom:new { w = w, h = h }, text },
    }
end

-- The grey line under a shelf book's author: which book of its series it is, and how far through it you are.
local function shelf_meta(book, progress)
    local parts = {}
    local number = tonumber(book.series_index)
    if book.series and book.series ~= "" and number then parts[#parts + 1] = string.format(_("Book %s"), string.format("%g", number)) end
    if progress and (tonumber(book.percent) or 0) > 0 then parts[#parts + 1] = string.format("%d%%", book.percent) end
    return #parts > 0 and table.concat(parts, " \u{00B7} ") or nil
end

local function button(text, solid)
    return FrameContainer:new {
        background = solid and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE, bordersize = Size.border.thin, radius = s(6),
        margin = 0, padding = s(5), padding_left = s(18), padding_right = s(18),
        TextWidget:new { text = text, face = face(14), bold = true, fgcolor = solid and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK },
    }
end

-- Text of at most `lines` lines: as tall as it needs, no taller, with an ellipsis when it was cut.
local function capped_text(text, f, width, lines, bold, fgcolor)
    local widget = TextBoxWidget:new { text = text, face = f, width = width, bold = bold, fgcolor = fgcolor }
    local one = TextBoxWidget:new { text = "Ag", face = f, width = width, bold = bold }
    local limit = lines * one:getSize().h -- a text box's own line height, which is not a single text widget's
    one:free()
    if widget:getSize().h > limit + 1 then
        widget:free()
        widget = TextBoxWidget:new { text = text, face = f, width = width, bold = bold, fgcolor = fgcolor, height = limit, height_overflow_show_ellipsis = true }
    end
    return widget
end

local PickRow = InputContainer:extend {}

local function authors_of(book) return book.authors and (tostring(book.authors):gsub("\n", ", ")) or "" end

function PickRow:init()
    local entry = self.entry
    self.ges_events = { TapSelect = { GestureRange:new { ges = "tap", range = self.dimen } } }
    local group = VerticalGroup:new { align = "left" }
    if not entry.at_top then group[#group + 1] = VerticalSpan:new { width = self.d.section_gap } end
    group[#group + 1] = entry.kind == "picks" and self:buildPicks() or self:buildLists()
    self[1] = LeftContainer:new { dimen = Geom:new { w = self.d.width, h = self.dimen.h }, group }
end

local function heading(text, d, width)
    return TextWidget:new { text = text, face = d.f_heading, bold = true, max_width = width, truncate_with_ellipsis = true }
end

-- A pick: the cover on the left, then the title, author, series, why it was picked, and a Start button at the bottom. What does not fit
-- beside the cover is left out, the least important first.
function PickRow:buildCard(card)
    local d = self.d
    local book = card.book
    local image = cover(book.path, book.title, d.pick_w, d.pick_h)
    local text_w = d.card_w - image:getSize().w - d.thumb_gap
    local btn = button(card.button or _("Start reading"), card.solid)
    local room = d.pick_h - btn:getSize().h - s(6)

    local function parts(why_lines, with_series)
        local list = { { capped_text(book.title or "?", Font:getFace("tfont", 16), text_w, 3, true), 0 } }
        local author = authors_of(book)
        if author ~= "" then list[#list + 1] = { TextWidget:new { text = author, face = face(13), max_width = text_w, truncate_with_ellipsis = true }, s(2) } end
        local series = with_series and Suggest.series_text(book)
        if series then list[#list + 1] = { TextWidget:new { text = series, face = face(11), fgcolor = GREY, max_width = text_w, truncate_with_ellipsis = true }, s(2) } end
        if why_lines > 0 and card.why and card.why ~= "" then list[#list + 1] = { capped_text(card.why, face(12), text_w, why_lines), s(6) } end
        local h = 0
        for _i, p in ipairs(list) do h = h + p[1]:getSize().h + p[2] end
        return list, h
    end
    local list, used
    for _i, try in ipairs({ { 4, true }, { 3, true }, { 2, true }, { 2, false }, { 1, false }, { 0, false } }) do
        list, used = parts(try[1], try[2])
        if used <= room then break end
    end
    local col = VerticalGroup:new { align = "left" }
    for _i, p in ipairs(list) do
        if p[2] > 0 then col[#col + 1] = VerticalSpan:new { width = p[2] } end
        col[#col + 1] = p[1]
    end
    col[#col + 1] = VerticalSpan:new { width = math.max(s(6), d.pick_h - used - btn:getSize().h) }
    col[#col + 1] = btn
    return VerticalGroup:new {
        align = "left",
        heading(card.heading, d, d.card_w),
        VerticalSpan:new { width = s(8) },
        HorizontalGroup:new { align = "top", image, HorizontalSpan:new { width = d.thumb_gap }, col },
    }
end

function PickRow:buildPicks()
    local d = self.d
    local row = HorizontalGroup:new { align = "top", HorizontalSpan:new { width = d.pad } }
    for i, card in ipairs(self.entry.cards) do
        local built = self:buildCard(card)
        row[#row + 1] = built
        if i < #self.entry.cards then row[#row + 1] = HorizontalSpan:new { width = d.card_w - built:getSize().w + d.col_gap } end
    end
    return row
end

-- What a list's text under a book is made of, top to bottom: the title (two lines at most), the author, a grey line, a thin bar.
local function list_text(book, progress, d)
    local col = VerticalGroup:new { align = "left" }
    col[#col + 1] = capped_text(book.title or "?", d.f_title, d.text_w, 2)
    local author = authors_of(book)
    if author ~= "" then col[#col + 1] = TextWidget:new { text = author, face = d.f_author, fgcolor = GREY, max_width = d.text_w, truncate_with_ellipsis = true } end
    local meta = shelf_meta(book, progress)
    if meta then col[#col + 1] = TextWidget:new { text = meta, face = d.f_meta, fgcolor = Blitbuffer.COLOR_GRAY_4, max_width = d.text_w, truncate_with_ellipsis = true } end
    if progress then
        local percent = math.max(0, math.min(100, tonumber(book.percent) or 0))
        col[#col + 1] = VerticalSpan:new { width = s(4) }
        col[#col + 1] = OverlapGroup:new {
            dimen = Geom:new { w = d.text_w, h = d.bar_h },
            LineWidget:new { dimen = Geom:new { w = d.text_w, h = d.bar_h }, background = Blitbuffer.COLOR_GRAY_D },
            LineWidget:new { dimen = Geom:new { w = math.max(1, math.floor(d.text_w * percent / 100)), h = d.bar_h }, background = Blitbuffer.COLOR_BLACK },
        }
    end
    return col
end

function PickRow:buildLists()
    local d, entry = self.d, self.entry
    local row = HorizontalGroup:new { align = "top", HorizontalSpan:new { width = d.pad } }
    for i, column in ipairs(entry.columns) do
        local col = VerticalGroup:new { align = "left" }
        col[#col + 1] = heading(column.heading, d, d.col_w)
        col[#col + 1] = VerticalSpan:new { width = s(8) }
        for _j, book in ipairs(column.books) do
            local text = list_text(book, column.progress, d)
            local top = math.max(0, math.floor((entry.row_h - text:getSize().h) / 2))
            local line = HorizontalGroup:new {
                align = "top",
                cover(book.path, book.title, d.thumb_w, d.thumb_h),
                HorizontalSpan:new { width = d.thumb_gap },
                VerticalGroup:new { align = "left", VerticalSpan:new { width = top }, text },
            }
            col[#col + 1] = line
            col[#col + 1] = VerticalSpan:new { width = math.max(0, entry.row_h - line:getSize().h) + d.row_gap }
        end
        row[#row + 1] = col
        if i < #entry.columns then row[#row + 1] = HorizontalSpan:new { width = d.col_gap } end
    end
    return row
end

function PickRow:onTapSelect(arg, ges)
    local entry, menu, d = self.entry, self.menu, self.d
    local x = ges.pos.x - self.dimen.x - d.pad
    if x < 0 then return true end
    if entry.kind == "picks" then
        local card = entry.cards[math.floor(x / (d.card_w + d.col_gap)) + 1]
        if card then menu.on_open(card.book) end
        return true
    end
    local column = entry.columns[math.floor(x / (d.col_w + d.col_gap)) + 1]
    local y = ges.pos.y - self.dimen.y - (entry.at_top and 0 or d.section_gap) - d.head_h
    local book = column and y >= 0 and column.books[math.floor(y / (entry.row_h + d.row_gap)) + 1]
    if book then menu.on_open(book) end
    return true
end

-- Focus handling the Menu expects of its rows (keys on a device without a touch screen); a row just takes it.
function PickRow:onFocus() return true end
function PickRow:onUnfocus() return true end
function PickRow:getFocusIndicatorRegion() return self.dimen end

local PickMenu = Menu:extend {}

-- How tall each row is, and which rows fit on which page: Menu's own rule, with this module's row heights. The picks take whatever
-- height the lists leave, so on one screen there is a big spotlight, and in landscape the same layout simply has a wider, shorter one.
function PickMenu:setupItemHeights()
    local d = dims(self.inner_dimen.w)
    self.dims = d
    -- how tall a book's row in a list needs to be: the tallest of any list's (every row in the screen shares it, so the columns line up)
    local row_h = d.thumb_h
    for _i, item in ipairs(self.item_table) do
        if item.kind == "lists" then
            for _j, column in ipairs(item.columns) do
                column.all = column.all or column.books
                for _k, book in ipairs(column.all) do
                    local text = list_text(book, column.progress, d)
                    row_h = math.max(row_h, text:getSize().h)
                    text:free()
                end
            end
        end
    end
    -- how many rows a list may have: the picks above need a cover worth looking at, so on a short (landscape) screen the lists are shorter
    local pick_min = s(140)
    local fit = math.floor((self.available_height - 2 * d.section_gap - 2 * d.head_h - pick_min - s(6) + d.row_gap) / (row_h + d.row_gap))
    local rows = math.max(2, fit)
    local first_lists
    for i, item in ipairs(self.item_table) do
        item.at_top = i == 1
        if item.kind == "lists" then
            local count = 0
            for _j, column in ipairs(item.columns) do
                column.books = {}
                for k = 1, math.min(rows, #column.all) do column.books[k] = column.all[k] end
                count = math.max(count, #column.books)
            end
            item.row_h = row_h
            item.body_h = d.head_h + count * (row_h + d.row_gap) - d.row_gap
            first_lists = first_lists or item
        end
    end
    -- the picks: as tall as is left after one row of lists on the same screen, and no wider than a pick's card has room for
    local fixed = first_lists and (d.section_gap + first_lists.body_h) or 0
    local want = self.available_height - fixed - d.section_gap - d.head_h - s(6)
    d.pick_h = math.max(s(96), math.min(want, math.floor(d.card_w * 0.5 * 1.5)))
    d.pick_w = math.floor(d.pick_h / 1.5)
    local function height(item)
        local top = item.at_top and 0 or d.section_gap
        if item.kind == "picks" then return top + d.head_h + d.pick_h end
        return top + item.body_h
    end
    self.page_items = {}
    local items, used = {}, 0
    for i, item in ipairs(self.item_table) do
        item.at_top = #items == 0
        item.height = height(item)
        if used + item.height > self.available_height and #items > 0 then
            table.insert(self.page_items, items)
            items, used = {}, 0
            item.at_top = true
            item.height = height(item)
        end
        table.insert(items, i)
        used = used + item.height
    end
    table.insert(self.page_items, items)
end

-- Menu:updateItems with this module's rows in place of MenuItem.
function PickMenu:updateItems(select_number, no_recalculate_dimen)
    local old_dimen = self.dimen and self.dimen:copy()
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    self:_recalculateDimen(no_recalculate_dimen)

    for idx, index in ipairs(self.page_items[self.page] or {}) do
        local item = self.item_table[index]
        item.idx = index
        if index == self.itemnumber then select_number = idx end
        local dimen = self.item_dimen:copy()
        dimen.h = item.height
        local row = PickRow:new { entry = item, menu = self, dimen = dimen, d = self.dims }
        table.insert(self.item_group, row)
        table.insert(self.layout, { row })
    end

    self:updatePageInfo(select_number)
    self:mergeTitleBarIntoLayout()
    UIManager:setDirty(self.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(self.dimen) or self.dimen
    end)
end


return PickMenu
