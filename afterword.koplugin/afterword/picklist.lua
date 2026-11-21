-- The list on the What to read next / Pick next screen: KOReader's own Menu (title bar, page arrows, paging) with its rows drawn
-- here. A row is one of:
--
--   { heading = true, text }                          a group's name
--   { kind = "hero", book, why, button }              the first single pick: a big cover, the details, a Start reading button
--   { kind = "card", book, why, button }              any other single pick: a smaller cover and card
--   { kind = "shelf", books, progress = bool }        up to four covers across, each with its title, its author, and a quiet grey
--                                                     line (which book of a series it is, how far through it you are)
--
-- A book is { path, title, authors, series, series_index, percent, ... } as Suggest makes it. Tapping a book calls menu.on_detail(book);
-- the Start buttons call menu.on_open(book). Covers are read from KOReader's book-info cache when a row is drawn, so only the page on
-- screen costs anything.
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
local SHELF = 4 -- covers across a shelf

local function s(n) return Screen:scaleBySize(n) end

local function face(size) return Font:getFace("cfont", size) end

local function line_height(f, bold)
    return TextWidget:new { text = "Ag", face = f, bold = bold }:getSize().h
end

-- Sizes for a list `width` wide. A cover is always two thirds as wide as it is tall.
local function dims(width, font_size)
    local d = { width = width, pad = s(22), gap = s(14), vgap = s(8), caption_gap = s(8) }
    d.shelf_w = math.floor(width * 0.19)
    d.shelf_gap = math.floor((width - 2 * d.pad - SHELF * (d.shelf_w + 2 * Size.border.thin)) / (SHELF - 1)) -- the rest of the width, between the covers
    d.shelf_h = math.floor(d.shelf_w * 1.5)
    d.hero_w = math.floor(width * 0.27)
    d.hero_h = math.floor(d.hero_w * 1.5)
    d.card_w = math.floor(width * 0.15)
    d.card_h = math.floor(d.card_w * 1.5)
    d.f_title = face(12)
    d.f_author = face(11)
    d.f_meta = face(11)
    d.f_heading = face(14)
    d.lh_title, d.lh_author, d.lh_meta = line_height(d.f_title), line_height(d.f_author), line_height(d.f_meta)
    d.lh_heading = line_height(d.f_heading, true)
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

-- Genre pills side by side, as many as fit in `max_width` (up to `limit`).
local function chips(tags, max_width, limit)
    local row = HorizontalGroup:new { align = "center" }
    local used = 0
    for i, tag in ipairs(tags or {}) do
        if i > (limit or 3) then break end
        local pill = FrameContainer:new {
            bordersize = Size.border.thin, radius = s(10), margin = 0, padding = s(2), padding_left = s(8), padding_right = s(8),
            TextWidget:new { text = tag, face = face(12) },
        }
        local w = pill:getSize().w + s(6)
        if used + w > max_width then break end
        row[#row + 1] = pill
        row[#row + 1] = HorizontalSpan:new { width = s(6) }
        used = used + w
    end
    return #row > 0 and row or nil
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

function PickRow:init()
    local entry = self.entry
    self.ges_events = { TapSelect = { GestureRange:new { ges = "tap", range = self.dimen } } }
    if entry.heading then return self:buildHeading() end
    if entry.kind == "shelf" then return self:buildShelf() end
    return self:buildCard()
end

function PickRow:buildHeading()
    local entry, d = self.entry, self.d
    local name = TextWidget:new { text = entry.text, face = d.f_heading, bold = true, max_width = d.width - 2 * d.pad, truncate_with_ellipsis = true }
    self[1] = VerticalGroup:new {
        align = "left",
        VerticalSpan:new { width = entry.at_top and 0 or d.heading_gap },
        HorizontalGroup:new { HorizontalSpan:new { width = d.pad }, name },
    }
end

-- A hero or a compact card: the cover on the left, the details on the right, and a Start button at the bottom of them. What does not
-- fit beside the cover is left out, the least important first: the description, then the tags, then the series.
function PickRow:buildCard()
    local entry, d = self.entry, self.d
    local book, hero = entry.book, entry.kind == "hero"
    local cw, ch = hero and d.hero_w or d.card_w, hero and d.hero_h or d.card_h
    local image = cover(book.path, book.title, cw, ch)
    local text_w = d.width - 2 * d.pad - image:getSize().w - d.gap
    local btn = button(entry.button or _("Start reading"), hero)
    self.start_button = btn
    local room = ch - btn:getSize().h - s(8) -- what the details may use above the button

    local parts = {} -- { key, widget, gap } in the order shown
    local title_face = Font:getFace("tfont", hero and 22 or 17)
    parts[#parts + 1] = { "title", capped_text(book.title or "?", title_face, text_w, 2, true), 0 }
    if book.authors and book.authors ~= "" then
        parts[#parts + 1] = { "author", TextWidget:new { text = (tostring(book.authors):gsub("\n", ", ")), face = face(hero and 16 or 14), max_width = text_w, truncate_with_ellipsis = true }, s(2) }
    end
    local series = Suggest.series_text(book)
    if series then
        parts[#parts + 1] = { "series", TextWidget:new { text = series, face = face(hero and 14 or 12), fgcolor = GREY, max_width = text_w, truncate_with_ellipsis = true }, s(2) }
    end
    if hero then
        local pills = chips(book.tags, text_w, 3)
        if pills then parts[#parts + 1] = { "chips", pills, s(6) } end
    end
    if entry.why and entry.why ~= "" then
        parts[#parts + 1] = { "why", capped_text(entry.why, face(hero and 14 or 13), text_w, 2), s(6) }
    end
    if hero and book.description and book.description ~= "" then
        local plain = require("util").htmlToPlainTextIfHtml(book.description):gsub("%s+", " ")
        parts[#parts + 1] = { "description", capped_text(plain, face(13), text_w, 2, false, GREY), s(6) }
    end

    local function total()
        local h = 0
        for _i, part in ipairs(parts) do h = h + part[2]:getSize().h + part[3] end
        return h
    end
    for _i, key in ipairs({ "description", "chips", "series" }) do
        if total() <= room then break end
        for i, part in ipairs(parts) do
            if part[1] == key then table.remove(parts, i); break end
        end
    end

    local col = VerticalGroup:new { align = "left" }
    local used = 0
    for _i, part in ipairs(parts) do
        if part[3] > 0 then col[#col + 1] = VerticalSpan:new { width = part[3] } end
        col[#col + 1] = part[2]
        used = used + part[2]:getSize().h + part[3]
    end
    col[#col + 1] = VerticalSpan:new { width = math.max(s(6), ch - used - btn:getSize().h) }
    col[#col + 1] = btn
    local row = HorizontalGroup:new { align = "top", HorizontalSpan:new { width = d.pad }, image, HorizontalSpan:new { width = d.gap }, col }
    self[1] = LeftContainer:new { dimen = Geom:new { w = d.width, h = self.dimen.h }, row }
end

-- Up to four covers across, each over its title, its author and a quiet grey line. The titles are as tall as they need to be, and the
-- authors line up across the row.
function PickRow:buildShelf()
    local entry, d = self.entry, self.d
    local row = HorizontalGroup:new { align = "top", HorizontalSpan:new { width = d.pad } }
    for i, book in ipairs(entry.books) do
        local cell = VerticalGroup:new { align = "left" }
        cell[#cell + 1] = cover(book.path, book.title, d.shelf_w, d.shelf_h)
        if entry.progress then
            local percent = math.max(0, math.min(100, tonumber(book.percent) or 0))
            local bar_w, bar_h = d.shelf_w, s(3)
            cell[#cell + 1] = VerticalSpan:new { width = s(6) }
            cell[#cell + 1] = OverlapGroup:new {
                dimen = Geom:new { w = bar_w, h = bar_h },
                LineWidget:new { dimen = Geom:new { w = bar_w, h = bar_h }, background = Blitbuffer.COLOR_GRAY_D },
                LineWidget:new { dimen = Geom:new { w = math.max(1, math.floor(bar_w * percent / 100)), h = bar_h }, background = Blitbuffer.COLOR_BLACK },
            }
        end
        cell[#cell + 1] = VerticalSpan:new { width = d.caption_gap }
        local title = capped_text(book.title or "?", d.f_title, d.shelf_w, 2)
        cell[#cell + 1] = title
        local author = book.authors and tostring(book.authors):gsub("\n", ", ") or ""
        if author ~= "" then
            cell[#cell + 1] = TextWidget:new { text = author, face = d.f_author, fgcolor = GREY, max_width = d.shelf_w, truncate_with_ellipsis = true }
        end
        local meta = shelf_meta(book, entry.progress)
        if meta then
            cell[#cell + 1] = TextWidget:new { text = meta, face = d.f_meta, fgcolor = Blitbuffer.COLOR_GRAY_4, max_width = d.shelf_w, truncate_with_ellipsis = true }
        end
        row[#row + 1] = cell
        if i < #entry.books then row[#row + 1] = HorizontalSpan:new { width = d.shelf_gap } end
    end
    self[1] = LeftContainer:new { dimen = Geom:new { w = d.width, h = self.dimen.h }, row }
end

function PickRow:onTapSelect(arg, ges)
    local entry, menu, d = self.entry, self.menu, self.d
    if entry.heading then return true end
    if entry.kind == "shelf" then
        local x = ges.pos.x - self.dimen.x - d.pad
        local index = math.floor(x / (d.shelf_w + d.shelf_gap)) + 1
        local book = entry.books[math.max(1, math.min(index, #entry.books))]
        if x >= 0 and book then menu.on_detail(book) end
        return true
    end
    local btn = self.start_button
    if btn and btn.dimen and ges.pos:intersectWith(btn.dimen) then
        menu.on_open(entry.book)
    else
        menu.on_detail(entry.book)
    end
    return true
end

-- Focus handling the Menu expects of its rows (keys on a device without a touch screen); a row just takes it.
function PickRow:onFocus() return true end
function PickRow:onUnfocus() return true end
function PickRow:getFocusIndicatorRegion() return self.dimen end

local PickMenu = Menu:extend {}

-- How tall each row is, and which rows fit on which page: Menu's own rule, with this module's row heights.
function PickMenu:setupItemHeights()
    local d = dims(self.inner_dimen.w, self.font_size)
    d.heading_gap = math.floor(d.lh_heading * 1.1) -- white space above a group's name, except at the top of a page
    self.dims = d
    -- A shelf's captions stack with no gaps: each book takes only the lines it has, and the row is as tall as its tallest caption.
    local function measure_shelf(item)
        if item.measured_width == d.shelf_w then return end
        local tallest = 0
        for _i, book in ipairs(item.books) do
            local title = capped_text(book.title or "?", d.f_title, d.shelf_w, 2)
            local h = title:getSize().h
            title:free()
            local author = book.authors and tostring(book.authors):gsub("\n", ", ") or ""
            if author ~= "" then h = h + d.lh_author end
            if shelf_meta(book, item.progress) then h = h + d.lh_meta end
            tallest = math.max(tallest, h)
        end
        item.caption_h, item.measured_width = tallest, d.shelf_w
    end
    local function height(item, at_top)
        if item.heading then
            item.at_top = at_top
            return d.lh_heading + s(8) + (at_top and 0 or d.heading_gap)
        elseif item.kind == "hero" then
            return d.hero_h + 2 * d.vgap
        elseif item.kind == "card" then
            return d.card_h + 2 * d.vgap
        end
        -- a shelf: the covers, then (for what you are reading) a thin bar, then the title, the author and a grey line
        measure_shelf(item)
        local bar = item.progress and (s(6) + s(3)) or 0
        return d.vgap + d.shelf_h + bar + d.caption_gap + item.caption_h + d.vgap
    end
    self.page_items = {}
    local items, used = {}, 0
    for i, item in ipairs(self.item_table) do
        item.height = height(item, i == 1)
        if used + item.height <= self.available_height then
            table.insert(items, i)
            used = used + item.height
        else
            -- a group's name is never left at the bottom of a page, away from its books
            local last = items[#items]
            local carry = last and self.item_table[last].heading and table.remove(items) or nil
            table.insert(self.page_items, items)
            items, used = {}, 0
            if carry then
                self.item_table[carry].height = height(self.item_table[carry], true)
                table.insert(items, carry)
                used = self.item_table[carry].height
            end
            item.height = height(item, #items == 0) -- a heading that starts a page needs no gap above
            table.insert(items, i)
            used = used + item.height
        end
        if i == #self.item_table then table.insert(self.page_items, items) end
    end
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

-- Pieces the detail sheet shares with the list, so the two look alike.
PickMenu.cover = cover
PickMenu.chips = chips
PickMenu.button = button

return PickMenu
