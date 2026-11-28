-- The Preferences screens: everything the person told Afterword not to suggest, in one place. An overview (a row per kind, however much is
-- in it) opens a screen per kind: books, snoozed books, authors and series (to select and bring back, or to add), the rows of the list
-- (switches) and the collections (Normal, Suggest from, Skip). They are KOReader's Menu again, as picklist.lua is, with rows of their own,
-- the plugin's header (a back arrow below the first screen) and ShelfSpace's way of selecting: a checkbox on every row, a Select all line, and
-- a bar that floats at the bottom with the count and what to do.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Exclusions = require("afterword/exclusions")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Header = require("afterword/header")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local PickMenu = require("afterword/picklist")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local Store = require("afterword/store")
local Suggest = require("afterword/suggest")
local Wanted = require("afterword/wanted")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local H = PickMenu.helpers
local s, face = H.s, H.face
local WHITE, BLACK, GREY = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK, H.GREY
local COLLECTION = "afterword_collection"

local Prefs = {}

-- The rows of the list a person can hide, in the order they are shown, with the name each is known by in suggest.lua.
Prefs.ROWS = {
    { "next_in_series", _("Next in the series") }, { "picked_for_you", _("Picked for you") },
    { "something_different", _("Something different") }, { "started", _("Keep reading") },
    { "more_by_author", _("More by this author") }, { "collection", _("From your collection") },
    { "recently_added", _("Recently added") }, { "on_hold", _("On hold") }, { "want_to_read", _("Want to read") },
}

local function exclusions() return Exclusions.new(G_reader_settings) end

-- The library, as far as these screens need it: titles, authors and how many books each author and series has.
local function library()
    local lib = { books = {}, by_path = {}, authors = {}, series = {} }
    pcall(function()
        local BIM = require("bookinfomanager")
        BIM:openDbConnection()
        lib.books = Store.books(BIM.db_conn)
    end)
    for _i, r in ipairs(lib.books) do
        lib.by_path[r.path] = r
        for name in tostring(r.authors or ""):gmatch("[^\n]+") do
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then lib.authors[name] = (lib.authors[name] or 0) + 1 end
        end
        if r.series and r.series ~= "" then lib.series[r.series] = (lib.series[r.series] or 0) + 1 end
    end
    return lib
end

local function title_of(lib, path)
    local r = lib.by_path[path]
    return r and r.title or path:match("([^/]+)%.%w+$") or path
end

local function sorted_by(list, key)
    table.sort(list, function(a, b) return tostring(a[key]):lower() < tostring(b[key]):lower() end)
    return list
end

local function days_until(time) return math.max(1, math.ceil((time - os.time()) / Exclusions.DAY)) end

local function plural(n, one, many) return T(n == 1 and one or many, n) end

-- ----------------------------------------------------------------------------------------------------------------------------------------
-- Pieces of a row

local function text(str, size, bold, color, max_w)
    return TextWidget:new { text = str, face = bold and Font:getFace("tfont", size) or face(size), bold = false, fgcolor = color or BLACK, max_width = max_w, truncate_with_ellipsis = true }
end

local function box(w, h) return OverlapGroup:new { dimen = Geom:new { w = w, h = h } } end

-- state: "on", "off" or "some" (the Select all line, when only some rows are ticked)
local function checkbox(state)
    local d = s(28)
    local glyph = state == "on" and "\u{2713}" or state == "some" and "\u{2013}" or nil
    local inner = CenterContainer:new { dimen = Geom:new { w = d, h = d },
        glyph and TextWidget:new { text = glyph, face = Font:getFace("tfont", 20), bold = true, fgcolor = WHITE } or box(0, 0) }
    return FrameContainer:new { background = state == "off" and WHITE or Header.accent(), bordersize = Size.border.default, radius = s(5), padding = 0, margin = 0, inner }
end

local function switch(on)
    local w, h, k = s(56), s(30), s(24)
    local knob = FrameContainer:new { background = on and WHITE or BLACK, bordersize = 0, radius = math.floor(k / 2), padding = 0, margin = 0, box(k, k) }
    local track = FrameContainer:new { background = on and Header.accent() or WHITE, bordersize = Size.border.default, radius = math.floor(h / 2),
        padding = 0, margin = 0, bordercolor = BLACK,
        HorizontalGroup:new { align = "center", HorizontalSpan:new { width = on and (w - k - s(6)) or s(2) }, knob, HorizontalSpan:new { width = on and s(2) or (w - k - s(6)) } } }
    return CenterContainer:new { dimen = Geom:new { w = w + s(4), h = h + s(4) }, track }
end

local function segmented(labels, chosen, widths)
    local row = HorizontalGroup:new {}
    for i, label in ipairs(labels) do
        local on = i == chosen
        row[#row + 1] = FrameContainer:new { background = on and Header.accent() or WHITE, bordersize = Size.border.thin, radius = 0, padding = 0, margin = 0,
            CenterContainer:new { dimen = Geom:new { w = widths[i], h = s(36) },
                TextWidget:new { text = label, face = face(12), bold = on, fgcolor = on and WHITE or BLACK } } }
    end
    return row
end

local function pill_button(label, solid)
    return FrameContainer:new { background = solid and WHITE or BLACK, bordersize = Size.border.thin, radius = s(18),
        bordercolor = WHITE, padding = s(5), padding_left = s(16), padding_right = s(16), margin = 0,
        TextWidget:new { text = label, face = Font:getFace("tfont", 14), fgcolor = solid and BLACK or WHITE } }
end

-- ShelfSpace's floating bar: a dark pill with the count and its buttons. Returns the bar and the buttons' widgets, for the menu to pass taps to.
local function floating_bar(label, buttons)
    local row = HorizontalGroup:new { align = "center", TextWidget:new { text = label, face = Font:getFace("tfont", 14), fgcolor = WHITE } }
    local hits = {}
    for _i, b in ipairs(buttons) do
        row[#row + 1] = HorizontalSpan:new { width = s(12) }
        local widget = pill_button(b.text, b.solid)
        row[#row + 1] = widget
        hits[#hits + 1] = { widget = widget, callback = b.callback }
    end
    local pad = s(8)
    local bar = FrameContainer:new { background = BLACK, bordersize = 0, margin = 0, padding = pad, padding_left = s(20),
        radius = math.floor((row:getSize().h + 2 * pad) / 2), row }
    return bar, hits
end

-- ----------------------------------------------------------------------------------------------------------------------------------------
-- Rows

local HEIGHT = {
    lead = 74, summary = 74, strip = 120, heading = 54, filter = 64, selectall = 54, item = 66, cover_item = 84, toggle = 62,
    segment = 88, message = 250, plain = 62, button = 66, spacer = 80, hint = 44,
    tabs = 64, listing = 76, pair = 76, note = 44,
}

local function row_height(entry) return s(entry.height or HEIGHT[entry.kind] or 60) end

-- The width of each tab of a row of tabs, the same for drawing and for finding which one was tapped.
local function tab_widths(labels)
    local widths = {}
    for i, label in ipairs(labels) do
        local widget = TextWidget:new { text = label, face = face(13), bold = true }
        widths[i] = widget:getSize().w + s(28)
        widget:free()
    end
    return widths
end
local TAB_GAP = 8

-- The widget for an entry, `w` wide. Taps are answered by entry.on_tap(x), x being across the row.
local function build(entry, w, state)
    local pad = s(22)
    local inner = w - 2 * pad
    local k = entry.kind
    local function left(widget) return HorizontalGroup:new { align = "center", HorizontalSpan:new { width = pad }, widget } end
    local function right_of(widget, h) return RightContainer:new { dimen = Geom:new { w = w - pad, h = h }, widget } end
    local h = entry.px or row_height(entry)
    local function over(...) return OverlapGroup:new { dimen = Geom:new { w = w, h = h }, ... } end
    if k == "lead" then
        local col = VerticalGroup:new { align = "left", text(entry.text, 19, true), VerticalSpan:new { width = s(2) }, text(entry.sub or "", 12, false, GREY, inner) }
        return left(col)
    elseif k == "summary" then
        local col = VerticalGroup:new { align = "left", text(entry.text, 18, true, BLACK, inner - s(120)) }
        if entry.strip then
            local strip = HorizontalGroup:new { align = "center" }
            for _i, book in ipairs(entry.strip) do
                strip[#strip + 1] = H.cover(book.path, book.title, s(44), s(66))
                strip[#strip + 1] = HorizontalSpan:new { width = s(8) }
            end
            if entry.more and entry.more > 0 then strip[#strip + 1] = text(T(_("+ %1 more"), entry.more), 13, true) end
            col[#col + 1] = VerticalSpan:new { width = s(8) }
            col[#col + 1] = strip
        elseif entry.sub then
            col[#col + 1] = VerticalSpan:new { width = s(2) }
            col[#col + 1] = text(entry.sub, 12, false, GREY, inner)
        end
        local count = HorizontalGroup:new { align = "center", text(entry.count or "", 17, true), HorizontalSpan:new { width = s(8) },
            TextWidget:new { text = "\u{203A}", face = Font:getFace("tfont", 24), fgcolor = Blitbuffer.COLOR_GRAY_4 } }
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, left(col) },
            RightContainer:new { dimen = Geom:new { w = w - pad, h = h }, count })
    elseif k == "heading" then
        local parts = { LeftContainer:new { dimen = Geom:new { w = w, h = h }, left(text(entry.text, 19, true, BLACK, inner - s(150))) } }
        if entry.action then parts[#parts + 1] = right_of(text(entry.action, 14, true), h) end
        return over(table.unpack(parts))
    elseif k == "filter" then
        local label = text(entry.text, 14, false, entry.active and BLACK or GREY, inner - s(40))
        local frame = FrameContainer:new { bordersize = Size.border.default, radius = s(8), padding = s(8), padding_left = s(14), margin = 0, background = WHITE,
            HorizontalGroup:new { label, HorizontalSpan:new { width = math.max(0, inner - s(44) - label:getSize().w) } } }
        return left(frame)
    elseif k == "button" then
        local frame = FrameContainer:new { bordersize = Size.border.default, radius = s(8), padding = s(10), margin = 0, background = WHITE,
            CenterContainer:new { dimen = Geom:new { w = inner - s(20), h = s(26) }, text(entry.text, 14, true) } }
        return left(frame)
    elseif k == "selectall" then
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, left(text(entry.text, 14, true)) }, right_of(checkbox(entry.state), h))
    elseif k == "item" then
        local x = pad
        local parts = HorizontalGroup:new { align = "center", HorizontalSpan:new { width = pad } }
        local text_w = inner - s(28) - s(40)
        if entry.cover then
            local c = H.cover(entry.cover, entry.text, s(40), s(60))
            parts[#parts + 1] = c
            parts[#parts + 1] = HorizontalSpan:new { width = s(14) }
            text_w = text_w - s(54)
        end
        local col = VerticalGroup:new { align = "left", text(entry.text, 16, true, BLACK, text_w) }
        if entry.sub then col[#col + 1] = text(entry.sub, 12, false, GREY, text_w) end
        parts[#parts + 1] = col
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, parts }, right_of(checkbox(entry.checked and "on" or "off"), h))
    elseif k == "toggle" then
        local col = VerticalGroup:new { align = "left", text(entry.text, 16, true, BLACK, inner - s(90)) }
        if entry.sub then col[#col + 1] = text(entry.sub, 12, false, GREY, inner - s(90)) end
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, left(col) }, right_of(switch(entry.on), h))
    elseif k == "segment" then
        local widths = { s(66), s(100), s(52) }
        local col = VerticalGroup:new { align = "left", text(entry.text, 16, true, BLACK, w - 2 * pad - s(230)) }
        if entry.sub then col[#col + 1] = text(entry.sub, 12, false, GREY, w - 2 * pad - s(230)) end
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, left(col) },
            right_of(segmented({ _("Normal"), _("Suggest from"), _("Skip") }, entry.chosen, widths), h))
    elseif k == "plain" then
        local value = HorizontalGroup:new { align = "center", text(entry.value or "", 15), HorizontalSpan:new { width = s(8) },
            TextWidget:new { text = "\u{203A}", face = Font:getFace("tfont", 24), fgcolor = Blitbuffer.COLOR_GRAY_4 } }
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, left(text(entry.text, 16, true)) }, right_of(value, h))
    elseif k == "message" then
        local col = VerticalGroup:new { align = "center" }
        for i, line in ipairs(entry.lines) do
            col[#col + 1] = text(line[1], line[2] or 14, line[3], line[4] or BLACK, inner)
            col[#col + 1] = VerticalSpan:new { width = s(8) }
        end
        return CenterContainer:new { dimen = Geom:new { w = w, h = h }, col }
    elseif k == "tabs" then
        local widths = tab_widths(entry.labels)
        local row = HorizontalGroup:new { align = "center", HorizontalSpan:new { width = pad } }
        for i, label in ipairs(entry.labels) do
            local on = i == entry.chosen
            row[#row + 1] = FrameContainer:new { background = on and Header.accent() or WHITE, bordersize = Size.border.thin, radius = s(16), padding = 0, margin = 0,
                CenterContainer:new { dimen = Geom:new { w = widths[i], h = s(32) },
                    TextWidget:new { text = label, face = face(13), bold = on, fgcolor = on and WHITE or BLACK } } }
            row[#row + 1] = HorizontalSpan:new { width = s(TAB_GAP) }
        end
        return row
    elseif k == "listing" then
        local parts = HorizontalGroup:new { align = "center", HorizontalSpan:new { width = pad } }
        parts[#parts + 1] = H.cover(entry.cover, entry.text, s(40), s(60)) -- no cover for a book that is not on the device: an empty frame
        parts[#parts + 1] = HorizontalSpan:new { width = s(14) }
        local text_w = inner - s(54) - s(110)
        local col = VerticalGroup:new { align = "left", text(entry.text, 16, true, BLACK, text_w) }
        if entry.sub then col[#col + 1] = text(entry.sub, 12, false, GREY, text_w) end
        parts[#parts + 1] = col
        local side = VerticalGroup:new { align = "right", text(entry.marks or "", 12, true), text(entry.status or "", 11, false, GREY) }
        return over(LeftContainer:new { dimen = Geom:new { w = w, h = h }, parts }, right_of(side, h))
    elseif k == "pair" then
        local half = math.floor((inner - s(12)) / 2)
        local function button(label)
            return FrameContainer:new { bordersize = Size.border.default, radius = s(8), padding = s(10), margin = 0, background = WHITE,
                CenterContainer:new { dimen = Geom:new { w = half - s(20), h = s(26) }, text(label, 14, true) } }
        end
        return left(HorizontalGroup:new { button(entry.first), HorizontalSpan:new { width = s(12) }, button(entry.second) })
    elseif k == "note" then
        return left(text(entry.text, 12, false, GREY, inner))
    elseif k == "hint" then
        return CenterContainer:new { dimen = Geom:new { w = w, h = h }, text(entry.text, 12, false, GREY, inner) }
    end
    return box(w, h)
end

local PrefRow = InputContainer:extend {}

function PrefRow:init()
    self.ges_events = { TapSelect = { GestureRange:new { ges = "tap", range = self.dimen } } }
    local w, h = self.dimen.w, self.dimen.h
    local group = VerticalGroup:new { align = "left" }
    group[#group + 1] = LeftContainer:new { dimen = Geom:new { w = w, h = h - Size.line.thin }, build(self.entry, w, self.menu.state) }
    if self.entry.rule ~= false and self.entry.kind ~= "spacer" and self.entry.kind ~= "message" then
        group[#group + 1] = HorizontalGroup:new { HorizontalSpan:new { width = s(22) },
            LineWidget:new { dimen = Geom:new { w = w - 2 * s(22), h = Size.line.thin }, background = Blitbuffer.COLOR_GRAY_D } }
    end
    self[1] = group
end

function PrefRow:onTapSelect(arg, ges)
    if self.entry.on_tap then self.entry.on_tap(ges.pos.x - self.dimen.x, self.dimen.w) end
    return true
end
function PrefRow:onFocus() return true end
function PrefRow:onUnfocus() return true end
function PrefRow:getFocusIndicatorRegion() return self.dimen end

-- ----------------------------------------------------------------------------------------------------------------------------------------
-- The menu

local PrefMenu = PickMenu:extend {}

function PrefMenu:init()
    self.custom_title_bar = Header:new { title = self.heading, width = Screen:getWidth(), on_close = function() Prefs.close_all() end, on_back = self.on_back }
    Menu.init(self)
    self.footer_box = self[1][1][3]
    self.page_arrows = self.footer_box and self.footer_box[1]
    self:syncFooter()
end

-- Menu keeps a table of its own in `self.layout` once it has drawn, so the method that packs the rows has another name here.
-- Rows keep their own heights, one after another, until a page is full.
function PrefMenu:layoutRows(avail)
    self.dims = { width = self.inner_dimen.w }
    self.page_items = {}
    local items, used = {}, 0
    for i, item in ipairs(self.item_table) do
        item.px = row_height(item) -- in pixels; item.height stays in the units the screens gave, so a second layout does not scale it again
        if used + item.px > avail and #items > 0 then
            table.insert(self.page_items, items)
            items, used = {}, 0
        end
        table.insert(items, i)
        used = used + item.px
    end
    table.insert(self.page_items, items)
end

-- Menu's own rule for which rows fit on a page, with this module's row heights (see PickMenu:setupItemHeights, which this follows).
function PrefMenu:setupItemHeights()
    local top = self.title_bar and self.title_bar:getHeight() or 0
    local footer = self.inner_dimen.h - top - self.available_height
    self:layoutRows(self.available_height + footer)
    self.one_page = #self.page_items == 1
    if self.one_page then
        self.available_height = self.available_height + footer
    else
        self:layoutRows(self.available_height)
    end
end

function PrefMenu:updateItems(select_number, no_recalculate_dimen)
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
        local dimen = self.item_dimen:copy()
        dimen.h = item.px
        local row = PrefRow:new { entry = item, menu = self, dimen = dimen }
        table.insert(self.item_group, row)
        table.insert(self.layout, { row })
    end
    self:updatePageInfo(select_number)
    self:syncFooter()
    self:mergeTitleBarIntoLayout()
    UIManager:setDirty(self.show_parent, function() return "ui", old_dimen and old_dimen:combine(self.dimen) or self.dimen end)
end

-- Builds the rows again from the settings (keeping the page), and the bar.
function PrefMenu:rebuild()
    local page = self.page
    self:switchItemTable(nil, self.spec.build(self.state, self))
    if page and page > 1 then
        self.page = math.min(page, #self.page_items)
        self:updateItems()
    end
    self:refreshBar()
end

function PrefMenu:refreshBar()
    self.bar, self.bar_hits, self.bar_zone = nil, nil, nil
    local info = self.spec.bar and self.spec.bar(self.state, self)
    if info then
        local bar, hits = floating_bar(info.label, info.buttons)
        local size = bar:getSize()
        local x = self.dimen.x + math.floor((self.dimen.w - size.w) / 2)
        local y = self.dimen.y + self.dimen.h - size.h - s(12)
        self.bar, self.bar_hits, self.bar_x, self.bar_y = bar, hits, x, y
        self.bar_zone = Geom:new { x = x, y = y, w = size.w, h = size.h }
    end
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function PrefMenu:paintTo(bb, x, y)
    PickMenu.paintTo(self, bb, x, y)
    if self.bar then self.bar:paintTo(bb, self.bar_x, self.bar_y) end
end

-- A tap on the bar is the bar's, and never reaches the list under it (KOReader gives a container's children an event first).
function PrefMenu:propagateEvent(event)
    local ges = event.handler == "onGesture" and event.args and event.args[1]
    if ges and ges.ges == "tap" and self.bar_zone and ges.pos and self.bar_zone:contains(ges.pos) then
        for _i, hit in ipairs(self.bar_hits or {}) do
            if hit.widget.dimen and hit.widget.dimen:contains(ges.pos) then hit.callback() break end
        end
        return true
    end
    return PickMenu.propagateEvent(self, event)
end

-- ----------------------------------------------------------------------------------------------------------------------------------------
-- Opening screens

local stack = {}

-- spec: { heading, build(state, menu) -> entries, bar(state, menu) -> { label, buttons } | nil }
function Prefs.push(spec, on_done)
    local state = { selected = {}, count = 0 }
    local parent = stack[#stack]
    local menu = PrefMenu:new {
        heading = spec.heading, title = spec.heading, spec = spec, state = state, item_table = spec.build(state, nil),
        is_borderless = true, is_popout = false, covers_fullscreen = true, is_enable_shortcut = false,
        items_max_lines = 2, -- rows of different heights: Menu asks setupItemHeights for the pages
        on_back = parent and function() Prefs.pop() end or nil,
        close_callback = function() Prefs.close_all() end,
    }
    menu.on_done = on_done
    state.menu = menu
    stack[#stack + 1] = menu
    UIManager:show(menu)
    menu:refreshBar()
    return menu
end

function Prefs.pop()
    local menu = table.remove(stack)
    if menu then UIManager:close(menu) end
    local parent = stack[#stack]
    if parent then parent:rebuild() end
end

function Prefs.close_all(skip_done)
    local root
    for i = #stack, 1, -1 do
        root = stack[i]
        UIManager:close(stack[i])
        stack[i] = nil
    end
    if root and root.on_done and not skip_done then root.on_done() end
end

-- ----------------------------------------------------------------------------------------------------------------------------------------
-- The screens

local KINDS = {
    book = { one = _("%1 hidden book"), many = _("%1 hidden books"), noun_one = _("%1 book"), noun_many = _("%1 books"), title = _("Hidden books") },
    snooze = { one = _("%1 snoozed book"), many = _("%1 snoozed books"), noun_one = _("%1 book"), noun_many = _("%1 books"), title = _("Snoozed books") },
    author = { one = _("%1 hidden author"), many = _("%1 hidden authors"), noun_one = _("%1 author"), noun_many = _("%1 authors"), title = _("Hidden authors") },
    series = { one = _("%1 hidden series"), many = _("%1 hidden series"), noun_one = _("%1 series"), noun_many = _("%1 series"), title = _("Hidden series") },
}

-- The rows of a list of things hidden, or of a list to choose from: `items` is { { key, text, sub, cover }, ... }.
local function checklist_rows(state, items, opts)
    local rows = {}
    local filter = state.filter and state.filter:lower() or nil
    local shown = {}
    for _i, it in ipairs(items) do
        if not filter or filter == "" or it.text:lower():find(filter, 1, true) then shown[#shown + 1] = it end
    end
    state.keys = {}
    for _i, it in ipairs(shown) do state.keys[#state.keys + 1] = it.key end
    return shown
end

local function selected_count(state)
    local n = 0
    for _key in pairs(state.selected) do n = n + 1 end
    return n
end

-- The screen of one kind of hidden thing: select some and bring them back, or all at once.
local function hidden_screen(kind, close_on_empty)
    local meta = KINDS[kind]
    local spec = { heading = meta.title }
    local function items(state)
        local ex, lib = exclusions(), library()
        local list = {}
        if kind == "book" or kind == "snooze" then
            local source = ex:get(kind)
            for path, value in pairs(source) do
                local r = lib.by_path[path]
                list[#list + 1] = {
                    key = path, text = title_of(lib, path), cover = path,
                    sub = kind == "snooze" and T(_("Back in %1 days"), days_until(value)) or (r and tostring(r.authors or ""):gsub("\n", ", ") or nil),
                }
            end
        else
            local counts = kind == "author" and lib.authors or lib.series
            for name in pairs(ex:get(kind)) do
                local n = counts[name] or 0
                list[#list + 1] = { key = name, text = name, sub = n > 0 and plural(n, _("%1 book"), _("%1 books")) or nil }
            end
        end
        return sorted_by(list, "text")
    end
    local function confirm(menu, keys)
        local state = menu.state
        local n = #keys
        local names = {}
        for _i, key in ipairs(keys) do names[#names + 1] = state.label_of[key] end
        local body = n <= 3 and T(_("%1 can be suggested again."), table.concat(names, ", ")) or _("They can be suggested again.")
        UIManager:show(ConfirmBox:new {
            text = T(_("Bring back %1?\n\n%2"), plural(n, meta.noun_one, meta.noun_many), body),
            ok_text = _("Bring back"),
            ok_callback = function()
                local ex = exclusions()
                for _i, key in ipairs(keys) do ex:remove(kind, key) end
                state.selected = {}
                menu:rebuild()
            end,
        })
    end
    spec.build = function(state, menu)
        local all = items(state)
        local rows = {}
        state.label_of = {}
        for _i, it in ipairs(all) do state.label_of[it.key] = it.text end
        state.total = #all
        rows[#rows + 1] = { kind = "heading", text = plural(#all, meta.one, meta.many), action = #all > 0 and _("Bring all back") or nil,
            on_tap = function(x, w)
                if x > w * 0.55 and #all > 0 then
                    local keys = {}
                    for _i, it in ipairs(all) do keys[#keys + 1] = it.key end
                    confirm(state.menu, keys)
                end
            end }
        if kind == "author" or kind == "series" then
            rows[#rows + 1] = { kind = "button", text = kind == "author" and _("+ Hide an author\u{2026}") or _("+ Hide a series\u{2026}"),
                on_tap = function() Prefs.push(Prefs.picker(kind)) end }
        end
        if #all > 8 then
            rows[#rows + 1] = { kind = "filter", text = state.filter and state.filter ~= "" and state.filter or _("Filter"), active = state.filter and state.filter ~= "",
                on_tap = function() Prefs.ask_filter(state, function() state.menu:rebuild() end) end }
        end
        local shown = checklist_rows(state, all)
        local picked = 0
        for _i, it in ipairs(shown) do if state.selected[it.key] then picked = picked + 1 end end
        rows[#rows + 1] = { kind = "selectall", state = picked == 0 and "off" or picked == #shown and "on" or "some",
            text = picked > 0 and T(_("Select all \u{00B7} %1 selected"), picked) or _("Select all"),
            on_tap = function()
                if picked == #shown then state.selected = {} else for _i, it in ipairs(shown) do state.selected[it.key] = true end end
                state.menu:rebuild()
            end }
        for _i, it in ipairs(shown) do
            rows[#rows + 1] = { kind = "item", height = it.cover and HEIGHT.cover_item or HEIGHT.item, text = it.text, sub = it.sub, cover = it.cover, checked = state.selected[it.key],
                on_tap = function() state.selected[it.key] = (not state.selected[it.key]) or nil; state.menu:rebuild() end }
        end
        rows[#rows + 1] = { kind = "spacer", rule = false }
        return rows
    end
    spec.bar = function(state, menu)
        local n = selected_count(state)
        if n == 0 then return nil end
        local keys = {}
        for key in pairs(state.selected) do keys[#keys + 1] = key end
        return { label = T(_("%1 selected"), n), buttons = {
            { text = _("Cancel"), callback = function() state.selected = {}; menu:rebuild() end },
            { text = _("Bring back"), solid = true, callback = function() confirm(menu, keys) end },
        } }
    end
    return spec
end

-- Choose from the library what to hide: every author (or series) not hidden yet.
function Prefs.picker(kind)
    local meta = KINDS[kind]
    local spec = { heading = kind == "author" and _("Hide authors") or _("Hide series") }
    spec.build = function(state, menu)
        local ex, lib = exclusions(), library()
        local counts = kind == "author" and lib.authors or lib.series
        local all = {}
        for name, n in pairs(counts) do
            if not ex:has(kind, name) then all[#all + 1] = { key = name, text = name, sub = plural(n, _("%1 book"), _("%1 books")) } end
        end
        sorted_by(all, "text")
        local rows = {}
        rows[#rows + 1] = { kind = "lead", text = kind == "author" and _("Pick the authors to stop suggesting") or _("Pick the series to stop suggesting"),
            sub = _("Everything of theirs in your library stays out of the suggestions.") , height = 66 }
        if #all > 8 then
            rows[#rows + 1] = { kind = "filter", text = state.filter and state.filter ~= "" and state.filter or _("Filter"), active = state.filter and state.filter ~= "",
                on_tap = function() Prefs.ask_filter(state, function() state.menu:rebuild() end) end }
        end
        local shown = checklist_rows(state, all)
        for _i, it in ipairs(shown) do
            rows[#rows + 1] = { kind = "item", text = it.text, sub = it.sub, checked = state.selected[it.key],
                on_tap = function() state.selected[it.key] = (not state.selected[it.key]) or nil; state.menu:rebuild() end }
        end
        if #shown == 0 then rows[#rows + 1] = { kind = "message", lines = { { _("Nothing to show."), 15, true } } } end
        rows[#rows + 1] = { kind = "spacer", rule = false }
        return rows
    end
    spec.bar = function(state, menu)
        local n = selected_count(state)
        if n == 0 then return nil end
        return { label = T(_("%1 selected"), n), buttons = {
            { text = _("Cancel"), callback = function() state.selected = {}; menu:rebuild() end },
            { text = T(_("Hide %1"), n), solid = true, callback = function()
                local ex = exclusions()
                for key in pairs(state.selected) do ex:add(kind, key) end
                Prefs.pop()
            end },
        } }
    end
    return spec
end

function Prefs.ask_filter(state, done)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new {
        title = _("Filter"), input = state.filter or "", input_hint = _("Part of a name"),
        buttons = { {
            { text = _("Clear"), callback = function() state.filter = nil; UIManager:close(dialog); done() end },
            { text = _("Filter"), is_enter_default = true, callback = function() state.filter = dialog:getInputText(); UIManager:close(dialog); done() end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function rows_screen()
    return { heading = _("Rows of the list"), build = function(state)
        local ex = exclusions()
        local rows = { { kind = "lead", text = _("Rows to show"), sub = _("Switch off a row you never want in the list."), height = 66 } }
        for _i, row in ipairs(Prefs.ROWS) do
            local hidden = ex:has("group", row[1])
            rows[#rows + 1] = { kind = "toggle", text = row[2], on = not hidden,
                on_tap = function()
                    if hidden then ex:remove("group", row[1]) else ex:add("group", row[1]) end
                    state.menu:rebuild()
                end }
        end
        rows[#rows + 1] = { kind = "spacer", rule = false, height = 20 }
        return rows
    end }
end

local function collection_names()
    local names, seen = {}, {}
    pcall(function() for name in pairs(require("readcollection").coll or {}) do seen[name] = true end end)
    for name in pairs(exclusions():get("collection")) do seen[name] = true end
    for name in pairs(seen) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local function collections_screen()
    return { heading = _("Collections"), build = function(state)
        local ex = exclusions()
        local chosen = G_reader_settings:readSetting(COLLECTION)
        local rows = { { kind = "lead", text = _("What each collection does"), sub = _("\u{201C}Suggest from\u{201D} adds a row of that collection's first books."), height = 66 } }
        local names = collection_names()
        if #names == 0 then
            rows[#rows + 1] = { kind = "message", lines = { { _("You have no collections yet."), 15, true }, { _("Make one from KOReader's file browser."), 13, false, GREY } } }
        end
        for _i, name in ipairs(names) do
            local count = 0
            pcall(function() for _j in ipairs(require("readcollection"):getOrderedCollection(name) or {}) do count = count + 1 end end)
            local current = ex:has("collection", name) and 3 or (chosen == name and 2 or 1)
            rows[#rows + 1] = { kind = "segment", text = name, sub = plural(count, _("%1 book"), _("%1 books")), chosen = current,
                on_tap = function(x, w)
                    local widths = { s(66), s(100), s(52) }
                    local start = w - s(22) - (widths[1] + widths[2] + widths[3])
                    local at = x - start
                    local pick = at < 0 and nil or at < widths[1] and 1 or at < widths[1] + widths[2] and 2 or at < widths[1] + widths[2] + widths[3] and 3 or nil
                    if not pick or pick == current then return end
                    if pick == 3 then ex:add("collection", name) else ex:remove("collection", name) end
                    if pick == 2 then G_reader_settings:saveSetting(COLLECTION, name) elseif chosen == name then G_reader_settings:delSetting(COLLECTION) end
                    state.menu:rebuild()
                end }
        end
        rows[#rows + 1] = { kind = "spacer", rule = false, height = 20 }
        return rows
    end }
end

-- ----------------------------------------------------------------------------------------------------------------------------------------
-- Want to read: the lists you imported, and a screen to browse them

local SOURCES = {
    goodreads = { _("Goodreads"), "GR" }, storygraph = { _("StoryGraph"), "SG" }, hardcover = { _("Hardcover"), "HC" }, csv = { _("CSV file"), "CSV" },
}
local function source_name(key) return SOURCES[key] and SOURCES[key][1] or tostring(key) end
local function source_mark(key) return SOURCES[key] and SOURCES[key][2] or tostring(key):upper():sub(1, 3) end

-- "today", "3 days ago": when a list was imported, in the words of the On hold row.
local function ago(time)
    local said = Suggest.put_down_text(time, os.time())
    return said and said:lower() or nil
end

local function count_of(set)
    local n = 0
    for _key in pairs(set) do n = n + 1 end
    return n
end

-- "Adrian Tchaikovsky \u{00B7} Book 4 of Children of Time"
local function about_line(book)
    local parts = {}
    if book.author and book.author ~= "" then parts[#parts + 1] = book.author end
    local series = Suggest.series_text(book)
    if series then parts[#parts + 1] = series end
    return #parts > 0 and table.concat(parts, " \u{00B7} ") or nil
end

-- Reads a CSV the person chose, says what is in it and how much of it is here, and keeps it as that source's list once they agree.
function Prefs.import_from(file, menu)
    local handle = io.open(file, "rb")
    if not handle then
        UIManager:show(InfoMessage:new { text = _("That file could not be read.") })
        return
    end
    local text = handle:read("*a")
    handle:close()
    local list, why = Wanted.from_csv(text)
    if not list then
        UIManager:show(InfoMessage:new { text = why == "columns" and _("That file has no Title and Author columns, so it is not a list of books.") or _("That file has no books in it.") })
        return
    end
    if #list.books == 0 then
        UIManager:show(InfoMessage:new { text = _("That file has no books on its want-to-read shelf.") })
        return
    end
    local here = count_of((Wanted.match(list, library().books)))
    UIManager:show(ConfirmBox:new {
        text = T(_("%1: %2 on the want-to-read shelf.\n\n%3 are on this device and will be tagged and ranked higher. %4 are not.\n\nThis replaces only the %1 list."),
            source_name(list.source), plural(#list.books, _("%1 book"), _("%1 books")), here, #list.books - here),
        ok_text = _("Import"),
        ok_callback = function()
            Wanted.save(G_reader_settings, list, os.time())
            if menu then menu:rebuild() end
        end,
    })
end

-- Asks for a CSV file on the device.
function Prefs.import_file(menu)
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new {
        title = _("Choose a CSV file"), path = G_reader_settings:readSetting("home_dir") or "/",
        select_directory = false, select_file = true, detailed_file_info = false,
        file_filter = function(name) return name:lower():match("%.csv$") ~= nil end,
        onConfirm = function(file) Prefs.import_from(file, menu) end,
    })
end

-- Browse the lists: a tab for All (merged, books you have first) and one for each list, with that list's own actions under it.
local function browse_screen(initial)
    return { heading = _("Want to read"), build = function(state)
        local lib = library()
        local lists = {}
        for _i, list in ipairs(Wanted.lists(G_reader_settings)) do
            if #list.books > 0 then lists[#lists + 1] = list end
        end
        local merged = Wanted.merged(G_reader_settings)
        state.tab = state.tab or initial or "all"
        local current
        for _i, list in ipairs(lists) do if list.source == state.tab then current = list end end
        if not current then state.tab = "all" end
        local labels, keys = { T(_("All %1"), #merged.books) }, { "all" }
        for _i, list in ipairs(lists) do
            labels[#labels + 1] = T(_("%1 %2"), source_name(list.source), #list.books)
            keys[#keys + 1] = list.source
        end
        local chosen = 1
        for i, key in ipairs(keys) do if key == state.tab then chosen = i end end
        local rows = {}
        if #lists == 0 then
            rows[#rows + 1] = { kind = "message", lines = { { _("No lists yet"), 18, true }, { _("Import one from Want to read in Preferences."), 13, false, GREY } } }
            return rows
        end
        rows[#rows + 1] = { kind = "tabs", labels = labels, chosen = chosen, rule = false,
            on_tap = function(x)
                local widths, at = tab_widths(labels), s(22)
                for i, width in ipairs(widths) do
                    if x >= at and x < at + width then
                        state.tab = keys[i]
                        state.menu.page = 1
                        state.menu:rebuild()
                        return
                    end
                    at = at + width + s(TAB_GAP)
                end
            end }
        local books = current and current.books or merged.books
        local owned = Wanted.match({ books = books }, lib.books)
        local path_of = {}
        for path, entry in pairs(owned) do path_of[entry] = path end
        local here, rest = {}, {}
        for _i, book in ipairs(books) do table.insert(path_of[book] and here or rest, book) end
        local note = T(_("%1 on this device \u{00B7} %2 not"), #here, #rest)
        if current then
            local when = ago(current.imported)
            if when then note = T(_("Imported %1 \u{00B7} %2"), when, note) end
        end
        rows[#rows + 1] = { kind = "note", text = note, rule = false }
        for _i, group in ipairs({ here, rest }) do
            for _j, book in ipairs(group) do
                local path = path_of[book]
                local marks = {}
                for _k, source in ipairs(book.sources or { state.tab }) do marks[#marks + 1] = source_mark(source) end
                rows[#rows + 1] = { kind = "listing", text = book.title, sub = about_line(book), cover = path, marks = table.concat(marks, " "),
                    status = path and _("On this device") or _("not on device"),
                    on_tap = path and function()
                        if Prefs.open_book then Prefs.close_all(true); Prefs.open_book(path) end
                    end or nil }
            end
        end
        if current then
            rows[#rows + 1] = { kind = "pair", first = _("Import again"), second = _("Remove this list"), rule = false,
                on_tap = function(x, w)
                    if x < w / 2 then
                        Prefs.import_file(state.menu)
                    else
                        UIManager:show(ConfirmBox:new {
                            text = T(_("Remove the %1 list?\n\n%2. Books that are on no other list stop being tagged and ranked higher. Nothing is deleted from your library or your account."),
                                source_name(current.source), plural(#current.books, _("%1 book"), _("%1 books"))),
                            ok_text = _("Remove list"),
                            ok_callback = function()
                                Wanted.forget(G_reader_settings, current.source)
                                state.tab = "all"
                                if #Wanted.lists(G_reader_settings) == 0 then Prefs.pop() else state.menu:rebuild() end
                            end,
                        })
                    end
                end }
            rows[#rows + 1] = { kind = "note", text = T(_("Removing a list forgets it here only. Your %1 account is untouched."), source_name(current.source)), rule = false }
        end
        rows[#rows + 1] = { kind = "spacer", rule = false, height = 20 }
        return rows
    end }
end

-- The lists you imported (tap one to browse it), how to import another, and the two switches.
local function wanted_screen()
    return { heading = _("Want to read"), build = function(state)
        local lib = library()
        local lists = Wanted.lists(G_reader_settings)
        local rows = { { kind = "lead", text = _("Want to read"), sub = _("Books you mean to read, from lists kept elsewhere."), height = 66 } }
        for _i, list in ipairs(lists) do
            local here = count_of((Wanted.match({ books = list.books }, lib.books)))
            local when = ago(list.imported)
            local sub = plural(#list.books, _("%1 book"), _("%1 books")) .. (when and (" \u{00B7} " .. T(_("imported %1"), when)) or "")
                .. " \u{00B7} " .. T(_("%1 on this device"), here)
            rows[#rows + 1] = { kind = "summary", text = source_name(list.source), sub = sub, count = source_mark(list.source),
                on_tap = function() Prefs.push(browse_screen(list.source)) end }
        end
        if #lists == 0 then
            rows[#rows + 1] = { kind = "message", height = 130, lines = { { _("No lists yet"), 18, true },
                { _("Export your want-to-read shelf from Goodreads or StoryGraph"), 12, false, GREY },
                { _("as a CSV file, put it on this device and import it here."), 12, false, GREY } } }
        end
        rows[#rows + 1] = { kind = "button", text = _("Import a list from a file\u{2026}"), on_tap = function() Prefs.import_file(state.menu) end }
        local boost, show = Wanted.boost(G_reader_settings), Wanted.show_unowned(G_reader_settings)
        rows[#rows + 1] = { kind = "toggle", height = 72, text = _("Rank books on my lists higher"), sub = _("Books you have that are on a list come first in the picks"), on = boost,
            on_tap = function() Wanted.set_boost(G_reader_settings, not boost); state.menu:rebuild() end }
        rows[#rows + 1] = { kind = "toggle", height = 72, text = _("Show books I don't own"), sub = _("A Want to read row in the picks, up to 4 books"), on = show,
            on_tap = function() Wanted.set_show_unowned(G_reader_settings, not show); state.menu:rebuild() end }
        rows[#rows + 1] = { kind = "spacer", rule = false, height = 20 }
        return rows
    end }
end

local function overview_screen()
    return { heading = _("Preferences"), build = function(state)
        local ex, lib = exclusions(), library()
        local function names(kind, limit)
            local keys = ex:keys(kind)
            local shown = {}
            for i = 1, math.min(limit or 3, #keys) do shown[#shown + 1] = keys[i] end
            local text = table.concat(shown, ", ")
            if #keys > #shown then text = T(_("%1, and %2 more"), text, #keys - #shown) end
            return text
        end
        local function open(spec) return function() Prefs.push(spec) end end
        local rows = {}
        local total = ex:total()
        local hidden_rows = ex:count("group")
        local chosen = G_reader_settings:readSetting(COLLECTION)
        if total == 0 then
            rows[#rows + 1] = { kind = "message", height = 230, lines = {
                { _("Nothing is hidden"), 22, true }, { _("Everything in your library can be suggested."), 14, false, GREY },
                { "", 8 }, { _("To stop suggesting something, press and hold"), 13 }, { _("a book in the list, then choose what to hide:"), 13 },
                { _("the book, its author, its series or its row,"), 13, true }, { _("or snooze it for 30 days."), 13 } } }
        else
            rows[#rows + 1] = { kind = "lead", text = _("Hidden from your suggestions"), sub = _("Tap a row to see and change what is in it.") }
            local books = ex:keys("book")
            if #books > 0 then
                local strip = {}
                local room = math.floor((Screen:getWidth() - 2 * s(22) - s(90)) / s(52))
                for i = 1, math.min(room, #books) do strip[#strip + 1] = { path = books[i], title = title_of(lib, books[i]) } end
                rows[#rows + 1] = { kind = "summary", height = HEIGHT.strip, text = _("Books"), count = tostring(#books), strip = strip, more = #books - #strip,
                    on_tap = open(hidden_screen("book")) }
            end
            if ex:count("snooze") > 0 then
                local first = ex:keys("snooze")[1]
                rows[#rows + 1] = { kind = "summary", text = _("Snoozed books"), count = tostring(ex:count("snooze")),
                    sub = ex:count("snooze") == 1 and T(_("%1, back in %2 days"), title_of(lib, first), days_until(ex:get("snooze")[first])) or nil,
                    on_tap = open(hidden_screen("snooze")) }
            end
            if ex:count("author") > 0 then
                rows[#rows + 1] = { kind = "summary", text = _("Authors"), count = tostring(ex:count("author")), sub = names("author"), on_tap = open(hidden_screen("author")) }
            end
            if ex:count("series") > 0 then
                rows[#rows + 1] = { kind = "summary", text = _("Series"), count = tostring(ex:count("series")), sub = names("series"), on_tap = open(hidden_screen("series")) }
            end
        end
        local hidden_names = {}
        for _i, row in ipairs(Prefs.ROWS) do if ex:has("group", row[1]) then hidden_names[#hidden_names + 1] = row[2] end end
        rows[#rows + 1] = { kind = "summary", text = _("Rows of the list"), count = hidden_rows > 0 and T(_("%1 of %2 hidden"), hidden_rows, #Prefs.ROWS) or _("All shown"),
            sub = #hidden_names > 0 and table.concat(hidden_names, ", ") or nil, on_tap = open(rows_screen()) }
        local skipped = ex:count("collection")
        rows[#rows + 1] = { kind = "summary", text = _("Collections"), count = skipped > 0 and T(_("%1 skipped"), skipped) or "",
            sub = skipped > 0 and names("collection") or nil, on_tap = open(collections_screen()) }
        rows[#rows + 1] = { kind = "plain", text = _("Suggest from"), value = chosen or _("None"), on_tap = open(collections_screen()) }
        local lists = Wanted.lists(G_reader_settings)
        rows[#rows + 1] = { kind = "plain", text = _("Want to read"), value = #lists > 0 and plural(#lists, _("%1 list"), _("%1 lists")) or _("None"), on_tap = open(wanted_screen()) }
        if total > 0 then rows[#rows + 1] = { kind = "hint", text = _("Press and hold any book in the list to hide it") } end
        return rows
    end }
end

-- The screens by name, and the one on top: for a test driver to open one directly and look at it.
Prefs.screens = { hidden = hidden_screen, rows = rows_screen, collections = collections_screen, overview = overview_screen, wanted = wanted_screen, browse = browse_screen }
function Prefs.top() return stack[#stack] end

-- Opens the Preferences. `on_done` runs when the last screen is closed (the list behind it can show what changed).
function Prefs.show(on_done, open_book)
    if stack[1] then return end -- already open
    Prefs.open_book = open_book -- opens a book of a list you are browsing: closes these screens and the list behind them
    Prefs.push(overview_screen(), on_done)
end

return Prefs
