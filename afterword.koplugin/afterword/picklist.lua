-- The list on the Pick next / What to read next screen: KOReader's own Menu (title bar, page arrows, paging) with its rows drawn
-- here, so a book can have the series on a second line in smaller grey text, and a note (tags, or how far through) flush right.
-- Each row is { text, subtitle, mandatory, callback } for a book, or { text, heading = true } for a group's name. A long title is
-- cut with an ellipsis rather than wrapped, so a row never starts further left than the one above it.
local Blitbuffer = require("ffi/blitbuffer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local GREY = Blitbuffer.COLOR_DARK_GRAY
local HAIRLINE = Blitbuffer.COLOR_GRAY -- between books; lighter than the text so it separates without shouting
local INDENT = 0.6 -- of the side padding, extra, for a book under its group's name

-- The three faces a row uses, from the menu's font size.
local function faces(font_size)
    return {
        title = Font:getFace("cfont", font_size),
        series = Font:getFace("cfont", math.max(12, font_size - 7)),
        note = Font:getFace("infont", math.max(12, font_size - 6)),
        heading = Font:getFace("cfont", math.max(12, font_size - 3)),
    }
end

local function line_height(face)
    return TextWidget:new { text = "Ag", face = face }:getSize().h
end

local PickRow = InputContainer:extend {}

function PickRow:init()
    local entry, width = self.entry, self.dimen.w
    local f = faces(self.font_size)
    self.ges_events = {
        TapSelect = { GestureRange:new { ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new { ges = "hold", range = self.dimen } },
    }
    local pad = Size.padding.fullscreen
    local indent = entry.heading and 0 or math.floor(pad * INDENT)
    local note = (not entry.heading and entry.mandatory) and TextWidget:new { text = tostring(entry.mandatory), face = f.note } or nil
    local gap = Size.padding.large
    local text_width = width - 2 * pad - indent - (note and (note:getSize().w + gap) or 0)

    local linesize = self.menu.linesize
    if entry.heading then
        -- A group's name: black and bold, space above it (none at the very top) and no rule, so groups are told apart by white space.
        local name = TextWidget:new { text = entry.text, face = f.heading, bold = true, max_width = width - 2 * pad, truncate_with_ellipsis = true }
        self[1] = VerticalGroup:new {
            align = "left",
            VerticalSpan:new { width = (self.heading_gap and not entry.at_top) and self.heading_gap or 0 },
            HorizontalGroup:new { HorizontalSpan:new { width = pad }, name },
        }
        return
    end

    local text = VerticalGroup:new { align = "left" }
    table.insert(text, TextWidget:new { text = entry.text, face = f.title, max_width = text_width, truncate_with_ellipsis = true })
    if entry.subtitle then
        table.insert(text, TextWidget:new { text = entry.subtitle, face = f.series, fgcolor = GREY, max_width = text_width, truncate_with_ellipsis = true })
    end
    local row = HorizontalGroup:new { align = "center", HorizontalSpan:new { width = pad + indent }, text }
    if note then
        table.insert(row, HorizontalSpan:new { width = math.max(gap, text_width - text:getSize().w + gap) })
        table.insert(row, note)
    end
    -- A hairline under a book, inset to line up with the text, except under the last one of a group.
    local rule = entry.last and VerticalSpan:new { width = linesize } or HorizontalGroup:new {
        HorizontalSpan:new { width = pad + indent },
        LineWidget:new { dimen = Geom:new { w = width - 2 * pad - indent, h = linesize }, background = HAIRLINE },
    }
    self[1] = VerticalGroup:new {
        align = "left",
        LeftContainer:new { dimen = Geom:new { w = width, h = self.dimen.h - linesize }, row }, -- left, and centred up and down
        rule,
    }
end

function PickRow:onTapSelect()
    if not self.entry.heading then self.menu:onMenuSelect(self.entry) end
    return true
end

function PickRow:onHoldSelect()
    return true
end

-- Focus handling the Menu expects of its rows (keys on a device without a touch screen); a row just takes it.
function PickRow:onFocus() return true end
function PickRow:onUnfocus() return true end
function PickRow:getFocusIndicatorRegion() return self.dimen end

local PickMenu = Menu:extend {}

-- How tall each row is, and which rows fit on which page: Menu's own rule, with this row's height.
function PickMenu:setupItemHeights()
    local f = faces(self.font_size)
    local title_h, series_h, heading_h = line_height(f.title), line_height(f.series), line_height(f.heading)
    local vertical = 2 * Size.span.vertical_default + self.linesize
    self.heading_gap = math.floor(heading_h * 0.5) -- white space above a group's name, except at the top of a page
    local function height(item, at_top)
        if item.heading then
            item.at_top = at_top
            return heading_h + Size.span.vertical_default + (at_top and 0 or self.heading_gap)
        end
        return title_h + (item.subtitle and series_h or 0) + vertical
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
        local row = PickRow:new { entry = item, menu = self, dimen = dimen, font_size = self.font_size, heading_gap = self.heading_gap }
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
